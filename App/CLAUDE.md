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
  (`Artwork.recipe`, `MosaicEngine.Recipe`: pieces, eyes, mouth, panel; tolerant; GenerationSettings
  stay written, unread). The finish and the gold ground are the app's, how every mosaic shows
  (`MosaicLook`, v0's keys `finish` and `ground`), not the recipe's. A mosaic's grout region is
  no part of `Artwork.isStarted`, `fractionComplete`, `paintedAreas` and `areaCount`.
  `Library.loadForPainting` and `regenerate` hand it out as `PaintingDocument.mosaic` (nil when
  missing or not one tile a region plus the grout). `ArtworkDraft` carries `mosaic` and `recipe`.
- **The create flow:** `CreateModel` is Ravenna's (its recipe, drafts at `MosaicMaker.draftLongSide`
  while Pieces moves, the engine's mosaics kept per tile recipe, a panel's analysis once); the
  preview's card (`TemplatePreviewView`) holds Pieces, Eyes, Mouth and the Panel (its sheet,
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
  the library once at launch (`Library.forLaunch`), a set tile a painted region.
- **Demos:** `ShellDemo` has no Refine, draft, line-art or suggestion scenarios; `create-custom`
  moves Pieces so the engine lays a library picture.
- **Left behind:** Paint by Moonlight's picture library and its line-drawing model
  (`LineArt.mlpackage`). The HED model is the same file in both apps. No test targets: Ravenna's
  checks are its package's tests on Linux, `[compile]` and `[shots]`.
