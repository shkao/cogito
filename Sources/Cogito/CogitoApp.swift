import SwiftUI

/// Handles file-open events from macOS (e.g. `open -a Cogito.app file.pdf`).
/// NSApplicationDelegate receives these before SwiftUI scenes are fully ready,
/// so we stash the URL and let CogitoApp pick it up on appear.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var pendingFileURL: URL?
    var onOpenFile: ((URL) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return }
        if let handler = onOpenFile {
            handler(url)
        } else {
            pendingFileURL = url
        }
    }
}

@main
struct CogitoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var vm = PDFViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    // Wire up delegate for future file-open events
                    appDelegate.onOpenFile = { url in vm.open(url: url) }

                    let args = CommandLine.arguments
                    var pdfPath: String?
                    var startPage: Int?
                    var chapterQuery: String?

                    // Parse CLI arguments: [pdf_path] [--page N] [--chapter TEXT]
                    var i = 1
                    while i < args.count {
                        switch args[i] {
                        case "--page" where i + 1 < args.count:
                            startPage = Int(args[i + 1])
                            i += 2
                        case "--chapter" where i + 1 < args.count:
                            chapterQuery = args[i + 1].lowercased()
                            i += 2
                        default:
                            if pdfPath == nil { pdfPath = args[i] }
                            i += 1
                        }
                    }

                    // Open PDF from delegate (open -a) or CLI arg
                    if let url = appDelegate.pendingFileURL {
                        appDelegate.pendingFileURL = nil
                        vm.open(url: url)
                    } else if let path = pdfPath {
                        let url = URL(fileURLWithPath: path)
                        if url.pathExtension.lowercased() == "pdf" {
                            vm.open(url: url)
                        }
                    }

                    // Override reading progress with CLI target page.
                    // Uses pendingPageRestore so navigation happens after the
                    // PDFView is ready and zoom-to-fit completes.
                    if let query = chapterQuery {
                        if let node = vm.outlineNodes.first(where: {
                            $0.label.lowercased().contains(query)
                        }) {
                            vm.overridePendingRestore(to: node.pageIndex)
                        }
                    } else if let page = startPage {
                        vm.overridePendingRestore(to: page)
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open PDF...") { vm.openFilePicker() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Next Page") { vm.nextPage() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                Button("Previous Page") { vm.previousPage() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                Divider()
                Button("Next Chapter") { vm.nextChapter() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Chapter") { vm.previousChapter() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("First Page") { vm.goToPage(0) }
                    .keyboardShortcut(.home, modifiers: .command)
                Button("Last Page") { vm.goToPage(vm.totalPages - 1) }
                    .keyboardShortcut(.end, modifiers: .command)
            }
            CommandMenu("View") {
                ForEach(DisplayMode.allCases) { mode in
                    Button(mode.label) { vm.displayMode = mode }
                }
                Divider()
                Button("Book Layout") { vm.displaysAsBook.toggle() }
                Divider()
                Button("Zoom In") { vm.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { vm.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Zoom to Fit") { vm.zoomToFit() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
