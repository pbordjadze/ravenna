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
- **Left behind:** Paint by Moonlight's picture library and its line-drawing model
  (`LineArt.mlpackage`): without it, generation falls back to classic lines until the engine is
  Ravenna's (phase 2). The HED model is the same file in both apps. No test targets: Ravenna's
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
