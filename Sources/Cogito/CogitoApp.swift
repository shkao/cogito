import SwiftUI

@main
struct CogitoApp: App {
    @StateObject private var vm = PDFViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open PDF...") { vm.openFilePicker() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Navigate") {
                Button("Next Page") { vm.nextPage() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Previous Page") { vm.previousPage() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                Button("First Page") { vm.goToPage(0) }
                    .keyboardShortcut(.home, modifiers: .command)
                Button("Last Page") { vm.goToPage(vm.totalPages - 1) }
                    .keyboardShortcut(.end, modifiers: .command)
            }
            CommandMenu("View") {
                ForEach(DisplayMode.allCases) { mode in
                    Button(mode.label) { vm.displayMode = mode }
                }
                Divider()
                Button("Book Layout") { vm.displaysAsBook.toggle() }
                Divider()
                Button("Zoom In") { vm.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("Zoom Out") { vm.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Zoom to Fit") { vm.zoomToFit() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
