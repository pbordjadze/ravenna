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
  `.ravenna`, so neither app claims the other's files) and Alegreya; the log subsystem and queue
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
  (`MosaicLook`, v0's key `finish`), not the recipe's. A mosaic's grout region is
  no part of `Artwork.isStarted`, `fractionComplete`, `paintedAreas` and `areaCount`.
  `Library.loadForPainting` and `regenerate` hand it out as `PaintingDocument.mosaic` (nil when
  missing or not one tile a region plus the grout). `ArtworkDraft` carries `mosaic` and `recipe`.
- **The create flow:** `CreateModel` is Ravenna's (its recipe, drafts at `MosaicMaker.draftLongSide`
  while Pieces moves, the engine's mosaics kept per tile recipe, a panel's analysis once); the
  preview's card (`TemplatePreviewView`) holds Pieces, Eyes, Mouth, Ground and the Panel (its sheet,
  `PanelFramingView`) where the sliders were. Out: Suggested settings (`AutoSettings`, the chip,
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
- **v0's mosaics:** `Model/V0CarryOver` carries v0's `Own/` mosaics and `Settings/` progress into
  the library once at launch (`Library.forLaunch`), a set tile a painted region, v0's app-wide
  `ground` recorded as each one's.
- **Demos:** `ShellDemo` has no Refine, draft, line-art or suggestion scenarios; `create-custom`
  moves Pieces so the engine lays a library picture. `[shots]` takes `create-custom`, `making-of`
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
  started. A drag lays a row (`TileWall.laying`, MosaicKit's `Laying`). Options in
  `TileOptions` (finish, one finger, a row's sound), v0's keys, with `Typeface`, shown in Settings (Music's
  Sun and Moon read Major and Minor). A painting without a mosaic draws
  as Paint by Moonlight's. Demos: `PaintDemoView`'s scenarios are mosaics; `paint-setting*` and
  `paint-mosaic-measure` (frame time and memory, `FrameMeter`) are Ravenna's.
- **Sound and haptics:** `FeedbackEngine` plays `TileSound` (v0's clinks of Paint by Moonlight's
  tune, major by Sun and minor by Moon) and `TileTouch` (v0's taps); `SoundPlayer`, `ToneSynth`,
  `PaintingMelody` and `HapticsPlayer` are gone.
- **The look** (phase 5): `Theme`'s tokens and the asset catalog's `Paper`, `Surface`, `Outline`
  and `AccentColor` are Ravenna's (apse, bench, joint, lime; lapis as `signature`; gold only where
  a tile sets), from the design page linked in `Theme`; Alegreya SC in `Font.display`, the
  navigation titles and the swatch numerals (`Font.numeral`), or the system serif (`Typeface`, an
  option until Paul chooses); `CanvasPalette`'s sheet, ink and backdrop; the launch screen is
  `LaunchGround`, and the app is dark only (`UIUserInterfaceStyle`).
- **A mosaic's card:** `Library.thumbnailPNG` draws a mosaic's thumbnail with `MosaicCard` (its
  ground, the places still to set faint on it, the set tiles in the app's finish, through
  `MosaicPicture` and `MosaicDrawing`), in place of `TemplateRasterizer`'s light paper; the
  time-lapse and print keep Paint by Moonlight's paper.
- **The words** (phase 5): Ravenna's vocabulary is in `Localizable.xcstrings` as English values over
  Paint by Moonlight's keys, so the sources keep its words and the catalog says Ravenna's: a
  painting is a mosaic, an area a tile, to paint is to set (a page is the mosaic; "Lay a Row",
  "Start the Mosaic", "Ready to Set"), and the app is Ravenna. Left: the samples' Paintings (the
  ancient works are paintings), colors, Nightfall and the unlock sheet (neither shows in Ravenna),
  the engine's acknowledgements, and the paints' nicknames, which are PaintCore's
  (`ColorNickname`, seeded per artwork) and wait on Paul. The feedback report's header names the
  app from `FeedbackCapture`.
