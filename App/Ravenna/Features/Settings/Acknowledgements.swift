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

/// Credits shown in Settings › Acknowledgements and repeated in `ACKNOWLEDGEMENTS.md`
/// (`AboutTests` keeps the two in step): the sample pictures (`Sample.all`, as `library.json`
/// records them), then the template engine's code, models and methods.
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
                localized: "acknowledgements.hedModel.usage", defaultValue: "Finds the outlines of a photo, for coloring books.",
                comment: "What a credited machine-learning model is used for (ControlNet's HED edge detector); shown in Settings under Acknowledgements"),
            license: .apache2),
        Acknowledgement(
            name: "Informative Drawings",
            credit: "Caroline Chan, Frédo Durand and Phillip Isola, Informative Drawings: sk_model.pth (contour style) from lllyasviel/Annotators",
            usage: String(
                localized: "acknowledgements.lineArtModel.usage", defaultValue: "Draws a photo’s lines, fur, petals and glass, for coloring books.",
                comment: "What a credited machine-learning model is used for (the Informative Drawings line-drawing generator); shown in Settings under Acknowledgements"),
            license: .mit),
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
            name: "Informative drawings",
            credit: "Caroline Chan, Frédo Durand and Phillip Isola, \"Learning to generate line drawings that convey geometry and semantics\", 2022",
            usage: String(
                localized: "acknowledgements.informativeDrawings.usage", defaultValue: "Turns a photo into a line drawing that keeps its geometry and meaning.",
                comment: "What a credited third-party method or library is used for in the template engine (Informative drawings); shown in Settings under Acknowledgements")),
        Acknowledgement(
            name: "SplitMix64",
            credit: "Guy Steele, Doug Lea and Christine Flood, \"Fast Splittable Pseudorandom Number Generators\", 2014",
            usage: String(
                localized: "acknowledgements.splitmix.usage", defaultValue: "Makes the same photo and settings always give the same template.",
                comment: "What a credited third-party method or library is used for in the template engine (SplitMix64); shown in Settings under Acknowledgements")),
    ]
}
