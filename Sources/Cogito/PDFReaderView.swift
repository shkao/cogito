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
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
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
            DispatchQueue.main.async {
                self.vm.zoomToFit()
                self.vm.applyPendingRestore()
            }
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
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowChangedScreen(_:)),
                name: NSWindow.didChangeScreenNotification,
                object: nil
            )
        }

        @objc func frameChanged(_ notification: Notification) {
            Task { @MainActor in self.vm.zoomToFit() }
        }

        @objc func pageChanged(_ notification: Notification) {
            Task { @MainActor in self.vm.syncCurrentPage() }
        }

        @objc func selectionChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView else { return }

            let sel = view.currentSelection
            let word = Self.normalizeWord(sel?.string)

            var yFrac: CGFloat = 0.5
            var onLeft = false
            if let sel, let page = sel.pages.first {
                let pageRect = sel.bounds(for: page)
                let viewRect = view.convert(pageRect, from: page)
                yFrac = 1.0 - viewRect.midY / max(view.bounds.height, 1)
                onLeft = viewRect.midX < view.bounds.midX
            }

            Task { @MainActor in
                guard !self.vm.suppressSelectionLookup else { return }
                guard let word else { self.vm.clearTranslation(); return }
                self.vm.scheduleTranslation(word: word, yFrac: yFrac, onLeft: onLeft)
            }
        }

        // Rejoins line-break hyphenation ("re-\nductionist") and validates single-word selections.
        static func normalizeWord(_ raw: String?) -> String? {
            guard var s = raw else { return nil }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)

            if let r = s.range(of: #"-\s+"#, options: .regularExpression) {
                let before = String(s[s.startIndex..<r.lowerBound])
                let after  = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !before.contains(" "), !after.contains(" ") {
                    s = before + after
                }
            }

            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty,
                  !s.contains(" "),
                  s.count <= 40,
                  s.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            else { return nil }
            return s
        }

        @objc func windowChangedScreen(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor [self] in
                guard window === vm.pdfView?.window else { return }
                vm.zoomToFit()
            }
        }
    }
}
