# Acknowledgements

Ravenna builds on others' work. Everything here is credited with its source; nothing is invented.

## Pictures

The mosaics bundled in the app are made from public-domain works in The Metropolitan Museum of
Art's Open Access collection (CC0): each one's credit line, accession number and link are in the
app (`App/Ravenna/Resources/Mosaics/catalog.json`).
`sketchbook/bundle.py` refuses a work whose record isn't public domain.

- *Young Woman in Red*, 90–120 CE, Roman Egypt: https://www.metmuseum.org/art/collection/search/547860 (09.181.6).
- *Young Woman with a Gilded Wreath*, 120–140 CE, Roman Egypt: https://www.metmuseum.org/art/collection/search/547861 (09.181.7).
- *The Boy Eutyches*, 100–150 CE, Roman Egypt: https://www.metmuseum.org/art/collection/search/547951 (18.9.2).
- *A Thin-Faced, Bearded Man*, 160–180 CE, Roman Egypt: https://www.metmuseum.org/art/collection/search/547856 (09.181.1).
- *William the Hippopotamus*, ca. 1961–1878 BCE, Middle Kingdom Egypt: https://www.metmuseum.org/art/collection/search/544227 (17.9.1).
- *A Man with a Mole on His Nose*, 130–150 CE, Roman Egypt: https://www.metmuseum.org/art/collection/search/547857 (09.181.2). Checked October 23, 2026: the Met's record marks it public domain (Open Access, CC0) with no rights restriction.
- *An Elderly Lady with a Gold Wreath*, 100–125 CE, Roman Egypt: https://www.metmuseum.org/art/collection/search/547859 (09.181.5). Checked October 23, 2026: the Met's record marks it public domain (Open Access, CC0) with no rights restriction.
- *A Mother and Child in Gold Glass*, early 4th century, Roman, probably Alexandria: https://www.metmuseum.org/art/collection/search/463989 (17.190.109a). Checked October 23, 2026: the Met's record marks it public domain (Open Access, CC0) with no rights restriction.
- *The Virgin and Child, a Hodegetria Icon*, 13th century, Byzantine or Crusader, Egypt: https://www.metmuseum.org/art/collection/search/831188 (2020.401). Checked October 23, 2026: the Met's record marks it public domain (Open Access, CC0) with no rights restriction.

## Models

### ControlNet HED

Finds the outlines of a photo, which the mosaic's strands follow. Copied, with its conversion, from
Paint by Moonlight (pbordjadze/paint-by-number: `App/PaintByNumber/Resources/Models/HED.mlpackage`,
made by `tools/models/convert_hed.py` there, which records where the weights come from).

Lvmin Zhang (lllyasviel), ControlNet: ControlNetHED.pth from lllyasviel/Annotators. The method is
Saining Xie and Zhuowen Tu, "Holistically-Nested Edge Detection" (ICCV 2015).

Apache License, Version 2.0 (in full below).

## Techniques

- Thinning: T. Y. Zhang and C. Y. Suen, "A fast parallel algorithm for thinning digital patterns"
  (1984), as scikit-image's `skeletonize` runs it: the engine (`Sources/MosaicEngine/Strokes.swift`)
  uses scikit-image's lookup table of which pixels may go (`_fast_skeletonize`, in
  `skimage/morphology/_skeletonize.py`), under the BSD-3-Clause license. That file's copyright, as
  scikit-image's LICENSE.txt gives it: 2003-2009 Massachusetts Institute of Technology, 2009-2011
  Broad Institute, 2003 Lee Kamentsky, 2003-2005 Peter J. Verveer. All rights reserved. Redistribution and
  use in source and binary forms, with or without modification, are permitted provided that the
  following conditions are met: (1) Redistributions of source code must retain the above copyright
  notice, this list of conditions and the following disclaimer. (2) Redistributions in binary form
  must reproduce the above copyright notice, this list of conditions and the following disclaimer
  in the documentation and/or other materials provided with the distribution. (3) Neither the name
  of the copyright holder nor the names of its contributors may be used to endorse or promote products derived
  from this software without specific prior written permission. THIS SOFTWARE IS PROVIDED BY THE
  AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
  SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
  DAMAGE.
- Felzenszwalb and Huttenlocher, "Distance Transforms of Sampled Functions" (2012): the engine's
  exact Euclidean distance transform.

- OKLab colour space: Björn Ottosson, "A perceptual color space for image processing" (2020).
- The paints chosen by k-means++: David Arthur and Sergei Vassilvitskii, "k-means++: The
  Advantages of Careful Seeding" (2007).
- Seeded randomness, so the same photo makes the same mosaic: SplitMix64, Guy Steele, Doug Lea and
  Christine Flood, "Fast Splittable Pseudorandom Number Generators" (2014).
- Face landmarks: Apple's Vision framework on the device; on the sketchbook's bench, Google's
  MediaPipe face landmarker (Apache-2.0), which never ships in the app.

## PaintCore

The app links Paint by Moonlight's PaintCore (pbordjadze/paint-by-number, at the commit
`tools/paintcore.sh` pins), whose template engine is compiled in with it. Settings ›
Acknowledgements credits the published methods it implements as Paint by Moonlight does: the
domain transform (Eduardo Gastal and Manuel Oliveira, 2011), relative total variation (Li Xu,
Qiong Yan, Yang Xia and Jiaya Jia, 2012), Potrace (Peter Selinger, 2003) and Douglas-Peucker
(David Douglas and Thomas Peucker, 1973), beside the ones above. PaintCore's own ports of Earcut
and Polylabel are under the same ISC License as Ravenna's (below). Paint by Moonlight's
line-drawing model (Informative Drawings) and its picture library are not shipped in Ravenna.

## Type

Alegreya and Alegreya SC, designed by Juan Pablo del Peral for Huerta Tipográfica
(https://github.com/huertatipografica/Alegreya), copied from Google Fonts
(https://github.com/google/fonts, `ofl/alegreya`, `ofl/alegreyasc`) into
`App/Ravenna/Resources/Fonts`. Copyright 2011 The Alegreya Project Authors. SIL Open Font
License 1.1, in full beside the fonts (`Alegreya-OFL.txt`, the same for both families).

## Sound

Every sound in the app is synthesized by it (`Sources/MosaicKit/Hand.swift`, `Voice`): a tap of
noise and decaying sine partials at a free bar's modes, computed when first needed. No recordings
or samples are used.

The tune the tiles play, its two scales, the arpeggio for a finished paint and the finale are
Paint by Moonlight's (pbordjadze/paint-by-number at 805b7ff: `App/PaintByNumber/Feedback/
PaintingMelody.swift` and `SoundPlayer.swift`), carried over at Paul's request.

## Code

### Earcut

Triangulates each tile and the grout into the mesh a template paints
(`Sources/MosaicCore/Earcut.swift`). mapbox/earcut 3.0 by Mapbox, Copyright (c) 2016, Mapbox; ISC
License (below). Copied from Paint by Moonlight's port (pbordjadze/paint-by-number,
`Sources/PaintCore/Vector/Earcut.swift`).

### Polylabel

Finds the point of a tile, or of the grout, farthest from its edges, where its number goes
(`Sources/MosaicCore/PolyLabel.swift`). mapbox/polylabel by Mapbox, Copyright (c) 2016 Mapbox; ISC
License (below). Copied from Paint by Moonlight's port (`Sources/PaintCore/Vector/PolyLabel.swift`
there).

## Apache License, Version 2.0

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

1. Definitions.

"License" shall mean the terms and conditions for use, reproduction, and distribution as defined by Sections 1 through 9 of this document.

"Licensor" shall mean the copyright owner or entity authorized by the copyright owner that is granting the License.

"Legal Entity" shall mean the union of the acting entity and all other entities that control, are controlled by, or are under common control with that entity. For the purposes of this definition, "control" means (i) the power, direct or indirect, to cause the direction or management of such entity, whether by contract or otherwise, or (ii) ownership of fifty percent (50%) or more of the outstanding shares, or (iii) beneficial ownership of such entity.

"You" (or "Your") shall mean an individual or Legal Entity exercising permissions granted by this License.

"Source" form shall mean the preferred form for making modifications, including but not limited to software source code, documentation source, and configuration files.

"Object" form shall mean any form resulting from mechanical transformation or translation of a Source form, including but not limited to compiled object code, generated documentation, and conversions to other media types.

"Work" shall mean the work of authorship, whether in Source or Object form, made available under the License, as indicated by a copyright notice that is included in or attached to the work (an example is provided in the Appendix below).

"Derivative Works" shall mean any work, whether in Source or Object form, that is based on (or derived from) the Work and for which the editorial revisions, annotations, elaborations, or other modifications represent, as a whole, an original work of authorship. For the purposes of this License, Derivative Works shall not include works that remain separable from, or merely link (or bind by name) to the interfaces of, the Work and Derivative Works thereof.

"Contribution" shall mean any work of authorship, including the original version of the Work and any modifications or additions to that Work or Derivative Works thereof, that is intentionally submitted to Licensor for inclusion in the Work by the copyright owner or by an individual or Legal Entity authorized to submit on behalf of the copyright owner. For the purposes of this definition, "submitted" means any form of electronic, verbal, or written communication sent to the Licensor or its representatives, including but not limited to communication on electronic mailing lists, source code control systems, and issue tracking systems that are managed by, or on behalf of, the Licensor for the purpose of discussing and improving the Work, but excluding communication that is conspicuously marked or otherwise designated in writing by the copyright owner as "Not a Contribution."

"Contributor" shall mean Licensor and any individual or Legal Entity on behalf of whom a Contribution has been received by Licensor and subsequently incorporated within the Work.

2. Grant of Copyright License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare Derivative Works of, publicly display, publicly perform, sublicense, and distribute the Work and such Derivative Works in Source or Object form.

3. Grant of Patent License. Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable (except as stated in this section) patent license to make, have made, use, offer to sell, sell, import, and otherwise transfer the Work, where such license applies only to those patent claims licensable by such Contributor that are necessarily infringed by their Contribution(s) alone or by combination of their Contribution(s) with the Work to which such Contribution(s) was submitted. If You institute patent litigation against any entity (including a cross-claim or counterclaim in a lawsuit) alleging that the Work or a Contribution incorporated within the Work constitutes direct or contributory patent infringement, then any patent licenses granted to You under this License for that Work shall terminate as of the date such litigation is filed.

4. Redistribution. You may reproduce and distribute copies of the Work or Derivative Works thereof in any medium, with or without modifications, and in Source or Object form, provided that You meet the following conditions:

(a) You must give any other recipients of the Work or Derivative Works a copy of this License; and

(b) You must cause any modified files to carry prominent notices stating that You changed the files; and

(c) You must retain, in the Source form of any Derivative Works that You distribute, all copyright, patent, trademark, and attribution notices from the Source form of the Work, excluding those notices that do not pertain to any part of the Derivative Works; and

(d) If the Work includes a "NOTICE" text file as part of its distribution, then any Derivative Works that You distribute must include a readable copy of the attribution notices contained within such NOTICE file, excluding those notices that do not pertain to any part of the Derivative Works, in at least one of the following places: within a NOTICE text file distributed as part of the Derivative Works; within the Source form or documentation, if provided along with the Derivative Works; or, within a display generated by the Derivative Works, if and wherever such third-party notices normally appear. The contents of the NOTICE file are for informational purposes only and do not modify the License. You may add Your own attribution notices within Derivative Works that You distribute, alongside or as an addendum to the NOTICE text from the Work, provided that such additional attribution notices cannot be construed as modifying the License.

You may add Your own copyright statement to Your modifications and may provide additional or different license terms and conditions for use, reproduction, or distribution of Your modifications, or for any such Derivative Works as a whole, provided Your use, reproduction, and distribution of the Work otherwise complies with the conditions stated in this License.

5. Submission of Contributions. Unless You explicitly state otherwise, any Contribution intentionally submitted for inclusion in the Work by You to the Licensor shall be under the terms and conditions of this License, without any additional terms or conditions. Notwithstanding the above, nothing herein shall supersede or modify the terms of any separate license agreement you may have executed with Licensor regarding such Contributions.

6. Trademarks. This License does not grant permission to use the trade names, trademarks, service marks, or product names of the Licensor, except as required for reasonable and customary use in describing the origin of the Work and reproducing the content of the NOTICE file.

7. Disclaimer of Warranty. Unless required by applicable law or agreed to in writing, Licensor provides the Work (and each Contributor provides its Contributions) on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, including, without limitation, any warranties or conditions of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE. You are solely responsible for determining the appropriateness of using or redistributing the Work and assume any risks associated with Your exercise of permissions under this License.

8. Limitation of Liability. In no event and under no legal theory, whether in tort (including negligence), contract, or otherwise, unless required by applicable law (such as deliberate and grossly negligent acts) or agreed to in writing, shall any Contributor be liable to You for damages, including any direct, indirect, special, incidental, or consequential damages of any character arising as a result of this License or out of the use or inability to use the Work (including but not limited to damages for loss of goodwill, work stoppage, computer failure or malfunction, or any and all other commercial damages or losses), even if such Contributor has been advised of the possibility of such damages.

9. Accepting Warranty or Additional Liability. While redistributing the Work or Derivative Works thereof, You may choose to offer, and charge a fee for, acceptance of support, warranty, indemnity, or other liability obligations and/or rights consistent with this License. However, in accepting such obligations, You may act only on Your own behalf and on Your sole responsibility, not on behalf of any other Contributor, and only if You agree to indemnify, defend, and hold each Contributor harmless for any liability incurred by, or claims asserted against, such Contributor by reason of your accepting any such warranty or additional liability.

END OF TERMS AND CONDITIONS

## ISC License

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
