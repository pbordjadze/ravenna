import SwiftUI

/// The painting in the focused window, for menu bar commands and keyboard shortcuts.
///
/// Equatable by what the menu shows, not by its closure: a focused value that never compares equal
/// counts as changed at every render of the painting screen, which rebuilt the Paint menu every
/// time and kept the screen rendering 30 to 70 times a second, enough to hang the UI tests
/// (`StartHandoffUITests`, October 19).
struct PaintingFocus: Equatable {
    let session: PaintingSession
    let controller: CanvasController
    let showsNumbers: Binding<Bool>
    /// Nil when the painting has no photo to show.
    let showsPhoto: Binding<Bool>?
    /// Feedback mode: painting is off, so are the commands.
    let isGivingFeedback: Bool
    let giveFeedback: () -> Void
    /// What the two toggles showed when this focus was made: their bindings read the current state,
    /// so an older focus would always agree with a newer one.
    private let shown: (numbers: Bool, photo: Bool?)

    init(
        session: PaintingSession, controller: CanvasController, showsNumbers: Binding<Bool>,
        showsPhoto: Binding<Bool>?, isGivingFeedback: Bool, giveFeedback: @escaping () -> Void
    ) {
        self.session = session
        self.controller = controller
        self.showsNumbers = showsNumbers
        self.showsPhoto = showsPhoto
        self.isGivingFeedback = isGivingFeedback
        self.giveFeedback = giveFeedback
        shown = (showsNumbers.wrappedValue, showsPhoto?.wrappedValue)
    }

    nonisolated static func == (lhs: PaintingFocus, rhs: PaintingFocus) -> Bool {
        lhs.session === rhs.session && lhs.controller === rhs.controller
            && lhs.isGivingFeedback == rhs.isGivingFeedback
            && lhs.shown.numbers == rhs.shown.numbers && lhs.shown.photo == rhs.shown.photo
    }
}

extension FocusedValues {
    @Entry var painting: PaintingFocus?
}

/// The Paint menu (iPadOS menu bar and the ⌘ shortcut overlay). Single keys act like tool
/// keys in drawing apps; the painting screen has no text input for them to collide with.
/// Undo and redo come from the window's undo manager (see `PaintChromeState`).
struct PaintCommands: Commands {
    @FocusedValue(\.painting) private var painting

    var body: some Commands {
        CommandMenu("Paint") {
            Group {
                Button("Next Color") { step(1) }
                    .keyboardShortcut("]", modifiers: [])
                Button("Previous Color") { step(-1) }
                    .keyboardShortcut("[", modifiers: [])
                Button("Show Hint") { painting?.controller.showHint() }
                    .keyboardShortcut("h", modifiers: [])
                    .disabled(painting?.session.isComplete ?? true)
                Divider()
                Toggle("Show Numbers", isOn: painting?.showsNumbers ?? .constant(true))
                    .keyboardShortcut("n", modifiers: [])
                Toggle("Show Photo", isOn: painting?.showsPhoto ?? .constant(false))
                    .keyboardShortcut("p", modifiers: [])
                    .disabled(painting?.showsPhoto == nil)
                Divider()
                Button("Zoom In") { painting?.controller.zoom(by: 2) }
                    .keyboardShortcut("+")
                Button("Zoom Out") { painting?.controller.zoom(by: 0.5) }
                    .keyboardShortcut("-")
                Button("Zoom to Fit") { painting?.controller.zoomToFit() }
                    .keyboardShortcut("0")
                Divider()
                Button("Give Feedback…") { painting?.giveFeedback() }
            }
            .disabled(painting == nil || painting?.isGivingFeedback == true)
        }
    }

    /// Selects the next (or previous) color in the palette's order that still has regions to
    /// paint.
    private func step(_ delta: Int) {
        guard let session = painting?.session,
              let next = session.nextIncompleteColor(after: session.selectedColor, backwards: delta < 0),
              next != session.selectedColor
        else { return }
        session.select(color: next)
        FeedbackEngine.shared.selectionChanged()
    }
}
