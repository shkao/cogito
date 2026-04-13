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
            case 125: // down arrow
                Task { @MainActor [weak self] in self?.nextPage() }
                return nil
            case 126: // up arrow
                Task { @MainActor [weak self] in self?.previousPage() }
                return nil
            case 124: // right arrow
                Task { @MainActor [weak self] in self?.nextChapter() }
                return nil
            case 123: // left arrow
                Task { @MainActor [weak self] in self?.previousChapter() }
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

    // MARK: Ask Question (RAG)
    @Published var isAskBarVisible: Bool = false
    @Published var askQuery: String = ""
    @Published var isAskingQuestion: Bool = false
    @Published var askAnswer: String?
    private var askTask: Task<Void, Never>?
    private var pageTextIndex: [(pageIndex: Int, text: String)] = []

    // MARK: LLM Status
    @Published var llmState: LLMService.State = .idle

    func refreshLLMState() {
        Task { llmState = await LLMService.shared.state }
    }

    // MARK: Translation
    @Published var selectedWord: String?
    @Published var wordTranslation: WikiTranslation?
    @Published var isLoadingTranslation = false
    @Published var translationError: String?
    @Published var selectionYFraction: CGFloat?
    @Published var selectionOnLeftPage: Bool = false
    @Published var translationLang: String = UserDefaults.standard.string(forKey: "translationLang") ?? "zh-tw" {
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

    // MARK: Mindmap

    struct MindmapDisplay {
        let title: String
        let root: MindmapNode
    }

    @Published var displayingMindmap: MindmapDisplay?
    @Published var mindmapGenerating: Set<String> = []
    private var mindmapTasks: [String: Task<Void, Never>] = [:]

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

        outlineInferenceTask?.cancel()
        outlineInferenceTask = nil
        for job in videoJobs {
            job.task?.cancel()
            Task { await videoService.cancel(title: job.id) }
            if let pdf = job.chapterPDF { try? FileManager.default.removeItem(at: pdf) }
        }
        videoJobs.removeAll()
        for (_, task) in mindmapTasks { task.cancel() }
        mindmapTasks.removeAll()
        mindmapGenerating.removeAll()
        displayingMindmap = nil
        clearTranslation()

        cropMarginsVisually(in: doc)
        document = doc
        documentURL = url
        currentPageIndex = 0
        searchResults = []
        searchQuery = ""
        bookmarks = []
        cornellNotes = [:]
        let nodes = doc.outlineRoot.map { buildOutlineNodes(from: $0, document: doc) } ?? []
        outlineNodes = nodes
        if nodes.isEmpty {
            inferOutlineWithLLM(doc: doc)
        }
        Task { buildPageTextIndex(doc: doc) }
        refreshCachedVideos()
        restoreReadingProgress()
    }

    private func buildOutlineNodes(from outline: PDFOutline, document: PDFDocument) -> [OutlineNode] {
        (0..<outline.numberOfChildren).compactMap { i -> OutlineNode? in
            guard let child = outline.child(at: i) else { return nil }
            let label = child.label ?? ""
            let pageIndex: Int = {
                guard let dest = child.destination, let page = dest.page else { return 0 }
                return document.index(for: page)
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

    func nextChapter() {
        guard let node = outlineNodes.first(where: { $0.pageIndex > currentPageIndex }) else { return }
        goToPage(node.pageIndex)
    }

    func previousChapter() {
        guard let node = outlineNodes.last(where: { $0.pageIndex < currentPageIndex }) else { return }
        goToPage(node.pageIndex)
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

    /// Override the pending page restore (e.g. from CLI --page or --chapter).
    /// Must be called after open() and before the view applies the restore.
    func overridePendingRestore(to pageIndex: Int) {
        pendingPageRestore = pageIndex
    }

    /// Returns the left and right page indices for the currently visible two-page spread.
    /// In book mode, page 0 is alone; subsequent pairs are (1,2), (3,4), ...
    /// In regular two-page mode, pairs are (0,1), (2,3), ...
    var spreadPages: (left: Int, right: Int) {
        let idx = currentPageIndex
        if displaysAsBook {
            if idx == 0 { return (0, 0) }
            let left = idx % 2 == 1 ? idx : idx - 1
            return (left, min(left + 1, totalPages - 1))
        } else {
            let left = idx % 2 == 0 ? idx : max(0, idx - 1)
            return (left, min(left + 1, totalPages - 1))
        }
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

    // MARK: Active outline path

    /// Returns the IDs of outline nodes from root to the deepest node containing `pageIndex`.
    /// Used to auto-expand and highlight the current position in the TOC.
    func activeOutlinePath(for pageIndex: Int) -> Set<UUID> {
        var result = Set<UUID>()
        func walk(_ nodes: [OutlineNode]) {
            // Find the last node whose pageIndex <= current page
            guard let match = nodes.last(where: { $0.pageIndex <= pageIndex }) else { return }
            result.insert(match.id)
            if let kids = match.children, !kids.isEmpty {
                walk(kids)
            }
        }
        walk(outlineNodes)
        return result
    }

    // MARK: Chapter page range

    private static let frontMatterLabels: Set<String> = [
        "preface", "foreword", "acknowledgments", "acknowledgements",
        "about the author", "about the authors", "dedication",
        "table of contents", "contents", "introduction",
    ]

    /// True when the chapter has enough content for video/mindmap generation
    /// and is not front matter (preface, foreword, etc.).
    func isContentChapter(_ node: OutlineNode) -> Bool {
        let lower = node.label.trimmingCharacters(in: .whitespaces).lowercased()
        if Self.frontMatterLabels.contains(lower) { return false }
        return chapterPageRange(for: node).count >= 5
    }

    /// Returns the top-level outline node whose start page matches `pageIndex`, if any.
    func chapterNode(at pageIndex: Int) -> OutlineNode? {
        outlineNodes.first { $0.pageIndex == pageIndex && isContentChapter($0) }
    }

    func chapterPageRange(for node: OutlineNode) -> Range<Int> {
        func searchSiblings(_ siblings: [OutlineNode]) -> Range<Int>? {
            guard let idx = siblings.firstIndex(where: { $0.id == node.id }) else {
                for sibling in siblings {
                    if let found = sibling.children.flatMap({ searchSiblings($0) }) {
                        return found
                    }
                }
                return nil
            }
            let end = idx + 1 < siblings.count ? siblings[idx + 1].pageIndex : totalPages
            return node.pageIndex..<max(node.pageIndex, end)
        }
        return searchSiblings(outlineNodes) ?? (node.pageIndex..<node.pageIndex)
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

    private func cacheSubdir(_ name: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = caches.appendingPathComponent("com.cogito.app/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func videoOutputDir() -> URL { cacheSubdir("Videos") }

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

    func videoURL(for title: String) -> URL? {
        let target = sanitizeTitle(title)
        return cachedVideos.first { videoTitle(from: $0) == target }
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
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
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
        return String(response[start.lowerBound..<end.upperBound])
    }

    // MARK: - Mindmap Generation

    func generateMindmap(for node: OutlineNode) {
        let title = node.label
        if mindmapGenerating.contains(title) { return }

        if let cached = loadCachedMindmap(for: title) {
            displayingMindmap = MindmapDisplay(title: title, root: cached)
            return
        }

        guard let doc = document else { return }
        mindmapGenerating.insert(title)

        let range = chapterPageRange(for: node)
        let task = Task {
            defer {
                mindmapGenerating.remove(title)
                mindmapTasks[title] = nil
            }

            let text = PDFTextExtractor.text(from: doc, pages: range)
            let truncated = String(text.prefix(4000))

            let prompt = """
            Create a mind map from this chapter. Return ONLY valid JSON, no other text.

            Format: {"title":"Topic","children":[{"title":"Branch","children":[{"title":"Leaf"}]}]}

            Rules:
            - Root title: the chapter's main topic in 3-6 words
            - 4-7 first-level branches for key concepts
            - 2-4 leaves per branch for important details
            - Maximum 3 levels deep
            - Each title: 2-6 words, no full sentences

            Chapter:
            \(truncated)
            """

            var response = ""
            do {
                let stream = await LLMService.shared.generate(
                    prompt: prompt,
                    systemPrompt: "You create mind maps from text. Return ONLY a valid JSON object, no other text.",
                    maxTokens: 1024
                )
                for try await token in stream {
                    if Task.isCancelled { return }
                    response += token
                }
            } catch {
                return
            }

            guard let mindmap = parseMindmapJSON(response) else { return }
            saveMindmapToCache(mindmap, for: title)
            displayingMindmap = MindmapDisplay(title: title, root: mindmap)
        }
        mindmapTasks[title] = task
    }

    func hasMindmap(for title: String) -> Bool {
        FileManager.default.fileExists(atPath: mindmapPath(for: title).path)
    }

    func deleteMindmap(for title: String) {
        try? FileManager.default.removeItem(at: mindmapPath(for: title))
    }

    private func parseMindmapJSON(_ response: String) -> MindmapNode? {
        guard let start = response.range(of: "{"),
              let end = response.range(of: "}", options: .backwards),
              start.lowerBound <= end.lowerBound else { return nil }
        let jsonStr = String(response[start.lowerBound..<end.upperBound])
        guard let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MindmapNode.self, from: data)
    }

    private func mindmapOutputDir() -> URL { cacheSubdir("Mindmaps") }

    private func mindmapPath(for title: String) -> URL {
        let safe = sanitizeTitle(title)
        return mindmapOutputDir().appendingPathComponent("\(safe)_\(bookHash).json")
    }

    private func loadCachedMindmap(for title: String) -> MindmapNode? {
        let path = mindmapPath(for: title)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(MindmapNode.self, from: data)
    }

    private func saveMindmapToCache(_ node: MindmapNode, for title: String) {
        let path = mindmapPath(for: title)
        guard let data = try? JSONEncoder().encode(node) else { return }
        try? data.write(to: path)
    }

    // MARK: - Ask Question (RAG)

    /// Build a per-page text index when a document is opened.
    private func buildPageTextIndex(doc: PDFDocument) {
        pageTextIndex = (0..<doc.pageCount).compactMap { i in
            guard let page = doc.page(at: i),
                  let text = PDFTextExtractor.text(from: page),
                  text.count > 50 else { return nil }
            return (pageIndex: i, text: text)
        }
    }

    /// BM25-lite retrieval: score each page by query term overlap.
    private func retrievePages(query: String, topK: Int = 5) -> [(pageIndex: Int, text: String)] {
        let queryTerms = tokenize(query)
        guard !queryTerms.isEmpty else { return [] }

        // Inverse document frequency: penalize terms that appear on many pages
        let totalDocs = Double(pageTextIndex.count)
        var docFreq: [String: Int] = [:]
        for entry in pageTextIndex {
            let pageTokens = Set(tokenize(entry.text))
            for term in queryTerms where pageTokens.contains(term) {
                docFreq[term, default: 0] += 1
            }
        }

        var scored: [(index: Int, score: Double)] = []
        for (i, entry) in pageTextIndex.enumerated() {
            let pageText = entry.text.lowercased()
            var score = 0.0
            for term in queryTerms {
                let tf = Double(Self.countOccurrences(of: term, in: pageText))
                guard tf > 0 else { continue }
                let df = Double(docFreq[term] ?? 1)
                let idf = log((totalDocs + 1) / (df + 1)) + 1
                score += tf * idf
            }
            if score > 0 {
                scored.append((index: i, score: score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(topK)
            .map { pageTextIndex[$0.index] }
    }

    /// Extract text passages (windows) around keyword occurrences.
    /// Returns surrounding context for each hit, merged if overlapping.
    private static func extractPassages(from text: String, matching terms: [String], windowChars: Int) -> [String] {
        let lower = text.lowercased()
        var ranges: [(Int, Int)] = []

        // Find all occurrences of each term and collect character ranges
        for term in terms {
            var searchStart = lower.startIndex
            while let found = lower.range(of: term, range: searchStart..<lower.endIndex) {
                let center = lower.distance(from: lower.startIndex, to: found.lowerBound)
                let start = max(0, center - windowChars / 2)
                let end = min(text.count, center + term.count + windowChars / 2)
                ranges.append((start, end))
                searchStart = found.upperBound
            }
        }

        guard !ranges.isEmpty else { return [] }

        // Sort and merge overlapping ranges
        let sorted = ranges.sorted { $0.0 < $1.0 }
        var merged: [(Int, Int)] = [sorted[0]]
        for r in sorted.dropFirst() {
            if r.0 <= merged[merged.count - 1].1 {
                merged[merged.count - 1].1 = max(merged[merged.count - 1].1, r.1)
            } else {
                merged.append(r)
            }
        }

        // Extract the text for each merged range
        return merged.compactMap { (start, end) in
            let s = text.index(text.startIndex, offsetBy: start, limitedBy: text.endIndex) ?? text.startIndex
            let e = text.index(text.startIndex, offsetBy: end, limitedBy: text.endIndex) ?? text.endIndex
            let passage = String(text[s..<e]).trimmingCharacters(in: .whitespacesAndNewlines)
            return passage.isEmpty ? nil : passage
        }
    }

    private static func countOccurrences(of term: String, in text: String) -> Int {
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
        }
        return count
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    func askQuestion() {
        let query = askQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let doc = document else { return }

        askTask?.cancel()
        isAskingQuestion = true
        askAnswer = nil

        askTask = Task {
            defer { isAskingQuestion = false }

            // Retrieve top pages by keyword matching (fast, no LLM)
            let topPages = retrievePages(query: query)
            guard !topPages.isEmpty else {
                askAnswer = "No relevant content found in this book."
                return
            }

            // Navigate to the best page immediately (before LLM answers)
            let targetPage = topPages[0].pageIndex
            goToPage(targetPage)
            highlightQueryTerms(query: query, near: targetPage, doc: doc)

            // Build context: extract text surrounding keyword occurrences on each page
            let queryTerms = tokenize(query).filter { !Self.stopWords.contains($0) }
            var context = ""
            var charCount = 0
            let charLimit = 4000
            for entry in topPages {
                guard charCount < charLimit else { break }
                // Extract passages around keyword hits rather than using the full page
                let passages = Self.extractPassages(from: entry.text, matching: queryTerms, windowChars: 400)
                let pageContext = passages.isEmpty
                    ? String(entry.text.prefix(charLimit - charCount))
                    : passages.joined(separator: " ... ")
                let snippet = String(pageContext.prefix(charLimit - charCount))
                context += "--- Page \(entry.pageIndex + 1) ---\n\(snippet)\n\n"
                charCount += snippet.count
            }

            let isDefinitionQuery = query.lowercased().hasPrefix("what is ")
                || query.lowercased().hasPrefix("what are ")
                || query.lowercased().hasPrefix("define ")

            let langName = SupportedLanguage.englishName(for: translationLang)

            let style = isDefinitionQuery
                ? """
                 The reader has NO technical background. Write your answer so a \
                smart 12-year-old can understand it:
                - Replace every technical term with a simple everyday word or a brief definition in parentheses.
                - Use short sentences. No jargon left unexplained.
                - Include a concrete everyday example in English to illustrate the concept.
                """
                : " Your answer must be self-contained. Briefly define any technical terms you use."

            let metaphor = """

            After your answer, add a blank line, then write ONE metaphor in \(langName).
            Format: 💡 <metaphor>
            Requirements for the metaphor:
            - Write it so a 12-year-old with zero technical knowledge understands instantly.
            - Use an everyday object or experience the child already knows (cooking, toys, school, games, drawing).
            - The metaphor must map the core concept to that everyday thing in 1 sentence.
            - No jargon, no technical words, no English terms. Pure simple \(langName).
            """

            let prompt = """
            A reader asks: "\(query)"

            BOOK TEXT (prioritize this to answer):
            \(context)
            END OF BOOK TEXT.

            RULES:
            - Answer in 3-5 sentences. Prioritize information from the book text above.
            - Start with "From the book, ".
            - Quote or closely paraphrase the book's own words when possible.
            - You may add brief clarifications to make the answer self-contained.\(style)\(metaphor)
            """

            // Stream answer token by token, post-process the full buffer for math symbols
            var rawAnswer = ""
            askAnswer = ""
            do {
                let stream = await LLMService.shared.generate(
                    prompt: prompt,
                    systemPrompt: "You answer questions prioritizing provided book excerpts. Quote the book's language when possible, and add brief clarifications only when needed for clarity. Use unicode math symbols (μ, σ, σ², x̂, θ, α, β, ε, λ, π) instead of writing out Greek letter names or LaTeX.",
                    maxTokens: 450
                )
                for try await token in stream {
                    if Task.isCancelled { return }
                    rawAnswer += token
                    askAnswer = Self.fixMathSymbols(rawAnswer)
                }
            } catch {
                if rawAnswer.isEmpty {
                    askAnswer = "Could not generate an answer."
                }
            }
        }
    }

    /// Post-process LLM output: strip LaTeX markup and convert to unicode.
    private static let latexCommands: [(String, String)] = [
        ("\\mathbf", ""), ("\\mathrm", ""), ("\\mathit", ""),
        ("\\mathcal", ""), ("\\mathbb", ""), ("\\text", ""),
        ("\\operatorname", ""), ("\\boldsymbol", ""),
        ("\\sigma", "σ"), ("\\Sigma", "Σ"),
        ("\\mu", "μ"), ("\\nu", "ν"),
        ("\\theta", "θ"), ("\\Theta", "Θ"),
        ("\\alpha", "α"), ("\\beta", "β"),
        ("\\gamma", "γ"), ("\\Gamma", "Γ"),
        ("\\delta", "δ"), ("\\Delta", "Δ"),
        ("\\epsilon", "ε"), ("\\varepsilon", "ε"),
        ("\\lambda", "λ"), ("\\Lambda", "Λ"),
        ("\\phi", "φ"), ("\\varphi", "φ"), ("\\Phi", "Φ"),
        ("\\psi", "ψ"), ("\\Psi", "Ψ"),
        ("\\omega", "ω"), ("\\Omega", "Ω"),
        ("\\pi", "π"), ("\\Pi", "Π"),
        ("\\rho", "ρ"), ("\\tau", "τ"),
        ("\\eta", "η"), ("\\zeta", "ζ"),
        ("\\chi", "χ"), ("\\xi", "ξ"), ("\\kappa", "κ"),
        ("\\partial", "∂"), ("\\nabla", "∇"),
        ("\\infty", "∞"), ("\\infinity", "∞"),
        ("\\approx", "≈"), ("\\neq", "≠"), ("\\ne", "≠"),
        ("\\leq", "≤"), ("\\geq", "≥"), ("\\le", "≤"), ("\\ge", "≥"),
        ("\\rightarrow", "→"), ("\\leftarrow", "←"),
        ("\\Rightarrow", "⇒"), ("\\Leftarrow", "⇐"),
        ("\\in", "∈"), ("\\notin", "∉"),
        ("\\subset", "⊂"), ("\\subseteq", "⊆"),
        ("\\times", "×"), ("\\cdot", "·"),
        ("\\ldots", "..."), ("\\dots", "..."), ("\\cdots", "..."),
        ("\\sim", "~"), ("\\propto", "∝"),
        ("\\sum", "Σ"), ("\\prod", "Π"), ("\\int", "∫"),
        ("\\log", "log"), ("\\exp", "exp"),
        ("\\hat", "\u{0302}"), ("\\tilde", "\u{0303}"), ("\\bar", "\u{0304}"),
        ("\\left", ""), ("\\right", ""),
        ("\\,", " "), ("\\;", " "), ("\\!", ""), ("\\quad", " "),
    ]

    private static let superscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "n": "ⁿ", "i": "ⁱ", "k": "ᵏ", "T": "ᵀ",
        "+": "⁺", "-": "⁻",
    ]

    private static let subscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
        "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "n": "ₙ", "t": "ₜ",
        "+": "₊", "-": "₋",
    ]

    private static let plainGreek: [(String, String)] = [
        ("sigma", "σ"), ("Sigma", "Σ"),
        ("theta", "θ"), ("alpha", "α"), ("beta", "β"),
        ("gamma", "γ"), ("delta", "δ"), ("epsilon", "ε"),
        ("lambda", "λ"), ("Lambda", "Λ"),
        ("phi", "φ"), ("omega", "ω"),
    ]

    private static func fixMathSymbols(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "$$", with: "")
        s = s.replacingOccurrences(of: "$", with: "")
        for (cmd, replacement) in latexCommands {
            s = s.replacingOccurrences(of: cmd, with: replacement)
        }
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")
        s = replaceScripts(in: s, marker: "^", map: superscriptMap)
        s = replaceScripts(in: s, marker: "_", map: subscriptMap)
        for (name, sym) in plainGreek {
            s = s.replacingOccurrences(of: "\\b\(name)\\b", with: sym, options: .regularExpression)
        }
        return s
    }

    /// Replace ^x or _x with the corresponding super/subscript unicode character.
    private static func replaceScripts(in text: String, marker: String, map: [Character: Character]) -> String {
        var result = ""
        var chars = text[text.startIndex...]
        let markerChar = marker.first!
        while let idx = chars.firstIndex(of: markerChar) {
            result += chars[chars.startIndex..<idx]
            let afterIdx = chars.index(after: idx)
            if afterIdx < chars.endIndex, let replacement = map[chars[afterIdx]] {
                result.append(replacement)
                chars = chars[chars.index(after: afterIdx)...]
            } else {
                result.append(markerChar)
                chars = chars[afterIdx...]
            }
        }
        result += chars
        return result
    }

    func clearAsk() {
        askTask?.cancel()
        askQuery = ""
        askAnswer = nil
        isAskingQuestion = false
        isAskBarVisible = false
        pdfView?.clearSelection()
    }

    private static let stopWords: Set<String> = [
        "what", "which", "where", "when", "how", "who", "whom", "why",
        "the", "this", "that", "these", "those", "and", "but", "for",
        "not", "are", "was", "were", "been", "being", "have", "has",
        "had", "does", "did", "will", "would", "could", "should",
        "may", "might", "can", "about", "with", "from", "into",
        "between", "through", "during", "before", "after", "above",
        "below", "all", "each", "every", "both", "few", "more",
        "most", "other", "some", "such", "than", "too", "very",
        "just", "also", "only", "own", "same", "then", "once",
        "here", "there", "its", "let", "say", "she", "his", "her",
        "they", "them", "their", "our", "your", "out", "off",
        "over", "under", "again", "further", "explain", "define",
        "tell", "describe", "mean", "means", "meaning",
    ]

    /// Highlight the first defining mention of the query subject on or near the target page.
    /// For abbreviations like "VAE", tries to find the expanded form (e.g. "variational autoencoder (VAE)")
    /// and highlights the full sentence fragment rather than just the abbreviation.
    private func highlightQueryTerms(query: String, near pageIndex: Int, doc: PDFDocument) {
        let terms = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !Self.stopWords.contains($0) }

        guard !terms.isEmpty else { return }

        let subject = terms.joined(separator: " ")

        // Extract text from the target page and neighbors to find the defining context
        let searchRange = max(0, pageIndex - 1)..<min(doc.pageCount, pageIndex + 2)
        let pageText = PDFTextExtractor.text(from: doc, pages: searchRange)

        // Look for a definition pattern: "full name (ABBREV)" or "ABBREV, or full name"
        // e.g. "variational autoencoder (VAE)" or "VAE (variational autoencoder)"
        if let defPhrase = findDefinitionPhrase(for: subject, in: pageText) {
            let results = doc.findString(defPhrase, withOptions: [.caseInsensitive])
            if let match = findOnPage(results, near: pageIndex, doc: doc) {
                applyHighlight(match)
                return
            }
        }

        // Fall back: find the first occurrence of the subject term on the page
        let results = doc.findString(subject, withOptions: [.caseInsensitive])
        if let match = findOnPage(results, near: pageIndex, doc: doc) {
            applyHighlight(match)
            return
        }

        // Last resort: try individual terms
        for term in terms.sorted(by: { $0.count > $1.count }) {
            let results = doc.findString(term, withOptions: [.caseInsensitive])
            if let match = findOnPage(results, near: pageIndex, doc: doc) {
                applyHighlight(match)
                return
            }
        }
    }

    /// Searches text for a definition pattern around a term, e.g. "variational autoencoder (VAE)".
    /// Returns the full phrase if found, nil otherwise.
    private func findDefinitionPhrase(for term: String, in text: String) -> String? {
        let lower = text.lowercased()
        let termLower = term.lowercased()

        // Pattern 1: "full name (TERM)" - e.g. "variational autoencoder (VAE)"
        // Look for "(term)" and grab the preceding words
        let parenPattern = "(\(NSRegularExpression.escapedPattern(for: termLower)))"
        if let parenRange = lower.range(of: parenPattern, options: .caseInsensitive) {
            // Walk backwards from the opening paren to grab 2-5 preceding words
            let beforeParen = text[text.startIndex..<parenRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let words = beforeParen.split(separator: " ").suffix(5)
            if words.count >= 2 {
                let fullPhrase = words.joined(separator: " ") + " " + String(text[parenRange])
                return fullPhrase
            }
        }

        // Pattern 2: "TERM (full name)" - e.g. "VAE (variational autoencoder)"
        if let termRange = lower.range(of: termLower) {
            let afterTerm = text[termRange.upperBound...]
            if afterTerm.hasPrefix(" (") || afterTerm.hasPrefix("(") {
                if let closeParen = afterTerm.firstIndex(of: ")") {
                    let fullPhrase = String(text[termRange.lowerBound...closeParen])
                    if fullPhrase.count < 80 { return fullPhrase }
                }
            }
        }

        return nil
    }

    private func findOnPage(_ selections: [PDFSelection], near pageIndex: Int, doc: PDFDocument) -> PDFSelection? {
        for radius in [0, 1, 2] {
            if let match = selections.first(where: { sel in
                guard let p = sel.pages.first else { return false }
                return abs(doc.index(for: p) - pageIndex) <= radius
            }) {
                return match
            }
        }
        return nil
    }

    private func applyHighlight(_ selection: PDFSelection) {
        suppressSelectionLookup = true
        pdfView?.setCurrentSelection(selection, animate: true)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.suppressSelectionLookup = false
        }
    }
}
