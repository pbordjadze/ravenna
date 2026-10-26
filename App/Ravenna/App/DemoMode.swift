#if DEBUG
import Foundation

/// Deterministic, launch-argument-driven app states for screenshots and UI tests.
///
///     xcrun simctl launch <udid> com.pbordjadze.paintbynumber -demo paint-progress
///
/// Scenario names are owned by the features that render them (see `RootView`). Scenarios named
/// `*-long-text` are launched with `-NSDoubleLocalizedStrings YES` as well (`ci/screenshots.sh`):
/// every localized string comes out twice as long, standing in for long translations.
///
/// Debug builds only (CI screenshots and UI tests): the demo types are compiled out of Release
/// builds, so a shipped app has no launch argument that swaps its content or library.
enum DemoMode {
    /// The requested scenario, e.g. "gallery", "create", "paint", "paint-progress". A name that
    /// ends in `--tip-<id>` (`paint--tip-benchZen`) is the scenario before it with that tip shown
    /// where it lives (`forcedTip`): this is the name without the suffix.
    static let scenario: String? = requested.map { $0.components(separatedBy: tipSuffix)[0] }

    /// The tip a `--tip-<id>` scenario shows, given its turn once its screen is in view whatever the
    /// moment and the pacing (`TipDesk.force`), so every tip can be seen at its view; the scenario
    /// signals readiness once it is up.
    static let forcedTip: TipID? = requested.flatMap { name in
        name.components(separatedBy: tipSuffix).dropFirst().first.flatMap(TipID.init(rawValue:))
    }

    private static let requested = UserDefaults.standard.string(forKey: "demo")
    private static var isForcingTip = false
    private static let tipSuffix = "--tip-"

    static var isActive: Bool { scenario != nil }

    /// The app is hosting the unit tests: like a demo, it keeps no state between runs.
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// `-openFileOnQuestion YES`: the `-openFile` file arrives the moment the gallery first asks a
    /// question (a rename, restart or delete), not at launch (`GalleryActionsTests`).
    static let opensFileOnQuestion = UserDefaults.standard.bool(forKey: "openFileOnQuestion")

    /// `-openFile <path>`: the file the app opens on launch, through the same handler as a file
    /// opened from the share sheet. The `create-from-file` and `create-unlock` scenarios, given
    /// none, open a library picture written to the temporary directory under a name of its own, so
    /// the title the create flow derives from the file name is visible.
    static let openFileURL: URL? = {
        if let path = UserDefaults.standard.string(forKey: "openFile") { return URL(fileURLWithPath: path) }
        guard ShellDemo.current == .createFromFile || ShellDemo.current == .createUnlock,
              let sample = Sample.named("red-fox")?.url else { return nil }
        let copy = FileManager.default.temporaryDirectory.appending(path: "Winter Fox.jpg")
        try? FileManager.default.removeItem(at: copy)
        do { try FileManager.default.copyItem(at: sample, to: copy) } catch { return nil }
        return copy
    }()

    /// `-tracePhotoPeek YES`: the Photo control's accessibility identifier lists every value it
    /// has had, since a UI test can't read the value mid-hold (`press(forDuration:)` blocks).
    static let tracesPhotoPeek = UserDefaults.standard.bool(forKey: "tracePhotoPeek")

    /// `-tracePaper YES`: the canvas's accessibility identifier names the paper it resolved
    /// (`canvas-paper-light` or `canvas-paper-dark`), so a UI test can see the preference reach it.
    static let tracesPaper = UserDefaults.standard.bool(forKey: "tracePaper")

    /// `-demoFixedPictures YES`: the scenarios that show the picture library by position
    /// (`gallery`, `create-preview`, `create-suggested`) show `ShellDemo`'s fixed pictures
    /// instead, for UI tests that name paintings by their titles: those stay put however the
    /// library is reordered.
    static let usesFixedPictures = UserDefaults.standard.bool(forKey: "demoFixedPictures")

    /// `-slowFullResolution <seconds>`: the create flow's full-resolution generations wait this long
    /// before they start, as one takes tens of seconds on a phone, for the UI tests of what the
    /// painter sees and can do meanwhile (`RefineAfterSlidersTests`).
    static let fullResolutionDelay: Duration? = {
        let seconds = UserDefaults.standard.double(forKey: "slowFullResolution")
        return seconds > 0 ? .seconds(seconds) : nil
    }()

    /// `tmp/demo-ready` in the app's data container. CI screenshots a scenario shortly after
    /// this file appears instead of sleeping for a worst-case delay (`ci/screenshots.sh`).
    static let readyMarker = FileManager.default.temporaryDirectory.appending(path: "demo-ready")

    /// Signals that the scenario's content is on screen; only animations are still settling.
    static func markReady() {
        guard let scenario else { return }
        if let forcedTip {
            // The scenario's content is on screen: now its tip may come, and readiness follows it.
            if !isForcingTip {
                isForcingTip = true
                PaintTips.desk.force(forcedTip)
            }
            Task {
                await PaintTips.awaitDemoTip()
                try? Data(scenario.utf8).write(to: readyMarker, options: .atomic)
            }
            return
        }
        try? Data(scenario.utf8).write(to: readyMarker, options: .atomic)
    }
}
#endif
