# The making-of

Paul: "the 'making of' screen should show the process of building the mosaic with like, techniques
named and credited to mosaic artists, the animations could be different, it might not even look like
paint going down, maybe it would look like tiles being placed."

This page has the research behind the show's cards and the storyboard. The prototype is
`prototype/making_of.py` (drawing) on `prototype/making_of_plan.py` (the plan, which `MakingOf` in
Sources/MosaicKit ports and its tests check against), and its stills and clip are on the storyboard page
(<https://claude.ai/artifact/2AWJhg62kn11pxj3hNctci>, private). Every claim here has a source that was fetched and read (October 2026).
Confidence: **H** is a primary text, museum or peer-reviewed source read directly. **M** is a
reputable secondary source. **L** is Wikipedia or a single unclear source, kept only as a pointer.
Nothing marked "not verified" may go on a card.

## The rule for credits

Never invent a name. Most mosaicists of Ravenna and Constantinople are anonymous: no source read
names a mosaicist for San Vitale, Sant'Apollinare Nuovo, the Mausoleum of Galla Placidia,
Sant'Apollinare in Classe, Hagia Sophia or the Chora. Where the honest answer is "anonymous", the
card says so. Liz James (Medieval Mosaics database, Daphni) warns that the "masters" art historians
assign to a work are speculation. Buchthal even imagined a dome master who fell from the scaffolding.
<https://medievalmosaics.com/mosaics/96> (H/M)

## Sources by stage

### 1. The drawing on the bed (cartoon, sinopia)

- **Hagia Sophia.** The bed went on in three layers. On the second, *"the mosaic painter drew with
  an indigo-blue pigment the broad outlines of his composition."* T. Whittemore, *The Mosaics of
  Haghia Sophia at Istanbul, Third Preliminary Report: Work Done in 1935–1938* (Byzantine Institute,
  1942), note 25. <https://archive.org/details/in.ernet.dli.2015.74839> (H)
- **Sant'Apollinare in Classe, Ravenna.** The 1970–76 restoration of the apse *"discovered the
  preparatory drawings of a different iconographic program from the one executed in mosaic."* The
  first idea had a cross with pairs of peacocks in place of the twelve lambs and Saint Apollinaris.
  The right half was detached and is in the Museo Nazionale, Ravenna. BYZART, University of Bologna.
  <http://hdl.handle.net/20.500.14008/26067>, <http://hdl.handle.net/20.500.14008/26115> (H)
- **Who drew it: not verified.** One article says a *pictor imaginarius* drew the design (G. Ventura
  da Silva, *Acta Scientiarum. Education*, 2016, citing Mansour 1994).
  <https://www.redalyc.org/journal/3033/303346622001/html/> (M). Not used on a card.
- "Sinopia" (red earth, named after Sinope) is what the Bologna records call Classe's drawings. The
  show draws in red by default, or in Hagia Sophia's indigo as an option (`SINOPIA=indigo`).

### 2. Outline rows (the engine's strands)

- Whittemore 1942 describes the Deesis head of Christ row by row: *"The outline of the wing is shown
  by a row of light yellow-olive curving up from the nostril"*. Elsewhere nimbi are outlined in red,
  ultramarine or green, and the Zoe panel has *"an outer line of red glass and an inner line of
  dolomite."* (H)
- **Caution.** The documented outline rows are often coloured, not dark. That outlines were *dark*
  is not verified, so the card doesn't say so. The engine's dark strands are a choice, not history.

### 3. The rows that echo them (andamento) and the *opus* names

- **Andamento** is an ordinary Italian word: *"der. di andare"*, *"il modo di andare, di muoversi"*,
  with no mosaic sense listed. Treccani. <https://www.treccani.it/vocabolario/andamento/> (H) The
  mosaic sense is on Ravenna's civic mosaic site: *"the way in which the tesserae are laced to the
  surface, one next to the other, to determine an image or effect."*
  <https://www.ravennacittadelmosaico.it/en/story/the-words-of-mosaic/> (M) When it became a mosaic
  term: not verified. The card calls it a workshop word, not an ancient one.
- **Rows that carry on a curve**, documented: *"The next line of greyish-rose tessellae continues the
  curve of the upper eyelid and ends against the wing of the nose."* (Whittemore 1942, the Deesis) (H)
- **Opus tessellatum:** *"small, regularly shaped, usually quadrangular, elements (generally 4 to 20
  millimetres wide) placed side by side in rows."* **Opus vermiculatum:** *"Type of opus tessellatum
  made of tesserae of very small dimensions (generally less than 4 mm wide)"*. An emblema is a small
  vermiculatum panel made in the workshop and set into the floor. **Opus sectile:** stone *"cut in
  regular shapes and placed side by side"*. Getty Conservation Institute and Institut National du
  Patrimoine, *Illustrated Glossary: Technician Training for the Maintenance of In Situ Mosaics*
  (2013). <https://media.getty.edu/Text/52638eec-d0f0-56f5-baa1-d6f51c31089d.pdf> (H)
- "Vermiculatum" is ancient. Pliny, *NH* 36.185, quotes Lucilius: *"arte pavimenti atque emblemate
  vermiculato"*. <https://penelope.uchicago.edu/Thayer/L/Roman/Texts/Pliny_the_Elder/36*.html> (H)
  Suetonius, *Julius* 46: Caesar carried *"tessellata et sectilia pavimenta"* on campaign.
  <https://penelope.uchicago.edu/Thayer/L/Roman/Texts/Suetonius/12Caesars/Julius*.html> (H)
- **Opus musivum** is Theophilus's own phrase (stage 4). "Opus regulatum" has no scholarly source
  (L), and neither do fan or scale backgrounds as a Byzantine practice. Neither is used.

### 4. Choosing the smalti; coloured and gold glass

- **Colour and opacity.** Clear colours come from *"iron…, cobalt…, copper… and manganese"*. The
  opacifiers are calcium antimonates, lead-antimony-tin yellow and copper, in *"technological
  continuity in a Roman tradition"*. Tin oxide appears from the 5th century. Glass was made as a
  cake, *"and then the mosaic master cuts it in tesserae pieces"*. Old tesserae were widely reused.
  Of the workshops: *"the workshops where glass tesserae were made are still unknown."* Neri,
  Morvan, Colomban, Guerra, Prigent, "Late Roman and Byzantine mosaic opaque 'glass-ceramics'
  tesserae (5th–9th century)", *Ceramics International* 42 (2016).
  <https://flore.unifi.it/bitstream/2158/1297264/1/18%201-s2.0-S0272884216315656-main.pdf> (H)
- **Gold glass:** *"a gold leaf less than 0.5 μm thick placed between two layers of glass… The bottom
  layer serves as support, and the thin top layer covers the gold leaf."* Guerra, Neri, Radtke, "Gold
  leaf tesserae: tracing the origins of gold using synchrotron-based techniques", *Eur. Phys. J.
  Plus* 138:127 (2023).
  <https://flore.unifi.it/retrieve/083b1696-9046-409a-b5ea-9e1d5c9f9389/GuerraNeriRadtke_EurPhysJPlus_2023.pdf> (H)
  "Cartellina" (the cover layer's usual Italian name) was not verified.
- **Theophilus Presbyter**, *De diversis artibus* (12th century), R. Hendrie's Latin and English
  (1847). <https://archive.org/details/theophiliquietru00theouoft> (H)
  - Book II, ch. XII gives no recipe for coloured mosaic glass. He says it is *found* *"in antiquis
    aedificiis Paganorum in musivo opere"* (in old pagan buildings, in mosaic work) and reused.
  - Book II, ch. XV, *"De vitro graeco, quod musivum opus decorat"*: clear glass is split *"calido
    ferro per quadras particulas minutas"* (with a hot iron into small squares), gold leaf is laid on
    one side, and ground glass is fused over it.
  - Don't use Hendrie's prologue line on Tuscan "mosaic work": the Latin is about enamel.
- **Pliny, NH 36.189:** mosaics *"pulsa deinde ex humo pavimenta in camaras transiere vitro"*,
  leaving the floor for the vaults, in glass, a recent invention in his day. (H)

### 5. The painted setting bed

- *"On each successive section of this third bed was painted the unfolding design of the mosaic,
  complete in every detail of form and colour, so that when all was done, had no mosaics followed,
  the result would have been a finished painting in true fresco."* Whittemore 1942, note 25. (H)
- In the John II Komnenos panel, where cubes had fallen from the emperor's face, *"the fresco
  painting on the setting-bed… together with the remaining mosaics completely preserve his
  features."* (H)
- On Roman floors, the bedding layer is *"applied in small sections… Tesserae are inserted in this
  layer before the mortar sets."* (Getty glossary) (H)

### 6. Tilting tiles to catch the light

- Gold and silver tesserae *"were also placed at slightly different angles… to optimise the effect
  produced by the high reflectance of the precious metals."* Guerra, Neri, Radtke (2023). (H)
- Hagia Sophia, the Zoe panel: the surface *"is not limited to a plane but is slightly wavy, thus
  creating subtle and varied reflections of light."* Whittemore 1942. (H)
- Church of the Nativity, Bethlehem: *"the tesserae are often tilted to catch and reflect light."*
  Liz James, Medieval Mosaics. <https://medievalmosaics.com/mosaics/112> (H/M)

### 7. Finer tesserae for faces; pieces for eyes

- Vermiculatum is tesserae under 4 mm (Getty glossary, H).
- Hagia Sophia, the Zoe panel: the tesserae of the (replaced) faces are *"relatively larger than those
  in the hands and even those in the vestments, proving that the original mosaic heads were of a
  finer workmanship."* Whittemore 1942. (H)
- The Deesis: a *"single small tessella of blackest violet"* makes a nostril, and flesh highlights are
  *"whitest marble"*. Flesh was often stone, not glass, which the material finish follows. (H)
- **Dioskourides of Samos** signed two comic-scene panels from the so-called Villa of Cicero, Pompeii,
  ΔΙΟΣΚΟΥΡΙΔΗΣ ΣΑΜΙΟΣ ΕΠΟΙΗΣΕ ("Dioskourides of Samos made it"). The musicians panel is *"Opus
  vermiculatum; 43 x 41 cm"*, the name *"written in tiny tesserae in the upper portion"*, *"End of
  second century BC"*, now in Naples (inv. 9985). Museo Galileo. <https://imss.fi.it/pompei/scienza/esc9.html> (H);
  Smith's *Dictionary* for the signature.
  <https://cts.perseids.org/read/pdlrefwk/viaf88890045/003/perseus-eng1/D.dioscurides_1> (M) Dates
  differ between sources (some say 1st century BC), so the card gives none.
- Tessera sizes for San Vitale's imperial panels, and millimetre sizes for the Deesis faces: not
  verified (tourist sites only).

## The named makers

| Name | What | Source | Sure |
| --- | --- | --- | --- |
| Sosus (at Pergamon; Pliny gives no origin) | The *asarotos oikos*, the "unswept room" floor, and the dove drinking. Pliny: *"celeberrimus fuit in hoc genere Sosus, qui Pergami stravit quem vocant asaroton oecon… parvis e tessellis tinctisque in varios colores."* No date given; Bostock's note: *"His age and country are unknown."* | Pliny, *NH* 36.184 (Bostock & Riley, Perseus: <https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=36:chapter=60>; Latin, LacusCurtius) | H |
| Gnosis | The stag hunt at Pella, a pebble mosaic, late 4th century BC: *"Gnosis epoesen" (Gnosis made this)*. Whether Gnosis set it or drew it is unknown. | BYZART, Bologna: <https://historica.unibo.it/handle/20.500.14008/19566?locale=en> | H |
| Dioskourides of Samos | Two signed vermiculatum panels, Pompeii (above). | Museo Galileo; Smith | H/M |
| Ephraim | Church of the Nativity, Bethlehem: *"This work was finished by the hand of Ephraim, historiographer and artist in mosaic"*, 1169. | Liz James, <https://medievalmosaics.com/mosaics/112> | H/M |
| Basilius | Same church: *"Basilius Pictor"*, with Syriac *"Basil the deacon depicted [this]."* | Same | H/M |

Their wages: Diocletian's Price Edict (301) gives the *musaearius* (wall mosaics) 60 denarii a day
and the *tessellarius* (floors) 50, both with maintenance. That is two agreeing secondary sources
(Ventura da Silva 2016, citing Ling and Dunbabin, and constantinethegreatcoins.com/edict), not
checked against the Latin (M). A figure painter got 150.

**Contested, never on a card as fact.** Byzantine craftsmen sent to the Umayyads (Damascus): al-Ya'qubi
and al-Tabari say so. Guerra, Neri and Radtke (2023) say *"The results obtained do not support"* it, and
Liz James disagrees too (<https://medievalmosaics.com/mosaics/84>). Córdoba's mihrab *"produced by the
craftsmen sent by Emperor Nicephorus II"* (the Mezquita's own site, M; James doesn't mention it).
Desiderius brought craftsmen from Constantinople to Monte Cassino (1066–71, after Leo of Ostia;
University of Cassino, M/H; Leo's own words not read).

## The algorithms

Paul: "maaaaybe a tiny addition as well of what algorithms we're using too still, since that remains
the case". Under each card, a line names the algorithm Ravenna uses for that step, from the engine's
own code (Sources/MosaicEngine, App/Ravenna/Contours.swift, Faces.swift, Sources/MosaicKit/Finish.swift):

| Card | Algorithm | Source | Sure |
| --- | --- | --- | --- |
| Smalti | k-means++ seeding, then Lloyd's iterations, in OKLab | D. Arthur and S. Vassilvitskii, "k-means++: The Advantages of Careful Seeding", SODA 2007, pp. 1027–1035 (<https://www.haralick.org/ML/kMeansPP-soda.pdf>); B. Ottosson, "A perceptual color space for image processing", 2020 (<https://bottosson.github.io/posts/oklab/>) | H |
| The drawing | HED edge detection, ControlNet's retraining by Lvmin Zhang (Apache-2.0) | S. Xie and Z. Tu, "Holistically-Nested Edge Detection", ICCV 2015 (<https://arxiv.org/abs/1504.06375>); the model's provenance in paint-by-number's `tools/models/convert_hed.py` | H |
| The painted bed | A Gaussian blur of the tiles' colours (sketchbook/render.py's bed; Bed.swift) | The code | H |
| Opus vermiculatum | Face landmarks: Apple's Vision (`VNDetectFaceLandmarksRequest`) on the device; Google's MediaPipe face landmarker for the bundled works (sketchbook/features.py) | The code | H |
| The outlines | Zhang–Suen thinning, as scikit-image's skeletonize runs it | T. Y. Zhang and C. Y. Suen, "A fast parallel algorithm for thinning digital patterns", CACM 27(3), 1984 (doi:10.1145/357994.358023) | H |
| Andamento | Each row a level of the Euclidean distance transform | P. Felzenszwalb and D. Huttenlocher, "Distance Transforms of Sampled Functions", Theory of Computing 8, 2012 (doi:10.4086/toc.2012.v008a019) | H |
| Set at a tilt | Each tile's tilt from SplitMix64's mixer (`TileColor.wobble`) | G. Steele, D. Lea and C. Flood, "Fast splittable pseudorandom number generators", OOPSLA 2014 (doi:10.1145/2660193.2660195) | H |

The papers' records were checked through Crossref, arXiv and the authors' pages, and each against the
code that runs it (Raster.swift's `Distance.edt`, Strokes.swift's `thin`, Cluster.swift's `KMeans`, Bed.swift).
The model and the closing cards carry no algorithm. The engine also simplifies each tile's outline with
Douglas–Peucker (Shapes.swift); no card covers that step, so none names it.

## The storyboard

Each engine stage is a scene. The show is a pure function of time (it can seek and hold still), as
in Paint by Moonlight's making-of. A tile is never painted on: it drops in from above, a little
large, its shadow under it, settles, and catches a warm light as it lands. That is the gold, and
the only gold: gold only where a tile catches the light.

| Scene | Engine stage | What is drawn | Card (title / line / credit) | s |
| --- | --- | --- | --- | --- |
| model | the picture | The photo, fading to bare lime | The model / its title / its credit | 3 |
| smalti | palette (k-means smalti) | Each paint a cake of glass, glowing orange as poured, cooling to its colour, cut into a grid of tesserae that spread apart | Smalti / glass coloured with copper, cobalt, iron, antimony and tin, poured as a cake, then cut into tesserae / anonymous glassmakers; where they worked is still unknown | 5.5 |
| sinopia | the cartoon (contour map, face features) | Lines in red earth drawn stroke by stroke on lime, the face first, the frame last | The drawing on the bed / the design is drawn first; at Classe the drawing under the apse shows a different design / Sant'Apollinare in Classe, 6th c.; anonymous | 5 |
| bed | the painted bed (`Finish.bed`) | The coloured bed spreading down over the drawing, which shows faintly through | The painted bed / "a finished painting in true fresco" / Hagia Sophia, recorded by Whittemore, 1942 | 3.5 |
| face | features, eyes, fine pitch | The features' rows, then iris and pupil as pieces, then the face's fine field | Opus vermiculatum / the face in the smallest pieces / as in the panels Dioskourides of Samos signed in tiny tesserae | 6.5 |
| outlines | strands | The strands, nearest first, tile by tile along each line | The outlines / "the outline of the wing is shown by a row" / Hagia Sophia, the Deesis; anonymous | 5 |
| andamento | echo rows and field | Ring after ring outward from the strands, quickening | Andamento / each row carries on the curve of the one before / Italian for "the way it goes", a workshop word | 9 |
| light | the material finish | A light crossing the finished mosaic; each tile flares at its own tilt, gold most, stone least | Set at a tilt / gold and glass at slightly different angles / Hagia Sophia; the Nativity, Bethlehem | 5.5 |
| hold | — | The finished mosaic | The makers / a few names survive: Sosus at Pergamon, Gnosis at Pella, Dioskourides of Samos, Ephraim at Bethlehem; most mosaicists are anonymous / Pliny, Natural History 36.184, and the works they signed | 5 |

About 48 seconds. The order follows the engine rather than one site's practice: at Hagia Sophia the
drawing was on the second bed and each section of the third was painted just before it was set.
The show compresses that into one drawing and one painted bed.

**Options** (creative forks, per Paul), in `MakingOf.Options` and the prototype's environment:
- the drawing's colour: red earth as at Ravenna, or indigo as at Hagia Sophia (`sinopia`);
- the setter's hand: shown as the shadow of a finger pressing each tile home, or not (`hand`);
- the flow: one scene a stage with a card each, or one continuous build that quickens, its cards following
  the stage being set (`flow`);
- the makers' names (`names`), below.

The drawing is the strands' and features' own tiles chained into strokes, so the app needs no contour
map to draw it: it is exactly the lines the outline rows will follow.

**In the app:** "The making-of" in a mosaic's More menu opens `App/Ravenna/MakingOfView.swift`, which
plays `MakingOf` with a Canvas (set tiles baked into one image as they settle, drawn by the look's
`Drawing`), the card under the picture, and the options in its own menu. With Reduce Motion it moves a
scene at a time.

The bundled mosaics carry each tile's stage (the engine, e77a25c), so each plays every scene; William
the hippopotamus has no face and skips that one.

**The makers' names:** Paul, October 23: "Name them!" The closing card names Sosus at Pergamon, Gnosis at
Pella, Dioskourides of Samos and Ephraim at Bethlehem, and the face's card credits the panels
Dioskourides signed. With `names` off, the closing card reads "Most mosaicists are anonymous; a few
names survive." and the face's card credits "the signed panels in tiny tesserae from Pompeii".
