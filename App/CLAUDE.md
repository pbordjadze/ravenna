# App notes

`App/Ravenna` is Paint by Moonlight's `App/PaintByNumber`, copied at the commit
`tools/paintcore.sh` pins (issue #13). Its map, gotchas and features are that commit's
[`App/CLAUDE.md`](https://github.com/pbordjadze/paint-by-number/blob/f1024441199d1634e7a8c35012fe6af2f9973648/App/CLAUDE.md)
and the App rules of its root
[`CLAUDE.md`](https://github.com/pbordjadze/paint-by-number/blob/f1024441199d1634e7a8c35012fe6af2f9973648/CLAUDE.md)
(isolation, `MemberImportVisibility`, localization, demo mode, saved data): read them before
changing the copied code. Type and file names stay Paint by Moonlight's, so the two can be compared
(`diff -r .deps/paint-by-number/App/PaintByNumber App/Ravenna` after `tools/paintcore.sh`).

## Ravenna's seams

Every change to the copy, kept small and listed here, so the copy can follow its source and one day
go back into it (#5).

- **Identity:** the target, bundle identifier and display name (`App/Ravenna.xcodeproj`,
  `InfoPlist.xcstrings`); `Config/Info.plist`'s own file type (`com.pbordjadze.ravenna.mosaic`,
  `.ravenna`, so neither app claims the other's files); the log subsystem and queue
  labels; the gallery's title and the PDF's footer; feedback reports name the app ("Ravenna …"
  in `FeedbackCapture`), since they reach Paint by Moonlight's relay.
- **Nothing sold:** `UnlimitedPaintings.forLaunch`. Every configuration defines `UNRELEASED`:
  Ravenna is only ever a SideStore build.
- **The library:** `Resources/Samples/library.json` lists the ancient works of
  `Resources/Mosaics/catalog.json`; `Sample.url` reads their `<id>-photo.jpg`; the starters and
  the demos' pictures (`ShellDemo.fixedPictures`, `PaintDemoView`) are theirs.
- **The engine:** templates are mosaics. `Generation/MosaicMaker` (photo cut to its panel → HED
  contours from `EdgeDetector`, faces from `SubjectVision`'s Vision pass mapped by `MosaicFaces` as
  v0 did → `MosaicEngine.make` → `MosaicCore.template(of:)`) stands where `TemplateGenerator` was,
  in `ArtworkFactory` (`draft`, `made`, `source`), `CreateModel` and `Library.regenerate` (now
  `regenerate(artwork:)`, from the artwork's recipe). A library picture whose recipe matches a
  bundled mosaic (`Recipe.bundledDetail`) is laid from it. `SubjectVision` runs only face landmarks
  and animals; `EdgeDetector` only HED. `Generation/MosaicPicture` draws a mosaic in its finish
  (v0's `TileArt`, as `MosaicDrawing`), for the preview and the making-of.
- **The mosaic kept:** each artwork folder has `mosaic.json` (`ArtworkStore.File.mosaic`, written
  by `create` and `replaceContents`, read by `readMosaic`) and `meta.json` records `recipe`
  (`Artwork.recipe`, `MosaicEngine.Recipe`: pieces, eyes, mouth, ground, panel; tolerant;
  GenerationSettings stay written, unread). The finish is the app's, how every mosaic shows
  (`MosaicLook`: Glass and Stone, `TileOptions.finish`), not the recipe's. A mosaic's grout region is
  no part of `Artwork.isStarted`, `fractionComplete`, `paintedAreas` and `areaCount` while it has
  its mosaic (`Artwork.isMosaic`: `meta.json`'s `hasMosaic`, else a recipe); `loadForPainting`
  records a `mosaic.json` missing or damaged (`hasMosaic` false: the grout is painted and counts)
  and `regenerate` its return.
  `Library.loadForPainting` and `regenerate` hand it out as `PaintingDocument.mosaic` (nil when
  missing or not one tile a region plus the grout). `ArtworkDraft` carries `mosaic` and `recipe`.
- **The create flow:** `CreateModel` is Ravenna's (its recipe, drafts at `MosaicMaker.draftLongSide`
  while Pieces moves, the engine's mosaics kept per tile recipe, a panel's analysis once). The
  preview's card (`TemplatePreviewView`) is Paint by Moonlight's folded one (`foldsSettings`, as
  `UNRELEASED` builds have it; `SettingsKey.previewShowsSettings`): the title, Adjust, the summary
  and Start the Mosaic; Adjust shows Pieces and the Ground where the sliders were. The Panel (its
  sheet, `PanelFramingView`) is the enlarged preview's, a third group in its chooser, and where
  the copy offers no enlarged preview (the iPad, side by side) Adjust's, after the Ground; the
  Eyes and the Mouth take the engine's defaults, and recipes saved with others keep them (Paul,
  October 28, issue #14). Out: Suggested settings (`AutoSettings`, the chip,
  Settings › Painting Length), Settings › Preview and Line Weight, the line-art picture (`CompareView`,
  `LineArtDrawing`), Refine (`Features/Refine`, its button, tips, notes, `TemplateRefinements`,
  `refinements.json`), drafts (`Drafts`, `CreateDraft`, `DraftRow`, `DraftSaveToast`), the
  line-art inputs (`LineArtInputs`, `LineArtMapsCache`, `TextFinder`, `ObjectFinder`, `EyeFinder`,
  `SubjectImportance`) and `DemoTemplateCache`. Their settings keys are retired
  (`Preferences.retiredKeys`); `PaintDemoView`'s book demo runs HED alone.
- **The making-of:** `Features/MakingOf` is v0's show (MosaicKit's `MakingOf.Show`, its cards and
  sources from docs/making-of.md) behind Paint by Moonlight's `MakingOfView` interface and hand-off
  (`StartHandoff`), with v0's options in a menu; always on (`SettingsDefault.playsMakingOf`, its
  Settings switch gone; Skip ends it).
  The `MakingOf` package product is unlinked and `making-of.json` is gone. Its demos:
  `making-of`, `-smalti`, `-andamento`, `-dark`, `-long-text`, `-end`, `-reduce-motion`.
- **v0's mosaics and settings:** `Model/V0CarryOver` carries v0's `Own/` mosaics and `Settings/`
  progress into the library once at launch (`Library.forLaunch`), a set tile a painted region,
  v0's app-wide `ground` recorded as each one's; a read failing just now is tried again at a later
  launch, a work failing 3 launches is given up, and the starters wait for it
  (`Library.forLaunch`, made only if it leaves the library empty). v0's keys `makingOf.*` are
  v1's own; `finish`, `oneFinger`, `rowSound` and `border`, with v1's `typeface`, are retired
  (`Preferences.retiredKeys`, issue #14); `Preferences.carryV0Settings` (from
  `removeRetiredSettings`) carries `sound`, `touch` and `tune` to Sounds, Haptics and Music where
  those are unset, removes them with `lesson` and `detail` (`retiredV0Keys`; v0's first lesson is
  the tips' Tap to Set and Lay a Row), and `ground` once the carry-over is done. v0's code is in
  the history (`App/v0/`, up to 108a3c7).
- **The More menu** (v0's): The Making-of plays the show again on an open mosaic, and About This
  Work shows a library work's record (`SampleAboutView`: title, maker and year, place, medium,
  credit, license and its page at The Met, from `library.json`'s `place`, `medium` and `source`,
  which `Sample` reads tolerantly). `ArtworkPaintingView` hands them to `PaintView` as
  `PaintingWork` (`\.paintingWork`); a painting without a mosaic has no making-of.
- **The row tip sooner:** Lay a Row (`DragPaintTip`) after 3 single taps, looked at every 3
  (`PaintChromeState.dragCheckEvery`), where Paint by Moonlight waits for 15: v0's first lesson
  taught the row right after the first tile.
- **The icon:** `App/AppIcon.swift`, v0's picker as Settings › Icon (`AppIconSection`), between
  the halo (`AppIcon`) and the alternates `AppIcon-Stars`, `-Tessera` and `-Rows`
  (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`; their pictures are the catalog's `Icon-…`),
  until Paul picks one.
- **Demos:** `ShellDemo` has no Refine, draft, line-art or suggestion scenarios; `create-custom`
  moves Pieces so the engine lays a library picture, with Adjust opened (`showsPreviewSettings`;
  the other scenarios fold it). `[shots]` takes `create-custom`, `making-of`
  and `making-of-end` beside Paint by Moonlight's (ci.yml's `ALL`).
- **Left behind:** Paint by Moonlight's picture library and its line-drawing model
  (`LineArt.mlpackage`). The HED model is the same file in both apps. No test targets: Ravenna's
  checks are its package's tests on Linux, `[compile]` and `[shots]`.
- **Tiles on the canvas** (issue #13, phase 3): a painting whose session has a mosaic
  (`PaintingSession.make(template:…mosaic:)`, `TileWall`) is drawn as tiles. `TileScene` puts the
  tiles on the GPU (shape, corners, body colour per `Finish`, the painted bed); `Shaders.metal`
  draws them in the fill pass (`tessera`, the ground, `rake`) and a lift pass draws tiles still
  raised over their neighbours (`liftVertex`, `RenderContext.encode`); `CanvasUniforms.tiles`,
  `.grout` and `CanvasFrame.tiles` carry the look. `CanvasView.setTiles` sets them a row's gap
  apart; the finish is the light raking across the wall (no `Nightfall`, no sparkles). The grout is
  the ground: set before the first tile (`PaintProgress.groutSet`), never undone, not counted as
  started. One finger moves the wall, as in Paint by Moonlight, and a press then a drag lays a
  row (`TileWall.laying`, MosaicKit's `Laying`), a quick run of the tune. `TileOptions` holds
  the finish, Glass and Stone: Paul fixed the options on October 28 (issue #14), and Settings is
  Paint by Moonlight's but for Music's Sun and Moon, which read Major and Minor, the tip's row and
  Icon. A painting without a mosaic draws
  as Paint by Moonlight's. Demos: `PaintDemoView`'s scenarios are mosaics; `paint-setting` and
  `paint-mosaic-measure` (frame time and memory, `FrameMeter`) are Ravenna's.
- **Sound and haptics:** `FeedbackEngine` plays `TileSound` (v0's clinks of Paint by Moonlight's
  tune, major by Sun and minor by Moon) and `TileTouch` (v0's taps); `SoundPlayer`, `ToneSynth`,
  `PaintingMelody` and `HapticsPlayer` are gone.
- **The look** (phase 5): `Theme`'s tokens and the asset catalog's `Paper`, `Surface`, `Outline`
  and `AccentColor` are Ravenna's (apse, bench, joint, lime; lapis as `signature`; gold only where
  a tile sets), from the design page linked in `Theme`; titles and numerals in New York, as
  Paint by Moonlight's (Paul kept the system serif, October 28); `CanvasPalette`'s sheet, ink and
  backdrop; the launch screen is
  `LaunchGround`, and the app is dark only (`UIUserInterfaceStyle`).
- **A mosaic as a picture:** `MosaicCard` draws a mosaic on the CPU (its ground, the places still to
  set faint on it, the set tiles in the app's finish, through `MosaicPicture` and `MosaicDrawing`),
  in place of Paint by Moonlight's light paper: the gallery's card (`Library.thumbnailPNG`) and the
  picture shared, saved or printed (`ArtworkExporter.paintingPNG`, `CompletionShare`), the latter
  with nothing round it (v0's border, Paul's None, October 28). The time-lapse replays a mosaic
  as tiles on its bed with the canvas shaders (`TimelapseFrameRenderer`, `TimelapseSource.live`'s
  mosaic). The printable template (PDF) keeps Paint by Moonlight's page.
- **The words** (phase 5): Ravenna's vocabulary is in `Localizable.xcstrings` as English values over
  Paint by Moonlight's keys, so the sources keep its words and the catalog says Ravenna's: a
  painting is a mosaic, an area a tile, to paint is to set (a page is the mosaic; "Lay a Row",
  "Start the Mosaic", "Ready to Set"), and the app is Ravenna. Left: the samples' Paintings (the
  ancient works are paintings), colors, Nightfall and the unlock sheet (neither shows in Ravenna),
  the engine's acknowledgements, and the paints' nicknames, which are PaintCore's
  (`ColorNickname`, seeded per artwork) and wait on Paul. The feedback report's header names the
  app from `FeedbackCapture`.
