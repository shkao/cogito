import SwiftUI
import PDFKit

struct PDFReaderView: NSViewRepresentable {
    @EnvironmentObject var vm: PDFViewModel

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()

        view.displayMode = vm.displayMode.pdfDisplayMode
        view.displaysAsBook = vm.displaysAsBook
        view.displayDirection = .horizontal
        view.displayBox = .cropBox
        view.autoScales = false
        view.displaysPageBreaks = false
        view.pageBreakMargins = NSEdgeInsetsZero
        view.pageShadowsEnabled = false
        view.backgroundColor = .white

        view.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.frameChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )

        vm.pdfView = view
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        var needsZoom = false

        if view.document !== vm.document {
            view.document = vm.document
            needsZoom = true
        }

        let targetMode = vm.displayMode.pdfDisplayMode
        if view.displayMode != targetMode {
            view.displayMode = targetMode
            needsZoom = true
        }

        if view.displaysAsBook != vm.displaysAsBook {
            view.displaysAsBook = vm.displaysAsBook
        }

        if needsZoom {
            DispatchQueue.main.async { self.vm.zoomToFit() }
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.vm.pdfView = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(vm: vm)
    }

    class Coordinator: NSObject {
        let vm: PDFViewModel

        init(vm: PDFViewModel) {
            self.vm = vm
        }

        @objc func frameChanged(_ notification: Notification) {
            Task { @MainActor in self.vm.zoomToFit() }
        }

        @objc func pageChanged(_ notification: Notification) {
            Task { @MainActor in self.vm.syncCurrentPage() }
        }
    }
}
