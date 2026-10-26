import SwiftUI
import UIKit

/// Presents the system share sheet for files as soon as there are some, and reports when it
/// closes, whether they were shared or not. SwiftUI's `ShareLink` can neither present from
/// code nor tell when sharing ends, and exported movies and feedback are deleted once it does.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    /// Called once the sheet closes; `completed` is false when the person backed out.
    let onFinish: (_ completed: Bool) -> Void

    init(items: [URL], onFinish: @escaping (_ completed: Bool) -> Void) {
        self.items = items
        self.onFinish = onFinish
    }

    init(item: URL?, onFinish: @escaping () -> Void) {
        self.init(items: item.map { [$0] } ?? []) { _ in onFinish() }
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.items = items
        controller.onFinish = onFinish
        // Never inside SwiftUI's update pass: it can race the sheet's own presentation.
        Task { @MainActor [weak controller] in controller?.presentIfNeeded() }
    }

    final class Controller: UIViewController {
        var items: [URL] = []
        var onFinish: ((Bool) -> Void)?
        private var presentedItems: [URL] = []

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            Task { @MainActor [weak self] in self?.presentIfNeeded() }
        }

        func presentIfNeeded() {
            guard !items.isEmpty, items != presentedItems, viewIfLoaded?.window != nil, presentedViewController == nil else { return }
            presentedItems = items
            let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                // iPad: centred over the sheet, without an arrow.
                popover.sourceView = view
                popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                popover.permittedArrowDirections = []
            }
            activity.completionWithItemsHandler = Self.completion { [weak self] completed in self?.onFinish?(completed) }
            present(activity, animated: true)
        }

        /// Built outside the main actor: UIKit may call it on any thread.
        nonisolated private static func completion(
            _ finish: @escaping @MainActor @Sendable (Bool) -> Void
        ) -> UIActivityViewController.CompletionWithItemsHandler {
            { _, completed, _, _ in Task { @MainActor in finish(completed) } }
        }
    }
}
