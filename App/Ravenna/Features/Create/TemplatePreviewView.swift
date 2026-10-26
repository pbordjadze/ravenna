import CoreGraphics
import Foundation
import MosaicEngine
import MosaicKit
import PaintCore
import SwiftUI
import UIKit

/// Second step of the create flow: the mosaic, compared with the photo, tuned live with the
/// recipe's few controls, and the painting's name. In compact windows (iPhone) the card shows one
/// group of the recipe at a time, chosen above it, and the preview can be enlarged: the comparison
/// then fills the page above that group, Pieces first.
///
/// Ravenna's seam: the card holds Ravenna's recipe (`MosaicEngine.Recipe`: Pieces, Eyes and Mouth,
/// the Ground, the Panel, as v0's new-mosaic sheet and options had them) where Paint by Moonlight's
/// Colors, Detail, Smoothness and Lines sliders were, with no suggestion chip, Adjust or Refine.
struct TemplatePreviewView: View {
    @Bindable var model: CreateModel
    var onStart: () async throws -> Void
    /// Closes the flow, where the preview is its first page (a sample or a photo opened from
    /// elsewhere); the enlarged preview hides it.
    var onClose: (() -> Void)?
    /// Told where the comparison's picture is on screen, for Start Painting's hand-off to move it
    /// from (`StartHandoff`).
    var pictureProbe: PreviewPictureProbe?

    @State private var size: CGSize = .zero
    /// `size` with the keyboard's room given back: what the layout is chosen for.
    @State private var roomSize: CGSize = .zero
    /// The layout chosen when title editing began, for that window width: kept until it ends.
    @State private var editingLayout: (width: CGFloat, sideBySide: Bool)?
    @State private var isStarting = false
    @State private var startError: String?
    /// Start Painting found no free painting left for the painter's own photo.
    @State private var offersUnlock = false
    @State private var isTuning = false
    /// The group a compact window's card shows; nil until the painter picks one.
    @State private var tunedSetting: Setting?
    /// The panel's sheet is up, and where the painter has moved the panel on it.
    @State private var isFraming = false
    @State private var framingCentre = SIMD2<Double>(0.5, 0.5)
    @FocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(UnlimitedPaintings.self) private var paintings

    // In two parts, which the compiler type-checks apart: as one chain it ran out of time.
    var body: some View {
        observingTheModel(screen)
            .modifier(UnlockOffer(isPresented: $offersUnlock, start: start))
            .alert("Couldn’t Create Painting", isPresented: isShowingStartError) {
                Button("Try Again", action: start)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(startError ?? "")
            }
    }

    /// The preview, its bar and its covers.
    private var screen: some View {
        Group {
            if isSideBySide {
                HStack(spacing: 24) {
                    canvas
                    // The card keeps its natural height, centred, and scrolls only when the
                    // window is too short for it (iPhone in landscape).
                    ScrollView {
                        controls
                            .background(Theme.surface, in: .rect(cornerRadius: 30, style: .continuous))
                            .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
                            .padding(.vertical, 12)
                            .frame(minHeight: max(0, size.height - 2 * sidePadding), alignment: .center)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .frame(width: panelWidth)
                }
                .padding(.horizontal, sidePadding)
                .padding(.vertical, sidePadding - 12)
            } else {
                VStack(spacing: 16) {
                    canvas
                        .padding(.horizontal, sidePadding)
                        .padding(.top, 4)
                    // One card for both, so it changes height rather than being replaced.
                    Group {
                        if isEnlarged {
                            tuningTray
                                .transition(.opacity)
                        } else {
                            controls
                                .transition(.opacity)
                        }
                    }
                    // Not scrollable here, unlike the side panel: past this size the
                    // controls would squeeze the preview away on a phone.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                            .fill(Theme.surface)
                            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: -4)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .background {
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { roomSize = $0 }
        }
        .onChange(of: titleFocused) { _, focused in
            editingLayout = focused ? (size.width, chosenLayout) : nil
        }
        // Side by side, the preview is as large as it gets already.
        .onChange(of: isSideBySide) { _, beside in
            if beside { isTuning = false }
        }
        // The title field names the painting; the bar says which step this is.
        .navigationTitle("New Painting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        // Shrink Preview is the way back from the enlarged preview. There is none while Start
        // Painting saves: leaving then would open the painting from whichever flow closes next.
        .navigationBarBackButtonHidden(isEnlarged || isStarting)
        .background { ContentSwipeBackOff().frame(width: 0, height: 0) }
        .sheet(isPresented: $isFraming) { framingSheet }
    }

    /// What the preview does as the model changes: its tips' moments and a start asked for early.
    private func observingTheModel(_ content: some View) -> some View {
        content
            // The preview's tips: a template that is final is a moment, a slider let go another.
            .onAppear {
                PaintTips.desk.enter(.preview)
                if model.isFinal { previewFinal() }
            }
            .onDisappear {
                PaintTips.desk.leave(.preview)
                model.withdrawStart()
            }
            .onChange(of: model.isFinal) { _, isFinal in
                if isFinal { previewFinal() }
            }
            // A start asked for early goes once the painting is made, unless something called it off.
            .onChange(of: model.startsNow) { _, now in
                if now {
                    model.withdrawStart()
                    start()
                }
            }
            .onChange(of: model.isAdjusting) { _, adjusting in
                // No suggestion to go back to: Ravenna's recipe is always the painter's own.
                if !adjusting { PaintTips.sliderReleased(isCustom: false) }
            }
            // Start Painting saves the painting, and The Making-of may play: the preview says no more.
            .onChange(of: isStarting) { _, starting in
                if starting { PaintTips.desk.leave(.preview) }
            }
    }

    /// Canvas beside the controls when that shows the photo larger than stacking them: landscape
    /// windows, and portrait photos on iPad. The controls' size is estimated rather than measured
    /// because measuring it would feed back into the choice of layout. The choice ignores the
    /// keyboard (`roomSize`) and holds while the title is edited: switching layouts then would
    /// rebuild the title field and drop its focus, and the keyboard with it.
    private var isSideBySide: Bool {
        if let editingLayout, editingLayout.width == size.width { return editingLayout.sideBySide }
        return chosenLayout
    }

    private var chosenLayout: Bool {
        let room = roomSize.width > 0 && roomSize.height > 0 ? roomSize : size
        guard room.width.isFinite, room.height.isFinite, room.width > 0, room.height > 0 else { return false }
        // The stacked controls card: title row, the recipe (one group and its chooser in a compact
        // window), summary, Start and the free paintings under it.
        let card: CGFloat = (room.width < Self.compactWidth ? 330 : 560) + (showsFreeCount ? 30 : 0)
        let stacked = Self.fittedArea(
            width: room.width - 2 * sidePadding, height: room.height - card, aspect: photoAspect)
        let beside = Self.fittedArea(
            width: room.width - 2 * sidePadding - panelWidth - 24, height: room.height - 2 * sidePadding, aspect: photoAspect)
        return beside > stacked
    }

    private var sidePadding: CGFloat { size.width > 900 ? 32 : 16 }
    private var panelWidth: CGFloat { size.width > 900 ? 360 : 320 }
    /// The card's rows sit closer stacked on a phone, where the card and the comparison share
    /// the screen's height.
    private var rowSpacing: CGFloat { !isSideBySide && isCompact ? 12 : 18 }
    /// A phone's width (or a narrow iPad window), where the stacked comparison is small.
    private var isCompact: Bool { size.width < Self.compactWidth }
    private static let compactWidth: CGFloat = 600

    /// The comparison can fill the page: stacked in a compact window, where the controls leave
    /// it a fraction of the screen.
    private var offersEnlarging: Bool { isCompact && !isSideBySide }
    private var isEnlarged: Bool { isTuning && !isSideBySide }

    private func setEnlarged(_ enlarged: Bool) {
        titleFocused = false
        withAnimation(reduceMotion ? nil : .snappy) { isTuning = enlarged }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let onClose, !isEnlarged {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: onClose)
                    .disabled(isStarting)
            }
        }
        if isEnlarged {
            // Where Enlarge Preview was, its mirror: a checkmark there read as accepting the
            // painting.
            ToolbarItem(placement: .primaryAction) {
                Button("Shrink Preview", systemImage: "arrow.down.right.and.arrow.up.left") { setEnlarged(false) }
            }
        }
        if offersEnlarging && !isEnlarged {
            ToolbarItem(placement: .primaryAction) {
                Button("Enlarge Preview", systemImage: "arrow.up.left.and.arrow.down.right") { setEnlarged(true) }
                    .disabled(model.preview == nil)
            }
        }
    }

    /// The shape of the photo as the mosaic shown lays it (its panel).
    private var photoAspect: CGFloat {
        guard let image = model.framed, image.width > 0, image.height > 0 else { return 4 / 3 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    private static func fittedArea(width: CGFloat, height: CGFloat, aspect: CGFloat) -> CGFloat {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        let fittedWidth = min(width, height * aspect)
        return fittedWidth * fittedWidth / aspect
    }

    /// The mosaic is final: the moment of the preview's tips (none for a suggestion: there is none).
    private func previewFinal() {
        PaintTips.previewFinal(isSuggested: false)
        #if DEBUG
        // `create-unlock` taps Start Painting once its painting is made, with no free painting left.
        if ShellDemo.current == .createUnlock { start() }
        #endif
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack {
            if let photo = model.framed {
                CompareView(
                    photo: photo, after: model.preview?.picture, afterID: model.preview?.id.uuidString ?? "none",
                    afterLabel: String(localized: "Mosaic"), aspectRatio: photoAspect, canvasSize: size, fillsSpace: isEnlarged)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        pictureProbe?.measured(frame: frame, aspect: photoAspect)
                    }
                    .overlay(alignment: .bottom) {
                        status.padding(14)
                    }
            } else if case .failed(let message) = model.phase {
                ContentUnavailableView("Couldn’t Open Photo", systemImage: "photo.badge.exclamationmark", description: Text(message))
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.large)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        Group {
            switch model.phase {
            case .loading, .analyzing:
                StatusCapsule {
                    ProgressView().controlSize(.small)
                    if model.phase == .loading {
                        Text("Opening photo…")
                    } else {
                        Text("Finding the subject…")
                    }
                }
            case .generating where !model.isAdjusting || model.making != nil:
                StatusCapsule {
                    ProgressView(value: model.progress)
                        .frame(width: 64)
                    if model.preview == nil {
                        Text("Making the painting…")
                    } else {
                        Text("Updating…")
                    }
                }
            case .failed(let message):
                StatusCapsule {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(message).lineLimit(2)
                }
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.phase)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            titleField
            if isCompact && !isSideBySide {
                // One group at a time on a phone (Paul's calmer menus, October 18): the card keeps
                // the comparison large and asks one thing at once.
                settingChooser
                group(shownSetting)
                    .id(shownSetting)
            } else {
                ForEach(Setting.allCases, id: \.self) { group($0) }
            }
            summary

            Button(action: start) {
                HStack(spacing: 10) {
                    if isStarting { ProgressView().tint(.white) }
                    if isPreparingStart {
                        Text("Preparing…")
                    } else {
                        Text("Start Painting")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.signature)
            .controlSize(.large)
            .disabled(model.preview == nil || (model.isChoosingSettings && !Self.startsEarly) || isStarting || model.startAsked)
            .accessibilityLabel("Start Painting")
            .accessibilityValue(isPreparingStart ? String(localized: "Preparing…") : "")

            if showsFreeCount { freeCount }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, isSideBySide ? 22 : 8)
    }

    /// The enlarged preview's controls: one group of the recipe, chosen above it, and the mosaic's
    /// summary. Pieces comes first, the pieces being what a large preview is for.
    private var tuningTray: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingChooser
            group(shownSetting)
                // Another group, not this one's controls changing.
                .id(shownSetting)
            summary
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    /// Which group a compact window's card shows: the painter's choice, else Pieces.
    private var shownSetting: Setting { tunedSetting ?? .pieces }

    /// The segmented control over the one group of a compact window and the enlarged preview.
    private var settingChooser: some View {
        Picker("Setting", selection: Binding(get: { shownSetting }, set: { tunedSetting = $0 })) {
            Text("Pieces").tag(Setting.pieces)
            Text("Face").tag(Setting.face)
            Text("Ground").tag(Setting.ground)
            Text("Panel").tag(Setting.panel)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("tuned-setting")
    }

    /// The recipe's groups: how many pieces; the eyes and the mouth; the background; how much of
    /// the photo is laid.
    private enum Setting: Hashable, CaseIterable { case pieces, face, ground, panel }

    /// Locked while Start Painting makes the painting (a change then would lay the mosaic again
    /// under it), and while the photo's contours and faces are found.
    @ViewBuilder
    private func group(_ setting: Setting) -> some View {
        groupBody(setting).disabled(isStarting || model.isChoosingSettings)
    }

    @ViewBuilder
    private func groupBody(_ setting: Setting) -> some View {
        switch setting {
        case .pieces:
            SettingSlider(
                title: "Pieces", value: model.recipe.pieces, onChange: { setPieces($0) },
                valueText: Self.piecesText(model.recipe.pieces), isPending: model.isChoosingSettings,
                detent: MosaicEngine.Recipe.standardPieces, onEditing: model.setAdjusting)
                // Fewer or More Areas: over the slider, clear of the preview's picture.
                .gentleTip(.newPaintingSliders, arrowEdge: .bottom)
        case .face:
            VStack(alignment: .leading, spacing: 4) {
                ChoiceRow(title: "Eyes", caption: "Mixed brighter, as an eye catches the light, or kept as the photo has them.") {
                    Picker("Eyes", selection: choice(\.eyes)) {
                        Text("As they look").tag(MosaicEngine.Eyes.asTheyLook)
                        Text("The photo’s colours").tag(MosaicEngine.Eyes.asInThePhoto)
                    }
                }
                ChoiceRow(title: "Mouth", caption: "Kept as the photo has it, or set small and closed, as Byzantine faces were.") {
                    Picker("Mouth", selection: choice(\.mouth)) {
                        Text("As in the photo").tag(MosaicEngine.Mouth.asInThePhoto)
                        Text("Byzantine").tag(MosaicEngine.Mouth.byzantine)
                    }
                }
            }
        case .ground:
            ChoiceRow(title: "Ground", caption: "Gold lays the picture’s background in gold smalti, as behind the figures at Ravenna.") {
                Picker("Ground", selection: choice(\.ground)) {
                    Text("As in the picture").tag(MosaicEngine.Ground.picture)
                    Text("Gold").tag(MosaicEngine.Ground.gold)
                }
            }
        case .panel:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Panel")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if model.recipe.panel != .whole {
                        Button("Move Panel", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { openFraming() }
                            .font(.subheadline)
                            .accessibilityIdentifier("move-panel")
                    }
                }
                Picker("Panel", selection: Binding(get: { model.recipe.panel }, set: { choosePanel($0) })) {
                    Text("Whole").tag(MosaicEngine.Panel.whole)
                    Text("Square").tag(MosaicEngine.Panel.square)
                    Text("Upright").tag(MosaicEngine.Panel.upright)
                    Text("Wide").tag(MosaicEngine.Panel.wide)
                }
                .pickerStyle(.segmented)
                Group {
                    if model.recipe.panel == .whole {
                        Text("All of the photo is laid.")
                    } else {
                        Text("Move the panel over the part to lay.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// A binding to one of the recipe's choices that lays the mosaic again when it changes.
    private func choice<T: Equatable>(_ keyPath: WritableKeyPath<MosaicEngine.Recipe, T>) -> Binding<T> {
        Binding(get: { model.recipe[keyPath: keyPath] }, set: { value in
            guard model.recipe[keyPath: keyPath] != value else { return }
            model.recipe[keyPath: keyPath] = value
            model.recipeChanged()
        })
    }

    /// Moves Pieces, ignoring unchanged values: a slider re-asserting its value would otherwise
    /// lay the mosaic again on every update.
    private func setPieces(_ value: Double) {
        guard abs(model.recipe.pieces - value) > 1e-9 else { return }
        model.recipe.pieces = value
        model.recipeChanged()
        PaintTips.sliderMoved(colorsOrDetail: true)
    }

    /// A panel's shape: laid at once from the photo's middle, and its sheet opens to move it.
    private func choosePanel(_ panel: MosaicEngine.Panel) {
        guard panel != model.recipe.panel else { return }
        model.recipe.panel = panel
        model.recipe.centre = SIMD2(0.5, 0.5)
        model.recipeChanged()
        if panel != .whole { openFraming() }
    }

    private func openFraming() {
        titleFocused = false
        framingCentre = model.recipe.centre
        isFraming = true
    }

    /// The photo with the panel over it, to drag where it is to be laid; Done lays it there.
    private var framingSheet: some View {
        NavigationStack {
            Group {
                if let photo = model.source?.preview {
                    PanelFramingView(image: photo, panel: model.recipe.panel, centre: $framingCentre)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
            .navigationTitle("Panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isFraming = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isFraming = false
                        guard framingCentre != model.recipe.centre else { return }
                        model.recipe.centre = framingCentre
                        model.recipeChanged()
                    }
                }
            }
        }
    }

    /// How many times the standard count of tiles the slider asks for.
    private static func piecesText(_ pieces: Double) -> String {
        let multiple = MosaicEngine.Recipe.multiple(pieces: pieces).formatted(.number.precision(.fractionLength(1)))
        return String(localized: "create.pieces.multiple", defaultValue: "\(multiple)×",
                      comment: "Pieces slider value: how many times the standard number of tiles, 0.5 to 3.0")
    }

    /// Tiles, paints and setting time of the latest mosaic at its own size.
    private var summary: some View {
        Text(model.stats?.summary ?? " ")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.primary.opacity(0.7))
            .monospacedDigit()
            .contentTransition(.numericText())
            .opacity(model.isFinal ? 1 : 0.7)
            .animation(.easeInOut(duration: 0.25), value: model.stats)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Empty shows the default (the sample's name or the date) as the prompt, and the
    /// painting takes that name.
    private var titleField: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Title", text: $model.title, prompt: Text(model.defaultTitle))
                .font(.display(.title3, weight: .semibold))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($titleFocused)
                .onSubmit { titleFocused = false }
                .accessibilityIdentifier("painting-title")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.paper, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private var isShowingStartError: Binding<Bool> {
        Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })
    }

    /// A photo of the painter's own, not a library picture: its painting may take a free painting.
    private var isOwnPhoto: Bool { model.source != nil && model.source?.sampleName == nil }

    /// The free paintings left show under Start Painting while one of the painter's own photos
    /// would take one (`UnlimitedPaintings`).
    private var showsFreeCount: Bool { isOwnPhoto && paintings.isSold && !paintings.isUnlocked }

    private var freeCount: some View {
        Group {
            let left = paintings.freeLeft
            if left > 0 {
                Text(String(localized: "unlock.freeLeft", defaultValue: "\(left) free paintings left",
                            comment: "Under the create flow's Start Painting, for a painting of the painter's own photo before Unlimited Paintings is bought; the argument is how many free paintings are left (at most 3)"))
            } else {
                Text("Your next free painting comes tomorrow.")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("free-paintings")
    }

    /// Start Painting works from the first draft on screen, while the settings are still being
    /// chosen and the painting made: tapped before the painting is final, it says Preparing… and
    /// starts by itself once it is (`CreateModel.askForStart`, `startsNow`). The free paintings are
    /// asked at the tap, so the unlock sheet comes then, never later on a screen the painter stopped
    /// watching. Meanwhile the flow stays live: a changed setting (a touch, VoiceOver's adjust or a
    /// key), a failed generation or the preview going calls the start off, and Close and Back leave.
    /// In SideStore and Debug builds only for now (`UNRELEASED`, until a Lamplit Table round and
    /// Paul choose it for the release): the first-five-minutes walk, October 23 ("Choosing
    /// settings…" takes tens of seconds on a phone, with Start off); Paul: "let's build them all".
    #if UNRELEASED
    private static let startsEarly = true
    #else
    private static let startsEarly = false
    #endif

    /// Start Painting was tapped and waits for the painting to be made.
    private var isPreparingStart: Bool { model.startAsked }

    /// Starts the painting, once a painting of the painter's own photo may (`UnlimitedPaintings`):
    /// without the unlock and a free painting left, the unlock's sheet instead.
    private func start() {
        guard !isStarting, !model.startAsked else { return }
        titleFocused = false
        let ownPhoto = isOwnPhoto
        if Self.startsEarly && !(model.isFinal && !model.isChoosingSettings) {
            // Early: the free paintings now, the start once the painting is made.
            model.askForStart()
            Task {
                guard await paintings.mayStart(ownPhoto: ownPhoto) else {
                    // Unless called off, or started meanwhile (which asks again).
                    if model.startAsked {
                        model.withdrawStart()
                        offersUnlock = true
                    }
                    return
                }
                // Made while the App Store answered.
                if model.startsNow {
                    model.withdrawStart()
                    start()
                }
            }
            return
        }
        isStarting = true
        Task {
            do {
                guard await paintings.mayStart(ownPhoto: ownPhoto) else {
                    isStarting = false
                    offersUnlock = true
                    return
                }
                try await onStart()
                paintings.started(ownPhoto: ownPhoto)
            } catch {
                startError = error.localizedDescription
                isStarting = false
            }
            // Started: the flow closes, and this stays set until it has, so a second tap during
            // the dismissal can't save the painting again.
        }
    }
}

/// One of the recipe's choices: its name, a menu of its options, and a line on what they do.
private struct ChoiceRow<Content: View>: View {
    let title: LocalizedStringKey
    let caption: LocalizedStringKey
    @ViewBuilder var picker: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                picker
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel(Text(title))
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The photo with the panel over it, as v0 framed a mosaic (its `Framing.swift`): drag to move
/// the panel; outside it, the photo dims. VoiceOver moves it a tenth at a time.
private struct PanelFramingView: View {
    let image: CGImage
    let panel: MosaicEngine.Panel
    @Binding var centre: SIMD2<Double>
    @State private var start: SIMD2<Double>?

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { g in
                    let unit = rect(centre)
                    let r = CGRect(x: unit.x * g.size.width, y: unit.y * g.size.height,
                                   width: unit.width * g.size.width, height: unit.height * g.size.height)
                    Path { p in p.addRect(CGRect(origin: .zero, size: g.size)); p.addRect(r) }
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    Rectangle()
                        .stroke(Theme.gold, lineWidth: 2)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                    Color.clear.contentShape(.rect)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            let from = start ?? SIMD2(unit.x + unit.width / 2, unit.y + unit.height / 2)
                            start = from
                            centre = clamped(from + SIMD2(Double(v.translation.width / max(g.size.width, 1)),
                                                          Double(v.translation.height / max(g.size.height, 1))))
                        }.onEnded { _ in start = nil })
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Your photo"))
            .accessibilityValue(Text(place))
            .accessibilityActions {
                Button("Move Left") { nudge(-0.1, 0) }
                Button("Move Right") { nudge(0.1, 0) }
                Button("Move Up") { nudge(0, -0.1) }
                Button("Move Down") { nudge(0, 0.1) }
            }
    }

    private func rect(_ c: SIMD2<Double>) -> (x: Double, y: Double, width: Double, height: Double) {
        panel.rect(width: Double(image.width), height: Double(image.height), centre: c)
    }

    /// Where the panel sits, in words.
    private var place: String {
        let unit = rect(centre)
        let midX = unit.x + unit.width / 2, midY = unit.y + unit.height / 2
        if unit.width >= 0.999 {
            if unit.height >= 0.999 { return String(localized: "create.panel.place.all", defaultValue: "All of it", comment: "VoiceOver value of the panel's photo when the panel covers all of it") }
            return midY < 0.4 ? String(localized: "create.panel.place.top", defaultValue: "Top", comment: "VoiceOver value of the panel's photo: the panel is at the top")
                : midY > 0.6 ? String(localized: "create.panel.place.bottom", defaultValue: "Bottom", comment: "VoiceOver value of the panel's photo: the panel is at the bottom")
                : String(localized: "create.panel.place.middle", defaultValue: "Middle", comment: "VoiceOver value of the panel's photo: the panel is in the middle")
        }
        return midX < 0.4 ? String(localized: "create.panel.place.left", defaultValue: "Left", comment: "VoiceOver value of the panel's photo: the panel is at the left")
            : midX > 0.6 ? String(localized: "create.panel.place.right", defaultValue: "Right", comment: "VoiceOver value of the panel's photo: the panel is at the right")
            : String(localized: "create.panel.place.centre", defaultValue: "Centre", comment: "VoiceOver value of the panel's photo: the panel is in the centre")
    }

    private func nudge(_ dx: Double, _ dy: Double) {
        let unit = rect(centre)
        centre = clamped(SIMD2(unit.x + unit.width / 2 + dx, unit.y + unit.height / 2 + dy))
    }

    /// The centre, kept where the panel stays on the photo.
    private func clamped(_ c: SIMD2<Double>) -> SIMD2<Double> {
        let unit = rect(c)
        return SIMD2(unit.x + unit.width / 2, unit.y + unit.height / 2)
    }
}

private struct StatusCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // One row where it fits, else the words above the bar: a tall photo on a phone leaves the
        // preview too narrow for both, and the row squeezed the words into a column of letters.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
            VStack(spacing: 7) { content }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .font(.footnote.weight(.medium))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

private struct SettingSlider: View {
    let title: LocalizedStringKey
    let value: Double
    var onChange: (Double) -> Void
    let valueText: String
    /// The value is not chosen yet (Suggested settings are being chosen): shown as a
    /// placeholder, and the slider waits.
    var isPending = false
    /// The suggested value: the thumb settles on it within `detentReach`, with a tick.
    var detent: Double?
    var onEditing: (Bool) -> Void

    static let detentReach = 0.02

    var body: some View {
        let value = Binding(get: { self.value }, set: { set($0) })
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(valueText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: valueText)
                    .redacted(reason: isPending ? .placeholder : [])
            }
            Slider(value: value, in: 0...1, onEditingChanged: onEditing)
                .disabled(isPending)
                .accessibilityLabel(title)
                .accessibilityValue(isPending ? Text("Choosing settings…") : Text(valueText))
        }
    }

    private func set(_ newValue: Double) {
        guard let detent, abs(newValue - detent) < Self.detentReach else {
            onChange(newValue)
            return
        }
        if value != detent { FeedbackEngine.shared.selectionChanged() }
        onChange(detent)
    }
}

/// Where the preview's picture is on screen: the preview writes it as it is laid out and the create
/// flow reads it when Start Painting is tapped, to move the picture from there (`StartHandoff`). A
/// reference, so that neither invalidates the other.
final class PreviewPictureProbe {
    private var frame = CGRect.zero
    private var aspect: CGFloat = 0

    /// The comparison's frame (global coordinates) and the photo's shape.
    func measured(frame: CGRect, aspect: CGFloat) {
        self.frame = frame
        self.aspect = aspect
    }

    /// The picture: the photo's shape fitted in the comparison's frame (the enlarged preview's
    /// frame is the whole page), in global coordinates; nil before it has been laid out.
    var picture: CGRect? {
        guard aspect > 0, frame.isPlace else { return nil }
        let size = CompareView.fitted(aspect, in: frame.size)
        return CGRect(
            x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
}

/// iOS 26 lets a swipe right from anywhere on a pushed screen go back. On the preview that took
/// the drags meant for the sliders (one that missed the thumb, or met a slider waiting for the
/// suggestion) and for the comparison, and left for the photo step. SwiftUI has no switch for
/// it, so this turns that content-area recognizer off while the preview shows; the edge swipe
/// and Back keep working (`CreateFlowTests.testSwipeAcrossSettingsStaysOnPreview`). The Tool
/// Guide's pages have it too, on iPhone, where a stroke to the right on a practice canvas went
/// back to the list (`RefineUITests.testToolGuidePracticesAndResets`).
struct ContentSwipeBackOff: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        /// The screens holding each recognizer off, and whether it was on before the first did:
        /// a guide page replacing another may appear before the one it replaces goes.
        private static var holds: [ObjectIdentifier: (count: Int, wasEnabled: Bool)] = [:]
        private weak var held: UIGestureRecognizer?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard held == nil, let recognizer = navigationController?.interactiveContentPopGestureRecognizer else { return }
            let key = ObjectIdentifier(recognizer)
            let hold = Self.holds[key] ?? (0, recognizer.isEnabled)
            Self.holds[key] = (hold.count + 1, hold.wasEnabled)
            recognizer.isEnabled = false
            held = recognizer
        }

        // On again as the last screen holding it goes; an edge swipe called off halfway appears
        // it again.
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let recognizer = held else { return }
            held = nil
            let key = ObjectIdentifier(recognizer)
            guard let hold = Self.holds[key] else { return }
            if hold.count > 1 {
                Self.holds[key] = (hold.count - 1, hold.wasEnabled)
            } else {
                Self.holds[key] = nil
                recognizer.isEnabled = hold.wasEnabled
            }
        }
    }
}

/// Unlimited Paintings' sheet over the preview (`UnlockSheet`): Start Painting opens it when no
/// free painting is left for the painter's own photo, and once the unlock is bought the painting
/// starts.
private struct UnlockOffer: ViewModifier {
    @Binding var isPresented: Bool
    let start: () -> Void
    @Environment(UnlimitedPaintings.self) private var paintings

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: { if paintings.isUnlocked { start() } }) {
            UnlockSheet(fromStart: true)
        }
    }
}
