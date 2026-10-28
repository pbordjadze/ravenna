import os
import UIKit

/// Apse is the app's icon (Paul, October 28, issue #15), and Settings › Icon is gone with the
/// alternates it chose between. iOS keeps an alternate a device chose until the app sets it back,
/// so the first time the app is active with one still set, this sets the primary: iOS shows its own
/// "You have changed the icon" alert for that one switch. After it `alternateIconName` is nil and
/// this does nothing; if the switch fails, the next activation tries again. Ravenna's seam.
enum PrimaryIcon {
    static func restore() async {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != nil, app.applicationState == .active else { return }
        do {
            try await app.setAlternateIconName(nil)
        } catch {
            Log.library.error("Restoring the app icon failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
