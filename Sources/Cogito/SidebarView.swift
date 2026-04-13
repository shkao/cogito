import SwiftUI
import PDFKit

// MARK: - Sidebar Container

struct SidebarView: View {
    @EnvironmentObject var vm: PDFViewModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar Mode", selection: $vm.sidebarMode) {
                ForEach(SidebarMode.allCases) { mode in
                    Image(systemName: mode.icon)
                        .tag(mode)
                        .accessibilityLabel(mode.label)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider().padding(.top, 8)

            // Content
            switch vm.sidebarMode {
            case .outline:    OutlineSidebarView()
            case .thumbnails: ThumbnailSidebarView()
            case .bookmarks:  BookmarkSidebarView()
            case .videos:     VideoLibrarySidebarView()
            }
        }
    }
}

// MARK: - Outline

struct OutlineSidebarView: View {
    @EnvironmentObject var vm: PDFViewModel
    @State private var expandedNodes: Set<UUID> = []

    var body: some View {
        if vm.outlineNodes.isEmpty {
            VStack(spacing: 8) {
                if vm.isInferringOutline {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Detecting chapters...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "list.bullet.indent")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(vm.document == nil ? "No document open" : "No outline available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollViewReader { proxy in
                let activePath = vm.activeOutlinePath(for: vm.currentPageIndex)
                List {
                    ForEach(vm.outlineNodes) { node in
                        OutlineNodeView(node: node, expandedNodes: $expandedNodes, activePath: activePath, isTopLevel: true)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: vm.currentPageIndex) { _, _ in
                    let path = vm.activeOutlinePath(for: vm.currentPageIndex)
                    // Only expand the active path; collapse everything else
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedNodes = path
                    }
                    // Scroll to the deepest active node
                    if let deepest = deepestActiveNode(in: vm.outlineNodes, path: path) {
                        withAnimation {
                            proxy.scrollTo(deepest, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    /// Walk the tree to find the deepest node whose ID is in the active path.
    private func deepestActiveNode(in nodes: [OutlineNode], path: Set<UUID>) -> UUID? {
        for node in nodes.reversed() {
            guard path.contains(node.id) else { continue }
            if let kids = node.children,
               let deeper = deepestActiveNode(in: kids, path: path) {
                return deeper
            }
            return node.id
        }
        return nil
    }
}

/// Recursive outline node with controlled expansion.
private struct OutlineNodeView: View {
    @EnvironmentObject var vm: PDFViewModel
    let node: OutlineNode
    @Binding var expandedNodes: Set<UUID>
    let activePath: Set<UUID>
    var isTopLevel: Bool = false

    private var isActive: Bool { activePath.contains(node.id) }

    /// True when this node is in the active path and none of its children are.
    private var isDeepestActive: Bool {
        guard isActive else { return false }
        guard let children = node.children else { return true }
        return !children.contains { activePath.contains($0.id) }
    }

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedNodes.contains(node.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedNodes.insert(node.id)
                        } else {
                            expandedNodes.remove(node.id)
                        }
                    }
                )
            ) {
                ForEach(children) { child in
                    OutlineNodeView(node: child, expandedNodes: $expandedNodes, activePath: activePath, isTopLevel: false)
                }
            } label: {
                OutlineRowView(node: node, isActive: isActive, isDeepestActive: isDeepestActive, isTopLevel: isTopLevel)
            }
            .id(node.id)
        } else {
            OutlineRowView(node: node, isActive: isActive, isDeepestActive: isDeepestActive, isTopLevel: isTopLevel)
                .id(node.id)
        }
    }
}

// MARK: - Video Library

struct VideoLibrarySidebarView: View {
    @EnvironmentObject var vm: PDFViewModel

    var body: some View {
        Group {
            if vm.cachedVideos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No videos yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Generate a video overview from any chapter.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.cachedVideos, id: \.path) { url in
                    VideoLibraryRow(url: url)
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct VideoLibraryRow: View {
    @EnvironmentObject var vm: PDFViewModel
    let url: URL

    private var title: String { vm.videoTitle(from: url) }

    private var fileSize: String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .lineLimit(2)
                Text(fileSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                vm.deleteCachedVideo(at: url)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete")

            Button {
                vm.playingVideoURL = url
            } label: {
                Image(systemName: "play.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Watch")
        }
    }
}
struct OutlineRowView: View {
    @EnvironmentObject var vm: PDFViewModel
    let node: OutlineNode
    var isActive: Bool = false
    var isDeepestActive: Bool = false
    var isTopLevel: Bool = false
    @State private var isHovered = false

    private var isEligibleForVideo: Bool {
        vm.chapterPageRange(for: node).count >= 5
    }

    private var hasExistingVideo: Bool {
        vm.hasVideo(for: node.label)
    }

    private var isGeneratingVideo: Bool {
        vm.isGeneratingVideo(for: node.label)
    }

    private var hasExistingMindmap: Bool {
        vm.hasMindmap(for: node.label)
    }

    var body: some View {
        Button {
            vm.goToPage(node.pageIndex)
        } label: {
            HStack(spacing: 4) {
                if isDeepestActive {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color(.systemIndigo))
                }
                Text(node.label)
                    .font(.callout)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? Color(.systemIndigo) : .primary)
                    .lineLimit(2)
                Spacer()
                if isTopLevel && isEligibleForVideo {
                    Button {
                        vm.generateMindmap(for: node)
                    } label: {
                        Image(systemName: vm.mindmapGenerating.contains(node.label)
                              ? "brain.head.profile.fill"
                              : (hasExistingMindmap ? "brain.fill" : "brain"))
                            .font(.system(size: 10))
                            .foregroundStyle(
                                vm.mindmapGenerating.contains(node.label)
                                    ? Color(.systemIndigo).opacity(0.75)
                                    : (hasExistingMindmap
                                        ? Color(.systemIndigo).opacity(0.75)
                                        : (isHovered ? Color.accentColor : Color.secondary.opacity(0.5)))
                            )
                            .symbolEffect(.pulse, isActive: vm.mindmapGenerating.contains(node.label))
                    }
                    .buttonStyle(.plain)
                    .help(hasExistingMindmap ? "View mindmap: \"\(node.label)\"" : "Generate mindmap: \"\(node.label)\"")

                    Button {
                        if hasExistingVideo {
                            vm.playingVideoURL = vm.videoURL(for: node.label)
                        } else {
                            vm.generateVideoOverview(for: node)
                        }
                    } label: {
                        Image(systemName: isGeneratingVideo
                              ? "video.badge.ellipsis"
                              : (hasExistingVideo ? "video.badge.checkmark" : "video.badge.waveform"))
                            .font(.system(size: 10))
                            .foregroundStyle(
                                isGeneratingVideo
                                    ? Color(.systemTeal).opacity(0.8)
                                    : (hasExistingVideo
                                        ? Color(.systemTeal).opacity(0.8)
                                        : (isHovered ? Color.accentColor : Color.secondary.opacity(0.5)))
                            )
                            .symbolEffect(.pulse, isActive: isGeneratingVideo)
                    }
                    .buttonStyle(.plain)
                    .help(isGeneratingVideo
                          ? "Generating video..."
                          : (hasExistingVideo ? "Watch: \"\(node.label)\"" : "Generate Video Overview for \"\(node.label)\""))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Thumbnails

struct ThumbnailSidebarView: View {
    @EnvironmentObject var vm: PDFViewModel

    private let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(0..<vm.totalPages, id: \.self) { index in
                        if let page = vm.document?.page(at: index) {
                            PageThumbnailView(page: page, index: index)
                                .id(index)
                                .onTapGesture { vm.goToPage(index) }
                        }
                    }
                }
                .padding(8)
            }
            .onChange(of: vm.currentPageIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

struct PageThumbnailView: View {
    @EnvironmentObject var vm: PDFViewModel
    let page: PDFPage
    let index: Int

    @State private var image: NSImage?

    private var isSelected: Bool { vm.currentPageIndex == index }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.85))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    ProgressView().scaleEffect(0.6)
                }
            }
            .frame(width: 78, height: 104)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            Text(page.label ?? "\(index + 1)")
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .task(id: index) {
            image = page.thumbnail(of: CGSize(width: 156, height: 208), for: .cropBox)
        }
    }
}

// MARK: - Bookmarks

struct BookmarkSidebarView: View {
    @EnvironmentObject var vm: PDFViewModel

    var body: some View {
        if vm.bookmarks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No bookmarks yet.\nPress Cmd+B to add one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List(vm.bookmarks.sorted(), id: \.self) { pageIndex in
                Button {
                    vm.goToPage(pageIndex)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        let label = vm.document?.page(at: pageIndex)?.label ?? "\(pageIndex + 1)"
                        Text("Page \(label)")
                            .font(.callout)
                            .foregroundStyle(vm.currentPageIndex == pageIndex ? Color.accentColor : .primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        vm.bookmarks.remove(pageIndex)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
