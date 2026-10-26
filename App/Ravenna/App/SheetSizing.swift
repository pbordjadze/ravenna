import SwiftUI
import UIKit

extension View {
    /// A sheet the size of a page on iPad, where the default form sheet leaves most of a large
    /// screen empty and cuts long content off below the fold; the system's default elsewhere.
    @ViewBuilder
    func pageSizedOnPad() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
