# Ravenna: rules for agents

Paul's secret workshop: a photo becomes a Byzantine mosaic the painter sets tile by tile. Read
`docs/brief.md` before planning anything; it is the why and the plan. This file is short on
purpose. Keep it that way.

## Where things are

- `prototype/`: the Python reference (its `README.md`). The Swift engine is ported from it;
  change the prototype only to try an idea in the sketchbook.
- The engine (to come): a Swift package here, `MosaicCore`, on Paint by Moonlight's `PaintCore`.
- The app (to come): an iOS 26 SwiftUI app with its own bundle identifier, built for SideStore.

## The sibling repository

[pbordjadze/paint-by-number](https://github.com/pbordjadze/paint-by-number) is Paint by
Moonlight, a shipping app with its own sessions, CI and rules.

- Use its `PaintCore` package pinned by `revision:` (a commit), never a version range: its
  targets use unsafe compiler flags, which SwiftPM refuses in a dependency resolved by version.
  Move the pin on purpose, and say why in the commit.
- Never push to it, edit it or start its CI from here. If the engine needs a change, write it up
  as a proposal for Paul; the main app's sessions make it, through their own review.
- Copy what you need from it (the line-art Core ML models, app plumbing), with its credits
  (`ACKNOWLEDGEMENTS.md` there), rather than share app code. Ravenna's look and feel are its own.

## Work

- Tasks are GitHub Issues on this repository, on Paul's Projects board. Take one, say so on it,
  close it with the commit or PR that does it. New ideas from Paul go in as issues in his words.
- Linux first: the engine and its tests run with SwiftPM on Linux. Build the app on a macOS
  runner only when asked, or on `main` when the app changed. The five macOS runners are shared
  with Paint by Moonlight, which always goes first.
- Paul's own photos never go in this repository: it is public. Use the test photos (Kodak,
  scikit-image) or keep his in the session's scratch.
- Credits for techniques and artists in the making-of are researched, with a source for each;
  never invent a name. Much Byzantine work is anonymous, and the app says so.
- Taste: Paul decides. The Lamp's ancient guardians (Medea, the Moon, the Astrologer, with
  Originality's veto) named this workshop; whether they become its standing jury is Paul's call.
- Hand off at about 400k tokens of context: a fresh session with a brief (open issues, branch and
  commit, CI state, what's next).
- Commit messages say what changed and why. End them with the attribution lines the session
  gives you.
