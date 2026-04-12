import Foundation
import PDFKit
import AppKit
import UserNotifications

// MARK: - Display Mode

enum DisplayMode: String, CaseIterable, Identifiable {
    case single
    case twoPage

    var id: String { rawValue }

    var pdfDisplayMode: PDFDisplayMode {
        switch self {
        case .single:  return .singlePage
        case .twoPage: return .twoUp
        }
    }

    var label: String {
        switch self {
        case .single:  return "Single Page"
        case .twoPage: return "Two Pages"
        }
    }

    var icon: String {
        switch self {
        case .single:  return "doc"
        case .twoPage: return "book.pages"
        }
    }

    var isTwoPage: Bool { self == .twoPage }
}

// MARK: - Sidebar Mode

enum SidebarMode: CaseIterable, Identifiable {
    var id: Self { self }
    case outline, thumbnails, bookmarks, videos

    var icon: String {
        switch self {
        case .outline:    return "list.bullet.indent"
        case .thumbnails: return "square.grid.2x2"
        case .bookmarks:  return "bookmark"
        case .videos:     return "video.badge.waveform"
        }
    }

    var label: String {
        switch self {
        case .outline:    return "Outline"
        case .thumbnails: return "Thumbnails"
        case .bookmarks:  return "Bookmarks"
        case .videos:     return "Video Library"
        }
    }
}

// MARK: - Outline Node

struct OutlineNode: Identifiable {
    let id = UUID()
    let label: String
    let pageIndex: Int
    let pageLabel: String
    let children: [OutlineNode]?
}

// MARK: - View Model

@MainActor
class PDFViewModel: ObservableObject {
    private var keyMonitor: Any?

    init() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.isEditingText, self.document != nil else { return event }
            switch event.keyCode {
            case 124, 125:
                Task { @MainActor [weak self] in self?.nextPage() }
                return nil
            case 123, 126:
                Task { @MainActor [weak self] in self?.previousPage() }
                return nil
            default:
                return event
            }
        }
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    @Published var document: PDFDocument?
    @Published var documentURL: URL?
    @Published var currentPageIndex: Int = 0

    var totalPages: Int { document?.pageCount ?? 0 }

    @Published var displayMode: DisplayMode = .twoPage
    @Published var displaysAsBook: Bool = true

    @Published var sidebarMode: SidebarMode = .outline
    @Published var outlineNodes: [OutlineNode] = []

    @Published var isEditingText: Bool = false
    @Published var isSearchBarVisible: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResults: [PDFSelection] = []
    @Published var currentSearchIndex: Int = 0

    @Published var bookmarks: Set<Int> = []
    @Published var cornellNotes: [Int: String] = [:]

    // MARK: Feynman Concept Cues
    @Published var conceptCues: [Int: ConceptCue] = [:]  // keyed by pageIndex
    @Published var isExtractingConcepts: Bool = false
    @Published var isAnalyzingGaps: Bool = false
    @Published var isGeneratingModelAnswer: Bool = false
    private var conceptCueTask: Task<Void, Never>?
    private var gapAnalysisTask: Task<Void, Never>?
    private var modelAnswerTask: Task<Void, Never>?
    private var conceptCueSaveTask: Task<Void, Never>?

    // MARK: Translation
    @Published var selectedWord: String?
    @Published var wordTranslation: WikiTranslation?
    @Published var isLoadingTranslation = false
    @Published var translationError: String?
    @Published var selectionYFraction: CGFloat?
    @Published var selectionOnLeftPage: Bool = false
    @Published var translationLang: String = UserDefaults.standard.string(forKey: "translationLang") ?? "zh" {
        didSet { UserDefaults.standard.set(translationLang, forKey: "translationLang") }
    }

    // MARK: Video Generation

    struct VideoJob: Identifiable {
        let id: String  // chapter title
        var status: VideoStatus
        var task: Task<Void, Never>?
        var chapterPDF: URL?
    }

    @Published var videoJobs: [VideoJob] = []
    @Published var isInferringOutline: Bool = false
    @Published var playingVideoURL: URL?

    @Published var videoFormat: VideoFormat = VideoFormat(rawValue: UserDefaults.standard.string(forKey: "videoFormat") ?? "") ?? .explainer {
        didSet { UserDefaults.standard.set(videoFormat.rawValue, forKey: "videoFormat") }
    }
    @Published var videoStyle: VideoStyle = VideoStyle(rawValue: UserDefaults.standard.string(forKey: "videoStyle") ?? "") ?? .whiteboard {
        didSet { UserDefaults.standard.set(videoStyle.rawValue, forKey: "videoStyle") }
    }

    private let videoService = NotebookLMService()
    private var outlineInferenceTask: Task<Void, Never>?
    private var pendingPageRestore: Int?

    func isGeneratingVideo(for title: String) -> Bool {
        videoJobs.first { $0.id == title }.map { !$0.status.isTerminal } ?? false
    }

    var suppressSelectionLookup = false
    private var lookupTask: Task<Void, Never>?
    private var selectionDebounceTask: Task<Void, Never>?

    func scheduleTranslation(word: String, yFrac: CGFloat, onLeft: Bool) {
        selectionDebounceTask?.cancel()
        selectionDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            selectedWord = word
            selectionYFraction = yFrac
            selectionOnLeftPage = onLeft
            lookupTranslation(for: word)
        }
    }

    func lookupTranslation(for word: String) {
        lookupTask?.cancel()
        wordTranslation = nil
        translationError = nil
        isLoadingTranslation = true
        lookupTask = Task {
            do {
                let result = try await WikiTranslationService.translate(word: word, targetLang: translationLang)
                guard !Task.isCancelled else { return }
                wordTranslation = result
                isLoadingTranslation = false
            } catch {
                guard !Task.isCancelled else { return }
                translationError = error.localizedDescription
                isLoadingTranslation = false
            }
        }
    }

    func clearTranslation() {
        selectionDebounceTask?.cancel()
        lookupTask?.cancel()
        selectedWord = nil
        wordTranslation = nil
        translationError = nil
        isLoadingTranslation = false
        selectionYFraction = nil
        selectionOnLeftPage = false
    }

    weak var pdfView: PDFView?

    // MARK: File

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.title = "Open PDF"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    func open(url: URL) {
        guard let doc = PDFDocument(url: url) else { return }
        cropMarginsVisually(in: doc)
        document = doc
        documentURL = url
        currentPageIndex = 0
        searchResults = []
        searchQuery = ""
        bookmarks = []
        cornellNotes = [:]
        conceptCues = [:]
        let nodes = doc.outlineRoot.map { buildOutlineNodes(from: $0, document: doc) } ?? []
        outlineNodes = nodes
        if nodes.isEmpty {
            inferOutlineWithLLM(doc: doc)
        }
        loadConceptCues()
        refreshCachedVideos()
        restoreReadingProgress()
    }

    private func buildOutlineNodes(from outline: PDFOutline, document: PDFDocument) -> [OutlineNode] {
        (0..<outline.numberOfChildren).compactMap { i -> OutlineNode? in
            guard let child = outline.child(at: i) else { return nil }
            let label = child.label ?? ""
            let pageIndex: Int = {
                guard let dest = child.destination, let page = dest.page else { return 0 }
                let idx = document.index(for: page)
                let y = dest.point.y
                // PDFs (e.g. Packt) sometimes encode chapter destinations with
                // kPDFDestinationUnspecifiedValue as Y, pointing to the page just
                // before the chapter. Add 1 to land on the actual chapter start page.
                if y >= CGFloat(Float.greatestFiniteMagnitude) * 0.5 {
                    return min(idx + 1, document.pageCount - 1)
                }
                return idx
            }()
            let page = document.page(at: pageIndex)
            let pageLabel = page?.label ?? "\(pageIndex + 1)"
            let kids = buildOutlineNodes(from: child, document: document)
            return OutlineNode(label: label, pageIndex: pageIndex, pageLabel: pageLabel, children: kids.isEmpty ? nil : kids)
        }
    }

    // Samples character bounds on the first few pages to detect the horizontal margin,
    // then sets each page's cropBox to strip those margins. Purely in-memory; the original file is never touched.
    private func cropMarginsVisually(in doc: PDFDocument) {
        var samples: [CGFloat] = []

        for i in 2..<min(8, doc.pageCount) {
            guard let page = doc.page(at: i),
                  let str = page.string, str.count > 60 else { continue }

            let media = page.bounds(for: .mediaBox)
            var minX = media.maxX
            let step = max(1, str.count / 150)
            var j = 0
            while j < str.count {
                let b = page.characterBounds(at: j)
                if b.width > 0.5 && b.minX > media.minX + 5 {
                    minX = Swift.min(minX, b.minX)
                }
                j += step
            }
            if minX < media.maxX { samples.append(minX - media.minX) }
        }

        guard !samples.isEmpty else { return }
        let avg = samples.reduce(0, +) / CGFloat(samples.count)
        let crop = max(0, avg * 0.4)
        guard crop > 15 else { return }

        // Skip pages 0-1 (cover spread); apply visual crop to content pages only
        for i in 2..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let m = page.bounds(for: .mediaBox)
            page.setBounds(
                CGRect(x: m.minX + crop, y: m.minY,
                       width: m.width - 2 * crop, height: m.height),
                for: .cropBox
            )
        }
    }

    // MARK: Navigation

    func goToPage(_ index: Int) {
        guard let doc = document,
              index >= 0, index < totalPages,
              let page = doc.page(at: index) else { return }
        currentPageIndex = index
        pdfView?.go(to: page)
        saveReadingProgress()
    }

    // MARK: Reading Progress

    private func saveReadingProgress() {
        guard documentURL != nil else { return }
        UserDefaults.standard.set(currentPageIndex, forKey: "readingProgress_\(bookHash)")
    }

    private func restoreReadingProgress() {
        let saved = UserDefaults.standard.integer(forKey: "readingProgress_\(bookHash)")
        if saved > 0, saved < totalPages {
            pendingPageRestore = saved
        }
    }

    func applyPendingRestore() {
        guard let page = pendingPageRestore else { return }
        pendingPageRestore = nil
        goToPage(page)
    }

    private var pageStep: Int { displayMode.isTwoPage ? 2 : 1 }

    func nextPage() {
        goToPage(min(currentPageIndex + pageStep, totalPages - 1))
    }

    func previousPage() {
        goToPage(max(currentPageIndex - pageStep, 0))
    }

    func syncCurrentPage() {
        guard let doc = document, let page = pdfView?.currentPage else { return }
        let newIndex = doc.index(for: page)
        guard newIndex != currentPageIndex else { return }
        currentPageIndex = newIndex
        saveReadingProgress()
    }

    // MARK: Zoom

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func zoomToFit() {
        guard let v = pdfView else { return }
        guard v.bounds.width > 0, v.bounds.height > 0 else { return }
        // currentPage can be nil when PDFKit hasn't finished loading yet.
        // Use a content page (index 2+) as the fallback: pages 0-1 skip cropBox adjustment
        // and may have different proportions than body pages.
        let fallback = v.document.flatMap { d in d.page(at: min(2, max(0, d.pageCount - 1))) }
        let page = v.currentPage ?? fallback
        guard let page else { return }
        let pageBounds = page.bounds(for: .cropBox)
        let totalWidth = displayMode.isTwoPage ? pageBounds.width * 2 : pageBounds.width
        guard totalWidth > 0, pageBounds.height > 0 else { return }
        let scaleByWidth = v.bounds.width / totalWidth
        let scaleByHeight = v.bounds.height / pageBounds.height
        let newScale = min(scaleByWidth, scaleByHeight)
        guard abs(newScale - v.scaleFactor) > 0.0001 else { return }
        v.scaleFactor = newScale
    }

    // MARK: Search

    func performSearch() {
        guard !searchQuery.isEmpty, let doc = document else {
            searchResults = []
            pdfView?.clearSelection()
            return
        }
        searchResults = doc.findString(searchQuery, withOptions: [.caseInsensitive])
        currentSearchIndex = 0
        highlightCurrentResult()
    }

    func nextSearchResult() { stepSearch(by: 1) }
    func previousSearchResult() { stepSearch(by: -1) }

    private func stepSearch(by delta: Int) {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + delta + searchResults.count) % searchResults.count
        highlightCurrentResult()
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        currentSearchIndex = 0
        pdfView?.clearSelection()
        isSearchBarVisible = false
    }

    private func highlightCurrentResult() {
        guard !searchResults.isEmpty else { return }
        let sel = searchResults[currentSearchIndex]
        suppressSelectionLookup = true
        pdfView?.go(to: sel)
        pdfView?.setCurrentSelection(sel, animate: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.suppressSelectionLookup = false
        }
    }

    // MARK: Bookmarks

    func toggleBookmark() {
        if bookmarks.contains(currentPageIndex) {
            bookmarks.remove(currentPageIndex)
        } else {
            bookmarks.insert(currentPageIndex)
        }
    }

    var isCurrentPageBookmarked: Bool { bookmarks.contains(currentPageIndex) }

    // MARK: Computed

    var documentTitle: String {
        documentURL?.deletingPathExtension().lastPathComponent ?? "Cogito"
    }

    var canGoBack: Bool { currentPageIndex > 0 }
    var canGoForward: Bool { currentPageIndex < totalPages - 1 }

    // MARK: Chapter page range

    /// Returns the top-level outline node whose start page matches `pageIndex`, if any.
    func chapterNode(at pageIndex: Int) -> OutlineNode? {
        outlineNodes.first { $0.pageIndex == pageIndex && chapterPageRange(for: $0).count >= 5 }
    }

    func chapterPageRange(for node: OutlineNode) -> Range<Int> {
        guard let idx = outlineNodes.firstIndex(where: { $0.id == node.id }) else {
            return node.pageIndex..<totalPages
        }
        let end = idx + 1 < outlineNodes.count ? outlineNodes[idx + 1].pageIndex : totalPages
        return node.pageIndex..<end
    }

    // MARK: Extract chapter pages into a temp PDF

    func extractChapterPDF(for node: OutlineNode) -> URL? {
        guard let docURL = documentURL,
              let freshDoc = PDFDocument(url: docURL) else { return nil }
        let range = chapterPageRange(for: node)
        let newDoc = PDFDocument()
        for i in range {
            guard let page = freshDoc.page(at: i) else { continue }
            newDoc.insert(page, at: newDoc.pageCount)
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cogito-chapter-\(UUID().uuidString).pdf")
        guard newDoc.write(to: tempURL) else {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
        return tempURL
    }

    // MARK: Video generation

    private func videoOutputDir() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = caches.appendingPathComponent("com.cogito.app/Videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var bookHash: String {
        // NSString.hash is stable across process launches (unlike Swift's hashValue,
        // which is randomized per-session since Swift 4.2).
        documentURL.map { String(format: "%06x", ($0.path as NSString).hash & 0xFFFFFF) } ?? "000000"
    }

    private func videoPath(for title: String) -> URL {
        let safe = sanitizeTitle(title)
        return videoOutputDir().appendingPathComponent("\(safe)_\(bookHash).mp4")
    }

    func hasVideo(for title: String) -> Bool {
        let target = sanitizeTitle(title)
        return cachedVideos.contains { videoTitle(from: $0) == target }
    }

    func videoTitle(from url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        guard base.count > 7, base.dropFirst(base.count - 7).first == "_" else { return base }
        return String(base.dropLast(7))
    }

    private func sanitizeTitle(_ title: String) -> String {
        String(title.map { c in
            c.isLetter || c.isNumber || c == " " || c == "-" || c == "_" ? c : Character("_")
        })
        .trimmingCharacters(in: .whitespaces)
    }

    func generateVideoOverview(for node: OutlineNode, forceRegenerate: Bool = false) {
        if isGeneratingVideo(for: node.label) { return }

        let videoURL = videoPath(for: node.label)
        if !forceRegenerate, FileManager.default.fileExists(atPath: videoURL.path) {
            upsertJob(id: node.label, status: .done(videoPath: videoURL))
            return
        }
        if forceRegenerate { try? FileManager.default.removeItem(at: videoURL) }

        guard let chapterPDF = extractChapterPDF(for: node) else { return }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        let title = node.label
        upsertJob(id: title, status: .uploading(message: "Preparing..."), chapterPDF: chapterPDF)

        let task = Task {
            for await status in await videoService.generateVideo(
                pdfPath: chapterPDF,
                outputPath: videoURL,
                title: title,
                format: videoFormat,
                style: videoStyle
            ) {
                upsertJob(id: title, status: status)
                if status.isTerminal {
                    try? FileManager.default.removeItem(at: chapterPDF)
                    upsertJob(id: title, status: status) { $0.chapterPDF = nil; $0.task = nil }
                    refreshCachedVideos()
                    if status.isDone {
                        self.sendCompletionNotification(for: title)
                    }
                }
            }
        }
        upsertJob(id: title, status: .uploading(message: "Preparing...")) { $0.task = task }
    }

    func cancelVideoGeneration(for title: String) {
        guard let job = videoJobs.first(where: { $0.id == title }) else { return }
        job.task?.cancel()
        Task { await videoService.cancel(title: title) }
        if let pdf = job.chapterPDF {
            try? FileManager.default.removeItem(at: pdf)
        }
        videoJobs.removeAll { $0.id == title }
    }

    func dismissJob(id: String) {
        videoJobs.removeAll { $0.id == id }
    }

    private func upsertJob(id: String, status: VideoStatus, chapterPDF: URL? = nil, _ update: ((inout VideoJob) -> Void)? = nil) {
        if let idx = videoJobs.firstIndex(where: { $0.id == id }) {
            videoJobs[idx].status = status
            if let pdf = chapterPDF { videoJobs[idx].chapterPDF = pdf }
            update?(&videoJobs[idx])
        } else {
            var job = VideoJob(id: id, status: status, chapterPDF: chapterPDF)
            update?(&job)
            videoJobs.append(job)
        }
    }

    @Published private(set) var cachedVideos: [URL] = []

    func refreshCachedVideos() {
        let dir = videoOutputDir()
        let hash = bookHash
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        )) ?? []
        cachedVideos = files
            .filter { $0.pathExtension == "mp4" && $0.lastPathComponent.contains("_\(hash)") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func deleteCachedVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        if playingVideoURL == url { playingVideoURL = nil }
        refreshCachedVideos()
    }

    private func sendCompletionNotification(for chapterTitle: String) {
        // Only notify if the app is not the frontmost window — no need to interrupt the user if they're watching.
        guard NSApp.isHidden || NSApp.windows.allSatisfy({ !$0.isKeyWindow }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Video ready"
        content.body = "\"\(chapterTitle)\" overview is ready to watch"
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: NotebookLM auth

    var notebooklmAuthError: Bool {
        videoJobs.contains { $0.status.isAuthRequired }
    }

    func loginToNotebookLM() {
        // notebooklm login is interactive: opens a browser then waits for ENTER.
        // Open Terminal.app with the command so the user can interact with it.
        let script = """
        tell application "Terminal"
            activate
            do script "python3 -m notebooklm login"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    // MARK: Feynman Concept Cues

    func conceptCueWidth(for pageIndex: Int) -> CGFloat {
        conceptCues[pageIndex] != nil ? 220 : 48
    }

    func extractConceptCues(for node: OutlineNode) {
        guard !isExtractingConcepts else { return }
        isExtractingConcepts = true
        conceptCueTask?.cancel()
        conceptCueTask = Task {
            defer { isExtractingConcepts = false }
            guard let doc = document else { return }

            let range = chapterPageRange(for: node)
            let sampledText = sampleChapterText(from: doc, range: range)
            guard !sampledText.isEmpty else { return }

            let prompt = """
            Below is text from a chapter titled "\(node.label)".
            Identify 3-5 key concepts a student must understand.
            For each, write a question asking the student to \
            explain it simply, as if to a 12-year-old.

            Return JSON: [{"concept": "...", "prompt": "..."}]

            \(sampledText)
            """

            var response = ""
            do {
                let stream = await LLMService.shared.generate(
                    prompt: prompt,
                    systemPrompt: "Return ONLY a valid JSON array.",
                    maxTokens: 512
                )
                for try await token in stream {
                    if Task.isCancelled { return }
                    response += token
                }
            } catch {
                return
            }

            let cues = parseConceptCues(
                response: response,
                chapterRange: range,
                doc: doc
            )
            guard !cues.isEmpty else { return }

            for cue in cues {
                conceptCues[cue.pageIndex] = cue
            }
            saveConceptCues(
                for: node.pageIndex,
                chapterLabel: node.label
            )
        }
    }

    func analyzeGaps(for pageIndex: Int) {
        guard var cue = conceptCues[pageIndex],
              !cue.userExplanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isAnalyzingGaps else { return }
        isAnalyzingGaps = true
        gapAnalysisTask?.cancel()
        gapAnalysisTask = Task {
            defer { isAnalyzingGaps = false }
            guard let doc = document else { return }

            let pageContext = PDFTextExtractor.contextWindow(document: doc, centerPage: pageIndex, radius: 1)
            let prompt = """
            The student was asked: "\(cue.promptQuestion)"

            Their explanation: "\(cue.userExplanation)"

            Source material from the textbook:
            \(pageContext)

            Identify 1-3 specific gaps, inaccuracies, or oversimplifications \
            in the student's explanation. Frame each as a question that \
            guides them back to the source material.
            Return JSON: ["question1", "question2", ...]
            """

            var response = ""
            do {
                let stream = await LLMService.shared.generate(
                    prompt: prompt,
                    systemPrompt: "You help students identify gaps in their understanding. "
                        + "Be specific. Frame observations as questions. "
                        + "Never give the answer directly.",
                    maxTokens: 384
                )
                for try await token in stream {
                    if Task.isCancelled { return }
                    response += token
                }
            } catch {
                return
            }

            guard let jsonStr = extractJSONArray(from: response),
                  let data = jsonStr.data(using: .utf8),
                  let questions = try? JSONSerialization.jsonObject(with: data) as? [String],
                  !questions.isEmpty else { return }

            cue.gapFeedback = questions
            cue.step = .reviewed
            conceptCues[pageIndex] = cue
            saveConceptCuesForPage(pageIndex)
        }
    }

    func revealModelExplanation(for pageIndex: Int) {
        guard var cue = conceptCues[pageIndex],
              cue.modelExplanation == nil,
              !isGeneratingModelAnswer else { return }
        isGeneratingModelAnswer = true
        modelAnswerTask?.cancel()
        modelAnswerTask = Task {
            defer { isGeneratingModelAnswer = false }
            guard let doc = document else { return }

            let pageContext = PDFTextExtractor.contextWindow(document: doc, centerPage: pageIndex, radius: 1)
            let prompt = "Explain \"\(cue.concept)\" simply.\n\nContext:\n\(pageContext)"

            var response = ""
            do {
                let stream = await LLMService.shared.generate(
                    prompt: prompt,
                    systemPrompt: "Explain concepts simply, as if talking to a curious "
                        + "12-year-old. Use one strong metaphor or analogy. "
                        + "Under 80 words.",
                    maxTokens: 256
                )
                for try await token in stream {
                    if Task.isCancelled { return }
                    response += token
                }
            } catch {
                return
            }

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            cue.modelExplanation = trimmed
            cue.step = .refined
            conceptCues[pageIndex] = cue
            saveConceptCuesForPage(pageIndex)
        }
    }

    func updateConceptCueExplanation(pageIndex: Int, text: String) {
        guard var cue = conceptCues[pageIndex] else { return }
        cue.userExplanation = text
        conceptCues[pageIndex] = cue

        conceptCueSaveTask?.cancel()
        conceptCueSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            saveConceptCuesForPage(pageIndex)
        }
    }

    // MARK: Concept Cue Persistence

    private func conceptCueStorageDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("com.cogito.app/ConceptCues", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveConceptCues(for chapterPageIndex: Int, chapterLabel: String) {
        let cuesForChapter = conceptCues.values.filter { cue in
            // Find which chapter this cue belongs to by checking outline ranges
            outlineNodes.contains { node in
                node.pageIndex == chapterPageIndex && chapterPageRange(for: node).contains(cue.pageIndex)
            }
        }
        let store = ConceptCueStore(cues: Array(cuesForChapter), chapterLabel: chapterLabel)
        let path = conceptCueStorageDir().appendingPathComponent("\(bookHash)_\(chapterPageIndex).json")
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: path, options: .atomic)
        }
    }

    private func saveConceptCuesForPage(_ pageIndex: Int) {
        // Find which chapter this page belongs to and save that chapter's cues
        for node in outlineNodes {
            let range = chapterPageRange(for: node)
            if range.contains(pageIndex) {
                saveConceptCues(for: node.pageIndex, chapterLabel: node.label)
                return
            }
        }
    }

    func loadConceptCues() {
        let dir = conceptCueStorageDir()
        let hash = bookHash
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        conceptCues = [:]
        for file in files where file.lastPathComponent.hasPrefix("\(hash)_") && file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let store = try? JSONDecoder().decode(ConceptCueStore.self, from: data) else { continue }
            for cue in store.cues {
                conceptCues[cue.pageIndex] = cue
            }
        }
    }

    // MARK: Concept Cue Helpers

    private func sampleChapterText(from doc: PDFDocument, range: Range<Int>) -> String {
        let pageCount = range.count
        var indices: [Int] = []

        // First 3 pages (intro, definitions)
        for i in 0..<min(3, pageCount) { indices.append(range.lowerBound + i) }

        // Middle 2 pages
        let mid = range.lowerBound + pageCount / 2
        for offset in [-1, 0] {
            let idx = mid + offset
            if !indices.contains(idx) && range.contains(idx) { indices.append(idx) }
        }

        // Last 2 pages (summary, conclusion)
        for offset in [-2, -1] {
            let idx = range.upperBound + offset
            if idx >= 0 && !indices.contains(idx) && range.contains(idx) { indices.append(idx) }
        }

        return indices.sorted().compactMap { i -> String? in
            guard let page = doc.page(at: i) else { return nil }
            return PDFTextExtractor.text(from: page)
        }.joined(separator: "\n\n")
    }

    private func parseConceptCues(response: String, chapterRange: Range<Int>, doc: PDFDocument) -> [ConceptCue] {
        guard let jsonStr = extractJSONArray(from: response),
              let data = jsonStr.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }

        return entries.compactMap { entry -> ConceptCue? in
            guard let concept = entry["concept"], !concept.isEmpty,
                  let prompt = entry["prompt"], !prompt.isEmpty else { return nil }
            let pageIndex = mapConceptToPage(concept: concept, in: chapterRange, doc: doc)
            return ConceptCue(concept: concept, promptQuestion: prompt, pageIndex: pageIndex)
        }
    }

    private func mapConceptToPage(concept: String, in range: Range<Int>, doc: PDFDocument) -> Int {
        let searchTerms = concept.lowercased().split(separator: " ").filter { $0.count >= 3 }
        guard !searchTerms.isEmpty else { return range.lowerBound }

        for i in range {
            guard let page = doc.page(at: i),
                  let text = PDFTextExtractor.text(from: page)?.lowercased() else { continue }
            let matches = searchTerms.filter { text.contains($0) }
            if matches.count >= max(1, searchTerms.count / 2) {
                return i
            }
        }
        return range.lowerBound
    }

    // MARK: LLM-based TOC inference

    private func inferOutlineWithLLM(doc: PDFDocument) {
        isInferringOutline = true
        outlineInferenceTask?.cancel()
        outlineInferenceTask = Task {
            defer { isInferringOutline = false }

            let labelIndex = buildPageLabelIndex(from: doc)
            let tocText = buildTOCText(from: doc)
            let prompt = buildTOCPrompt(tocText)

            var response = ""
            do {
                let stream = await LLMService.shared.generate(
                    prompt: prompt,
                    systemPrompt: "You parse tables of contents from PDF text. Return ONLY a valid JSON array, no other text.",
                    maxTokens: 1024
                )
                for try await token in stream {
                    if Task.isCancelled { return }
                    response += token
                }
            } catch {
                return
            }

            let nodes = parseAndValidateTOC(response: response, labelIndex: labelIndex, doc: doc)
            if !nodes.isEmpty {
                outlineNodes = nodes
            }
        }
    }

    private func buildPageLabelIndex(from doc: PDFDocument) -> [String: Int] {
        var map: [String: Int] = [:]
        for i in 0..<doc.pageCount {
            if let label = doc.page(at: i)?.label, !label.isEmpty {
                map[label] = i
            }
        }
        return map
    }

    private func buildTOCText(from doc: PDFDocument) -> String {
        let limit = min(16, doc.pageCount)
        var parts: [String] = []
        for i in 0..<limit {
            guard let page = doc.page(at: i),
                  let text = PDFTextExtractor.text(from: page) else { continue }
            let label = page.label ?? "\(i + 1)"
            parts.append("--- Page index \(i) (printed label: \(label)) ---\n\(text)")
        }
        return parts.joined(separator: "\n\n")
    }

    private func buildTOCPrompt(_ tocText: String) -> String {
        """
        Below is text extracted from the first pages of a PDF, with page index and printed label markers.
        Find the table of contents and extract top-level chapter entries only (not subsections).

        Return a JSON array where each object has exactly two fields:
          "title": the chapter title as printed in the TOC
          "page_label": the page number exactly as it appears in the TOC (e.g. "1", "45", "xii")

        If no table of contents is found, return [].

        \(tocText)
        """
    }

    private func parseAndValidateTOC(
        response: String,
        labelIndex: [String: Int],
        doc: PDFDocument
    ) -> [OutlineNode] {
        guard let jsonStr = extractJSONArray(from: response),
              let data = jsonStr.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }

        var nodes: [OutlineNode] = []
        for entry in entries {
            guard let title = entry["title"], !title.isEmpty,
                  let pageLabel = entry["page_label"], !pageLabel.isEmpty else { continue }

            // Resolve page index via label lookup, then numeric fallback
            var pageIndex: Int? = labelIndex[pageLabel]
            if pageIndex == nil, let n = Int(pageLabel) {
                let candidate = n - 1
                if candidate >= 0 && candidate < doc.pageCount {
                    pageIndex = candidate
                }
            }
            guard let idx = pageIndex else { continue }

            // Validate: check that title words appear on or near the target page
            if !titleAppearsNearPage(title: title, pageIndex: idx, doc: doc) { continue }

            let pageObj = doc.page(at: idx)
            let displayLabel = pageObj?.label ?? "\(idx + 1)"
            nodes.append(OutlineNode(label: title, pageIndex: idx, pageLabel: displayLabel, children: nil))
        }
        return nodes
    }

    private func titleAppearsNearPage(title: String, pageIndex: Int, doc: PDFDocument) -> Bool {
        let normalized = normalizeTOCText(title)
        // Use first meaningful word (skip short words like "the", "a", "of")
        let words = normalized.split(separator: " ").map(String.init)
        guard let keyWord = words.first(where: { $0.count >= 4 }) ?? words.first else { return false }

        // Check target page and neighbors
        for offset in [0, 1, -1, 2] {
            let i = pageIndex + offset
            guard i >= 0 && i < doc.pageCount,
                  let page = doc.page(at: i),
                  let text = PDFTextExtractor.text(from: page) else { continue }
            let pageNorm = normalizeTOCText(text)
            // Check within first ~600 chars (heading area)
            let searchArea = String(pageNorm.prefix(600))
            if searchArea.contains(keyWord) { return true }
        }
        return false
    }

    /// Strips text to lowercase alphanumeric tokens for fuzzy chapter-title matching.
    private func normalizeTOCText(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Extracts a JSON array substring from an LLM response that may contain preamble/postamble.
    private func extractJSONArray(from response: String) -> String? {
        guard let start = response.range(of: "["),
              let end = response.range(of: "]", options: .backwards),
              start.lowerBound <= end.lowerBound else { return nil }
        return String(response[start.lowerBound...end.upperBound])
    }
}
