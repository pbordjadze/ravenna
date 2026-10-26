import SwiftUI
import UIKit

/// The app's icon, v0's halo or one of the design page's alternatives (the asset catalog's
/// `AppIcon-Stars`, `-Tessera` and `-Rows`, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`), an
/// option in Settings › Icon until Paul picks one. Ravenna's seam, ported from v0's Options.
enum AppIcon: String, CaseIterable, Identifiable {
    case halo, stars, tessera, rows

    var id: Self { self }

    /// The alternate icon's name in the asset catalog; nil for the primary.
    var asset: String? { self == .halo ? nil : "AppIcon-\(rawValue.capitalized)" }
    /// Its picture for Settings (the catalog's `Icon-…` image).
    var preview: String { "Icon-\(rawValue.capitalized)" }

    var name: String {
        switch self {
        case .halo: String(localized: "appIcon.halo", defaultValue: "Halo",
                           comment: "Choice of Settings › Icon: the app icon of a gold halo in an apse")
        case .stars: String(localized: "appIcon.stars", defaultValue: "Stars",
                            comment: "Choice of Settings › Icon: the app icon of gold stars on blue")
        case .tessera: String(localized: "appIcon.tessera", defaultValue: "Tessera",
                              comment: "Choice of Settings › Icon: the app icon of one gold mosaic tile (a tessera)")
        case .rows: String(localized: "appIcon.rows", defaultValue: "Rows",
                           comment: "Choice of Settings › Icon: the app icon of an arch laid in rows of tiles")
        }
    }

    var about: String {
        switch self {
        case .halo: String(localized: "appIcon.halo.about", defaultValue: "A gold halo in an apse of lapis rows",
                           comment: "Settings › Icon: what the Halo app icon shows")
        case .stars: String(localized: "appIcon.stars.about", defaultValue: "Gold stars on lapis, after the vault of Galla Placidia",
                            comment: "Settings › Icon: what the Stars app icon shows (the Mausoleum of Galla Placidia, Ravenna, a proper name)")
        case .tessera: String(localized: "appIcon.tessera.about", defaultValue: "One gold tessera being set",
                              comment: "Settings › Icon: what the Tessera app icon shows")
        case .rows: String(localized: "appIcon.rows.about", defaultValue: "An arch laid from the inside out",
                           comment: "Settings › Icon: what the Rows app icon shows")
        }
    }

    /// The icon the app has now.
    static var current: AppIcon { allCases.first { $0.asset == UIApplication.shared.alternateIconName } ?? .halo }
}

/// Settings › Icon: each icon with its picture, the one in use checked.
struct AppIconSection: View {
    @State private var icon = AppIcon.current

    var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            Section {
                ForEach(AppIcon.allCases) { choice in
                    Button {
                        choose(choice)
                    } label: {
                        HStack(spacing: 14) {
                            Image(choice.preview)
                                .resizable()
                                .frame(width: 52, height: 52)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.name).foregroundStyle(.primary)
                                Text(choice.about).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if icon == choice {
                                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(icon == choice ? .isSelected : [])
                    .accessibilityIdentifier("settings-icon-\(choice.rawValue)")
                }
            } header: {
                Text(String(localized: "settings.section.icon", defaultValue: "Icon",
                            comment: "Header of the Settings section that chooses the app's icon"))
            } footer: {
                Text(String(localized: "settings.icon.footer", defaultValue: "For now, until one is chosen.",
                            comment: "Footer of Settings › Icon: the icons are choices until the app's own is decided"))
            }
        }
    }

    private func choose(_ choice: AppIcon) {
        guard choice != icon else { return }
        icon = choice
        Task {
            do { try await UIApplication.shared.setAlternateIconName(choice.asset) } catch { icon = AppIcon.current }
        }
    }
}
