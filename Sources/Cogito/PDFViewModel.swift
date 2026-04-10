import Foundation
import PDFKit
import AppKit

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
    case outline, thumbnails, bookmarks

    var icon: String {
        switch self {
        case .outline:    return "list.bullet.indent"
        case .thumbnails: return "square.grid.2x2"
        case .bookmarks:  return "bookmark"
        }
    }

    var label: String {
        switch self {
        case .outline:    return "Outline"
        case .thumbnails: return "Thumbnails"
        case .bookmarks:  return "Bookmarks"
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
        cropMarginsVisually(in: doc)  // in-memory only; never writes to file
        document = doc
        documentURL = url
        currentPageIndex = 0
        searchResults = []
        searchQuery = ""
        bookmarks = []
        cornellNotes = [:]
        outlineNodes = doc.outlineRoot.map { buildOutlineNodes(from: $0, document: doc) } ?? []
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
    }

    // MARK: Zoom

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func zoomToFit() {
        guard let v = pdfView, let page = v.currentPage else { return }
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
        pdfView?.go(to: sel)
        pdfView?.setCurrentSelection(sel, animate: true)
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
}
