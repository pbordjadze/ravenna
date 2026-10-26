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
