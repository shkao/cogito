import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var vm: PDFViewModel
    @State private var isDroppingFile = false
    @State private var showingSettings = false
    @State private var showSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView()
                    .frame(width: 240)
                    .background(.background)
                Divider()
            }

            ZStack {
                if vm.document != nil {
                    if vm.displayMode == .twoPage {
                        HStack(spacing: 0) {
                            CornellNoteView(pageIndex: vm.currentPageIndex)
                                .frame(width: 48)
                            PDFReaderView()
                            if vm.currentPageIndex + 1 < vm.totalPages {
                                CornellNoteView(pageIndex: vm.currentPageIndex + 1)
                                    .frame(width: 48)
                            }
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

                    if !vm.videoJobs.isEmpty {
                        VStack {
                            Spacer()
                            VideoGenerationBannerView()
                                .padding(.bottom, 10)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if vm.selectedWord != nil {
                        GeometryReader { geo in
                            let cardWidth: CGFloat = 200
                            let cardHeight: CGFloat = 90
                            let yFrac = vm.selectionYFraction ?? 0.5
                            let clampedY = max(cardHeight / 2 + 8,
                                              min(geo.size.height - cardHeight / 2 - 8,
                                                  geo.size.height * yFrac))
                            // Anchor to the nearest Cornell panel: left margin or right margin
                            let cardX: CGFloat = vm.selectionOnLeftPage
                                ? cardWidth / 2 + 4
                                : geo.size.width - cardWidth / 2 - 4
                            TranslationCardView()
                                .frame(width: cardWidth)
                                .position(x: cardX, y: clampedY)
                        }
                        .allowsHitTesting(true)
                        .transition(.opacity)
                    }
                } else {
                    DropZoneView(openFile: vm.openFilePicker)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: vm.isSearchBarVisible)
            .animation(.easeInOut(duration: 0.2), value: vm.videoJobs.isEmpty)
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
        .overlay {
            if let url = vm.playingVideoURL {
                VideoOverlayView(url: url) { vm.playingVideoURL = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.playingVideoURL == nil)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { withAnimation { showSidebar.toggle() } } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle Sidebar")
        }

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

            Divider()

            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: vm.notebooklmAuthError ? "gear.badge.exclamationmark" : "gear")
                    .foregroundStyle(vm.notebooklmAuthError ? Color.red : Color.primary)
            }
            .help("Settings")
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                NotebookLMSettingsView()
                    .environmentObject(vm)
            }
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

// MARK: - Translation Card

struct TranslationCardView: View {
    @EnvironmentObject var vm: PDFViewModel
    @State private var showingLangPicker = false

    private let langs: [(code: String, label: String)] = [
        ("zh", "中文"), ("ja", "日本語"), ("es", "Español"),
        ("fr", "Français"), ("de", "Deutsch"), ("ko", "한국어"),
        ("pt", "Português"), ("it", "Italiano"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(vm.selectedWord ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer()
                Button {
                    showingLangPicker.toggle()
                } label: {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingLangPicker, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(langs, id: \.code) { lang in
                            Button {
                                vm.translationLang = lang.code
                                if let word = vm.selectedWord { vm.lookupTranslation(for: word) }
                                showingLangPicker = false
                            } label: {
                                HStack {
                                    Text(lang.label).foregroundStyle(.primary)
                                    Spacer()
                                    if vm.translationLang == lang.code {
                                        Image(systemName: "checkmark").font(.system(size: 10))
                                    }
                                }
                                .frame(minWidth: 100)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button { vm.clearTranslation() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            if vm.isLoadingTranslation {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65).tint(.white)
                    Text("Looking up...").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
            } else if let t = vm.wordTranslation {
                Text(t.targetTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                if let desc = t.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
            } else if let err = vm.translationError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }
}

// MARK: - Video Overlay
//
// Uses AVFoundation (AVPlayerLayer) instead of AVKit to avoid loading
// _AVKit_SwiftUI, which crashes on macOS 26.3.1 beta.

private final class VideoHostView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct VideoLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> VideoHostView {
        let v = VideoHostView()
        v.playerLayer.player = player
        return v
    }

    func updateNSView(_ nsView: VideoHostView, context: Context) {
        nsView.playerLayer.player = player
    }
}

@MainActor
private final class VideoPlayerModel: NSObject, ObservableObject {
    let player: AVPlayer
    @Published var isPlaying = true
    @Published var progress: Double = 0
    @Published var duration: Double = 1
    @Published var isSeeking = false
    @Published var currentCaption: String?
    @Published var captionsEnabled = true

    private var timeObserver: Any?
    private var legibleOutput: AVPlayerItemLegibleOutput?
    private var captionsTask: Task<Void, Never>?

    init(url: URL) {
        player = AVPlayer(url: url)
    }

    func start() {
        player.play()
        Task {
            if let d = try? await player.currentItem?.asset.load(.duration), d.seconds > 0 {
                duration = d.seconds
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let s = time.seconds
            Task { @MainActor [weak self] in
                guard let self, !self.isSeeking else { return }
                self.progress = s
            }
        }
        setupCaptions()
    }

    func stop() {
        player.pause()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        captionsTask?.cancel()
        captionsTask = nil
        if let out = legibleOutput {
            player.currentItem?.remove(out)
            legibleOutput = nil
        }
    }

    func togglePlay() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func toggleCaptions() {
        captionsEnabled.toggle()
        if !captionsEnabled { currentCaption = nil }
    }

    private func setupCaptions() {
        guard let item = player.currentItem else { return }
        captionsTask = Task {
            // Select the best matching subtitle/caption track
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                let preferred = AVMediaSelectionGroup.mediaSelectionOptions(
                    from: group.options,
                    filteredAndSortedAccordingToPreferredLanguages: Locale.preferredLanguages
                ).first ?? group.defaultOption ?? group.options.first
                if let opt = preferred {
                    item.select(opt, in: group)
                }
            }
            // Wire up delegate to receive caption strings
            let output = AVPlayerItemLegibleOutput(mediaSubtypesForNativeRepresentation: [])
            output.suppressesPlayerRendering = true
            output.setDelegate(self, queue: .main)
            item.add(output)
            self.legibleOutput = output
        }
    }

    private func formatTime(_ s: Double) -> String {
        let t = Int(max(0, s))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var progressText: String { formatTime(progress) + " / " + formatTime(duration) }
}

extension VideoPlayerModel: AVPlayerItemLegibleOutputPushDelegate {
    nonisolated func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers nativeSamples: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings.first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor [weak self] in
            guard let self, self.captionsEnabled else { return }
            self.currentCaption = text?.isEmpty == false ? text : nil
        }
    }
}

struct VideoOverlayView: View {
    let url: URL
    let onClose: () -> Void

    @StateObject private var model: VideoPlayerModel

    init(url: URL, onClose: @escaping () -> Void) {
        self.url = url
        self.onClose = onClose
        self._model = StateObject(wrappedValue: VideoPlayerModel(url: url))
    }

    var body: some View {
        GeometryReader { geo in
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            // .onExitCommand only fires when a view has focus; a hidden button
            // with a keyboard shortcut works unconditionally.
            Button("", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()

            VStack(spacing: 12) {
                VideoLayerView(player: model.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxHeight: geo.size.height * 0.75)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                    .onAppear { model.start() }
                    .onDisappear { model.stop() }
                    .onTapGesture { model.togglePlay() }
                    .overlay(alignment: .topTrailing) {
                        Button { onClose() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 12, y: -12)
                    }
                    .overlay(alignment: .bottom) {
                        if let caption = model.currentCaption {
                            Text(caption)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                                .padding(.bottom, 14)
                                .padding(.horizontal, 32)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: model.currentCaption)
                    .padding(.horizontal, 40)

                // Playback controls
                HStack(spacing: 14) {
                    Button { model.togglePlay() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24)
                    }
                    .buttonStyle(.plain)

                    Slider(value: $model.progress, in: 0...model.duration) { editing in
                        model.isSeeking = editing
                        if !editing { model.seek(to: model.progress) }
                    }
                    .tint(Color.white.opacity(0.85))

                    Text(model.progressText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 80, alignment: .trailing)

                    Button { model.toggleCaptions() } label: {
                        Image(systemName: model.captionsEnabled ? "captions.bubble.fill" : "captions.bubble")
                            .font(.system(size: 14))
                            .foregroundStyle(model.captionsEnabled ? Color.white : Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help(model.captionsEnabled ? "Hide Captions" : "Show Captions")
                }
                .padding(.horizontal, 44)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
        }
    }
}
