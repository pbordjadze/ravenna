import CoreHaptics
import Foundation
import MosaicKit
import PaintCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.autoAdvance) private var autoAdvance = SettingsDefault.autoAdvance
    @AppStorage(SettingsKey.haptics) private var haptics = SettingsDefault.haptics
    @AppStorage(SettingsKey.sounds) private var sounds = SettingsDefault.sounds
    @AppStorage(SettingsKey.sky) private var sky = SkySetting.default
    @AppStorage(SettingsKey.paintingLength) private var paintingLength = PaintingLength.default
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @AppStorage(SettingsKey.lineWeight) private var lineWeight = LineWeight.default
    @AppStorage(SettingsKey.previewStyle) private var previewStyle = PreviewStyle.default
    /// On until switched off here (`TipPreference`).
    @AppStorage(SettingsKey.tipsEnabled) private var tipsEnabled = SettingsDefault.tipsEnabled
    @AppStorage(SettingsKey.playsMakingOf) private var playsMakingOf = SettingsDefault.playsMakingOf
    // Ravenna's options (`TileOptions`, `Typeface`), until Paul narrows them.
    @AppStorage(TileOptions.finishKey) private var finish = Finish.material
    @AppStorage(TileOptions.oneFingerKey) private var oneFinger = OneFinger.lays
    @AppStorage(TileOptions.rowSoundKey) private var rowSound = RowSound.run
    @AppStorage(Typeface.key) private var typeface = Typeface.alegreya
    @Environment(UnlimitedPaintings.self) private var paintings
    @State private var path: [Destination] = []
    @State private var isUnlocking = false

    private let appInfo = AppInfo()
    /// iPad and the simulator have no haptics: nothing to switch, and the header says Sound alone.
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private enum Destination: Hashable { case acknowledgements }
    private static let paintingLengthRow = "painting-length"
    @State private var tipsReset = false

    init() {
        #if DEBUG
        if ShellDemo.current == .settingsAcknowledgements { _path = State(initialValue: [.acknowledgements]) }
        #endif
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        Toggle(isOn: $autoAdvance) {
                            SwiftUI.Label("Advance to Next Color", systemImage: "arrow.forward.circle")
                        }
                        Picker(selection: $paperAppearance) {
                            ForEach(PaperAppearance.allCases) { appearance in
                                Text(appearance.name).tag(appearance)
                            }
                        } label: {
                            SwiftUI.Label("Paper", systemImage: "circle.lefthalf.filled")
                        }
                        .accessibilityIdentifier("paper-appearance")
                        Picker(selection: $lineWeight) {
                            ForEach(LineWeight.allCases) { weight in
                                Text(weight.name).tag(weight)
                            }
                        } label: {
                            SwiftUI.Label("Line Weight", systemImage: "lineweight")
                        }
                        .accessibilityIdentifier("settings-line-weight")
                        Picker(selection: $finish) {
                            ForEach(Finish.allCases, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        } label: {
                            SwiftUI.Label("Finish", systemImage: "square.grid.3x3.fill")
                        }
                        .accessibilityIdentifier("settings-finish")
                        Picker(selection: $oneFinger) {
                            ForEach(OneFinger.allCases, id: \.self) { choice in
                                Text(choice.name).tag(choice)
                            }
                        } label: {
                            SwiftUI.Label("One Finger", systemImage: "hand.point.up")
                        }
                        .accessibilityIdentifier("settings-one-finger")
                        Picker(selection: $typeface) {
                            ForEach(Typeface.allCases, id: \.self) { choice in
                                Text(choice.name).tag(choice)
                            }
                        } label: {
                            SwiftUI.Label("Typeface", systemImage: "textformat")
                        }
                        .accessibilityIdentifier("settings-typeface")
                    } header: {
                        // Not the "Painting" key: that one names a picture, this one the activity.
                        Text(String(localized: "settings.section.painting", defaultValue: "Painting",
                                    comment: "Header of the Settings section about how painting behaves (the activity, not a picture); it holds Advance to Next Color, Paper and Line Weight"))
                    }

                    Section {
                        Toggle(isOn: $tipsEnabled) {
                            SwiftUI.Label("Tips", systemImage: "lightbulb")
                        }
                        .accessibilityIdentifier("settings-tips")
                        Button {
                            PaintTips.showAgain()
                            tipsReset = true
                        } label: {
                            if tipsReset {
                                SwiftUI.Label("Tips Will Show Again", systemImage: "checkmark")
                            } else {
                                SwiftUI.Label("Show Tips Again", systemImage: "arrow.counterclockwise")
                            }
                        }
                        .disabled(tipsReset)
                        .accessibilityIdentifier("settings-show-tips-again")
                    } footer: {
                        Text("Tips appear beside things as you reach them, one at a time. Turn them off here whenever you like.")
                    }

                    Section {
                        if supportsHaptics {
                            Toggle(isOn: $haptics) {
                                SwiftUI.Label("Haptics", systemImage: "hand.tap")
                            }
                        }
                        Toggle(isOn: $sounds) {
                            SwiftUI.Label("Sounds", systemImage: "speaker.wave.2")
                        }
                        // A theme of its own, apart from the appearance and the paper: Sun, Moon or
                        // Auto, one row like Paper's (Paul, October 18, from the plain list he
                        // first asked for).
                        Picker(selection: $sky) {
                            ForEach(SkySetting.allCases) { choice in
                                Text(choice.name).tag(choice)
                            }
                        } label: {
                            SwiftUI.Label("Music", systemImage: "music.note")
                        }
                        .accessibilityIdentifier("settings-music")
                        Picker(selection: $rowSound) {
                            ForEach(RowSound.allCases, id: \.self) { choice in
                                Text(choice.name).tag(choice)
                            }
                        } label: {
                            SwiftUI.Label("Row Sound", systemImage: "music.note.list")
                        }
                        .accessibilityIdentifier("settings-row-sound")
                    } header: {
                        if supportsHaptics {
                            Text("Sound & Haptics")
                        } else {
                            Text("Sound")
                        }
                    } footer: {
                        // Only Auto has hours to explain: under Sun or Moon the line described a
                        // choice not made.
                        if sky == .auto {
                            Text(String(localized: "settings.sky.footer",
                                        defaultValue: "Auto plays the tune in major from \(Sky.clockText(Sky.sunrise)) and in minor from \(Sky.clockText(Sky.nightfall)), your time.",
                                        comment: "Footer of Settings › Sound, under its Music row while it is set to Auto (the other choices are Major and Minor). The arguments are the hours, as the painter's clock writes them: when major begins (6 AM) and when minor begins (7 PM)"))
                        }
                    }

                    // Painting Length last, so its footer sits under it.
                    Section {
                        Picker(selection: $previewStyle) {
                            ForEach(PreviewStyle.allCases) { style in
                                Text(style.name).tag(style)
                            }
                        } label: {
                            SwiftUI.Label("Preview", systemImage: "rectangle.split.2x1")
                        }
                        .accessibilityIdentifier("settings-preview")
                        Picker(selection: $paintingLength) {
                            ForEach(PaintingLength.allCases, id: \.self) { length in
                                Text(length.name).tag(length)
                            }
                        } label: {
                            SwiftUI.Label("Painting Length", systemImage: "hourglass")
                        }
                        .accessibilityIdentifier("painting-length")
                        .id(Self.paintingLengthRow)
                        // Worth a Look Here, the first time Settings opens, once the row is there to point at.
                        .gentleTip(.drawerWorthALook, arrowEdge: .top)
                        .onAppear { PaintTips.drawerRowReached() }
                    } header: {
                        Text("New Paintings")
                    } footer: {
                        Text(paintingLength.footer)
                            .accessibilityIdentifier("painting-length-footer")
                    }

                    Section {
                        Toggle(isOn: $playsMakingOf) {
                            SwiftUI.Label("The Making-of", systemImage: "film")
                        }
                        .accessibilityIdentifier("settings-making-of")
                    } footer: {
                        Text("After Start Painting, watch your photo become its painting, step by step. It takes about 20 seconds, and a tap skips it.")
                    }

                    if paintings.isSold { unlimitedPaintings }

                    Section {
                        LabeledContent {
                            Text(appInfo.summary)
                        } label: {
                            SwiftUI.Label("Version", systemImage: "info.circle")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("about-version")
                        NavigationLink(value: Destination.acknowledgements) {
                            SwiftUI.Label("Acknowledgements", systemImage: "text.book.closed")
                        }
                        .accessibilityIdentifier("about-acknowledgements")
                    } header: {
                        Text("About")
                    } footer: {
                        Text("Your photos and paintings stay on this device unless you share them or choose to send feedback. Paint by Moonlight has no accounts, ads or tracking.")
                    }
                }
                #if DEBUG
                // On a phone the row is below the fold, and its tip comes only once it is reached.
                .task {
                    guard ShellDemo.current == .settingsTip else { return }
                    try? await Task.sleep(for: .seconds(1))
                    withAnimation { proxy.scrollTo(Self.paintingLengthRow, anchor: .center) }
                }
                #endif
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .acknowledgements: AcknowledgementsView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                        .tint(Theme.signature)
                }
            }
        }
        .presentationDetents([.large])
        .pageSizedOnPad()
        .tint(Theme.accent)
        // Tips on or off takes effect at once, and Show Tips Again can be used once more after the
        // switch has been turned off.
        .onChange(of: tipsEnabled) { _, enabled in
            PaintTips.setEnabled(enabled)
            if !enabled { tipsReset = false }
        }
        .onAppear { PaintTips.drawerOpened() }
        .onDisappear { PaintTips.desk.leave(.drawer) }
        .sheet(isPresented: $isUnlocking) { UnlockSheet() }
    }

    /// Unlimited Paintings (`UnlimitedPaintings`): bought, or the free paintings left and the way
    /// to buy it or restore it (`UnlockSheet`). SideStore builds sell nothing and show none of it.
    private var unlimitedPaintings: some View {
        Section {
            if paintings.isUnlocked {
                LabeledContent {
                    Text("Unlocked")
                } label: {
                    SwiftUI.Label("Unlimited Paintings", systemImage: "infinity")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings-unlimited")
            } else {
                LabeledContent {
                    Text(String(localized: "settings.freePaintings.left", defaultValue: "\(paintings.freeLeft) left",
                                comment: "Settings › Unlimited Paintings: the value of its Free Paintings row before the unlock is bought; the argument is how many free paintings are left (at most 3)"))
                } label: {
                    SwiftUI.Label("Free Paintings", systemImage: "photo")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("settings-free-paintings")
                Button {
                    isUnlocking = true
                } label: {
                    SwiftUI.Label("Unlimited Paintings", systemImage: "infinity")
                }
                .accessibilityIdentifier("settings-unlimited")
            }
        } footer: {
            if paintings.isUnlocked {
                Text("Thank you for supporting Paint by Moonlight.")
            } else {
                Text("A free painting of your own photos comes back each day, up to three. Everything in Samples is always free.")
            }
        }
    }
}
