import CoreGraphics
import MosaicEngine
import os
import SwiftUI

/// New painting: pick a photo (library, camera or a sample) → tune the mosaic → paint.
///
/// Ravenna's seam: no drafts (Refine made them) and no Settings › Preview; the making-of is
/// Ravenna's own show of the mosaic being set (`MakingOfView`), on by default.
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
    var onStart: (Artwork) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.startHandoff) private var handoff
    @Environment(Library.self) private var library
    @State private var model = CreateModel()
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
            if ShellDemo.current?.movesASlider == true, model.recipe.pieces == MosaicEngine.Recipe.standardPieces {
                // As a painter would: Pieces moved off the standard count and let go, so the engine
                // lays it (the standard count of a library picture is its bundled mosaic).
                model.recipe.pieces = 0.75
                model.recipeChanged()
                return
            }
            if let marks = ShellDemo.current?.refineMarks, model.recipe.marks.isEmpty {
                // As a painter would in Refine: a line drawn and gold brushed, then laid.
                model.recipe.marks = marks
                model.recipeChanged()
                return
            }
            if openingSample != nil || ShellDemo.current == .createFromFile {
                DemoMode.markReady()
            }
        }
        #endif
        .onDisappear {
            model.cancelAll()
        }
    }

    @ViewBuilder
    private var root: some View {
        if droppedPhoto != nil || openingSample != nil {
            TemplatePreviewView(model: model, onStart: start, onClose: { dismiss() }, pictureProbe: previewPicture)
        } else {
            PhotoSourceView(model: model, initialPane: initialPane, onClose: { dismiss() }) {
                path = [.preview]
            }
        }
    }

    /// The `create-samples` demos open on the Samples pane; everything else starts on Photos.
    private var initialPane: PhotoSourceView.Pane {
        #if DEBUG
        if ShellDemo.current?.opensSamples == true { return .samples }
        #endif
        return .photos
    }

    /// Saves the mosaic's template to the library and opens it for painting. With Settings › The
    /// Making-of on (as it is unless switched off), the saved painting's show plays first, and the
    /// painting opens when it ends.
    private func start() async throws {
        let draft = try await model.makeDraft()
        let artwork = try await library.create(draft)
        PaintTips.pageMade()
        let place = previewPicture.picture
        let from = StartHandoffPlan.entry(reduceMotion: reduceMotion, from: place)
        if Preferences().playsMakingOf, let source = model.makingOfSource(for: draft) {
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
        }
    }
}
