import PaintCore

/// Ravenna's engine. For now only the workshop's foundation: the PaintCore it builds on.
/// The mosaic itself (strands, rows that echo them, tiles as template areas) is ported from
/// `prototype/` in plan step 3 (`docs/brief.md`).
public enum MosaicCore {
    /// The PaintCore pipeline version this engine was built against.
    public static let paintCorePipelineVersion = TemplateGenerator.pipelineVersion

    /// A one-area template over the photo, PaintCore's Refine "Blank" start: the ground a
    /// mosaic's tiles are cut from.
    public static func ground(width: Int, height: Int, photo: RGBAImage) throws -> Template {
        try TemplateEditor.blank(width: width, height: height, photo: photo, colorSpace: .displayP3)
    }
}
