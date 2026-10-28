import SwiftUI
import TipKit

@main
struct PaintByNumberApp: App {
    @State private var library = Library.forLaunch()
    @State private var paintings = UnlimitedPaintings.forLaunch()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if DemoMode.isActive { MainThreadWatchdog.start() }
        #endif
        Preferences.removeRetiredSettings()
        PaintTips.configure()
        Theme.styleNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(paintings)
                .tint(Theme.accent)
                // Tip popovers draw their icons in the system blue otherwise, not the tint.
                .tipImageStyle(Theme.accent)
                // Ravenna's seam: Apse back on a device that chose one of the old alternates.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { Task { await PrimaryIcon.restore() } }
                }
        }
        .commands { PaintCommands() }
    }
}
