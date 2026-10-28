import Foundation

/// A credited work used by the app.
nonisolated struct Acknowledgement: Identifiable, Hashable, Sendable {
    let name: String
    /// Who made it (and when, for papers).
    let credit: String
    /// What the app uses it for.
    let usage: String
    /// The copyright line of ported code; nil for published methods and for models whose
    /// source states none.
    var copyright: String?
    /// The license ported code or model weights are distributed under; nil for published methods.
    var license: License?

    var id: String { name }
}

/// Credits shown in Settings › Acknowledgements and repeated in `ACKNOWLEDGEMENTS.md`: the ancient
/// works (`Sample.all`, as `library.json` records them), then the code, models and methods of
/// Ravenna's engine and the PaintCore it builds on.
///
/// Ravenna's seam: no line-drawing model or method (Informative Drawings: not shipped); the HED
/// model's use is the mosaic's; scikit-image's thinning table, Zhang–Suen thinning and
/// the face landmarks added.
nonisolated enum Acknowledgements {
    /// "Katsushika Hokusai, c. 1830–32": who made a picture, and when.
    static func byline(_ provenance: Sample.Provenance) -> String {
        String(localized: "acknowledgements.picture.byline", defaultValue: "\(provenance.creator), \(provenance.year)",
               comment: "A credited picture's maker and date in Acknowledgements, as its source gives them; the arguments are the creator and the year, e.g. “Katsushika Hokusai, c. 1830–32”")
    }

    /// Swift ports of open-source libraries (`Sources/PaintCore/Vector`).
    static let code: [Acknowledgement] = [
        Acknowledgement(
            name: "Earcut",
            credit: "mapbox/earcut 3.0 by Mapbox",
            usage: String(
                localized: "acknowledgements.earcut.usage", defaultValue: "Triangulates each region’s outline into the mesh the canvas paints.",
                comment: "What a credited third-party method or library is used for in the template engine (Earcut); shown in Settings under Acknowledgements"),
            copyright: "Copyright (c) 2016, Mapbox",
            license: .isc),
        Acknowledgement(
            name: "Polylabel",
            credit: "mapbox/polylabel by Mapbox",
            usage: String(
                localized: "acknowledgements.polylabel.usage", defaultValue: "Finds the point of a region farthest from its edges, where its number is placed.",
                comment: "What a credited third-party method or library is used for in the template engine (Polylabel); shown in Settings under Acknowledgements"),
            copyright: "Copyright (c) 2016 Mapbox",
            license: .isc),
        Acknowledgement(
            name: "scikit-image skeletonize",
            credit: "scikit-image: the lookup table of _fast_skeletonize (skimage/morphology/_skeletonize.py)",
            usage: String(
                localized: "acknowledgements.skeletonize.usage", defaultValue: "Thins a photo’s outlines to the single rows its strands of tiles are laid along.",
                comment: "What a credited third-party method or library is used for in Ravenna's mosaic engine (scikit-image's thinning table); shown in Settings under Acknowledgements"),
            copyright: "Copyright (C) 2003-2009 Massachusetts Institute of Technology, 2009-2011 Broad Institute, 2003 Lee Kamentsky, 2003-2005 Peter J. Verveer",
            license: .bsd3),
    ]

    /// The footer under the open-source code credits.
    static var codeFooter: String {
        String(localized: "acknowledgements.codeFooter",
               defaultValue: "Swift ports of these libraries are part of the template engine.",
               comment: "Footer under the Open-Source Code list in Acknowledgements")
    }

    /// Machine-learning models bundled with the app (`Resources/Models`), with their weights' license.
    static let models: [Acknowledgement] = [
        Acknowledgement(
            name: "ControlNet HED",
            credit: "Lvmin Zhang (lllyasviel), ControlNet: ControlNetHED.pth from lllyasviel/Annotators",
            usage: String(
                localized: "acknowledgements.hedModel.mosaic.usage", defaultValue: "Finds the outlines of a photo, which the mosaic’s strands of tiles follow.",
                comment: "What a credited machine-learning model is used for (ControlNet's HED edge detector) in Ravenna; shown in Settings under Acknowledgements"),
            license: .apache2),
    ]

    /// The footer under the model credits.
    static var modelsFooter: String {
        String(localized: "acknowledgements.modelsFooter",
               defaultValue: "Machine-learning models that run on your device.",
               comment: "Footer under the Models list in Acknowledgements")
    }

    /// Published methods the template engine implements.
    static let methods: [Acknowledgement] = [
        Acknowledgement(
            name: "Domain transform",
            credit: "Eduardo Gastal and Manuel Oliveira, \"Domain Transform for Edge-Aware Image and Video Processing\", 2011",
            usage: String(
                localized: "acknowledgements.domainTransform.usage", defaultValue: "Smooths texture into painterly patches while keeping contours sharp.",
                comment: "What a credited third-party method or library is used for in the template engine (Domain transform); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Relative total variation",
            credit: "Li Xu, Qiong Yan, Yang Xia and Jiaya Jia, \"Structure Extraction from Texture via Relative Total Variation\", 2012",
            usage: String(
                localized: "acknowledgements.rtv.usage", defaultValue: "Tells texture from structure, so faces and edges keep their detail.",
                comment: "What a credited third-party method or library is used for in the template engine (Relative total variation); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Distance transforms",
            credit: "Pedro Felzenszwalb and Daniel Huttenlocher, \"Distance Transforms of Sampled Functions\", 2012",
            usage: String(
                localized: "acknowledgements.distanceTransforms.usage", defaultValue: "Measures how thick each region is, so every area is big enough to paint.",
                comment: "What a credited third-party method or library is used for in the template engine (Distance transforms); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "OKLab",
            credit: "Björn Ottosson, \"A perceptual color space for image processing\", 2020",
            usage: String(
                localized: "acknowledgements.oklab.usage", defaultValue: "Compares colors the way the eye does when choosing the palette.",
                comment: "What a credited third-party method or library is used for in the template engine (OKLab); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "k-means++",
            credit: "David Arthur and Sergei Vassilvitskii, \"k-means++: The Advantages of Careful Seeding\", 2007",
            usage: String(
                localized: "acknowledgements.kmeans.usage", defaultValue: "Picks well-spread starting colors for the palette.",
                comment: "What a credited third-party method or library is used for in the template engine (k-means++); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Potrace",
            credit: "Peter Selinger, \"Potrace: a polygon-based tracing algorithm\", 2003",
            usage: String(
                localized: "acknowledgements.potrace.usage", defaultValue: "Turns stair-stepped region outlines into smooth curves.",
                comment: "What a credited third-party method or library is used for in the template engine (Potrace); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Douglas-Peucker",
            credit: "David Douglas and Thomas Peucker, \"Algorithms for the reduction of the number of points required to represent a digitized line or its caricature\", 1973",
            usage: String(
                localized: "acknowledgements.douglasPeucker.usage", defaultValue: "Thins out curve points that do not change the shape.",
                comment: "What a credited third-party method or library is used for in the template engine (Douglas-Peucker); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Holistically-nested edge detection",
            credit: "Saining Xie and Zhuowen Tu, \"Holistically-Nested Edge Detection\", 2015",
            usage: String(
                localized: "acknowledgements.hed.usage", defaultValue: "Combines edges found at five scales into one map of a photo’s lines.",
                comment: "What a credited third-party method or library is used for in the template engine (Holistically-nested edge detection); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Zhang–Suen thinning",
            credit: "T. Y. Zhang and C. Y. Suen, \"A fast parallel algorithm for thinning digital patterns\", 1984",
            usage: String(
                localized: "acknowledgements.zhangSuen.usage", defaultValue: "Thins the outlines to single rows, so a strand of tiles runs along each.",
                comment: "What a credited third-party method or library is used for in Ravenna's mosaic engine (Zhang–Suen thinning); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "Face landmarks",
            credit: "Apple's Vision framework on your device; Google's MediaPipe face landmarker (Apache-2.0) for the ancient works' bundled mosaics, never shipped",
            usage: String(
                localized: "acknowledgements.faceLandmarks.usage", defaultValue: "Finds a face’s eyes, brows, nose and lips, which are set first, as pieces of their own.",
                comment: "What a credited third-party method or library is used for in Ravenna's mosaic engine (face landmarks); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "SplitMix64",
            credit: "Guy Steele, Doug Lea and Christine Flood, \"Fast Splittable Pseudorandom Number Generators\", 2014",
            usage: String(
                localized: "acknowledgements.splitmix.usage", defaultValue: "Makes the same photo and settings always give the same template.",
                comment: "What a credited third-party method or library is used for in the template engine (SplitMix64); shown in Settings under Acknowledgements")),
    ]
}
