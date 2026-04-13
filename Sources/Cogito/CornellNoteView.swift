import SwiftUI

struct CornellNoteView: View {
    @EnvironmentObject var vm: PDFViewModel
    let pageIndex: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        let noteText = Binding(
            get: { vm.cornellNotes[pageIndex] ?? "" },
            set: { vm.cornellNotes[pageIndex] = $0.isEmpty ? nil : $0 }
        )

        VStack(spacing: 0) {
            TextEditor(text: noteText)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    vm.isEditingText = focused
                }
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .background(Color(.textBackgroundColor))
        }
    }
}
