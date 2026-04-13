import SwiftUI

// MARK: - Mindmap Data Model

struct MindmapNode: Codable, Identifiable {
    var id = UUID()
    let title: String
    let children: [MindmapNode]?

    enum CodingKeys: String, CodingKey {
        case title, children
    }

    init(title: String, children: [MindmapNode]? = nil) {
        self.title = title
        self.children = children
    }
}

// MARK: - Branch Colors

private let branchPalette: [Color] = [
    Color(red: 0.36, green: 0.54, blue: 0.86),
    Color(red: 0.30, green: 0.70, blue: 0.60),
    Color(red: 0.85, green: 0.55, blue: 0.25),
    Color(red: 0.65, green: 0.45, blue: 0.78),
    Color(red: 0.85, green: 0.42, blue: 0.55),
    Color(red: 0.45, green: 0.68, blue: 0.35),
    Color(red: 0.75, green: 0.35, blue: 0.35),
    Color(red: 0.55, green: 0.55, blue: 0.75),
]

// MARK: - Mindmap Overlay

struct MindmapOverlayView: View {
    let root: MindmapNode
    let chapterTitle: String
    let onClose: () -> Void
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            Button("", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "brain")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(chapterTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()

                    HStack(spacing: 10) {
                        Button { scale = max(0.4, scale - 0.15) } label: {
                            Image(systemName: "minus.magnifyingglass")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)

                        Text("\(Int(scale * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 36)

                        Button { scale = min(2.5, scale + 0.15) } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }

                    Button { onClose() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                ScrollView([.horizontal, .vertical]) {
                    MindmapTreeView(root: root)
                        .scaleEffect(scale, anchor: .center)
                        .padding(80)
                        .frame(minWidth: 600, minHeight: 400)
                }
                .background(Color(white: 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
    }
}

// MARK: - Mindmap Tree (root + branches)

struct MindmapTreeView: View {
    let root: MindmapNode

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            NodeBadge(title: root.title, depth: 0, colorIndex: 0)

            if let children = root.children, !children.isEmpty {
                ConnectorLine(color: Color.accentColor.opacity(0.4))
                BranchGroup(nodes: children, depth: 1, parentColorIndex: nil)
            }
        }
    }
}

// MARK: - Branch Group (vertical stack with bracket connector)

private struct BranchGroup: View {
    let nodes: [MindmapNode]
    let depth: Int
    let parentColorIndex: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if nodes.count > 1 {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: depth <= 1 ? 10 : 6) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { idx, child in
                    let colorIdx = parentColorIndex ?? idx
                    HStack(spacing: 0) {
                        ConnectorLine(color: branchPalette[colorIdx % branchPalette.count].opacity(0.4))
                        BranchView(node: child, depth: depth, branchColorIndex: colorIdx)
                    }
                }
            }
        }
    }
}

// MARK: - Single Branch (node + optional children)

private struct BranchView: View {
    let node: MindmapNode
    let depth: Int
    let branchColorIndex: Int

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            NodeBadge(title: node.title, depth: depth, colorIndex: branchColorIndex)

            if let children = node.children, !children.isEmpty {
                ConnectorLine(color: branchPalette[branchColorIndex % branchPalette.count].opacity(0.35))
                BranchGroup(nodes: children, depth: depth + 1, parentColorIndex: branchColorIndex)
            }
        }
    }
}

// MARK: - Node Badge

private struct NodeBadge: View {
    let title: String
    let depth: Int
    let colorIndex: Int

    private var color: Color {
        if depth == 0 { return Color.accentColor }
        let base = branchPalette[colorIndex % branchPalette.count]
        return depth == 1 ? base : base.opacity(max(0.55, 1.0 - Double(depth - 1) * 0.2))
    }

    private var fontSize: CGFloat {
        switch depth {
        case 0: return 15
        case 1: return 12
        case 2: return 11
        default: return 10
        }
    }

    var body: some View {
        Text(title)
            .font(.system(size: fontSize, weight: depth <= 1 ? .semibold : .regular))
            .foregroundStyle(.white)
            .fixedSize()
            .padding(.horizontal, depth == 0 ? 18 : (depth == 1 ? 12 : 8))
            .padding(.vertical, depth == 0 ? 10 : (depth == 1 ? 6 : 4))
            .background(color, in: RoundedRectangle(cornerRadius: depth == 0 ? 14 : (depth == 1 ? 10 : 7)))
            .shadow(color: color.opacity(0.3), radius: depth <= 1 ? 4 : 2, y: 1)
    }
}

// MARK: - Connector Line

private struct ConnectorLine: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 22, height: 2)
    }
}
