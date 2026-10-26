#if DEBUG
import CoreGraphics
import Foundation
import os
import PaintCore

/// Demo scenarios owned by the app shell (see `DemoMode`). Each uses a throwaway library
/// seeded deterministically from the library's pictures (`pictures`): the ones a viewer judges
/// the app by show the library by position, the rest six pictures chosen by name
/// (`fixedPictures`).
///
/// - `gallery`, `gallery-dark`: the library's first six pictures (all of them while it holds
///   fewer) painted to various stages, the third a favorite.
/// - `gallery-favorites`, `gallery-favorites-dark`: the fixed pictures' paintings with two
///   favorites and the Show filter on Favorites.
/// - `gallery-search`, `gallery-search-dark`: the same paintings with "re" typed in the search
///   field (two results).
/// - `gallery-no-favorites-long-text`: the Favorites filter with nothing favorited (its empty state),
///   with every localized string twice as long.
/// - `gallery-empty`: the empty state, once its sketch has painted itself (SideStore and Debug).
/// - `gallery-first-run`: the gallery as the first launch leaves it: the library's two starter
///   paintings, none of them painted on (ready to paint, nothing in progress).
/// - `gallery-preparing`: the first launch's gallery while its two starters are still being made:
///   their placeholders, held there (`Library.holdPlaceholders`), ready once their pictures load.
/// - `gallery-draft`, `gallery-draft-long-text`: three paintings below the create flow's draft
///   (The Great Wave, refined as in `create-refine`), with its photo, "Continue Refining" and
///   Discard; the second with every localized string twice as long.
/// - `create`: the photo picker step of the create flow.
/// - `create-samples`, `create-samples-long-text`: the same step on its Samples pane (iPhone;
///   iPad shows both); the second with every localized string twice as long.
/// - `create-samples-paintings`, `create-samples-photographs`: the Samples pane scrolled to its
///   Paintings or Photographs section.
/// - `create-preview`, `create-preview-dark`: the painting starter generated, comparison at half.
/// - `create-line-art`: `create-preview` with Settings › Preview on Line Art: the drawing alone
///   beside the photo.
/// - `create-refine`, `create-refine-dark`: The Great Wave's Refine screen, refined as a painter
///   might (`refinements(canvas:)`, edits made to the template by hand): the big cloud's edge drawn
///   in, exactly as drawn, the spray off the wave's crest rubbed out.
/// - `create-refine-colors`, `create-refine-colors-dark`: the same, in Starry Night, with Refine's
///   Looks open over the painting (`RefineColorsPanel`).
/// - `create-refine-colors-picked`, `create-refine-colors-picked-dark`: Edit Paint with the paint
///   used by the most areas the current paint, all of those areas glowing (`RefinePaintGlow`).
/// - `create-refine-card`, `create-refine-card-dark`: the Studio with the card of the largest
///   area open, as a long press opens it (`RefineAreaCard`), its paint's areas glowing.
/// - `create-refine-select`, `create-refine-select-dark`: the Toolbox on Select with the largest
///   area selected: its outline, its bar (`RefineSelectionBar`), the palette and the cells' undrawn
///   edges.
/// - `create-refine-guide`, `-dark`, `-long-text`: Refine's Tool Guide over the Toolbox, on Merge's
///   page: the practice picture on its canvas, the words beside it (`RefineGuideView`); ready once
///   the canvas shows.
/// - `create-suggested`: the photograph starter on its suggested settings ("Suggested for this
///   picture" chip).
/// - `create-custom`, `create-custom-long-text`: The Great Wave after Detail moved off the
///   suggestion (the chip offers Reset to Suggested); the second with every localized string
///   twice as long.
/// - `create-from-file`: a photo file opened as if shared from another app ("Open in Paint by
///   Moonlight"): the create flow on that photo's preview, titled with the file's name. The file
///   is the red fox written to the temporary directory at launch (`DemoMode.openFileURL`).
/// - `create-unlock`, `-dark`, `-long-text`: the same photo with no free painting left
///   (`freePaintings`): Start Painting tapped once the painting is made, Unlimited Paintings'
///   sheet over the preview, ready once its price shows (`UnlockSheet`).
/// - `gallery-tip`, `-dark`, `-long-text`: the gallery as the first launch leaves it, with A Page
///   Is Waiting inline in Ready to Paint; the tips show only in the scenarios named here and
///   `paint-tip` (`PaintTips.configure`).
/// - `gallery-tip-gear`: one finished painting on the shelf, with Settings and Tips as a card atop
///   the pages. `gallery-tips-off` (UI tests) is the first launch's gallery with the Tips switch off.
/// - `create-tip`: the photograph starter's preview with Already Chosen for You at the
///   "Suggested for this picture" chip (the divider's tip is closed already).
/// - `settings`: the settings sheet over the gallery.
/// - `settings-tips`: the same with tips on, for its Tips section; `settings-tip` waits for Worth a
///   Look Here at Painting Length.
/// - `settings-acknowledgements`: the settings sheet on its Acknowledgements screen.
/// - `gallery-open`: a painting opened from its card (zoom transition into `PaintView`).
/// - `gallery-send`, `gallery-send-dark`, `gallery-send-long-text`: Send Template's sheet over
///   the gallery, for The Great Wave painted in part: the blank page, Original Photo on.
/// - `gallery-received`, `gallery-received-dark`: a painting someone sent opened in the app, as
///   "Open in Paint by Moonlight" does with a `.moonlight` file: The Great Wave refined as in
///   `create-refine`, sent with its photo as Send Template… makes it (`sentPaintingFile`), added
///   to the empty library and opened, blank.
/// - `gallery-damaged`: a painting whose template file is damaged, opened: the recovery screen.
/// - `gallery-timelapse`: a finished painting's time-lapse being made (progress sheet).
/// - `gallery-long-text`, `gallery-timelapse-long-text`, `settings-long-text`: the fixed
///   pictures' gallery (with a deletion, so its Undo toast is up), `gallery-timelapse` and
///   `settings` with every localized string twice as long: `ci/screenshots.sh` adds
///   `-NSDoubleLocalizedStrings YES` to scenarios named `*-long-text`, the pseudo-localization that
///   shows where translations (German, Finnish, ...) would truncate or overflow.
enum ShellDemo: Equatable {
    case gallery, galleryFavorites, gallerySearch, galleryNoFavorites, galleryLongText, galleryEmpty, galleryFirstRun, galleryPreparing,
         galleryDraft, galleryOpen, gallerySend, galleryReceived, galleryDamaged, galleryTimelapse, galleryTimelapseLongText, create, createSamples, createSamplesPaintings,
         createSamplesPhotographs, createPreview, createLineArt, createRefine, createRefineColors, createRefineColorsPicked, createRefineCard, createRefineSelect, createRefineGuide, createSuggested, createCustom, createFromFile,
         createUnlock, galleryTip, galleryTipGear, galleryTipsOff, createTip, settingsTips, settingsTip,
         settings, settingsLongText, settingsAcknowledgements

    static let current: ShellDemo? = {
        switch DemoMode.scenario {
        case "gallery", "gallery-dark": .gallery
        case "gallery-favorites", "gallery-favorites-dark": .galleryFavorites
        case "gallery-search", "gallery-search-dark": .gallerySearch
        case "gallery-no-favorites-long-text": .galleryNoFavorites
        case "gallery-long-text": .galleryLongText
        case "gallery-empty": .galleryEmpty
        case "gallery-first-run": .galleryFirstRun
        case "gallery-preparing": .galleryPreparing
        case "gallery-draft", "gallery-draft-long-text": .galleryDraft
        case "gallery-open": .galleryOpen
        case "gallery-send", "gallery-send-dark", "gallery-send-long-text": .gallerySend
        case "gallery-received", "gallery-received-dark": .galleryReceived
        case "gallery-damaged": .galleryDamaged
        case "gallery-timelapse": .galleryTimelapse
        case "gallery-timelapse-long-text": .galleryTimelapseLongText
        case "create": .create
        case "create-samples", "create-samples-long-text": .createSamples
        case "create-samples-paintings": .createSamplesPaintings
        case "create-samples-photographs": .createSamplesPhotographs
        case "create-preview", "create-preview-dark": .createPreview
        case "create-line-art": .createLineArt
        case "create-refine", "create-refine-dark": .createRefine
        case "create-refine-colors", "create-refine-colors-dark": .createRefineColors
        case "create-refine-colors-picked", "create-refine-colors-picked-dark": .createRefineColorsPicked
        case "create-refine-card", "create-refine-card-dark": .createRefineCard
        case "create-refine-select", "create-refine-select-dark": .createRefineSelect
        case "create-refine-guide", "create-refine-guide-dark", "create-refine-guide-long-text": .createRefineGuide
        case "create-suggested": .createSuggested
        case "create-custom", "create-custom-long-text": .createCustom
        case "create-from-file": .createFromFile
        case "create-unlock", "create-unlock-dark", "create-unlock-long-text": .createUnlock
        case "gallery-tip", "gallery-tip-dark", "gallery-tip-long-text": .galleryTip
        case "gallery-tip-gear": .galleryTipGear
        case "gallery-tips-off": .galleryTipsOff
        case "create-tip": .createTip
        case "settings-tips": .settingsTips
        case "settings-tip": .settingsTip
        case "settings": .settings
        case "settings-long-text": .settingsLongText
        case "settings-acknowledgements": .settingsAcknowledgements
        default: nil
        }
    }()

    /// The Show filter starts on Favorites.
    var showsFavoritesOnly: Bool { self == .galleryFavorites || self == .galleryNoFavorites }

    /// Whether the scenario shows the library by position: the ones a viewer judges the app by
    /// do (`Sample.all`, `Sample.starters`), so curating the library needs no edit here. The
    /// rest, and UI tests that name paintings (`-demoFixedPictures YES`), show `fixedPictures`.
    private var showsLibrary: Bool {
        (self == .gallery || self == .createPreview || self == .createLineArt || self == .createSuggested)
            && !DemoMode.usesFixedPictures
    }

    /// Six library pictures by name, whose titles UI tests look for, in the order the gallery
    /// scenarios paint them (`galleryItems`): a painting and a photograph first (the create
    /// scenarios' too), the favorites third and sixth (`favoriteSamples`), and only the fourth
    /// and sixth matching `searchText`. A picture the library drops is replaced here and in the
    /// UI tests.
    private static let fixedPictures: [Sample] =
        ["great-wave", "delicate-arch", "earthrise", "red-fox", "milkmaid", "red-fuji"].compactMap(Sample.named)

    /// The pictures the gallery scenarios paint, by position.
    private var pictures: [Sample] { showsLibrary ? Sample.all : Self.fixedPictures }

    /// The pictures whose paintings are favorites, by position in `pictures` (of the fixed
    /// pictures: Earthrise, and Red Fuji).
    private var favoriteSamples: [String] {
        let positions: [Int] = switch self {
        case .gallery, .gallerySearch: [2]
        case .galleryFavorites: [2, 5]
        default: []
        }
        return positions.filter { $0 < pictures.count }.map { pictures[$0].id }
    }

    /// The search field starts with this text: it finds "Red Fox in Snow" and "Red Fuji".
    var searchText: String? { self == .gallerySearch ? "re" : nil }

    var sharesTimelapse: Bool { self == .galleryTimelapse || self == .galleryTimelapseLongText }

    var sendsTemplate: Bool { self == .gallerySend }

    var opensCreateFlow: Bool {
        self == .create || opensSamples || self == .createPreview || self == .createLineArt || self == .createRefine
            || opensColors || opensCard || selectsCell || opensGuide != nil || self == .createSuggested || self == .createCustom || self == .createTip
    }

    /// The create flow starts on its Samples pane (iPhone; iPad shows both panes).
    var opensSamples: Bool { self == .createSamples || self == .createSamplesPaintings || self == .createSamplesPhotographs }

    /// The Samples pane starts scrolled to this section.
    var samplesSection: Sample.Kind? {
        switch self {
        case .createSamplesPaintings: .painting
        case .createSamplesPhotographs: .photograph
        default: nil
        }
    }

    var opensSettings: Bool {
        self == .settings || self == .settingsLongText || self == .settingsAcknowledgements || self == .settingsTips
            || self == .settingsTip
    }

    var previewSample: Sample? {
        switch self {
        // A painting and a photograph: the library's starters, or the first two fixed pictures.
        case .createPreview, .createLineArt: showsLibrary ? Sample.starters.first : pictures.first
        case .createSuggested: showsLibrary ? Sample.starters.last : pictures.dropFirst().first
        case .createTip: pictures.dropFirst().first
        case .createCustom, .createRefine, .createRefineColors, .createRefineColorsPicked, .createRefineCard, .createRefineSelect,
             .createRefineGuide:
            pictures.first
        default: nil
        }
    }

    /// The free paintings left at launch (`UnlockStoreStub`); nil leaves the three a new painter has.
    var freePaintings: Int? { self == .createUnlock ? 0 : nil }

    /// The painter moves Detail once the suggestion is ready, so the settings become custom.
    var movesASlider: Bool { self == .createCustom }

    /// Settings › Preview for the scenario's create flow; nil keeps the stored one.
    var previewStyle: PreviewStyle? { self == .createLineArt ? .lineArt : nil }

    /// The create flow refines its painting (`refinements(canvas:)`) once the suggestion is ready,
    /// and shows the Refine screen.
    var refines: Bool { self == .createRefine || opensColors || opensCard || selectsCell || opensGuide != nil }

    /// Refine opens the card of its largest area once its edits have landed.
    var opensCard: Bool { self == .createRefineCard }

    /// Refine opens the Tool Guide on this page, ready once its practice canvas shows
    /// (`RefineView.land`).
    var opensGuide: RefineGuideTopic? { self == .createRefineGuide ? .tool(.merge) : nil }

    /// Refine opens on Select with its largest area selected once its edits have landed.
    var selectsCell: Bool { self == .createRefineSelect }

    /// Refine opens on Colors, over the painting.
    var opensColors: Bool { self == .createRefineColors || picksColorPaint }

    /// Refine picks the paint used by the most areas when it opens Colors.
    var picksColorPaint: Bool { self == .createRefineColorsPicked }

    /// What `create-refine` draws and erases on The Great Wave (the first fixed picture), for the
    /// canvas of `template`.
    static func refinements(for template: Template) -> TemplateRefinements {
        var refinements = refinements(canvas: CGSize(width: template.width, height: template.height))
        if current?.opensColors == true { refinements.edits.append(TemplateEditor.look(.starryNight, strength: 1, on: template)) }
        return refinements
    }

    /// The same for a canvas of `size`, in canvas units: laid on the template by hand, as Refine
    /// does.
    static func refinements(canvas size: CGSize) -> TemplateRefinements {
        func at(_ x: Float, _ y: Float) -> SIMD2<Float> { SIMD2(x * Float(size.width), y * Float(size.height)) }
        var refinements = TemplateRefinements()
        refinements.edits = [
            .draw(points: [
                at(0.53, 0.22), at(0.56, 0.15), at(0.62, 0.10), at(0.70, 0.09), at(0.77, 0.12), at(0.82, 0.18), at(0.90, 0.22),
                at(1.02, 0.25),
            ]),
            .erase(path: [at(0.55, 0.40), at(0.58, 0.44), at(0.60, 0.48)], radius: 0.02 * Float(max(size.width, size.height))),
        ]
        return refinements
    }

    /// How long `create` and the `create-samples` scenarios give the library picker (and the
    /// sample tiles) to load before they signal readiness: the picker runs out of process and
    /// reports nothing when its grid is up. The value is empirical: raise it if CI's `create`
    /// screenshots show the picker still loading (`*-steps.log` gives each scenario's time to
    /// readiness, launch included).
    static let pickerLoadAllowance: Duration = .seconds(3)

    func prepare(_ library: Library) {
        switch self {
        case .gallery, .galleryFavorites, .gallerySearch, .galleryNoFavorites:
            let favorites = favoriteSamples
            library.seed(galleryItems, completion: { _ in
                for artwork in library.artworks {
                    if let sample = artwork.sampleName, favorites.contains(sample) { library.setFavorite(artwork.id, true) }
                }
                DemoMode.markReady()
            })
        case .galleryFirstRun, .galleryTipsOff:
            // What the first launch makes (`Library.seedIfNeeded`): the starters, nobody's touched.
            library.seed(Sample.starters.map { Library.SeedItem(sample: $0, photoMaxPixelSize: 560) }, completion: { _ in
                DemoMode.markReady()
            })
        case .galleryPreparing:
            // The first launch's pages before they are made: nothing is made, the placeholders stay.
            library.holdPlaceholders(Sample.starters)
            Task {
                // Ready once their pictures are loaded, at the size the cards ask for (the cache
                // hands the cards the same images).
                for sample in Sample.starters { _ = await SampleImages.shared.load(sample, maxPixelSize: PlaceholderCard.pictureSize) }
                DemoMode.markReady()
            }
        case .galleryTip:
            // The first launch's gallery, ready once the tip the scenario shows is up.
            library.seed(Sample.starters.map { Library.SeedItem(sample: $0, photoMaxPixelSize: 560) }, completion: { _ in
                Task {
                    await PaintTips.awaitDemoTip()
                    DemoMode.markReady()
                }
            })
        case .galleryTipGear:
            // A finished painting: nothing waits to be painted, so the gear's tip comes first.
            library.seed([Library.SeedItem(sample: pictures[1], painted: 1, photoMaxPixelSize: 560)], completion: { _ in
                Task {
                    await PaintTips.awaitDemoTip()
                    DemoMode.markReady()
                }
            })
        case .createTip, .settingsTip:
            Task {
                await PaintTips.awaitDemoTip()
                DemoMode.markReady()
            }
        case .galleryLongText:
            library.seed(galleryItems, completion: { _ in
                // The newest deletion keeps its Undo toast up for `Library.undoWindow`, well past the screenshot.
                if let id = library.finished.last?.id { library.delete(id) }
                DemoMode.markReady()
            })
        case .galleryDraft:
            library.seed(Array(galleryItems.prefix(3))) { _ in
                Task {
                    await seedDraft(in: library)
                    DemoMode.markReady()
                }
            }
        case .galleryOpen:
            let painted = ProcessInfo.processInfo.arguments.contains("-playHarness") ? 0.0 : 0.42
            library.seed([Library.SeedItem(sample: pictures[0], painted: painted, photoMaxPixelSize: 560)])
        case .galleryDamaged:
            library.seed([Library.SeedItem(sample: pictures[0], painted: 0.42, photoMaxPixelSize: 560)]) { _ in
                // Synchronous on purpose: this runs in the same main-actor job that empties
                // `placeholders`, so the file is damaged before SwiftUI's next update delivers
                // the `onChange` that opens the painting (`AppShellView`).
                guard let id = library.artworks.first?.id else { return }
                try? Data("damaged".utf8).write(to: library.store.url(.template, of: id))
            }
        case .galleryTimelapse, .galleryTimelapseLongText:
            library.seed([Library.SeedItem(sample: pictures[1], painted: 1, photoMaxPixelSize: 560)])
        case .gallerySend:
            library.seed([Library.SeedItem(sample: pictures[0], painted: 0.42, photoMaxPixelSize: 560)])
        case .create, .createSamples, .createSamplesPaintings, .createSamplesPhotographs, .createPreview,
             .createLineArt, .createRefine, .createRefineColors, .createRefineColorsPicked, .createRefineCard, .createRefineSelect, .createRefineGuide, .createSuggested, .createCustom, .createFromFile, .createUnlock, .galleryReceived, .galleryEmpty, .settings,
             .settingsTips, .settingsLongText, .settingsAcknowledgements:
            break
        }
    }

    /// The create flow's draft: the first picture refined as `create-refine` does it, kept the way
    /// the flow keeps one.
    private func seedDraft(in library: Library) async {
        guard let sample = pictures.first, let url = sample.url,
              let photo = await Background.run({ try? PhotoLoader.load(url: url, maxPixelSize: 560) }),
              let image = PhotoLoader.cgImage(from: photo) else { return }
        // The canvas the draft's settings make of its photo, which is what resuming lays the edits on.
        let settings = GenerationSettings()
        let canvas = settings.workingSize(sourceWidth: photo.width, sourceHeight: photo.height)
        library.drafts.keep(
            CreateDraft(
                photoID: UUID(), title: "", defaultTitle: sample.title, settings: settings, lines: 0.5,
                sampleName: sample.id, refinements: Self.refinements(canvas: CGSize(width: canvas.width, height: canvas.height))),
            photo: image)
        await library.drafts.flush()
    }

    /// What `gallery-received` opens: the first fixed picture refined as `create-refine` does it,
    /// written with its photo as Send Template… writes it.
    static func sentPaintingFile() async -> URL? {
        guard let sample = fixedPictures.first else { return nil }
        do {
            let draft = try await ArtworkFactory.draft(sample: sample, photoMaxPixelSize: 560)
            let edits = refinements(for: draft.template).edits
            let title = sample.title
            return try await Background.run {
                let template = try ArtworkFactory.laying(edits, on: draft.template)
                let photo = draft.photo.flatMap { ImageCodec.jpegData($0, quality: 0.88) }
                let data = try SharedPaintingCodec.encode(SharedPainting(
                    title: title, settings: draft.settings, template: template, photo: photo, sampleName: draft.sampleName))
                return try ArtworkExporter.temporaryFile(
                    data, name: ArtworkExporter.templateName(title: title), pathExtension: SharedPaintingCodec.fileExtension)
            }
        } catch {
            Log.demo.error("The sent painting couldn't be made: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The first six pictures painted to various stages: three in progress, one nobody has painted
    /// on, two finished (`GalleryActionsTests` waits for the subtitle that counts them, "3 in
    /// progress · 1 ready · 2 finished"; with two pictures, one in progress and one finished).
    private var galleryItems: [Library.SeedItem] {
        let hour: TimeInterval = 3600
        // By position: the fraction painted, and the hours since it was last painted.
        let stages: [(painted: Double, hours: TimeInterval)] = [(0.42, 1), (1, 5), (0.68, 3), (0.12, 26), (0, 50), (1, 80)]
        return zip(pictures, stages).map { sample, stage in
            Library.SeedItem(sample: sample, painted: stage.painted, age: stage.hours * hour, photoMaxPixelSize: 560)
        }
    }

    /// Scenarios that are complete as soon as the shell appears (the rest signal readiness
    /// once their content has been generated or loaded; `gallery-empty` once its sketch has
    /// painted itself, `SelfPaintingSketch`).
    var isReadyOnAppear: Bool { opensSettings && self != .settingsTip }
}
#endif
