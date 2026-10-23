import SwiftUI
import UIKit

/// Where the painter's own options are kept.
enum Keys {
    static let finger = "oneFinger"
    static let sound = "sound"
    static let touch = "touch"
    static let border = "border"
    static let tune = "tune"
    static let row = "rowSound"
    static let ground = "ground"
}

/// What one finger does on the wall (an option until Paul narrows it).
enum OneFinger: String, CaseIterable {
    /// A tap sets a tile, a drag lays a row; two fingers move and zoom.
    case lays
    /// A drag moves the wall and a tap sets a tile, as in v0.
    case moves

    var name: String {
        switch self {
        case .lays: "Lays tiles"
        case .moves: "Moves the wall"
        }
    }
}

/// What a row dragged along the wall sounds like (an option until Paul narrows it).
enum RowSound: String, CaseIterable {
    /// A quick run of the tune, a note a tile.
    case run
    /// One note for the row.
    case note

    var name: String {
        switch self {
        case .run: "A run of the tune"
        case .note: "One note"
        }
    }
}

extension Melody.Mode {
    var name: String {
        switch self {
        case .major: "Major"
        case .minor: "Minor"
        }
    }
}

/// The picture's background as it is, or laid in gold (an option until Paul narrows it).
nonisolated enum GroundChoice: String, CaseIterable, Sendable {
    case picture, gold

    var name: String {
        switch self {
        case .picture: "As in the picture"
        case .gold: "Gold"
        }
    }

    /// The mosaic to set, its background gilded or not.
    func applied(to m: Mosaic) -> Mosaic { self == .gold ? m.goldGround() : m }
}

/// The app's icon: v0's and the alternatives on the design page, until Paul picks.
enum AppIcon: String, CaseIterable, Identifiable {
    case halo, stars, tessera, rows

    var id: Self { self }
    var name: String { rawValue.capitalized }
    /// The alternate icon's name in the asset catalog; nil for the primary.
    var asset: String? { self == .halo ? nil : "AppIcon-\(name)" }
    var preview: String { "Icon-\(name)" }

    var about: String {
        switch self {
        case .halo: "A gold halo in an apse of lapis rows"
        case .stars: "Gold stars on lapis, after the vault of Galla Placidia"
        case .tessera: "One gold tessera being set"
        case .rows: "An arch laid from the inside out"
        }
    }

    static var current: AppIcon { allCases.first { $0.asset == UIApplication.shared.alternateIconName } ?? .halo }
}

/// The painter's options: each a creative fork kept open until Paul narrows it.
struct OptionsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Keys.finger) private var finger = OneFinger.lays
    @AppStorage(Keys.sound) private var sound = true
    @AppStorage(Keys.touch) private var touch = true
    @AppStorage(Keys.border) private var border = Border.none
    @AppStorage(Keys.tune) private var tune = Melody.Mode.major
    @AppStorage(Keys.row) private var row = RowSound.run
    @AppStorage(Keys.ground) private var ground = GroundChoice.picture
    @State private var icon = AppIcon.current

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                Section {
                    Picker("Finish", selection: $library.finish) {
                        ForEach(Finish.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Finish")
                } footer: {
                    Text("How set tiles look. Painted bed: the joints take the colour of the tiles round them, as the plaster under Byzantine mosaics was painted. Glass and stone: glass catches the light at its edges, faces are matte stone, and gold tilts.")
                }
                Section {
                    Picker("Ground", selection: $ground) {
                        ForEach(GroundChoice.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Ground")
                } footer: {
                    Text("Gold lays the picture's background in gold smalti, as behind the figures at Ravenna and in the icons, on a red-brown bed. Your work carries over either way.")
                }
                Section {
                    Picker("Detail", selection: $library.detail) {
                        ForEach(Detail.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Detail")
                } footer: {
                    Text("How many pieces a picture is laid in. Each detail is its own mosaic, and your work on each is kept.")
                }
                Section {
                    Picker("One finger", selection: $finger) {
                        ForEach(OneFinger.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("One finger")
                } footer: {
                    Text(finger == .lays
                         ? "Tap a tile to set it, or drag along a row to lay every tile of the paint in hand, as a mosaicist lays rows. Two fingers move and zoom; a double tap zooms in."
                         : "Drag to move the wall and tap a tile to set it. Pinch to zoom; a double tap zooms in.")
                }
                Section {
                    Toggle("Sound", isOn: $sound)
                    Picker("Tune", selection: $tune) {
                        ForEach(Melody.Mode.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .disabled(!sound)
                    Picker("A row", selection: $row) {
                        ForEach(RowSound.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .disabled(!sound)
                    Toggle("Touch", isOn: $touch)
                } header: {
                    Text("Setting")
                } footer: {
                    Text("Sound: each tile plays the next note of Paint by Moonlight's tune as it clinks into the bed: glass rings, stone is drier, gold shimmers. A used-up paint plays a rising arpeggio, and a finished wall a finale. The silent switch silences it. Touch: a tap on the finger as each tile lands.")
                }
                Section {
                    Picker("Border", selection: $border) {
                        ForEach(Border.allCases) { Text($0.name).tag($0) }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("What goes round the picture of the wall when you share or save it.")
                }
                Section {
                    ForEach(AppIcon.allCases) { choice in
                        Button { choose(choice) } label: {
                            HStack(spacing: 14) {
                                Image(choice.preview).resizable().frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.name).foregroundStyle(Theme.plaster)
                                    Text(choice.about).font(.footnote).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                if icon == choice { Image(systemName: "checkmark").foregroundStyle(Theme.tint) }
                            }
                        }
                        .accessibilityAddTraits(icon == choice ? .isSelected : [])
                    }
                } header: {
                    Text("Icon")
                } footer: {
                    Text("For now, until one is chosen.")
                }
                Section("About") {
                    Text("The pictures are in the public domain, from The Metropolitan Museum of Art's Open Access collection. Each mosaic credits its work.")
                    Text("Contours by Holistically-Nested Edge Detection (Saining Xie and Zhuowen Tu, 2015), in Lvmin Zhang's ControlNet annotator (Apache-2.0).")
                    Text("Set in Alegreya and Alegreya SC by Juan Pablo del Peral, Huerta Tipográfica (SIL Open Font License 1.1).")
                    Text("Most Byzantine mosaicists are anonymous. Ravenna is named for the city whose sixth-century mosaics are its touchstone.")
                }
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func choose(_ choice: AppIcon) {
        guard choice != icon, UIApplication.shared.supportsAlternateIcons else { return }
        icon = choice
        Task {
            do { try await UIApplication.shared.setAlternateIconName(choice.asset) } catch { icon = AppIcon.current }
        }
    }
}
