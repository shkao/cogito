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
                let flat = flattenOutline(nodes: vm.outlineNodes, expandedNodes: expandedNodes, activePath: activePath)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(flat.items.enumerated()), id: \.element.node.id) { index, item in
                            if item.depth == 0 && index > 0 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 0.5)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                            OutlineRowView(
                                node: item.node,
                                isActive: item.isActive,
                                isDeepestActive: item.isDeepestActive,
                                depth: item.depth
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedNodes.contains(item.node.id) {
                                        expandedNodes.remove(item.node.id)
                                    } else {
                                        expandedNodes.insert(item.node.id)
                                    }
                                }
                            }
                            .id(item.node.id)
                            .padding(.leading, CGFloat(item.depth) * 16)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
                .onChange(of: vm.currentPageIndex) { _, _ in
                    let path = vm.activeOutlinePath(for: vm.currentPageIndex)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedNodes = path
                    }
                    let result = flattenOutline(nodes: vm.outlineNodes, expandedNodes: path, activePath: path)
                    if let deepest = result.deepestActiveID {
                        withAnimation {
                            proxy.scrollTo(deepest, anchor: .center)
                        }
                    }
                }
            }
        }
    }

}

struct FlatOutlineItem {
    let node: OutlineNode
    let depth: Int
    let isActive: Bool
    let isDeepestActive: Bool
}

struct FlatOutlineResult {
    let items: [FlatOutlineItem]
    let deepestActiveID: UUID?
}

private func flattenOutline(
    nodes: [OutlineNode],
    expandedNodes: Set<UUID>,
    activePath: Set<UUID>,
    depth: Int = 0
) -> FlatOutlineResult {
    var items: [FlatOutlineItem] = []
    var deepestActiveID: UUID?
    func walk(_ nodes: [OutlineNode], depth: Int) {
        for node in nodes {
            let isActive = activePath.contains(node.id)
            let isDeepestActive: Bool = {
                guard isActive else { return false }
                guard let children = node.children else { return true }
                return !children.contains { activePath.contains($0.id) }
            }()
            if isDeepestActive { deepestActiveID = node.id }
            items.append(FlatOutlineItem(node: node, depth: depth, isActive: isActive, isDeepestActive: isDeepestActive))
            if let children = node.children, !children.isEmpty, expandedNodes.contains(node.id) {
                walk(children, depth: depth + 1)
            }
        }
    }
    walk(nodes, depth: depth)
    return FlatOutlineResult(items: items, deepestActiveID: deepestActiveID)
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
    var depth: Int = 0
    var onToggleExpand: (() -> Void)?
    @State private var isHovered = false

    private var isEligibleForVideo: Bool {
        vm.isContentChapter(node)
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

    private var isMindmapGenerating: Bool {
        vm.mindmapGenerating.contains(node.label)
    }

    private var fontSize: Font {
        switch depth {
        case 0:  return .body
        case 1:  return .callout
        default: return .footnote
        }
    }

    private var fontWeight: Font.Weight {
        if depth == 0 { return isActive ? .semibold : .medium }
        return isActive ? .medium : .regular
    }

    private var shouldShowActions: Bool {
        isHovered || hasExistingMindmap || hasExistingVideo || isGeneratingVideo || isMindmapGenerating
    }

    var body: some View {
        Button {
            vm.goToPage(node.pageIndex)
            if node.children?.isEmpty == false { onToggleExpand?() }
        } label: {
            HStack(spacing: 6) {
                Text(node.label)
                    .font(fontSize)
                    .fontWeight(fontWeight)
                    .foregroundStyle(isDeepestActive ? Color.accentColor : .primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(node.pageLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                if depth == 0 && isEligibleForVideo {
                    HStack(spacing: 6) {
                        Button {
                            vm.generateMindmap(for: node)
                        } label: {
                            Image(systemName: isMindmapGenerating
                                  ? "brain.head.profile.fill"
                                  : (hasExistingMindmap ? "brain.fill" : "brain"))
                                .font(.system(size: 13))
                                .foregroundStyle(
                                    isMindmapGenerating
                                        ? Color.accentColor.opacity(0.75)
                                        : (hasExistingMindmap
                                            ? Color.accentColor.opacity(0.75)
                                            : (isHovered ? Color.accentColor : Color.secondary.opacity(0.5)))
                                )
                                .symbolEffect(.pulse, isActive: isMindmapGenerating)
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
                                .font(.system(size: 13))
                                .foregroundStyle(
                                    isGeneratingVideo
                                        ? Color.teal.opacity(0.8)
                                        : (hasExistingVideo
                                            ? Color.teal.opacity(0.8)
                                            : (isHovered ? Color.accentColor : Color.secondary.opacity(0.5)))
                                )
                                .symbolEffect(.pulse, isActive: isGeneratingVideo)
                        }
                        .buttonStyle(.plain)
                        .help(isGeneratingVideo
                              ? "Generating video..."
                              : (hasExistingVideo ? "Watch: \"\(node.label)\"" : "Generate Video Overview for \"\(node.label)\""))
                    }
                    .opacity(shouldShowActions ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .background {
            if isDeepestActive {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
            } else if isHovered {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            }
        }
        .overlay(alignment: .leading) {
            if isDeepestActive {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
