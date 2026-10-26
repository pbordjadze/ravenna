import Foundation

/// The app's version as shown in Settings › About, read from the bundle's Info.plist
/// (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, which CI sets for every build).
nonisolated struct AppInfo: Equatable, Sendable {
    var version: String
    var build: String

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "?"
        build = infoDictionary["CFBundleVersion"] as? String ?? "?"
    }

    /// "1.0.42 (42)"
    var summary: String { "\(version) (\(build))" }
}
