import CoreGraphics
import Foundation
import MosaicKit
import os
import PaintCore
import SwiftUI
import UIKit

/// Opens an artwork for painting: loads it off the main actor, hosts `PaintView`, and
/// saves progress while the user paints. When it can't be opened it explains why and offers
/// recovery (`PaintingRecoveryView`).
struct ArtworkPaintingView: View {
    let artworkID: UUID
    var onClose: () -> Void

    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    /// The hand-off from Start Painting: this painting, just made, opens under the create flow's
    /// cover, which dissolves into it once the canvas has drawn (`StartHandoff`).
    @Environment(\.startHandoff) private var handoff
    @AppStorage(SettingsKey.paperAppearance) private var paperAppearance = PaperAppearance.default
    @Environment(\.colorScheme) private var colorScheme
    @State private var autosaver: PaintingAutosaver?
    /// Made once when the painting is presented, not in `body`: each autosave replaces the
    /// artwork in the library, and values made afresh would reach `PaintView` as changed
    /// environment on every one. None of what they read changes while painting.
    @State private var sourcePhotoLoader: SourcePhotoLoader?
    @State private var feedbackSource: FeedbackSource?
    /// Ravenna's seam: the More menu's making-of and About This Work (`PaintingWork`).
    @State private var paintingWork: PaintingWork?
    /// The push has finished. Only then does the painting replace its thumbnail: the zoom
    /// transition lays the screen out afresh every frame, and the painting screen rendered at
    /// each of them kept CI's simulator from answering for up to half a minute (hundreds of
    /// renders in one push), where the thumbnail costs next to nothing.
    @State private var hasLanded = false
    @State private var failure: Library.OpenError?
    @State private var regeneration: Task<Void, Never>?
    @State private var regenerationFailed = false
    @State private var notice: ShownNotice?

    private struct ShownNotice: Equatable {
        var notice: OpenNotice
        var id = UUID()
    }

    private var artwork: Artwork? { library.artwork(with: artworkID) }
    private var saveFailed: Bool { library.writeFailures[artworkID] != nil }

    /// Under the create flow's cover, waiting to be handed the screen: nothing of the painting
    /// fades in, since the cover is what dissolves.
    private var isUnderCover: Bool { handoff?.isOpening(artworkID) == true }

    /// What the canvas tells once its first frame is on screen, while the cover waits for it, and
    /// when a layout moves the template after that.
    private var canvasReport: ((CGRect) -> Void)? {
        guard isUnderCover else { return nil }
        return { rect in canvasDrew(rect) }
    }

    /// The canvas has its template at `templateRect` (global coordinates): where the cover is to
    /// bring its picture.
    private func canvasDrew(_ templateRect: CGRect) {
        Log.create.notice("Painting reports its template at \(String(describing: templateRect), privacy: .public)")
        handoff?.paintingDrew(artworkID, templateRect: templateRect)
    }

    /// Where the painting came from, for feedback given on it. The painter's own photo is read
    /// (as stored, off the main actor) only if they choose to send it; a library picture's is
    /// in the repository.
    private func makeFeedbackSource(for artwork: Artwork) -> FeedbackSource {
        let store = library.store, id = artworkID
        var photo: (@Sendable () async -> Data?)?
        if artwork.sampleName == nil {
            photo = { await Background.run { try? Data(contentsOf: store.url(.source, of: id)) } }
        }
        return FeedbackSource(
            artworkID: id, settings: artwork.settings, settingsOrigin: artwork.settingsOrigin,
            paintingLength: artwork.paintingLength, sampleName: artwork.sampleName, createdAt: artwork.createdAt, photo: photo)
    }

    /// What the More menu tells of this mosaic: its making-of, made from its mosaic and its stored
    /// photo when asked for, and a library work's record.
    private func makePaintingWork(mosaic: Mosaic?) -> PaintingWork {
        let sample = artwork?.sampleName.flatMap(Sample.named), title = artwork?.title ?? ""
        var makingOf: (@Sendable () async -> MakingOfSource?)?
        if let mosaic {
            makingOf = { [library, artworkID] in
                guard let photo = await library.sourcePhoto(for: artworkID) else { return nil }
                return MakingOfSource(
                    mosaic: mosaic, photo: photo, finish: MosaicLook.current.finish, title: title,
                    credit: sample.map { MakingOfSource.credit(of: $0) } ?? MakingOfSource.ownPhotoCredit)
            }
        }
        return PaintingWork(sample: sample, makingOf: makingOf)
    }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let autosaver, hasLanded {
                PaintView(
                    session: autosaver.session, title: artwork?.title ?? "", onClose: close,
                    onTemplateFrame: canvasReport)
                    .environment(\.sourcePhotoLoader, sourcePhotoLoader)
                    .environment(\.feedbackSource, feedbackSource)
                    .environment(\.paintingWork, paintingWork)
                    .background { RevisionObserver(session: autosaver.session, onChange: autosaver.sessionChanged) }
                    .transition(.opacity)
            } else if let failure {
                PaintingRecoveryView(
                    artwork: artwork, failure: failure,
                    progress: regeneration == nil ? nil : (library.regenerating[artworkID] ?? 0),
                    didFail: regenerationFailed,
                    onRegenerate: regenerate, onDelete: delete, onClose: onClose)
                    .transition(.opacity)
                    #if DEBUG
                    .onAppear {
                        if ShellDemo.current == .galleryDamaged { DemoMode.markReady() }
                    }
                    #endif
            } else if let artwork {
                // What the zoom transition shows, and where it lands while the template loads.
                ArtworkThumbnail(artwork: artwork, contentMode: .fit)
                    .aspectRatio(artwork.aspectRatio, contentMode: .fit)
                    .padding(20)
                    .overlay {
                        if autosaver == nil { ProgressView().controlSize(.large) }
                    }
            }
        }
        // Below PaintView's top bar (6 pt inset + 44 pt buttons).
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let notice {
                    Toast(text: notice.notice.text, systemImage: notice.notice.systemImage, edge: .top)
                        // Taps reach the canvas under it.
                        .allowsHitTesting(false)
                }
                if saveFailed {
                    Toast(text: String(localized: "Couldn’t save progress"), systemImage: "exclamationmark.triangle", edge: .top) {
                        Button("Retry") { library.retrySaving(artworkID) }
                            .fontWeight(.semibold)
                    }
                }
            }
            .padding(.top, 62)
            .padding(.horizontal, 20)
            // Over the painting, like its bars.
            .environment(\.colorScheme, PaintView.chromeScheme(paper: paperAppearance, system: colorScheme))
        }
        .animation(.snappy, value: notice)
        .animation(.snappy, value: saveFailed)
        .onChange(of: saveFailed) { _, failed in
            if failed { Announcer.announce(String(localized: "Couldn’t save progress")) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background { CanvasGesturesOverZoomDismissal(onAppear: land).frame(width: 0, height: 0) }
        .task { await open() }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            autosaver?.saveNow(refreshThumbnail: true)
            if phase == .background {
                let library = library
                BackgroundSaving.shared.hold { await library.flush() }
            }
        }
        .onDisappear {
            regeneration?.cancel()
            autosaver?.saveNow(refreshThumbnail: true)
        }
    }

    private func open() async {
        guard autosaver == nil, failure == nil else { return }
        do {
            let document = try await library.loadForPainting(artworkID)
            _ = await RenderContext.ready()
            await present(document)
        } catch {
            Log.library.error("Opening \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            withAnimation(.easeOut(duration: 0.25)) {
                failure = error as? Library.OpenError ?? .damaged(canRegenerate: false)
            }
        }
    }

    /// Callers await `RenderContext.ready()` first: the canvas this shows needs it.
    private func present(_ document: PaintingDocument) async {
        let session: PaintingSession
        do {
            session = try await PaintingSession.make(
                template: document.template, progress: document.progress, mosaic: document.mosaic,
                nicknameSeed: ColorNickname.seed(for: artworkID),
                nicknameVersion: artwork?.nicknameVersion ?? 1)
        } catch is CancellationError {
            return
        } catch {
            // The library hands out matching progress; this guards against a bug, not a file.
            Log.library.error("Opening \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            failure = .damaged(canRegenerate: artwork.map { ArtworkFactory.canRegenerate($0, store: library.store) } ?? false)
            return
        }
        // Before the painting screen appears: its first tip and the first painting's limit.
        PaintTips.artworkOpened(artworkID)
        withAnimation(isUnderCover ? nil : .easeOut(duration: 0.25)) {
            failure = nil
            regenerationFailed = false
            autosaver = PaintingAutosaver(session: session, artworkID: artworkID, library: library)
            sourcePhotoLoader = SourcePhotoLoader { [library, artworkID] maxPixelSize in
                await library.sourcePhoto(for: artworkID, maxPixelSize: maxPixelSize)
            }
            feedbackSource = artwork.map(makeFeedbackSource)
            paintingWork = makePaintingWork(mosaic: document.mosaic)
        }
        if let notice = document.notice { show(notice) }
        Log.library.notice("Opened \(artworkID.uuidString, privacy: .public): \(document.template.regions.count, privacy: .public) regions")
        #if DEBUG
        markDemoReady()
        #endif
    }

    /// The push finished: the painting, when loaded, takes the thumbnail's place.
    private func land() {
        guard !hasLanded else { return }
        withAnimation(isUnderCover ? nil : .easeOut(duration: 0.25)) { hasLanded = true }
        #if DEBUG
        markDemoReady()
        #endif
    }

    #if DEBUG
    /// `gallery-open` and `gallery-received` are ready once the painting is on screen.
    private func markDemoReady() {
        guard autosaver != nil, hasLanded, ShellDemo.current == .galleryOpen || ShellDemo.current == .galleryReceived else { return }
        DemoMode.markReady()
    }
    #endif

    private func show(_ openNotice: OpenNotice) {
        let shown = ShownNotice(notice: openNotice)
        notice = shown
        Announcer.announce(openNotice.text)
        Task {
            try? await Task.sleep(for: .seconds(4))
            if notice == shown { notice = nil }
        }
    }

    private func regenerate() {
        guard artwork != nil, regeneration == nil else { return }
        regenerationFailed = false
        regeneration = Task {
            do {
                let document = try await library.regenerate(artwork: artworkID)
                _ = await RenderContext.ready()
                await present(document)
            } catch is CancellationError {
            } catch let error as Library.OpenError {
                failure = error
            } catch {
                Log.library.error("Regenerating \(artworkID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                regenerationFailed = true
            }
            regeneration = nil
        }
    }

    private func delete() {
        library.delete(artworkID)
        onClose()
    }

    private func close() {
        autosaver?.saveNow(refreshThumbnail: true)
        onClose()
    }
}

/// The zoom transition lets a swipe down or a pinch anywhere dismiss the pushed screen, which
/// steals the canvas's pan and pinch and drops the painter back in the gallery. SwiftUI has no
/// switch for it, so this turns the recognizers behind those two gestures off on the pushed
/// controller's view once it has appeared; the edge swipe back and the Back button keep
/// working. The recognizers are found by their UIKit class names (`PaintingNavigationTests`
/// notices if they change). It also tells `onAppear` that the push has finished (SwiftUI's own
/// `onAppear` comes as it starts).
private struct CanvasGesturesOverZoomDismissal: UIViewControllerRepresentable {
    var onAppear: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onAppear = onAppear
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) { controller.onAppear = onAppear }

    final class Controller: UIViewController {
        var onAppear: () -> Void = {}

        private static let dismissalRecognizers: Set<String> = [
            "_UIContentSwipeDismissGestureRecognizer", "_UISwipeDownGestureRecognizer", "_UITransformGestureRecognizer",
        ]

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The transition may install its recognizers just after the push completes.
            disableDismissalGestures()
            // Next turn: SwiftUI may be mid-update when UIKit calls this.
            Task { onAppear() }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                disableDismissalGestures()
            }
        }

        private func disableDismissalGestures() {
            var pushed: UIViewController? = self
            while let controller = pushed, !(controller.parent is UINavigationController) { pushed = controller.parent }
            guard let recognizers = pushed?.view.gestureRecognizers, !recognizers.isEmpty else { return }
            var names: [String] = []
            for recognizer in recognizers {
                let name = String(describing: type(of: recognizer))
                if recognizer.isEnabled && Self.dismissalRecognizers.contains(name) {
                    recognizer.isEnabled = false
                    names.append("\(name) (disabled)")
                } else {
                    names.append(name)
                }
            }
            Log.library.notice("Painting screen recognizers: \(names.joined(separator: ", "), privacy: .public)")
        }
    }
}

/// Re-evaluates only itself on each paint, keeping `PaintView` out of the invalidation.
private struct RevisionObserver: View {
    let session: PaintingSession
    var onChange: () -> Void

    var body: some View {
        Color.clear
            .onChange(of: session.revision) { onChange() }
    }
}

private extension OpenNotice {
    var text: String {
        switch self {
        case .progressReset:
            String(localized: "gallery.notice.progressReset",
                   defaultValue: "This painting’s saved progress couldn’t be read, so it starts fresh.",
                   comment: "Toast when a painting's saved progress was unreadable and has been reset")
        case .regenerated(keptProgress: true):
            String(localized: "gallery.notice.regeneratedKept",
                   defaultValue: "Painting regenerated. Your painted areas were kept.",
                   comment: "Toast after a damaged painting was regenerated and its painted areas carried over")
        case .regenerated(keptProgress: false):
            String(localized: "gallery.notice.regenerated",
                   defaultValue: "Painting regenerated from the original photo.",
                   comment: "Toast after a damaged painting was regenerated from its photo without its painted areas")
        }
    }

    var systemImage: String {
        switch self {
        case .progressReset: "exclamationmark.triangle"
        case .regenerated: "checkmark.circle"
        }
    }
}
