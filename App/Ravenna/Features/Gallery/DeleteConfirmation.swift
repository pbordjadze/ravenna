import Foundation
import SwiftUI

/// What asking to delete a painting says, wherever it asks: a gallery card's Delete and the
/// recovery screen's Delete Painting. The dialog's title and its button's text are the same in
/// both ("Delete this painting?", this), and so is what the message says is at stake.
enum DeleteConfirmation {
    /// The destructive button: "Delete “Wheat Field”".
    static func buttonTitle(for artwork: Artwork) -> String {
        String(localized: "gallery.delete.confirm", defaultValue: "Delete “\(artwork.title)”",
               comment: "Destructive button of the delete confirmation; the argument is the painting's title")
    }
}

/// The delete confirmation's message: how far along the painting is.
struct DeleteConfirmationMessage: View {
    let artwork: Artwork

    var body: some View {
        if artwork.isComplete {
            Text(String(localized: "gallery.delete.message.finished", defaultValue: "“\(artwork.title)” is finished.",
                        comment: "Delete confirmation message for a finished painting; the argument is its title"))
        } else if artwork.isStarted {
            let percent = ProgressCaption.percentText(artwork)
            Text(String(localized: "gallery.delete.message.started", defaultValue: "“\(artwork.title)” is \(percent) painted.",
                        comment: "Delete confirmation message for a painting in progress; the arguments are its title and the formatted percentage painted, e.g. 42%"))
        } else {
            Text(String(localized: "gallery.delete.message.notStarted", defaultValue: "“\(artwork.title)” hasn’t been started yet.",
                        comment: "Delete confirmation message for a painting nobody has painted on; the argument is its title"))
        }
    }
}
