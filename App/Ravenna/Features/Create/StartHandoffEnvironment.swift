import SwiftUI

private nonisolated struct StartHandoffKey: EnvironmentKey {
    static let defaultValue: StartHandoff? = nil
}

extension EnvironmentValues {
    /// The hand-off from Start Painting to the painting (`StartHandoff`); nil outside the app shell
    /// (previews, demo scenarios that open a painting directly).
    var startHandoff: StartHandoff? {
        get { self[StartHandoffKey.self] }
        set { self[StartHandoffKey.self] = newValue }
    }
}
