import Foundation
import SwiftUI

/// Says the last save of this photo's draft failed (`Drafts.saveFailed`), with a Retry, at the
/// top of the create flow's preview and of Refine, as the painting screen says so of its progress.
/// The flow tells VoiceOver once when it comes (`CreateFlowView`). Nothing while saves land.
struct DraftSaveToast: View {
    let photoID: UUID
    @Environment(Library.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var text: String { String(localized: "Couldn’t save the draft") }

    var body: some View {
        let drafts = library.drafts
        let failed = drafts.saveFailed == photoID
        VStack {
            if failed {
                Toast(text: Self.text, systemImage: "exclamationmark.triangle", edge: .top) {
                    Button("Retry") { drafts.retry() }
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .accessibilityIdentifier("draft-save-failed")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: failed)
    }
}
