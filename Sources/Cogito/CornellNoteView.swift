import SwiftUI

// Overrides the TextEditor's I-beam by deferring the cursor set to the
// next run loop tick, after NSTextView has processed the mouse-moved event.
private struct PointingHandCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ nsView: CursorView, context: Context) {}

    class CursorView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                    DispatchQueue.main.async { self?.applyIfNeeded() }
                    return event
                }
            } else {
                removeMonitor()
            }
        }

        private func applyIfNeeded() {
            guard let window else { return }
            let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(loc) { NSCursor.pointingHand.set() }
        }

        private func removeMonitor() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        deinit { removeMonitor() }
    }
}

private struct VideoIconButton: View {
    let label: String
    let blocked: Bool
    let action: () -> Void
    let regenAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: { if !blocked { action() } }) {
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 13))
                .foregroundStyle(blocked ? Color.secondary : (isHovered ? Color.white : Color.accentColor))
                .padding(6)
                .background(
                    blocked
                        ? AnyShapeStyle(Color.primary.opacity(0.06))
                        : (isHovered ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.1))),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 && !blocked }
        .background(blocked ? nil : PointingHandCursor())
        .help(blocked ? "Already generating a video..." : "Generate Video Overview for \"\(label)\"")
        .scaleEffect(!blocked && isHovered ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .opacity(blocked ? 0.5 : 1.0)
        .contextMenu {
            Button("Generate Video Overview") { if !blocked { action() } }
                .disabled(blocked)
            Button("Re-generate") { if !blocked { regenAction() } }
                .disabled(blocked)
        }
    }
}

struct CornellNoteView: View {
    @EnvironmentObject var vm: PDFViewModel
    let pageIndex: Int

    @FocusState private var isFocused: Bool

    private var noteText: Binding<String> {
        Binding(
            get: { vm.cornellNotes[pageIndex] ?? "" },
            set: { vm.cornellNotes[pageIndex] = $0.isEmpty ? nil : $0 }
        )
    }

    private var chapterNode: OutlineNode? {
        guard pageIndex >= 2 else { return nil }
        guard let node = vm.outlineNodes.first(where: { $0.pageIndex == pageIndex }) else { return nil }
        guard vm.chapterPageRange(for: node).count >= 5 else { return nil }
        return node
    }

    var body: some View {
        ZStack(alignment: .top) {
            TextEditor(text: noteText)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.2))
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in vm.isEditingText = focused }
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .background(Color.white)

            if let node = chapterNode {
                let blocked = vm.isGeneratingVideo
                VideoIconButton(label: node.label, blocked: blocked) {
                    vm.generateVideoOverview(for: node)
                } regenAction: {
                    vm.generateVideoOverview(for: node, forceRegenerate: true)
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
        }
    }
}
