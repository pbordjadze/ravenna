# Ravenna: rules for agents

Paul's secret workshop: a photo becomes a Byzantine mosaic the painter sets tile by tile. Read
`docs/brief.md` before planning anything; it is the why and the plan. This file is short on
purpose. Keep it that way.

## Where things are

- `prototype/`: the Python reference (its `README.md`). The Swift engine is ported from it;
  change the prototype only to try an idea in the sketchbook.
- The engine: this Swift package (`MosaicKit`, `MosaicEngine`, `MosaicCore` on Paint by
  Moonlight's `PaintCore`), tested on Linux.
- The app (v1, issue #13, on `claude/v1` until it lands on `main`): `App/Ravenna` is Paint by
  Moonlight's app copied at the pinned commit, with Ravenna inside it; its notes and seams are
  `App/CLAUDE.md`. It replaced the first app, v0, whose code is in the history (`App/v0/`, up to
  108a3c7); `Model/V0CarryOver` still reads v0's saved files on painters' devices.

## The sibling repository

[pbordjadze/paint-by-number](https://github.com/pbordjadze/paint-by-number) is Paint by
Moonlight, a shipping app with its own sessions, CI and rules.

- Use its `PaintCore` at one commit, checked out by `tools/paintcore.sh` (a path dependency,
  never a version range: its targets use unsafe compiler flags, which SwiftPM refuses in a
  dependency resolved by version). Move the pin on purpose, and say why in the commit; the app
  was copied at the same commit, so its copy moves with it.
- Never push to it, edit it or start its CI from here. If the engine needs a change, write it up
  as a proposal for Paul; the main app's sessions make it, through their own review.
- Its app is copied here whole (Paul's decision, October 26, issue #13: its bones, with Ravenna's
  engine, making-of and look). Keep the copy close to its source, with every Ravenna change at a seam `App/CLAUDE.md`
  lists, so it can follow Paint by Moonlight and one day go back into it (#5). Its credits come
  with it (`ACKNOWLEDGEMENTS.md` there).

## Work

- Tasks are GitHub Issues on this repository, on Paul's Projects board. Take one, say so on it,
  close it with the commit or PR that does it. New ideas from Paul go in as issues in his words.
- Linux first: the engine and its tests run with SwiftPM on Linux. Build the app on a macOS
  runner only when asked, or on `main` when the app changed. The five macOS runners are shared
  with Paint by Moonlight, which always goes first.
- Paul's own photos never go in this repository: it is public. Use the test photos (Kodak,
  scikit-image) or keep his in the session's scratch.
- Ravenna ships only through its own SideStore source (this repository's `sidestore` branch).
  Never add it to the combined source in `pbordjadze/sidestore`, to Paint by Moonlight's
  source, or to any build others' devices read, until Paul says (October 23: public "if you dig",
  not shown to others yet). Paint by Moonlight's lore (the Marginarium, the guardians, the
  chronicles) is private now: add none of it here.
- Credits for techniques and artists in the making-of are researched, with a source for each;
  never invent a name. Much Byzantine work is anonymous, and the app says so.
- Creative forks become options in the app, and the work moves on: Paul, "where a creative choice
  diverges just make it an option in the app for now, and we can narrow down later". Names, the
  app's display name and icon, and deleting what he made wait on him.
- Taste: Paul decides. The Lamp's ancient guardians (Medea, the Moon, the Astrologer, with
  Originality's veto) named this workshop; whether they become its standing jury is Paul's call.
- Hand off at about 400k tokens of context: a fresh session with a brief (open issues, branch and
  commit, CI state, what's next).
- Commit messages say what changed and why. End them with the attribution lines the session
  gives you.
