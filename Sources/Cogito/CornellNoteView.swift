import SwiftUI

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

    var body: some View {
        let chapterNode = vm.chapterNode(at: pageIndex)
        ZStack(alignment: .top) {
            TextEditor(text: noteText)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.2))
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in vm.isEditingText = focused }
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .padding(.vertical, chapterNode != nil ? 42 : 4)
                .background(Color.white)

            if let node = chapterNode {
                Button {
                    vm.generateVideoOverview(for: node)
                } label: {
                    Image(systemName: "video.badge.waveform")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white)
                }
                .buttonStyle(.plain)
                .help("Generate Video Overview: \(node.label)")
            }
        }
    }
}
