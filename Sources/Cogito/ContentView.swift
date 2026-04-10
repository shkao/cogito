import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var vm: PDFViewModel
    @State private var isDroppingFile = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            ZStack {
                if vm.document != nil {
                    if vm.displayMode == .twoPage {
                        HStack(spacing: 0) {
                            CornellNoteView(pageIndex: vm.currentPageIndex)
                                .frame(width: 48)
                            PDFReaderView()
                            CornellNoteView(pageIndex: min(vm.currentPageIndex + 1, vm.totalPages - 1))
                                .frame(width: 48)
                        }
                    } else {
                        PDFReaderView()
                    }
                    if vm.isSearchBarVisible {
                        VStack {
                            SearchBarView()
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .padding(.top, 4)
                            Spacer()
                        }
                    }
                } else {
                    DropZoneView(openFile: vm.openFilePicker)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: vm.isSearchBarVisible)
            .onDrop(of: [UTType.pdf, UTType.fileURL], isTargeted: $isDroppingFile) { providers in
                loadDroppedPDF(from: providers)
            }
            .overlay {
                if isDroppingFile {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.06).clipShape(RoundedRectangle(cornerRadius: 10)))
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
        }
        .toolbar { toolbarItems }
        .navigationTitle(vm.documentTitle)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if vm.document != nil {
                HStack(spacing: 2) {
                    Button { vm.previousPage() } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!vm.canGoBack)
                    .help("Previous Page (Cmd+Left)")

                    PageIndicatorView()

                    Button { vm.nextPage() } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!vm.canGoForward)
                    .help("Next Page (Cmd+Right)")
                }
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            DisplayModePicker()

            Divider()

            Button { vm.zoomOut() } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out (Cmd+-)")

            Button { vm.zoomToFit() } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Zoom to Fit (Cmd+0)")

            Button { vm.zoomIn() } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In (Cmd+=)")

            Divider()

            Button { vm.openFilePicker() } label: {
                Image(systemName: "folder")
            }
            .help("Open PDF (Cmd+O)")

            Button {
                withAnimation { vm.isSearchBarVisible.toggle() }
                if !vm.isSearchBarVisible { vm.clearSearch() }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search (Cmd+F)")
            .keyboardShortcut("f", modifiers: .command)

            Button { vm.toggleBookmark() } label: {
                Image(systemName: vm.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundColor(vm.isCurrentPageBookmarked ? .yellow : .primary)
            }
            .help(vm.isCurrentPageBookmarked ? "Remove Bookmark (Cmd+B)" : "Add Bookmark (Cmd+B)")
            .keyboardShortcut("b", modifiers: .command)
            .disabled(vm.document == nil)
        }
    }

    // MARK: - Drop

    private func loadDroppedPDF(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.pdf.identifier) { item, _ in
                let url: URL? = {
                    if let u = item as? URL { return u }
                    if let d = item as? Data { return URL(dataRepresentation: d, relativeTo: nil) }
                    return nil
                }()
                if let url {
                    Task { @MainActor in vm.open(url: url) }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "pdf" else { return }
                Task { @MainActor in vm.open(url: url) }
            }
            return true
        }

        return false
    }
}

// MARK: - Drop Zone

struct DropZoneView: View {
    let openFile: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 52))
                .foregroundColor(.secondary)
                .symbolEffect(.pulse, isActive: isHovering)

            Text("Open a PDF to start reading")
                .font(.title3)
                .foregroundColor(.secondary)

            Button("Choose File...") { openFile() }
                .keyboardShortcut("o", modifiers: .command)
                .controlSize(.large)

            Text("or drag and drop a PDF here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

// MARK: - Search Bar

struct SearchBarView: View {
    @EnvironmentObject var vm: PDFViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.callout)

            TextField("Search in document...", text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in vm.isEditingText = focused }
                .onSubmit { vm.performSearch() }

            if !vm.searchResults.isEmpty {
                Text("\(vm.currentSearchIndex + 1) / \(vm.searchResults.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Button { vm.previousSearchResult() } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .help("Previous Result")

                Button { vm.nextSearchResult() } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .help("Next Result")
            } else if !vm.searchQuery.isEmpty {
                Text("No results")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button { vm.clearSearch() } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Search (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(.horizontal, 120)
        .onAppear { isFocused = true }
    }
}

// MARK: - Display Mode Picker (segmented style with per-button tooltips)

struct DisplayModePicker: View {
    @EnvironmentObject var vm: PDFViewModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DisplayMode.allCases) { mode in
                Button {
                    vm.displayMode = mode
                } label: {
                    Image(systemName: mode.icon)
                        .frame(width: 28, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    vm.displayMode == mode
                        ? Color.primary.opacity(0.15)
                        : Color.clear
                )
                .help(mode.label)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
    }
}

// MARK: - Page Indicator

struct PageIndicatorView: View {
    @EnvironmentObject var vm: PDFViewModel
    @State private var isEditing = false
    @State private var inputText = ""
    @FocusState private var isFocused: Bool

    private var spread: String {
        guard vm.totalPages > 0 else { return "" }
        let p = vm.currentPageIndex + 1
        if vm.displayMode.isTwoPage, p < vm.totalPages {
            return "\(p)–\(p + 1)"
        }
        return "\(p)"
    }

    private var pct: Int {
        guard vm.totalPages > 0 else { return 0 }
        return Int(round(Double(vm.currentPageIndex + 1) / Double(vm.totalPages) * 100))
    }

    var body: some View {
        Group {
            if isEditing {
                TextField("Go to page", text: $inputText)
                    .frame(width: 90)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12).monospacedDigit())
                    .focused($isFocused)
                    .onChange(of: isFocused) { _, focused in
                        vm.isEditingText = focused
                        if !focused { isEditing = false }
                    }
                    .onSubmit {
                        if let n = Int(inputText), n >= 1, n <= vm.totalPages {
                            vm.goToPage(n - 1)
                        }
                        inputText = ""
                        isEditing = false
                    }
                    .onExitCommand {
                        inputText = ""
                        isEditing = false
                    }
                    .onAppear { isFocused = true }
            } else {
                HStack(spacing: 0) {
                    Text(spread)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)

                    Text(" / \(vm.totalPages)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text("  ·  ")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)

                    Text("\(pct)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .onTapGesture { isEditing = true }
                .help("Click to jump to page")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }
}
