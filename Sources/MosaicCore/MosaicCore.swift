import PaintCore

/// A mosaic (MosaicEngine's, or a bundled one) as a PaintCore template: each tile a numbered area,
/// the grout one more (`template(of:)`, MosaicTemplate.swift), on the PaintCore it builds on.
public enum MosaicCore {
    /// The PaintCore pipeline version this engine was built against.
    public static let paintCorePipelineVersion = TemplateGenerator.pipelineVersion

    /// A one-area template over the photo, PaintCore's Refine "Blank" start: the ground a
    /// mosaic's tiles are cut from.
    public static func ground(width: Int, height: Int, photo: RGBAImage) throws -> Template {
        try TemplateEditor.blank(width: width, height: height, photo: photo, colorSpace: .displayP3)
    }
}
