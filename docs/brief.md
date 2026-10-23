# Ravenna: the brief

Written October 23, 2026 by the session that proposed the mosaic (paint-by-number session
`session_01FVkR2j8KVZmvGcQ4pnFc1u`), for the sessions that build it.

## How it started

A study of Paint by Moonlight's Refine screen asked whether a painter could make a glass mosaic
with it. They could, but a good one took 1,464 exact gestures a program had worked out, and the
lesson was that excellence came from the design (outline rows first, rows that follow them, a
few chosen colors), which a program can do in seconds. That became a proposal for a Mosaic look:
https://claude.ai/artifact/Ufh733xVz3SdCjzB9ziisa (the study: https://claude.ai/artifact/CqrEj9WmgWEd2VvHifcqUb).

## Paul's words

> "This Mosaic proposal is incredible and I really like it. Can we keep heading down this
> path—but—this is a bold choice here, can you actually make it a separate app on SideStore
> please, for now at least?"

> "I think it shares a lot of the same mechanisms but almost should be like, a crazy hidden
> feature Easter egg deep in the bowels of the app, so I'd want to finish it first and make it
> good before even like, really telling anyone."

> "I'm imagining like—you know how we already plan to tell the users to change the time in their
> settings for more free paintings? Well what if we have… somewhere VERY hidden, another 'time
> change' setting, that takes us ALLLL the way back to some era (you said Byzantine?)"

> "Then it would be a whole new app. It would share the general structure but actually
> everything would be different—there would be a whole new design language, the 'making of'
> screen should show the process of building the mosaic with like, techniques named and credited
> to mosaic artists, the animations could be different, it might not even look like paint going
> down, maybe it would look like tiles being placed."

> "This could be so wide-ranging—it's making me so excited to think about. I want to keep working
> on and thinking about this."

> "I'm just worried about my agents, because this is so heavily agentic. I just don't want agents
> to get lost or confused or things like that."

> "I'm almost thinking of doing a re-theme of the entire lamp for the Byzantine to be Byzantine."
> (Thinking ahead, not a request yet.)

## Decided (Paul, October 23)

- A separate public repository, `pbordjadze/ravenna`, with its own sessions and CI, so agents
  working here can't reach the main app.
- GitHub Issues with a Projects board for its tasks.
- The working name Ravenna (proposed by Medea, the Moon and the Astrologer; Andamento close
  behind). Their cautions: don't lean on the bare word "Mosaic" (a famous early browser, a
  crowded name); don't spread gold over every screen, keep the dark and let gold catch the light
  where a tile is being set; nothing that is only glitter without the craft behind it.
- For now a separate SideStore app; one day an era inside Paint by Moonlight.

## Proposed, waiting on Paul

From the proposal's three decisions, each with its recommendation: light grout painted as one
area (rather than stained-glass dark lines); tile count set by Painting Length (about 600 short,
about 2,000 long); SideStore first. And: whether the eyes keep the photo's colors or are mixed
as they look (the cat's eyes came out gold; the photo's are olive-brown).

## The plan

1. **The workshop** (half a session): this repository's skeleton, a Swift package with
   `MosaicCore` on PaintCore pinned by revision and its tests on Linux, a Linux CI workflow,
   the issues for the plan, and the Projects board (Paul may need to make the board: give him
   one short step).
2. **Faces first, in the sketchbook** (1–2 sessions), the gate: noses, mouths and pets' faces
   that read, on a dozen portraits and pets. Iterate in a sketchbook page (an Artifact): Paul
   sends photos or names library pictures, the session renders mosaics and posts them, and his
   comments on the page wake the session. No builds. If faces won't come, the mosaic stays a look
   for landscapes and things, or stops; say so plainly.
3. **The engine in Swift**: the prototype ported to `MosaicCore`, deterministic (the same photo
   makes the same mosaic on any device), building the template directly, with every template
   passing PaintCore's `Template.validate`.
4. **A bare app** (about 2 sessions): photo, mosaic, tap to set tiles; its own bundle identifier,
   an unsigned IPA from CI and a SideStore source. A free Apple ID runs three sideloaded apps at
   once, SideStore included: check with Paul which apps he keeps.
5. **The Byzantine world**: its own design language, tile-setting animations and sounds, the
   making-of with techniques named and credited (researched with sources: Pliny credits Sosus of
   Pergamon with the "unswept floor"; Dioskourides of Samos signed mosaics found at Pompeii;
   most Byzantine mosaicists are anonymous).
6. **The secret door**, only when Paul says it's good: Ravenna's code moved into
   paint-by-number as a module (one app can't link the engine twice) and opened by a hidden clock
   set back to Byzantium (an idea: 547, the year San Vitale was consecrated).

## Where things are

- `prototype/`: the scripts and what they taught (`prototype/README.md`).
- In paint-by-number: `tools/models/convert_hed.py` (contour maps), the test photos
  (`Tests/Corpus/`) and their maps (`tools/baseline/lines/`), `pbn refine` (replays a design as
  edits), `ACKNOWLEDGEMENTS.md` (the models' licenses: HED and ControlNet Apache-2.0, the
  line-drawing network MIT).
- The naming round: paint-by-number's `claude/vibe-factory` branch, `factory/pieces/byzantine-name`.
