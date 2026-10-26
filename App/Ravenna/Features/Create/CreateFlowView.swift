import CoreGraphics
import os
import SwiftUI

/// New painting: pick a photo (library, camera or a sample) → tune the template → paint.
///
/// Start Painting ends in one motion into the painting (`StartHandoff`): the painting opens under
/// the cover this flow is presented in, and once its canvas has drawn, the flow's picture (the
/// making-of show's when it played, else the preview's) moves to where the template sits in it while
/// everything else fades to clear, and cross-fades into the canvas. The cover's background is
/// clear for that (`AppShellView`), so the flow draws its own.
struct CreateFlowView: View {
    /// A bundled sample to open straight on its preview (demo scenarios).
    var openingSample: Sample?
    /// A photo dropped on the gallery: the flow opens on its preview.
    var droppedPhoto: Data?
    /// The dropped or opened file's name, when it has one.
    var droppedTitle: String?
    /// The draft to continue refining (`Drafts`): the flow opens on its preview.
    var resuming: Drafts.Opened?
    var onStart: (Artwork) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.startHandoff) private var handoff
    @Environment(Library.self) private var library
    @State private var model = CreateModel(previewStyle: Self.previewStyle)
    @State private var path: [Step] = []
    /// The painting Start saved, while its making-of plays over the flow (Settings › The Making-of).
    @State private var makingOf: MakingOfRequest?
    /// Where the preview's picture is on screen, which the show or the hand-off moves it from.
    @State private var previewPicture = PreviewPictureProbe()
    /// The preview's picture on its way to the painting, when no making-of plays.
    @State private var departure: PictureDeparture?
    /// How the making-of show leaves, once the painting has drawn.
    @State private var leaving = MakingOfView.Leaving.staying
    /// The flow itself (its screens and its background), fading to clear as the painting takes over.
    @State private var flowOpacity = 1.0
    @State private var isDissolving = false
    /// Where the picture is moving to (global coordinates), and whether it has started to
    /// cross-fade into the canvas: a layout that moves the template meanwhile moves the target.
    @State private var flightTarget: CGRect?
    @State private var targetChangedAt = ContinuousClock.now
    @State private var hasLanded = false

    enum Step: Hashable { case preview }

    private struct MakingOfRequest {
        let artwork: Artwork
        let source: MakingOfSource
        /// Where the preview's picture was (global coordinates): the show's picture starts there.
        let entry: CGRect?
    }

    var body: some View {
        flow
            .background(Theme.paper.ignoresSafeArea())
            .opacity(flowOpacity)
            .overlay {
                if let makingOf {
                    MakingOfView(
                        source: makingOf.source, entry: makingOf.entry, leaving: leaving,
                        onFinish: { onStart(makingOf.artwork) })
                }
            }
            .overlay {
                if let departure { DepartingPicture(departure: departure) }
            }
            // Touches go nowhere while the painting is being opened and taken over.
            .overlay {
                if handoff?.isRunning == true { Color.clear.contentShape(.rect) }
            }
            // The painting beneath takes the status bar's room with it as the flow goes: its
            // layout is then the one it keeps once the cover is gone.
            .statusBarHidden(isDissolving)
            .onChange(of: handoff?.phase, initial: true) { _, phase in
                switch phase {
                case .ready(_, let target)?: if isDissolving { retarget(to: target) } else { dissolve(into: target) }
                case .timedOut?: giveUp()
                default: break
                }
            }
    }

    private var flow: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Step.self) { _ in
                    TemplatePreviewView(model: model, onStart: start, pictureProbe: previewPicture)
                }
        }
        .task {
            // A dropped photo or demo opens straight on the preview (pushing while the cover
            // is still being presented would stall the presentation).
            guard model.source == nil else { return }
            if let droppedPhoto {
                model.load(imageData: droppedPhoto, title: droppedTitle)
            } else if let resuming {
                model.load(draft: resuming.draft, photo: resuming.photo, kept: resuming.kept)
            } else if let openingSample {
                model.load(sample: openingSample)
            }
        }
        #if DEBUG
        .task {
            // A cancelled wait must not signal readiness.
            guard ShellDemo.current == .create || ShellDemo.current?.opensSamples == true else { return }
            do { try await Task.sleep(for: ShellDemo.pickerLoadAllowance) } catch { return }
            DemoMode.markReady()
        }
        .onChange(of: model.isFinal) { _, isFinal in
            guard isFinal else { return }
            if ShellDemo.current?.movesASlider == true, model.settingsOrigin == .suggested {
                // As a painter would: Detail moved a step off the suggestion and released.
                model.detail = model.detail < 0.75 ? model.detail + 0.25 : model.detail - 0.25
                model.settingsChanged()
                return
            }
            if ShellDemo.current?.refines == true, model.refinements.isEmpty, let template = model.preview?.template {
                // As a painter would in Refine; the preview opens it (`TemplatePreviewView`).
                model.refine(ShellDemo.refinements(for: template))
                return
            }
            // `create-tip` is ready once its tip is up (`ShellDemo.prepare`).
            // `create-refine-guide` is ready once the guide's practice canvas shows (`RefineView.land`).
            if (openingSample != nil && ShellDemo.current != .createTip && ShellDemo.current?.opensGuide == nil)
                || ShellDemo.current == .createFromFile {
                DemoMode.markReady()
            }
        }
        #endif
        // With the template on screen too: its trail, once its edits are laid, goes with the draft.
        .onChange(of: DraftKeeping(draft: model.draft, shown: model.preview?.id)) { old, keeping in
            if let draft = keeping.draft, let photo = model.source?.preview {
                library.drafts.keep(draft, photo: photo, kept: model.keptTrail)
            } else if let old = old.draft, model.source != nil, old.photoID == model.photoID {
                // Undone down to nothing. Another photo, or none, leaves the draft of the last.
                library.drafts.drop(photoID: old.photoID)
            }
        }
        .onChange(of: library.drafts.saveFailed == model.photoID) { _, failed in
            // Shown on the preview and in Refine (`DraftSaveToast`), told here once.
            if failed { Announcer.announce(DraftSaveToast.text) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            library.drafts.saveNow()
            if phase == .background {
                let drafts = library.drafts
                BackgroundSaving.shared.hold { await drafts.flush() }
            }
        }
        .onDisappear {
            model.cancelAll()
            library.drafts.saveNow()
        }
    }

    @ViewBuilder
    private var root: some View {
        if droppedPhoto != nil || openingSample != nil || resuming != nil {
            TemplatePreviewView(model: model, onStart: start, onClose: { dismiss() }, pictureProbe: previewPicture)
        } else {
            PhotoSourceView(model: model, initialPane: initialPane, onClose: { dismiss() }) {
                path = [.preview]
            }
        }
    }

    /// Settings › Preview, or the scenario's (demo launches).
    private static var previewStyle: PreviewStyle {
        #if DEBUG
        if let style = ShellDemo.current?.previewStyle { return style }
        #endif
        return Preferences().previewStyle
    }

    /// The `create-samples` demos open on the Samples pane; everything else starts on Photos.
    private var initialPane: PhotoSourceView.Pane {
        #if DEBUG
        if ShellDemo.current?.opensSamples == true { return .samples }
        #endif
        return .photos
    }

    /// Saves the full-resolution template to the library and opens it for painting; the draft of
    /// this photo, if the painter kept one, has done its work. With Settings › The Making-of on, the
    /// saved painting's show plays first, and the painting opens when it ends.
    private func start() async throws {
        let draft = try await model.makeDraft()
        let artwork = try await library.create(draft)
        library.drafts.drop(photoID: model.photoID)
        PaintTips.pageMade()
        let place = previewPicture.picture
        let from = StartHandoffPlan.entry(reduceMotion: reduceMotion, from: place)
        if Preferences().playsMakingOf, let source = model.makingOfSource(for: draft, artworkID: artwork.id) {
            makingOf = MakingOfRequest(artwork: artwork, source: source, entry: from)
        } else {
            // The preview's picture is what moves to the painting, from where it is.
            if let from, let picture = model.preview?.picture {
                departure = PictureDeparture(picture: picture, rect: from, radius: Theme.cardRadius, opacity: 0)
            }
            onStart(artwork)
        }
    }

    // MARK: Into the painting

    /// The painting beneath the cover has drawn its first frame, its template at `target` (global
    /// coordinates): the picture moves there while the rest of the flow fades to clear, then
    /// cross-fades into the canvas. Reduce Motion fades the whole flow instead, in place.
    private func dissolve(into target: CGRect) {
        guard !isDissolving else { return }
        isDissolving = true
        Log.create.notice("Hand-off: the painting drew, template at \(String(describing: target), privacy: .public)")
        hideFlowUnderTheShow()
        let motion = StartHandoffPlan.motion(reduceMotion: reduceMotion, target: target)
        if motion == .fly {
            flightTarget = target
            targetChangedAt = .now
        }
        Task {
            switch motion {
            case .fly:
                withAnimation(.spring(duration: StartHandoffPlan.move, bounce: StartHandoffPlan.bounce)) {
                    leaving = .moving(target)
                    departure?.rect = target
                    departure?.radius = 2
                }
                withAnimation(.easeOut(duration: StartHandoffPlan.appear)) { departure?.opacity = 1 }
                withAnimation(.easeOut(duration: StartHandoffPlan.fade)) { flowOpacity = 0 }
                try? await Task.sleep(for: .seconds(StartHandoffPlan.landAfter))
                // Not while the template is still moving: the status bar going takes the painting's
                // layout with it, a moment after the flow started to go.
                for _ in 0..<30 where ContinuousClock.now - targetChangedAt < StartHandoffPlan.settle {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                hasLanded = true
                withAnimation(.easeOut(duration: StartHandoffPlan.crossFade)) {
                    leaving = .landed(flightTarget ?? target)
                    departure?.opacity = 0
                }
                try? await Task.sleep(for: .seconds(StartHandoffPlan.crossFade + 0.05))
            case .crossFade:
                withAnimation(.easeInOut(duration: StartHandoffPlan.move)) {
                    leaving = .landed(nil)
                    flowOpacity = 0
                }
                try? await Task.sleep(for: .seconds(StartHandoffPlan.move + 0.05))
            }
            handoff?.complete()
        }
    }

    /// The show's paper hides the settings until it fades; they go at once, or they would show
    /// through it, faintly, as it does.
    private func hideFlowUnderTheShow() {
        guard makingOf != nil else { return }
        withAnimation(nil) { flowOpacity = 0 }
    }

    /// A layout moved the template while the picture was on its way (the palette settling, the
    /// status bar going): the picture heads for where it is now. Once it is cross-fading into the
    /// canvas it is left where it landed.
    private func retarget(to target: CGRect) {
        guard let current = flightTarget, current != target, !hasLanded else { return }
        Log.create.notice("Hand-off: the template moved to \(String(describing: target), privacy: .public)")
        flightTarget = target
        targetChangedAt = .now
        withAnimation(.spring(duration: StartHandoffPlan.move, bounce: StartHandoffPlan.bounce)) {
            leaving = .moving(target)
            departure?.rect = target
        }
    }

    /// The painting didn't draw in time (a slow open, or the recovery screen): the flow fades away
    /// alone, and the painting stays pushed beneath.
    private func giveUp() {
        guard !isDissolving else { return }
        isDissolving = true
        Log.create.notice("Hand-off: the painting never drew; the cover fades away")
        hideFlowUnderTheShow()
        Task {
            withAnimation(.easeInOut(duration: StartHandoffPlan.move)) {
                leaving = .landed(nil)
                departure?.opacity = 0
                flowOpacity = 0
            }
            try? await Task.sleep(for: .seconds(StartHandoffPlan.move + 0.05))
            handoff?.complete()
        }
    }
}

/// The preview's picture, between Start and the painting: fixed in its place, then moved to where
/// the painting's template is, with the picture's corners squaring as the canvas's do.
private struct PictureDeparture {
    let picture: CreateModel.Picture
    /// Global coordinates.
    var rect: CGRect
    var radius: CGFloat
    var opacity: Double
}

private struct DepartingPicture: View {
    let departure: PictureDeparture

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            picture
                .frame(width: departure.rect.width, height: departure.rect.height)
                .clipShape(.rect(cornerRadius: departure.radius, style: .continuous))
                .offset(x: departure.rect.minX - origin.x, y: departure.rect.minY - origin.y)
                .opacity(departure.opacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var picture: some View {
        switch departure.picture {
        case .painting(let image):
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
        case .lineArt(let drawing):
            LineArtLayer(drawing: drawing, picture: CGRect(origin: .zero, size: departure.rect.size), scale: 1)
                .equatable()
        }
    }
}

/// What the flow hands the drafts (`Drafts.keep`): the draft, and the template on screen, whose
/// trail goes with it once the draft's edits are all laid.
private struct DraftKeeping: Equatable {
    let draft: CreateDraft?
    let shown: UUID?
}
