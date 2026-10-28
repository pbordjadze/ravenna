import SwiftUI
import UIKit

/// The app's icon, v0's halo or one of issue #15's candidates (the asset catalog's `AppIcon-Moonlight`,
/// `-Delta`, `-Star`, `-Tessera`, `-Nimbus` and `-Apse`, `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`,
/// drawn by `sketchbook/icon_candidates.py`), an option in Settings › Icon until Paul picks one.
/// Ravenna's seam, ported from v0's Options.
enum AppIcon: String, CaseIterable, Identifiable {
    case halo, moonlight, delta, star, tessera, nimbus, apse

    var id: Self { self }

    /// The alternate icon's name in the asset catalog; nil for the primary.
    var asset: String? { self == .halo ? nil : "AppIcon-\(rawValue.capitalized)" }
    /// Its picture for Settings (the catalog's `Icon-…` image).
    var preview: String { "Icon-\(rawValue.capitalized)" }

    var name: String {
        switch self {
        case .halo: String(localized: "appIcon.halo", defaultValue: "Halo",
                           comment: "Choice of Settings › Icon: the app icon of a gold halo in an apse")
        case .moonlight: String(localized: "appIcon.moonlight", defaultValue: "Moonlight",
                                comment: "Choice of Settings › Icon: the app icon of a crescent moon over hills, laid in mosaic")
        case .delta: String(localized: "appIcon.delta", defaultValue: "Delta",
                            comment: "Choice of Settings › Icon: the app icon of a night in mosaic with the Greek numeral four (Δʹ, delta)")
        case .star: String(localized: "appIcon.star", defaultValue: "Star",
                           comment: "Choice of Settings › Icon: the app icon of one gold star on blue")
        case .tessera: String(localized: "appIcon.tessera", defaultValue: "Tessera",
                              comment: "Choice of Settings › Icon: the app icon of one gold mosaic tile (a tessera)")
        case .nimbus: String(localized: "appIcon.nimbus", defaultValue: "Nimbus",
                             comment: "Choice of Settings › Icon: the app icon of a moon in a gold halo (a nimbus)")
        case .apse: String(localized: "appIcon.apse", defaultValue: "Apse",
                           comment: "Choice of Settings › Icon: the app icon of an arch opening on a night sky")
        }
    }

    var about: String {
        switch self {
        case .halo: String(localized: "appIcon.halo.about", defaultValue: "A gold halo in an apse of lapis rows",
                           comment: "Settings › Icon: what the Halo app icon shows")
        case .moonlight: String(localized: "appIcon.moonlight.about", defaultValue: "Paint by Moonlight's night, set in smalti",
                                comment: "Settings › Icon: what the Moonlight app icon shows (Paint by Moonlight is an app's name; smalti are mosaic glass)")
        case .delta: String(localized: "appIcon.delta.about", defaultValue: "The same night, its 4 written Δʹ, the Greek numeral",
                            comment: "Settings › Icon: what the Delta app icon shows (Δʹ is the Greek numeral four; keep it as is)")
        case .star: String(localized: "appIcon.star.about", defaultValue: "A gold star on lapis, after the vault of Galla Placidia",
                           comment: "Settings › Icon: what the Star app icon shows (the Mausoleum of Galla Placidia, Ravenna, a proper name)")
        case .tessera: String(localized: "appIcon.tessera.about", defaultValue: "One gold tessera lifted over its place",
                              comment: "Settings › Icon: what the Tessera app icon shows")
        case .nimbus: String(localized: "appIcon.nimbus.about", defaultValue: "The moon in a gold halo, as at San Vitale",
                             comment: "Settings › Icon: what the Nimbus app icon shows (San Vitale, a church in Ravenna, a proper name)")
        case .apse: String(localized: "appIcon.apse.about", defaultValue: "An arch of gold and red opening on the night",
                           comment: "Settings › Icon: what the Apse app icon shows")
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
