import SwiftUI
import PDFKit

// MARK: - Sidebar Container

struct SidebarView: View {
    @EnvironmentObject var vm: PDFViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Mode switcher
            HStack(spacing: 0) {
                ForEach(SidebarMode.allCases) { mode in
                    Button {
                        vm.sidebarMode = mode
                    } label: {
                        Image(systemName: mode.icon)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(vm.sidebarMode == mode ? Color.accentColor.opacity(0.15) : .clear)
                            .foregroundColor(vm.sidebarMode == mode ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)

            Divider().padding(.top, 6)

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

    var body: some View {
        if vm.outlineNodes.isEmpty {
            VStack(spacing: 8) {
                if vm.isInferringOutline {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text("Detecting chapters...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "list.bullet.indent")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text(vm.document == nil ? "No document open" : "No outline available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            List(vm.outlineNodes, children: \.children) { node in
                OutlineRowView(node: node)
            }
            .listStyle(.sidebar)
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
    @State private var isHovered = false

    private var isEligibleForVideo: Bool {
        vm.chapterPageRange(for: node).count >= 5
    }

    private var hasExistingVideo: Bool {
        vm.hasVideo(for: node.label)
    }

    var body: some View {
        Button {
            vm.goToPage(node.pageIndex)
        } label: {
            HStack(spacing: 4) {
                Text(node.label)
                    .font(.callout)
                    .foregroundColor(vm.currentPageIndex == node.pageIndex ? .accentColor : .primary)
                    .lineLimit(2)
                Spacer()
                if isEligibleForVideo {
                    Button {
                        vm.generateVideoOverview(for: node)
                    } label: {
                        Image(systemName: hasExistingVideo ? "video.badge.checkmark" : "video.badge.waveform")
                            .font(.system(size: 10))
                            .foregroundStyle(hasExistingVideo ? Color.green : (isHovered ? Color.accentColor : Color.secondary.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .help(hasExistingVideo ? "Video ready: \"\(node.label)\"" : "Generate Video Overview for \"\(node.label)\"")
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
                .foregroundColor(isSelected ? .accentColor : .secondary)
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
                    .foregroundColor(.secondary)
                Text("No bookmarks yet.\nPress Cmd+B to add one.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                            .foregroundColor(.yellow)
                            .font(.caption)
                        let label = vm.document?.page(at: pageIndex)?.label ?? "\(pageIndex + 1)"
                        Text("Page \(label)")
                            .font(.callout)
                            .foregroundColor(vm.currentPageIndex == pageIndex ? .accentColor : .primary)
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
