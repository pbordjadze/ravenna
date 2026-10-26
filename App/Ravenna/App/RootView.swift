import SwiftUI

/// Routes to the app shell. Debug builds route to a demo scenario when launched with
/// `-demo <name>` (see `DemoMode`); Release builds always show the shell.
struct RootView: View {
    var body: some View {
        #if DEBUG
        switch DemoMode.scenario {
        case "paint-unavailable":
            // The painting screen's stand-in when the device can't draw the canvas.
            CanvasUnavailableView(onClose: {})
                .background(Theme.paper)
                .task { DemoMode.markReady() }
        case let scenario? where scenario.hasPrefix("paint"):
            PaintDemoView(scenario: scenario)
        case let scenario? where scenario.hasPrefix("making-of"):
            MakingOfDemoView(scenario: scenario)
        default:
            AppShellView()
        }
        #else
        AppShellView()
        #endif
    }
}
