import CoreGraphics
import Foundation
import PaintCore
import SwiftUI
import UIKit

/// Second step of the create flow: the generated template, compared with the photo,
/// tuned live with a few simple controls, and the painting's name. In compact windows (iPhone)
/// the card shows the slider of one setting at a time, chosen above it, and the preview can be
/// enlarged: the comparison then fills the page above that slider, Lines first, to look closely
/// while tuning the lines.
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
    #if UNRELEASED
    @State private var isRefining = false
    #endif
    /// The setting the one slider of a compact window tunes; nil until the painter picks one.
    @State private var tunedSetting: Setting?
    /// The painter opened Adjust, and the card shows its settings from then on (`foldsSettings`).
    @AppStorage(SettingsKey.previewShowsSettings) private var opensSettings = SettingsDefault.previewShowsSettings
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
        #if UNRELEASED
        // Refine's button goes while the preview is enlarged, and its tip with it.
        .barTips(.newPaintingRefine, active: !isEnlarged)
        #endif
        // Shrink Preview is the way back from the enlarged preview. There is none while Start
        // Painting saves: leaving then would open the painting from whichever flow closes next.
        .navigationBarBackButtonHidden(isEnlarged || isStarting)
        .background { ContentSwipeBackOff().frame(width: 0, height: 0) }
        #if UNRELEASED
        .fullScreenCover(isPresented: $isRefining) { RefineView(model: model) }
        // A tap on Refine made while the painting was updating: it opens once it is made.
        .onChange(of: model.opensRefine) { _, opens in
            if opens { openRefine() }
        }
        #endif
    }

    /// What the preview does as the model changes: its tips' moments, Refine and a start asked
    /// for early.
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
                if !adjusting { PaintTips.sliderReleased(isCustom: model.settingsOrigin == .custom) }
            }
            .onChange(of: model.settingsOrigin) { old, origin in
                if old == .custom, origin == .suggested { PaintTips.resetUsed() }
            }
            #if UNRELEASED
            .onChange(of: isRefining) { _, refining in
                if refining { PaintTips.refineOpened() }
            }
            #endif
            // Start Painting saves the painting, and The Making-of may play: the preview says no more.
            .onChange(of: isStarting) { _, starting in
                if starting { PaintTips.desk.leave(.preview) }
            }
            #if DEBUG && UNRELEASED
            // `create-refine` shows the Refine screen once its painting is refined.
            .onChange(of: model.refinements.isEmpty) { _, isEmpty in
                if ShellDemo.current?.refines == true, !isEmpty { isRefining = true }
            }
            #endif
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
        // The stacked controls card: title row, settings chip, the sliders (one and its chooser in
        // a compact window), summary, Start and the free paintings under it.
        // With its settings shown, folded or not: Adjust then never moves the card from under the finger.
        let card: CGFloat = (room.width < Self.compactWidth ? 364 : (hasLines ? 512 : 460)) + (showsFreeCount ? 30 : 0)
        let stacked = Self.fittedArea(
            width: room.width - 2 * sidePadding, height: room.height - card, aspect: photoAspect)
        let beside = Self.fittedArea(
            width: room.width - 2 * sidePadding - panelWidth - 24, height: room.height - 2 * sidePadding, aspect: photoAspect)
        return beside > stacked
    }

    private var sidePadding: CGFloat { size.width > 900 ? 32 : 16 }
    private var panelWidth: CGFloat { size.width > 900 ? 360 : 320 }
    /// The card's rows sit closer stacked on a phone, where the card and the comparison share
    /// the screen's height: with four sliders, 18 pt between rows left the comparison 125 pt tall
    /// on an iPhone 17 Pro.
    private var rowSpacing: CGFloat { !isSideBySide && isCompact ? 12 : 18 }
    /// A phone's width (or a narrow iPad window), where the stacked comparison is small.
    private var isCompact: Bool { size.width < Self.compactWidth }
    private static let compactWidth: CGFloat = 600

    /// The comparison can fill the page: stacked in a compact window, where the controls leave
    /// it a fraction of the screen.
    private var offersEnlarging: Bool { isCompact && !isSideBySide }
    private var isEnlarged: Bool { isTuning && !isSideBySide }

    #if UNRELEASED
    /// Refine on the final template, or, while it is being made, as soon as it is.
    private func openRefine() {
        titleFocused = false
        guard !isStarting else { return }
        model.withdrawStart()
        if model.canRefine {
            model.withdrawRefine()
            isRefining = true
        } else {
            model.askForRefine()
        }
    }
    #endif

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
        #if UNRELEASED
        // Refine is in SideStore and Debug builds only for now: the release has no Refine step.
        if !isEnlarged {
            // The optional Refine step: a text button, so it reads as a step and not a view.
            ToolbarItem(placement: .primaryAction) {
                Button(action: openRefine) {
                    if model.isWaitingToRefine {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Preparing…")
                        }
                    } else {
                        Text("Refine")
                    }
                }
                // Without line art there is nothing to draw on. Else it is on while the painting
                // updates: Refine draws on the final template alone (its edits are made in that
                // template's canvas units), so a tap before it is made waits for it
                // (`CreateModel.askForRefine`) and opens by itself.
                .disabled(!model.canAskForRefine || isStarting || !model.hasLineArtInput)
                .accessibilityLabel("Refine")
                .accessibilityValue(
                    model.isWaitingToRefine ? String(localized: "Preparing…") : RefineView.changes(model.refinements.changeCount))
                .accessibilityIdentifier("refine")
            }
        }
        #endif
        if offersEnlarging && !isEnlarged {
            ToolbarItem(placement: .primaryAction) {
                Button("Enlarge Preview", systemImage: "arrow.up.left.and.arrow.down.right") { setEnlarged(true) }
                    .disabled(model.preview == nil)
            }
        }
    }

    private var photoAspect: CGFloat {
        guard let image = model.source?.image, image.width > 0, image.height > 0 else { return 4 / 3 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    private static func fittedArea(width: CGFloat, height: CGFloat, aspect: CGFloat) -> CGFloat {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return 0 }
        let fittedWidth = min(width, height * aspect)
        return fittedWidth * fittedWidth / aspect
    }

    /// The colors slider runs on a squared scale: the first half of the track covers 6–42,
    /// where each color matters, the rest reaches up to 150.
    private static let colorBounds = (
        Double(GenerationSettings.colorCountRange.lowerBound), Double(GenerationSettings.colorCountRange.upperBound))

    private static func colorCount(at position: Double) -> Double {
        (colorBounds.0 + (colorBounds.1 - colorBounds.0) * position * position).rounded()
    }

    private static func colorPosition(_ count: Double) -> Double {
        min(max((count - colorBounds.0) / (colorBounds.1 - colorBounds.0), 0), 1).squareRoot()
    }

    /// Updates a setting the painter moved, ignoring unchanged values: a slider re-asserting
    /// its value would otherwise invalidate the model on every update.
    private func update(_ keyPath: ReferenceWritableKeyPath<CreateModel, Double>, _ value: Double) {
        guard abs(model[keyPath: keyPath] - value) > 1e-9 else { return }
        model[keyPath: keyPath] = value
        model.settingsChanged()
        PaintTips.sliderMoved(colorsOrDetail: keyPath == \CreateModel.colorCount || keyPath == \CreateModel.detail)
    }

    /// The template is final: the moment of the preview's tips. The suggestion's is only while the
    /// settings are still the suggested ones.
    private func previewFinal() {
        #if UNRELEASED
        let canRefine = model.canRefine
        #else
        let canRefine = false
        #endif
        PaintTips.previewFinal(isSuggested: model.settingsOrigin == .suggested, canRefine: canRefine)
        #if DEBUG
        // `create-unlock` taps Start Painting once its painting is made, with no free painting left.
        if ShellDemo.current == .createUnlock { start() }
        #endif
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack {
            if let source = model.source {
                CompareView(
                    photo: source.preview, after: model.preview?.picture, afterID: model.preview?.id.uuidString ?? "none",
                    afterLabel: model.previewStyle.name, aspectRatio: photoAspect, canvasSize: size, fillsSpace: isEnlarged)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        pictureProbe?.measured(frame: frame, aspect: photoAspect)
                    }
                    .overlay(alignment: .bottom) {
                        status.padding(14)
                    }
                    #if UNRELEASED
                    // What Refine had to say once the sliders made the template again, and a
                    // draft that couldn't be saved.
                    .overlay(alignment: .top) {
                        VStack(spacing: 8) {
                            RefineNoteToast(note: model.note)
                            DraftSaveToast(photoID: model.photoID)
                        }
                        .padding(.top, 8)
                    }
                    .animation(reduceMotion ? nil : .snappy, value: model.note)
                    #endif
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
            case .loading, .analyzing, .suggesting:
                StatusCapsule {
                    ProgressView().controlSize(.small)
                    if model.phase == .loading {
                        Text("Opening photo…")
                    } else if model.phase == .analyzing {
                        Text("Finding the subject…")
                    } else {
                        Text("Choosing settings…")
                    }
                }
            case .generating where !model.isAdjusting || model.refining != nil:
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
            if Self.foldsSettings {
                HStack(spacing: 12) {
                    originChip
                    adjustButton
                }
            } else {
                originChip
            }
            if showsSettings {
                if isCompact && !isSideBySide {
                    // One slider at a time on a phone (Paul's calmer menus, October 18): the card keeps
                    // the comparison large and asks one thing at once.
                    settingChooser
                    slider(shownSetting)
                        .id(shownSetting)
                } else {
                    slider(.colors)
                    slider(.detail)
                    slider(.smoothness)
                    if hasLines { slider(.lines) }
                }
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

    /// The enlarged preview's controls: the slider of one setting, chosen above it, and the
    /// template's summary. Lines comes first, the lines being what a large preview is for.
    private var tuningTray: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingChooser
            slider(shownSetting)
                // Another setting's slider, not this one's thumb sliding to its value.
                .id(shownSetting)
            summary
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    /// In SideStore and Debug builds (`UNRELEASED`, until a Lamplit Table round and Paul choose it for
    /// the release) the card folds its settings away: the title, the suggestion, the summary and
    /// Start Painting, and Adjust, which shows the sliders as they are and keeps them shown for
    /// whoever opened it (`SettingsKey.previewShowsSettings`). The first-five-minutes walk, October
    /// 23: four questions a newcomer can't answer, while Already Chosen for You says to just tap
    /// Start Painting; Paul: "let's build them all". Adjust alone shows or folds them: settings of
    /// the painter's own (from the enlarged preview) fold too, the chip saying Custom with its Reset
    /// to Suggested, so no slider goes from under a finger as its drag comes back to its detent.
    #if UNRELEASED
    private static let foldsSettings = true
    #else
    private static let foldsSettings = false
    #endif

    private var showsSettings: Bool { !Self.foldsSettings || opensSettings }

    /// Shows the settings, or folds them away again. Fewer or More Areas points here while they are
    /// folded.
    private var adjustButton: some View {
        Button {
            titleFocused = false
            withAnimation(reduceMotion ? nil : .snappy) { opensSettings.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text("Adjust")
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(opensSettings ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(isStarting)
        .accessibilityValue(opensSettings ? Text("Settings shown") : Text("Settings hidden"))
        .accessibilityIdentifier("preview-adjust")
        .gentleTip(.newPaintingSliders, active: !showsSettings, arrowEdge: .bottom)
    }

    /// Which setting the one slider tunes: the painter's choice, else Colors in the card and
    /// Lines in the enlarged preview; a choice made in either holds in both.
    private var shownSetting: Setting {
        if let tunedSetting, tunedSetting != .lines || hasLines { return tunedSetting }
        if isEnlarged { return hasLines ? .lines : .detail }
        return .colors
    }

    /// The segmented control over the one slider of a compact window and the enlarged preview.
    private var settingChooser: some View {
        Picker("Setting", selection: Binding(get: { shownSetting }, set: { tunedSetting = $0 })) {
            Text("Colors").tag(Setting.colors)
            Text("Detail").tag(Setting.detail)
            Text("Smoothness").tag(Setting.smoothness)
            if hasLines { Text("Lines").tag(Setting.lines) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("tuned-setting")
    }

    /// The settings a slider tunes.
    private enum Setting: Hashable { case colors, detail, smoothness, lines }

    /// Locked while Start Painting makes the painting: a change then would make the template again
    /// under it.
    @ViewBuilder
    private func slider(_ setting: Setting) -> some View {
        sliderBody(setting).disabled(isStarting)
    }

    @ViewBuilder
    private func sliderBody(_ setting: Setting) -> some View {
        switch setting {
        case .colors:
            SettingSlider(
                title: "Colors", value: Self.colorPosition(model.colorCount),
                onChange: { update(\.colorCount, Self.colorCount(at: $0)) },
                valueText: Int(model.colorCount.rounded()).formatted(), isPending: model.isChoosingSettings,
                detent: suggested.map { Self.colorPosition(Double($0.colorCount)) }, onEditing: model.setAdjusting)
                // Fewer or More Areas: over the slider, clear of the preview's picture.
                .gentleTip(.newPaintingSliders, active: showsSettings, arrowEdge: .bottom)
        case .detail:
            SettingSlider(
                title: "Detail", value: model.detail, onChange: { update(\.detail, $0) },
                valueText: Self.detailWord(model.detail), isPending: model.isChoosingSettings,
                detent: suggested.map { Double($0.detail) }, onEditing: model.setAdjusting)
        case .smoothness:
            SettingSlider(
                title: "Smoothness", value: model.smoothness, onChange: { update(\.smoothness, $0) },
                valueText: Self.smoothnessWord(model.smoothness), isPending: model.isChoosingSettings,
                detent: suggested.map { Double($0.smoothness) }, onEditing: model.setAdjusting)
        case .lines:
            SettingSlider(
                title: "Lines", value: model.lines, onChange: { update(\.lines, $0) },
                valueText: Self.linesWord(model.lines), isPending: model.isChoosingSettings,
                detent: 0.5, onEditing: model.setAdjusting)
        }
    }

    /// Colors, areas and painting time of the latest full-resolution template.
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

    /// The suggestion's settings, where each slider has a detent.
    private var suggested: GenerationSettings? { model.decision?.settings }

    /// Classic line art has no lines to tune.
    private var hasLines: Bool { model.baseLineArt.style != .classic }

    /// Where the settings came from: the suggestion for this photo, or the painter's own with
    /// a way back to it. Its room is kept, empty, until there is a suggestion.
    private var originChip: some View {
        Group {
            if model.settingsOrigin == .custom {
                Button { model.resetToSuggested() } label: {
                    HStack(spacing: 6) {
                        Text("Custom")
                            .foregroundStyle(.secondary)
                        Text(verbatim: "·")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        SwiftUI.Label("Reset to Suggested", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(Theme.accent)
                    }
                    .chipBackground(Theme.paper)
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
                .accessibilityLabel("Reset to Suggested")
                .accessibilityValue("Custom")
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.accent)
                    Text("Suggested for this picture")
                }
                .chipBackground(Theme.accent.opacity(0.14))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(String(
                    localized: "create.settingsOrigin.label", defaultValue: "Settings",
                    comment: "VoiceOver label of the chip above the create sliders; its value says whether they are suggested for the picture or custom")))
                .accessibilityValue("Suggested for this picture")
            }
        }
        .accessibilityIdentifier("settings-origin")
        // Already Chosen for You hangs above the chip; You Can Always Go Back below it, where the
        // preview is left in view to watch. Before the frame: they point at the chip, not the row.
        .gentleTip(.newPaintingSuggested, active: model.settingsOrigin != .custom, arrowEdge: .bottom)
        .gentleTip(.newPaintingReset, active: model.settingsOrigin == .custom, arrowEdge: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(model.settingsOrigin == nil ? 0 : 1)
        .accessibilityHidden(model.settingsOrigin == nil)
        .animation(.snappy, value: model.settingsOrigin)
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
    /// starts by itself once it is (`CreateModel.askForStart`, `startsNow`), as Refine's button
    /// opens Refine. The free paintings are asked at the tap, so the unlock sheet comes then, never
    /// later on a screen the painter stopped watching. Meanwhile the flow stays live: a changed
    /// setting (a touch, VoiceOver's adjust or a key), Reset to Suggested, Refine, a failed
    /// generation or the preview going calls the start off, and Close and Back leave.
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

    /// Which of `count` equal steps of 0…1 `value` falls in.
    private static func step(_ value: Double, of count: Int) -> Int {
        min(count - 1, max(0, Int(value * Double(count))))
    }

    private static func detailWord(_ value: Double) -> String {
        switch step(value, of: 4) {
        case 0: String(localized: "create.detail.simple", defaultValue: "Simple",
                       comment: "Detail slider value: the fewest, largest areas")
        case 1: String(localized: "create.detail.moderate", defaultValue: "Moderate",
                       comment: "Detail slider value: second step")
        case 2: String(localized: "create.detail.detailed", defaultValue: "Detailed",
                       comment: "Detail slider value: third step")
        default: String(localized: "create.detail.intricate", defaultValue: "Intricate",
                        comment: "Detail slider value: the most, smallest areas")
        }
    }

    private static func linesWord(_ value: Double) -> String {
        switch step(value, of: 5) {
        case 0: String(localized: "create.lines.fewest", defaultValue: "Fewest",
                       comment: "Lines slider value: only the strongest edges are drawn")
        case 1: String(localized: "create.lines.fewer", defaultValue: "Fewer",
                       comment: "Lines slider value: second step")
        case 2: String(localized: "create.lines.balanced", defaultValue: "Balanced",
                       comment: "Lines slider value: the middle, the lines as a painting is drawn by default")
        case 3: String(localized: "create.lines.more", defaultValue: "More",
                       comment: "Lines slider value: fourth step")
        default: String(localized: "create.lines.most", defaultValue: "Most",
                        comment: "Lines slider value: the faintest edges drawn too")
        }
    }

    private static func smoothnessWord(_ value: Double) -> String {
        switch step(value, of: 4) {
        case 0: String(localized: "create.smoothness.crisp", defaultValue: "Crisp",
                       comment: "Smoothness slider value: sharp, angular outlines")
        case 1: String(localized: "create.smoothness.clean", defaultValue: "Clean",
                       comment: "Smoothness slider value: second step")
        case 2: String(localized: "create.smoothness.smooth", defaultValue: "Smooth",
                       comment: "Smoothness slider value: third step")
        default: String(localized: "create.smoothness.flowing", defaultValue: "Flowing",
                        comment: "Smoothness slider value: soft, flowing outlines")
        }
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

private extension View {
    /// The origin chip's shape: a capsule on one line, a rounded card when long text wraps.
    func chipBackground(_ style: some ShapeStyle) -> some View {
        font(.footnote.weight(.semibold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(style, in: .rect(cornerRadius: 15, style: .continuous))
            // A comfortable target without making the chip itself taller.
            .frame(minHeight: 44)
            .contentShape(.rect)
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
