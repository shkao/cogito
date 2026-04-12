import SwiftUI

struct CornellNoteView: View {
    @EnvironmentObject var vm: PDFViewModel
    let pageIndex: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        let chapterNode = vm.chapterNode(at: pageIndex)
        let noteText = Binding(
            get: { vm.cornellNotes[pageIndex] ?? "" },
            set: { vm.cornellNotes[pageIndex] = $0.isEmpty ? nil : $0 }
        )

        VStack(spacing: 0) {
            if let node = chapterNode {
                Button {
                    vm.generateVideoOverview(for: node)
                } label: {
                    Image(systemName: "video.badge.waveform")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(Color.white)
                .help("Generate Video Overview: \(node.label)")
            }

            TextEditor(text: noteText)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.2))
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    vm.isEditingText = focused
                }
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .background(Color.white)
        }
    }
}
