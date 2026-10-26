import CoreGraphics
import os
import PaintCore
import SwiftUI
import UIKit

/// A page of Refine's Tool Guide (`RefineGuideView`): the two that start it, or a tool's.
nonisolated enum RefineGuideTopic: Hashable, Identifiable {
    /// How a picture is made (ink, cells, paint) and how to move around it.
    case basics
    /// What shows beneath the lines.
    case views
    case tool(RefineTool)

    var id: Self { self }

    /// The guide's sections: Start Here, then a section per group of the Toolbox with the tools it
    /// offers, in their order on screen, so a tool the Toolbox stops offering leaves the guide too.
    static var sections: [RefineGuideSection] {
        [RefineGuideSection(group: nil, topics: [.basics, .views])]
            + RefineGroup.allCases.map { group in RefineGuideSection(group: group, topics: group.tools.map { .tool($0) }) }
    }

    /// The page the guide opens on from `tool`: its own, or The Basics.
    static func opening(at tool: RefineTool) -> RefineGuideTopic {
        sections.contains { $0.topics.contains(.tool(tool)) } ? .tool(tool) : .basics
    }

    /// The page's accessibility identifier, after `refine-guide-topic-`.
    var identifier: String {
        switch self {
        case .basics: "basics"
        case .views: "views"
        case .tool(let tool): RefineView.toolID(tool)
        }
    }
}

/// A section of the guide's list: Start Here (no group), or a group of the Toolbox.
nonisolated struct RefineGuideSection: Identifiable {
    var group: RefineGroup?
    var topics: [RefineGuideTopic]

    var id: RefineGroup? { group }
}

/// What a page's practice canvas opens with.
nonisolated struct RefinePracticeSetup: Hashable {
    var scene: RefinePractice.Scene
    /// The finger's tool.
    var tool: RefineTool
    var backdrop: RefineBackdrop = .painting
    var shape: RefineShape?
    /// The tool the page teaches when it is an action, not the finger's (Try Painting).
    var teaches: RefineTool?
}

extension RefinePracticeSetup {
    /// Where a practice canvas keeps Snap, Color from Photo and the brush's Size: its own, seeded
    /// from the painter's as the guide opens (`seedSettings`), so trying a switch on a page
    /// leaves Refine's as it was.
    @MainActor static let settings = UserDefaults(suiteName: "RefinePractice") ?? UserDefaults()

    /// The painter's Snap, Color from Photo and Size, as the practice canvases' start.
    @MainActor static func seedSettings() {
        for key in [SettingsKey.refineSnaps, SettingsKey.refinePenColors, SettingsKey.refineBrushSize] {
            settings.set(UserDefaults.standard.object(forKey: key), forKey: key)
        }
    }
}

/// A Tool Guide page's words and practice: what the tool does, how to use it, something to try on
/// the practice picture, what is good to know, and the tools that go with it. A tool's words live
/// here, in one switch, so a new tool can't reach the Toolbox without its page, and a tool that
/// changes has its page beside it to change too.
nonisolated struct RefineGuidePage {
    /// One line: under the tool's name in the guide's list, and atop its page.
    var summary: String
    var about: String
    var steps: [String]
    /// Something to do on the practice picture.
    var tryThis: String?
    var notes: [String]
    var related: [RefineTool]
    /// None where the practice picture has nothing for the tool (Writing).
    var practice: RefinePracticeSetup?

    // The practice picture: a moonlit evening with a far hill, a near hill with a tree, a cottage
    // with a four-paned window, the moon and a few stars (`RefinePractice`).
    static func of(_ topic: RefineGuideTopic) -> RefineGuidePage {
        switch topic {
        case .basics:
            RefineGuidePage(
                summary: String(localized: "refine.guide.basics.summary", defaultValue: "How a picture is made, and how to move around it.",
                                comment: "Tool Guide, The Basics: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.basics.about",
                              defaultValue: "Every picture has three layers. Ink is the lines you see. Cells are the areas the lines and edges make, each with its own number. Paint is the color of each cell. Each tool works on one layer, so drawing a line never changes a color you chose, and painting never moves a line.",
                              comment: "Tool Guide, The Basics: the paragraph that explains a picture's three layers (ink, cells, paint)"),
                steps: [
                    String(localized: "refine.guide.basics.step1", defaultValue: "Pinch with two fingers to zoom, and drag with two fingers to move around.",
                           comment: "Tool Guide, The Basics: a step of How to Use It"),
                    String(localized: "refine.guide.basics.step2", defaultValue: "Tap with two fingers to undo. Undo and Redo are at the top too.",
                           comment: "Tool Guide, The Basics: a step of How to Use It"),
                    String(localized: "refine.guide.basics.step3",
                           defaultValue: "Press and hold any cell to see its paint, and to give that cell a color of its own.",
                           comment: "Tool Guide, The Basics: a step of How to Use It (a long press opens an area's card, with Only This Area)"),
                    String(localized: "refine.guide.basics.step4",
                           defaultValue: "With an Apple Pencil, the Pencil draws and one finger moves the picture, so your hand leaves no mark. Double-tap the Pencil to switch between drawing and erasing.",
                           comment: "Tool Guide, The Basics: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.basics.try",
                                defaultValue: "Zoom in on the cottage’s window, then press and hold one of its panes.",
                                comment: "Tool Guide, The Basics: Try This, something to do on the practice picture (an evening with hills, a tree, a cottage with a four-paned window and the moon)"),
                notes: [
                    String(localized: "refine.guide.basics.note1",
                           defaultValue: "Nothing is kept until you tap Done. Cancel puts everything back as it was when Refine opened.",
                           comment: "Tool Guide, The Basics: a note under Good to Know"),
                    String(localized: "refine.guide.basics.note2",
                           defaultValue: "When a tool can’t do something, a note at the top says why, and nothing changes.",
                           comment: "Tool Guide, The Basics: a note under Good to Know"),
                ],
                related: [.pen, .select, .bucket],
                practice: RefinePracticeSetup(scene: .painted, tool: .select))
        case .views:
            RefineGuidePage(
                summary: String(localized: "refine.guide.views.summary", defaultValue: "What shows under the lines: the painting, paper or your photo.",
                                comment: "Tool Guide, Views: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.views.about",
                              defaultValue: "The views at the top of Refine choose what you see beneath the ink. They change only what you see, never the picture.",
                              comment: "Tool Guide, Views: the paragraph about the views (Painting, Paper, Photo, Photo Behind)"),
                steps: [
                    String(localized: "refine.guide.views.step1", defaultValue: "Painting shows every cell in its paint, as the picture will look finished.",
                           comment: "Tool Guide, Views: a step of How to Use It"),
                    String(localized: "refine.guide.views.step2", defaultValue: "Paper shows the lines alone, as the page looks before you paint.",
                           comment: "Tool Guide, Views: a step of How to Use It"),
                    String(localized: "refine.guide.views.step3", defaultValue: "Photo shows your photo under the lines.",
                           comment: "Tool Guide, Views: a step of How to Use It"),
                    String(localized: "refine.guide.views.step4",
                           defaultValue: "Photo Behind lays the painting over your photo. Its slider sets how much of the photo shows through, for tracing.",
                           comment: "Tool Guide, Views: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.views.try",
                                defaultValue: "In Photo Behind, slide toward the photo, then trace the peach glow above the far hills with the Pen.",
                                comment: "Tool Guide, Views: Try This, something to do on the practice picture (the glow is in the photo, not a cell of its own)"),
                notes: [
                    String(localized: "refine.guide.views.note1", defaultValue: "On iPhone, the views are in the menu at the top, which names the one showing.",
                           comment: "Tool Guide, Views: a note under Good to Know"),
                ],
                related: [.pen, .eyedropper],
                practice: RefinePracticeSetup(scene: .inked, tool: .pen, backdrop: .photoBehind))
        case .tool(let tool):
            page(of: tool)
        }
    }

    private static func page(of tool: RefineTool) -> RefineGuidePage {
        switch tool {
        case .pen:
            RefineGuidePage(
                summary: String(localized: "refine.guide.pen.summary", defaultValue: "Draws lines exactly where you draw them.",
                                comment: "Tool Guide, the Pen: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.pen.about",
                              defaultValue: "The Pen draws ink: lines that show in the finished picture. A line that closes off a shape makes a new cell with its own number. Lines leave the colors alone, unless Color from Photo is on.",
                              comment: "Tool Guide, the Pen: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.pen.step1", defaultValue: "Draw with a finger or the Pencil.",
                           comment: "Tool Guide, the Pen: a step of How to Use It"),
                    String(localized: "refine.guide.pen.step2",
                           defaultValue: "End a line on another line to close a shape. With Snap on, an end that touches a line joins it.",
                           comment: "Tool Guide, the Pen: a step of How to Use It"),
                    String(localized: "refine.guide.pen.step3",
                           defaultValue: "Turn on Color from Photo to give each new cell the photo’s color there.",
                           comment: "Tool Guide, the Pen: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.pen.try",
                                defaultValue: "Draw a cloud in the sky, ending where you began. Then turn on Color from Photo and draw a line across the moon.",
                                comment: "Tool Guide, the Pen: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.pen.note1",
                           defaultValue: "A line that doubles back on itself can’t be drawn; a note says so.",
                           comment: "Tool Guide, the Pen: a note under Good to Know"),
                    String(localized: "refine.guide.pen.note2",
                           defaultValue: "A shape too small for a number stays a line, and doesn’t become a cell.",
                           comment: "Tool Guide, the Pen: a note under Good to Know"),
                ],
                related: [.shape, .eraser, .bendLine, .cellEdge],
                practice: RefinePracticeSetup(scene: .inked, tool: .pen))
        case .shape:
            RefineGuidePage(
                summary: String(localized: "refine.guide.shape.summary", defaultValue: "Draws straight lines, rectangles, ovals, curves, hexagons and stars.",
                                comment: "Tool Guide, Shapes: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.shape.about",
                              defaultValue: "Shapes draws a clean figure across a drag. Like the Pen, it draws ink, and a closed figure becomes a cell of its own.",
                              comment: "Tool Guide, Shapes: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.shape.step1", defaultValue: "Pick a figure above the tools.",
                           comment: "Tool Guide, Shapes: a step of How to Use It"),
                    String(localized: "refine.guide.shape.step2",
                           defaultValue: "Drag from one corner to the opposite one, or from one end of a line to the other.",
                           comment: "Tool Guide, Shapes: a step of How to Use It"),
                    String(localized: "refine.guide.shape.step3",
                           defaultValue: "For a curve, drag its ends first, then drag again to bend it. A tap leaves it straight.",
                           comment: "Tool Guide, Shapes: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.shape.try",
                                defaultValue: "Draw a star in the sky. Then pick the curve and give the cottage a path to its door.",
                                comment: "Tool Guide, Shapes: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.shape.note1",
                           defaultValue: "The figure shows as it will be while your finger is down, so you can adjust it before you let go.",
                           comment: "Tool Guide, Shapes: a note under Good to Know"),
                    String(localized: "refine.guide.shape.note2", defaultValue: "With Snap on, a line’s ends join the lines they touch.",
                           comment: "Tool Guide, Shapes: a note under Good to Know"),
                ],
                related: [.pen, .fill, .eraser],
                practice: RefinePracticeSetup(scene: .inked, tool: .shape, shape: .star))
        case .eraser:
            RefineGuidePage(
                summary: String(localized: "refine.guide.eraser.summary", defaultValue: "Rubs out the ink it touches.",
                                comment: "Tool Guide, the Eraser: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.eraser.about",
                              defaultValue: "The Eraser takes out the ink along your stroke, cut cleanly where it stops. Where it breaks a line between two cells, they become one, in the paint of the larger.",
                              comment: "Tool Guide, the Eraser: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.eraser.step1", defaultValue: "Rub over the lines you want gone.",
                           comment: "Tool Guide, the Eraser: a step of How to Use It"),
                    String(localized: "refine.guide.eraser.step2", defaultValue: "Tap to take out a small dab.",
                           comment: "Tool Guide, the Eraser: a step of How to Use It"),
                    String(localized: "refine.guide.eraser.step3", defaultValue: "Zoom in to erase finer: the Eraser keeps its size on the screen.",
                           comment: "Tool Guide, the Eraser: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.eraser.try",
                                defaultValue: "Rub out the cross in the cottage’s window, so its four panes become one.",
                                comment: "Tool Guide, the Eraser: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.eraser.note1",
                           defaultValue: "The Eraser takes ink only. To take away a dashed edge between cells, use Merge.",
                           comment: "Tool Guide, the Eraser: a note under Good to Know"),
                    String(localized: "refine.guide.eraser.note2", defaultValue: "Double-tap the Apple Pencil to switch between the Pen and the Eraser.",
                           comment: "Tool Guide, the Eraser: a note under Good to Know"),
                ],
                related: [.smartEraser, .merge, .pen],
                practice: RefinePracticeSetup(scene: .painted, tool: .eraser))
        case .smartEraser:
            RefineGuidePage(
                summary: String(localized: "refine.guide.smartEraser.summary", defaultValue: "Takes out a whole line with one tap.",
                                comment: "Tool Guide, the Line Eraser: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.smartEraser.about",
                              defaultValue: "Tap a line and the Line Eraser takes it out from one junction to the next, the stretch between the lines it meets. Drag it to rub out what you touch, as the Eraser does.",
                              comment: "Tool Guide, the Line Eraser: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.smartEraser.step1", defaultValue: "Tap a line to take it out, junction to junction.",
                           comment: "Tool Guide, the Line Eraser: a step of How to Use It"),
                    String(localized: "refine.guide.smartEraser.step2", defaultValue: "Drag to rub out what you touch.",
                           comment: "Tool Guide, the Line Eraser: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.smartEraser.try", defaultValue: "Tap the line around the moon, then the cottage’s door.",
                                comment: "Tool Guide, the Line Eraser: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.smartEraser.note1",
                           defaultValue: "The stretch flashes as it goes, so you can see what the tap took.",
                           comment: "Tool Guide, the Line Eraser: a note under Good to Know"),
                    String(localized: "refine.guide.smartEraser.note2", defaultValue: "The cells the line kept apart become one.",
                           comment: "Tool Guide, the Line Eraser: a note under Good to Know"),
                ],
                related: [.eraser, .bendLine, .merge],
                practice: RefinePracticeSetup(scene: .painted, tool: .smartEraser))
        case .bendLine:
            RefineGuidePage(
                summary: String(localized: "refine.guide.bendLine.summary", defaultValue: "Drag a line to reshape it.",
                                comment: "Tool Guide, Bend Line: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.bendLine.about",
                              defaultValue: "Grab a line and drag. The spot you grabbed goes where your finger goes, and the line bends smoothly around it, less the farther along. Its ends stay where they meet other lines, and the cells on either side keep their paint and follow the new shape.",
                              comment: "Tool Guide, Bend Line: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.bendLine.step1", defaultValue: "Put your finger on a line and drag.",
                           comment: "Tool Guide, Bend Line: a step of How to Use It"),
                    String(localized: "refine.guide.bendLine.step2", defaultValue: "The line shows where it will lie. Lift your finger to keep it.",
                           comment: "Tool Guide, Bend Line: a step of How to Use It"),
                    String(localized: "refine.guide.bendLine.step3", defaultValue: "Drag again to keep shaping.",
                           comment: "Tool Guide, Bend Line: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.bendLine.try", defaultValue: "Pull the far hills’ line up into a mountain.",
                                comment: "Tool Guide, Bend Line: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.bendLine.note1",
                           defaultValue: "A line can’t bend across another line, off the picture, or so far that a cell has no room for its number; a note says so. Try a shorter drag.",
                           comment: "Tool Guide, Bend Line: a note under Good to Know"),
                    String(localized: "refine.guide.bendLine.note2",
                           defaultValue: "Bend Line moves ink. To move a dashed edge between cells, use Move Edge.",
                           comment: "Tool Guide, Bend Line: a note under Good to Know"),
                ],
                related: [.moveEdge, .pen, .smartEraser],
                practice: RefinePracticeSetup(scene: .painted, tool: .bendLine))
        case .select:
            RefineGuidePage(
                summary: String(localized: "refine.guide.select.summary", defaultValue: "Shows a cell: its paint and how much of the picture it covers.",
                                comment: "Tool Guide, Select: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.select.about",
                              defaultValue: "Tap a cell to select it. It glows, and the bar below shows its paint, how many cells use that paint and its share of the picture. Change Color there gives it a new color.",
                              comment: "Tool Guide, Select: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.select.step1", defaultValue: "Tap a cell to select it.",
                           comment: "Tool Guide, Select: a step of How to Use It"),
                    String(localized: "refine.guide.select.step2", defaultValue: "Tap it again to let it go.",
                           comment: "Tool Guide, Select: a step of How to Use It"),
                    String(localized: "refine.guide.select.step3", defaultValue: "Tap Change Color to give it a color of its own.",
                           comment: "Tool Guide, Select: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.select.try", defaultValue: "Select the sky, then the moon, and compare how much of the picture each covers.",
                                comment: "Tool Guide, Select: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.select.note1",
                           defaultValue: "While a Cells tool is picked, dashed lines show the edges between cells that have no ink. They divide the paint, but won’t be drawn.",
                           comment: "Tool Guide, Select: a note under Good to Know"),
                    String(localized: "refine.guide.select.note2", defaultValue: "With any tool, press and hold a cell to open its card.",
                           comment: "Tool Guide, Select: a note under Good to Know"),
                ],
                related: [.cellEdge, .merge, .bucket],
                practice: RefinePracticeSetup(scene: .painted, tool: .select))
        case .cellEdge:
            RefineGuidePage(
                summary: String(localized: "refine.guide.cellEdge.summary", defaultValue: "Divides a cell without drawing a line.",
                                comment: "Tool Guide, Cell Edge: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.cellEdge.about",
                              defaultValue: "Draw across a cell to divide it in two. The new edge has no ink, so it won’t show as a line in the finished picture, and both cells keep their paint. Each is a cell of its own, which you can give another paint.",
                              comment: "Tool Guide, Cell Edge: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.cellEdge.step1",
                           defaultValue: "Draw across a cell from one of its edges to another, or draw a loop inside it.",
                           comment: "Tool Guide, Cell Edge: a step of How to Use It"),
                    String(localized: "refine.guide.cellEdge.step2",
                           defaultValue: "Give one side a new paint with the Bucket or the Paint Brush.",
                           comment: "Tool Guide, Cell Edge: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.cellEdge.try",
                                defaultValue: "Draw an edge across the near hill. Its two halves keep one paint, each with a number of its own.",
                                comment: "Tool Guide, Cell Edge: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.cellEdge.note1", defaultValue: "Edges without ink show dashed while a Cells tool is picked.",
                           comment: "Tool Guide, Cell Edge: a note under Good to Know"),
                    String(localized: "refine.guide.cellEdge.note2", defaultValue: "To take an edge away again, Merge across it.",
                           comment: "Tool Guide, Cell Edge: a note under Good to Know"),
                ],
                related: [.merge, .bucket, .pen],
                practice: RefinePracticeSetup(scene: .painted, tool: .cellEdge))
        case .merge:
            RefineGuidePage(
                summary: String(localized: "refine.guide.merge.summary", defaultValue: "Joins the cells you drag across into one.",
                                comment: "Tool Guide, Merge: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.merge.about",
                              defaultValue: "Drag across neighbouring cells to make them one. The cell you start in keeps its paint and number, and the lines and edges between them go.",
                              comment: "Tool Guide, Merge: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.merge.step1", defaultValue: "Start in the cell whose paint you want to keep.",
                           comment: "Tool Guide, Merge: a step of How to Use It"),
                    String(localized: "refine.guide.merge.step2", defaultValue: "Drag across the cells beside it that should join it.",
                           comment: "Tool Guide, Merge: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.merge.try", defaultValue: "Drag across the window’s four panes to make one big pane.",
                                comment: "Tool Guide, Merge: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.merge.note1", defaultValue: "Merge takes away ink between the cells as well as dashed edges.",
                           comment: "Tool Guide, Merge: a note under Good to Know"),
                    String(localized: "refine.guide.merge.note2", defaultValue: "A paint left with no cells leaves the palette.",
                           comment: "Tool Guide, Merge: a note under Good to Know"),
                ],
                related: [.cellEdge, .eraser, .select],
                practice: RefinePracticeSetup(scene: .painted, tool: .merge))
        case .moveEdge:
            RefineGuidePage(
                summary: String(localized: "refine.guide.moveEdge.summary", defaultValue: "Drag the border between two cells to change their shapes.",
                                comment: "Tool Guide, Move Edge: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.moveEdge.about",
                              defaultValue: "Grab the border between two cells, inked or dashed, and drag it. One cell grows as the other shrinks, and both keep their paint.",
                              comment: "Tool Guide, Move Edge: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.moveEdge.step1", defaultValue: "Put your finger on the border between two cells and drag.",
                           comment: "Tool Guide, Move Edge: a step of How to Use It"),
                    String(localized: "refine.guide.moveEdge.step2", defaultValue: "Lift your finger where the border should be.",
                           comment: "Tool Guide, Move Edge: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.moveEdge.try", defaultValue: "Drag the border between the two hills down a little, between the tree and the cottage, so the far hills grow taller.",
                                comment: "Tool Guide, Move Edge: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.moveEdge.note1",
                           defaultValue: "As with Bend Line, a border can’t cross another or leave a cell without room for its number.",
                           comment: "Tool Guide, Move Edge: a note under Good to Know"),
                    String(localized: "refine.guide.moveEdge.note2",
                           defaultValue: "Move Edge grabs the borders between cells. Bend Line grabs any line you drew.",
                           comment: "Tool Guide, Move Edge: a note under Good to Know"),
                ],
                related: [.bendLine, .cellEdge],
                practice: RefinePracticeSetup(scene: .painted, tool: .moveEdge))
        case .fill:
            RefineGuidePage(
                summary: String(localized: "refine.guide.fill.summary", defaultValue: "Makes a closed shape a cell of its own, in the photo’s color.",
                                comment: "Tool Guide, Fill Shape: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.fill.about",
                              defaultValue: "Tap inside a shape outlined in ink and it becomes a cell of its own, painted the photo’s color where you tapped. Even a tiny shape keeps its number, smaller and read zoomed in.",
                              comment: "Tool Guide, Fill Shape: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.fill.step1", defaultValue: "Tap inside a closed shape.",
                           comment: "Tool Guide, Fill Shape: a step of How to Use It"),
                    String(localized: "refine.guide.fill.step2", defaultValue: "Tap a filled shape again to take the fill out.",
                           comment: "Tool Guide, Fill Shape: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.fill.try", defaultValue: "Tap inside the moon, then the roof and the door.",
                                comment: "Tool Guide, Fill Shape: Try This, something to do on the practice picture (its shapes are outlined in ink, in the paint around them)"),
                notes: [
                    String(localized: "refine.guide.fill.note1",
                           defaultValue: "A shape that isn’t closed fills the area around it. Undo takes it back.",
                           comment: "Tool Guide, Fill Shape: a note under Good to Know"),
                    String(localized: "refine.guide.fill.note2",
                           defaultValue: "Fill Shape takes the photo’s colors. To pour a paint you chose, use the Bucket.",
                           comment: "Tool Guide, Fill Shape: a note under Good to Know"),
                ],
                related: [.bucket, .shape, .pen],
                practice: RefinePracticeSetup(scene: .inked, tool: .fill))
        case .bucket:
            RefineGuidePage(
                summary: String(localized: "refine.guide.bucket.summary", defaultValue: "Pours the current paint into a cell.",
                                comment: "Tool Guide, the Bucket: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.bucket.about",
                              defaultValue: "Tap a cell to give it the current paint, the one marked in the palette. Only that cell changes: the other cells of its old paint keep theirs.",
                              comment: "Tool Guide, the Bucket: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.bucket.step1",
                           defaultValue: "Pick a paint in the palette, or tap the color wheel at its end to choose any color.",
                           comment: "Tool Guide, the Bucket: a step of How to Use It (the palette ends with a system color picker, New Paint)"),
                    String(localized: "refine.guide.bucket.step2", defaultValue: "Tap a cell to pour it in.",
                           comment: "Tool Guide, the Bucket: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.bucket.try",
                                defaultValue: "Choose a brick red from the color wheel and pour it into the cottage’s roof. Then pick the sky’s paint and pour it into the far hills.",
                                comment: "Tool Guide, the Bucket: Try This, something to do on the practice picture (on it the roof and the moon are outlined only, in the paint around them)"),
                notes: [
                    String(localized: "refine.guide.bucket.note1",
                           defaultValue: "A color the picture doesn’t have becomes a paint of its own the first time you pour it.",
                           comment: "Tool Guide, the Bucket: a note under Good to Know"),
                    String(localized: "refine.guide.bucket.note2",
                           defaultValue: "Two cells of one paint with no ink between them become one cell.",
                           comment: "Tool Guide, the Bucket: a note under Good to Know"),
                ],
                related: [.brush, .eyedropper, .editPaint],
                practice: RefinePracticeSetup(scene: .inked, tool: .bucket))
        case .brush:
            RefineGuidePage(
                summary: String(localized: "refine.guide.brush.summary", defaultValue: "Paints a stroke in the current paint.",
                                comment: "Tool Guide, the Paint Brush: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.brush.about",
                              defaultValue: "Brush across the picture and the stroke takes the current paint, shaping cells as it goes: it joins the cells of that paint it touches, and makes a cell of its own across the others.",
                              comment: "Tool Guide, the Paint Brush: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.brush.step1", defaultValue: "Pick a paint in the palette.",
                           comment: "Tool Guide, the Paint Brush: a step of How to Use It"),
                    String(localized: "refine.guide.brush.step2", defaultValue: "Brush across the picture, or tap for a dab.",
                           comment: "Tool Guide, the Paint Brush: a step of How to Use It"),
                    String(localized: "refine.guide.brush.step3", defaultValue: "Set Size for a wider or finer brush, and zoom in for detail.",
                           comment: "Tool Guide, the Paint Brush: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.brush.try",
                                defaultValue: "Pick the cottage’s cream and paint a winding path across the near hill.",
                                comment: "Tool Guide, the Paint Brush: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.brush.note1", defaultValue: "The ink always stays on top: the brush paints under the lines.",
                           comment: "Tool Guide, the Paint Brush: a note under Good to Know"),
                    String(localized: "refine.guide.brush.note2", defaultValue: "Size is measured on the screen, so a zoomed-in brush paints finer.",
                           comment: "Tool Guide, the Paint Brush: a note under Good to Know"),
                ],
                related: [.bucket, .eyedropper, .cellEdge],
                practice: RefinePracticeSetup(scene: .painted, tool: .brush))
        case .eyedropper:
            RefineGuidePage(
                summary: String(localized: "refine.guide.eyedropper.summary", defaultValue: "Picks up a paint from the picture.",
                                comment: "Tool Guide, the Eyedropper: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.eyedropper.about",
                              defaultValue: "Tap a cell and its paint becomes the current paint. With the Photo view, it picks the photo’s color where you tap instead, or the paint that matches it.",
                              comment: "Tool Guide, the Eyedropper: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.eyedropper.step1", defaultValue: "Tap a cell to pick up its paint.",
                           comment: "Tool Guide, the Eyedropper: a step of How to Use It"),
                    String(localized: "refine.guide.eyedropper.step2", defaultValue: "Switch to Photo and tap to pick a color from the photo.",
                           comment: "Tool Guide, the Eyedropper: a step of How to Use It"),
                    String(localized: "refine.guide.eyedropper.step3", defaultValue: "Then pour it with the Bucket or brush it with the Paint Brush.",
                           comment: "Tool Guide, the Eyedropper: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.eyedropper.try",
                                defaultValue: "Pick up the window’s yellow. Then switch to Photo and pick the peach glow above the hills.",
                                comment: "Tool Guide, the Eyedropper: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.eyedropper.note1", defaultValue: "The palette marks the current paint.",
                           comment: "Tool Guide, the Eyedropper: a note under Good to Know"),
                ],
                related: [.bucket, .brush, .editPaint],
                practice: RefinePracticeSetup(scene: .painted, tool: .eyedropper))
        case .editPaint:
            RefineGuidePage(
                summary: String(localized: "refine.guide.editPaint.summary", defaultValue: "Changes a paint’s color everywhere it’s used.",
                                comment: "Tool Guide, Edit Paint: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.editPaint.about",
                              defaultValue: "Pick a paint by tapping a cell or its swatch, and give it a new color: every cell of that paint changes together. Drag one swatch onto another to make the two one paint.",
                              comment: "Tool Guide, Edit Paint: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.editPaint.step1", defaultValue: "Tap a cell or a swatch to pick its paint. Its cells glow.",
                           comment: "Tool Guide, Edit Paint: a step of How to Use It"),
                    String(localized: "refine.guide.editPaint.step2", defaultValue: "Choose its new color with Color.",
                           comment: "Tool Guide, Edit Paint: a step of How to Use It (Color is the panel's color picker)"),
                    String(localized: "refine.guide.editPaint.step3",
                           defaultValue: "Turn on Similar colors too to move the paints near it along with it.",
                           comment: "Tool Guide, Edit Paint: a step of How to Use It (Similar colors too is the panel's switch, in sentence case)"),
                    String(localized: "refine.guide.editPaint.step4", defaultValue: "Drag a swatch onto another to merge the two paints.",
                           comment: "Tool Guide, Edit Paint: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.editPaint.try",
                                defaultValue: "Make the near hill an autumn orange. Then drag the window’s swatch onto the moon’s.",
                                comment: "Tool Guide, Edit Paint: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.editPaint.note1",
                           defaultValue: "To change one cell alone, pour it with the Bucket, or press and hold it and choose Only This Area.",
                           comment: "Tool Guide, Edit Paint: a note under Good to Know"),
                ],
                related: [.looks, .bucket, .eyedropper],
                practice: RefinePracticeSetup(scene: .painted, tool: .editPaint))
        case .looks:
            RefineGuidePage(
                summary: String(localized: "refine.guide.looks.summary", defaultValue: "Recolors the whole picture in a mood.",
                                comment: "Tool Guide, Looks: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.looks.about",
                              defaultValue: "A look moves every paint together, toward a time of day or a painter’s colors, keeping the picture’s lights and darks. Photo goes back to the photo’s own colors.",
                              comment: "Tool Guide, Looks: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.looks.step1", defaultValue: "Tap a look.", comment: "Tool Guide, Looks: a step of How to Use It"),
                    String(localized: "refine.guide.looks.step2", defaultValue: "Slide Strength to set how far it goes.",
                           comment: "Tool Guide, Looks: a step of How to Use It"),
                    String(localized: "refine.guide.looks.step3", defaultValue: "Tap Photo to go back to the photo’s colors.",
                           comment: "Tool Guide, Looks: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.looks.try", defaultValue: "Try each look on the evening, then turn its Strength down halfway.",
                                comment: "Tool Guide, Looks: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.looks.note1", defaultValue: "One look at a time: a new look takes the place of the last.",
                           comment: "Tool Guide, Looks: a note under Good to Know"),
                    String(localized: "refine.guide.looks.note2", defaultValue: "Paints a look makes alike become one paint, and a note says so.",
                           comment: "Tool Guide, Looks: a note under Good to Know"),
                ],
                related: [.editPaint, .bucket],
                practice: RefinePracticeSetup(scene: .painted, tool: .looks))
        case .moveNumber:
            RefineGuidePage(
                summary: String(localized: "refine.guide.moveNumber.summary", defaultValue: "Moves a number to a better spot in its cell.",
                                comment: "Tool Guide, Move Number: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.moveNumber.about",
                              defaultValue: "While Move Number is picked, every cell shows its number. Drag one anywhere in its own cell where it fits, and it’s sized for the room there.",
                              comment: "Tool Guide, Move Number: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.moveNumber.step1", defaultValue: "Put your finger on a number and drag it.",
                           comment: "Tool Guide, Move Number: a step of How to Use It"),
                    String(localized: "refine.guide.moveNumber.step2", defaultValue: "Lift your finger where it should sit.",
                           comment: "Tool Guide, Move Number: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.moveNumber.try", defaultValue: "Move the sky’s number up beside the moon.",
                                comment: "Tool Guide, Move Number: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.moveNumber.note1",
                           defaultValue: "A number stays in its own cell, off the lines and clear of the cell’s other numbers.",
                           comment: "Tool Guide, Move Number: a note under Good to Know"),
                    String(localized: "refine.guide.moveNumber.note2",
                           defaultValue: "In a tight spot it gets smaller, but never smaller than a painter can read.",
                           comment: "Tool Guide, Move Number: a note under Good to Know"),
                ],
                related: [.select, .cellEdge],
                practice: RefinePracticeSetup(scene: .painted, tool: .moveNumber))
        case .text:
            RefineGuidePage(
                summary: String(localized: "refine.guide.text.summary", defaultValue: "Keeps the words in your photo readable.",
                                comment: "Tool Guide, Writing: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.text.about",
                              defaultValue: "When your photo has writing in it, the app finds it and draws its letters so they can be read. Writing shows the lines of words it found: tap one to turn it off or on, or drag across words it missed.",
                              comment: "Tool Guide, Writing: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.text.step1", defaultValue: "Tap a line of words to turn it off or on.",
                           comment: "Tool Guide, Writing: a step of How to Use It"),
                    String(localized: "refine.guide.text.step2", defaultValue: "Drag across a line of words the app missed.",
                           comment: "Tool Guide, Writing: a step of How to Use It"),
                ],
                tryThis: nil,
                notes: [
                    String(localized: "refine.guide.text.note1",
                           defaultValue: "Writing changes how the picture is made, so it’s made again, with your other changes laid on it.",
                           comment: "Tool Guide, Writing: a note under Good to Know"),
                    String(localized: "refine.guide.text.note2",
                           defaultValue: "There’s nothing to practice on here: the practice picture has no writing. Try it on a photo with a sign or a label.",
                           comment: "Tool Guide, Writing: a note under Good to Know, where other pages have a practice picture"),
                ],
                related: [.tryPainting],
                practice: nil)
        case .tryPainting:
            RefineGuidePage(
                summary: String(localized: "refine.guide.tryPainting.summary", defaultValue: "Paints the picture as it is now, to see how it feels.",
                                comment: "Tool Guide, Try Painting: one line under its name in the guide's list and atop its page"),
                about: String(localized: "refine.guide.tryPainting.about",
                              defaultValue: "Try Painting opens the painting screen on the picture with your changes, so you can check that its cells are pleasant to paint and its numbers easy to find. Nothing you paint there is kept.",
                              comment: "Tool Guide, Try Painting: the paragraph about what it does"),
                steps: [
                    String(localized: "refine.guide.tryPainting.step1", defaultValue: "Make a change, then tap Try Painting.",
                           comment: "Tool Guide, Try Painting: a step of How to Use It"),
                    String(localized: "refine.guide.tryPainting.step2", defaultValue: "Paint a few cells.",
                           comment: "Tool Guide, Try Painting: a step of How to Use It"),
                    String(localized: "refine.guide.tryPainting.step3", defaultValue: "Close it to come back to Refine.",
                           comment: "Tool Guide, Try Painting: a step of How to Use It"),
                ],
                tryThis: String(localized: "refine.guide.tryPainting.try",
                                defaultValue: "Draw a line across the sky with the Pen, then tap Try Painting and paint both halves.",
                                comment: "Tool Guide, Try Painting: Try This, something to do on the practice picture"),
                notes: [
                    String(localized: "refine.guide.tryPainting.note1",
                           defaultValue: "Your painting starts fresh once you tap Done in Refine and start painting it.",
                           comment: "Tool Guide, Try Painting: a note under Good to Know"),
                ],
                related: [.pen, .moveNumber],
                practice: RefinePracticeSetup(scene: .inked, tool: .pen, teaches: .tryPainting))
        }
    }
}

/// The Tool Guide's practice picture (PaintCore's `RefinePractice`): its photo and the template
/// of each scene, made off the main actor the first time a guide opens and kept for the launch.
nonisolated struct RefinePracticePicture: Sendable {
    let photo: RGBAImage
    let preview: CGImage
    let painted: Template
    let inked: Template

    func template(_ scene: RefinePractice.Scene) -> Template {
        switch scene {
        case .painted: painted
        case .inked: inked
        }
    }

    @concurrent
    static func make() async throws -> RefinePracticePicture {
        let photo = RefinePractice.photo()
        guard let preview = PhotoLoader.cgImage(from: photo) else { throw CreateModel.CreateError.renderFailed }
        return RefinePracticePicture(
            photo: photo, preview: preview, painted: try RefinePractice.template(.painted, photo: photo),
            inked: try RefinePractice.template(.inked, photo: photo))
    }

    /// The picture, made once a launch.
    @MainActor static func shared() async throws -> RefinePracticePicture {
        if let made { return made }
        let picture = try await make()
        made = picture
        return picture
    }

    @MainActor private static var made: RefinePracticePicture?
}

/// Refine's Tool Guide (Paul, October 21: "each tool with a scenario that you can play with and
/// reset easily to get a hang for what that tool does, and a nice description"): a page per tool
/// of the Toolbox, in its groups, after The Basics and Views. A page says what the tool does, how to
/// use it, something to try and what is good to know (`RefineGuidePage`), beside a practice canvas
/// (`RefineView`'s practice mode): the real tool, alone, over a practice picture made for it
/// (`RefinePracticePicture`), with Undo, Redo, the views and Reset. Opened from Refine's toolbar
/// on the tool in hand. A sidebar of the pages on iPad, a list that pushes them on iPhone.
struct RefineGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var topic: RefineGuideTopic?
    @State private var column = NavigationSplitViewColumn.detail
    @State private var picture: RefinePracticePicture?
    @State private var failed = false

    init(opening: RefineGuideTopic) {
        _topic = State(initialValue: opening)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            List(selection: $topic) {
                ForEach(RefineGuideTopic.sections) { section in
                    Section {
                        ForEach(section.topics) { topic in
                            RefineGuideRow(topic: topic).tag(topic)
                        }
                    } header: {
                        if let group = section.group { RefineView.groupName(group) } else { Text("Start Here") }
                    }
                }
            }
            .navigationTitle("Tool Guide")
            .toolbar {
                if sizeClass == .compact {
                    ToolbarItem(placement: .confirmationAction) { doneButton }
                }
            }
        } detail: {
            if let topic {
                RefineGuidePageView(topic: topic, picture: picture, failed: failed) { self.topic = $0 }
                    .id(topic)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { doneButton }
                    }
            }
        }
        .onAppear(perform: RefinePracticeSetup.seedSettings)
        .task {
            do {
                picture = try await RefinePracticePicture.shared()
            } catch {
                Log.create.error("The practice picture failed: \(String(describing: error), privacy: .public)")
                failed = true
            }
        }
    }

    private var doneButton: some View {
        Button("Done", systemImage: "checkmark") { dismiss() }
            .tint(Theme.signature)
            .accessibilityIdentifier("refine-guide-done")
    }
}

/// A page in the guide's list: the tool's symbol, name and what it does in a line.
private struct RefineGuideRow: View {
    let topic: RefineGuideTopic

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                RefineGuidePageView.title(topic)
                Text(RefineGuidePage.of(topic).summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } icon: {
            Image(systemName: RefineGuidePageView.symbol(topic))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("refine-guide-topic-\(topic.identifier)")
    }
}

/// A page of the guide: the practice canvas and the words, side by side where the page is wide,
/// the canvas above the words where it isn't.
struct RefineGuidePageView: View {
    let topic: RefineGuideTopic
    let picture: RefinePracticePicture?
    let failed: Bool
    /// Opens another page (Goes Well With).
    let open: (RefineGuideTopic) -> Void

    @State private var model: CreateModel?
    /// Reset's count: the canvas is made again each time.
    @State private var resets = 0
    /// The cover (or, on iPhone, the page's push) has finished coming in. The practice canvas waits
    /// for it: as the guide opened, CI's simulators stopped answering UI tests for 20 to 40 s
    /// (main's runs 559 and 561), as the painting screen did while it was laid out at every frame
    /// of its push (`ArtworkPaintingView.hasLanded`).
    @State private var hasLanded = false
    @ScaledMetric(relativeTo: .subheadline) private var stepSize: CGFloat = 26

    private var page: RefineGuidePage { .of(topic) }

    var body: some View {
        GeometryReader { proxy in
            if let practice = page.practice {
                if proxy.size.width >= 760 {
                    HStack(spacing: 0) {
                        pad(practice)
                            .padding(16)
                        ScrollView { words }
                            .frame(width: min(420, proxy.size.width * 0.4))
                    }
                } else {
                    VStack(spacing: 0) {
                        pad(practice)
                            .frame(height: min(max(360, proxy.size.height * 0.58), proxy.size.height * 0.85))
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        ScrollView { words }
                    }
                }
            } else {
                ScrollView {
                    words
                        .frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Theme.paper)
        // A stroke to the right on the practice canvas draws: it never goes back (iPhone).
        .background { ContentSwipeBackOff().frame(width: 0, height: 0) }
        .background { GuidePageArrival(onArrival: land).frame(width: 0, height: 0) }
        .navigationTitle(Self.title(topic))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: picture != nil) {
            guard let picture, let practice = page.practice, model == nil else { return }
            let model = CreateModel(previewStyle: .lineArt)
            model.practice(picture, scene: practice.scene)
            self.model = model
        }
    }

    // MARK: Practice

    private func land() {
        guard !hasLanded else { return }
        hasLanded = true
        Log.create.notice("Tool Guide page shown: \(topic.identifier, privacy: .public)")
    }

    @ViewBuilder
    private func pad(_ practice: RefinePracticeSetup) -> some View {
        Group {
            // Once the picture is on it: a stroke before would have nothing to lay on.
            if hasLanded, let model, model.phase == .ready {
                RefineView(model: model, practice: practice) { resets += 1 }
                    .id(resets)
            } else if failed {
                ContentUnavailableView {
                    Label { Text("The Practice Picture Didn’t Open") } icon: { Image(systemName: "exclamationmark.triangle") }
                }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Practice"))
        .accessibilityIdentifier("refine-practice")
    }

    // MARK: Words

    private var words: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Text(page.about)
                .fixedSize(horizontal: false, vertical: true)
            section(Text("How to Use It")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(page.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text((index + 1).formatted())
                                .font(.display(.subheadline, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.signature)
                                .frame(width: stepSize, height: stepSize)
                                .background(Circle().strokeBorder(Theme.signature.opacity(0.5), lineWidth: 1.5))
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                            Text(step)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if let tryThis = page.tryThis {
                tryCard(tryThis)
            }
            if !page.notes.isEmpty {
                section(Text("Good to Know")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(page.notes, id: \.self) { note in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 5))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(note)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.subheadline)
                }
            }
            let related = page.related.map { RefineGuideTopic.tool($0) }
                .filter { topic in RefineGuideTopic.sections.contains { $0.topics.contains(topic) } }
            if !related.isEmpty {
                section(Text("Goes Well With")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(related) { topic in
                            Button {
                                FeedbackEngine.shared.selectionChanged()
                                open(topic)
                            } label: {
                                Label { Self.title(topic) } icon: { Image(systemName: Self.symbol(topic)) }
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("refine-guide-related-\(topic.identifier)")
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: Self.symbol(topic))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Theme.signature))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Self.title(topic)
                    .font(.display(.title2, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(page.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func section<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func tryCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("Try This")
            } icon: {
                RefineSparkleShape(star: false)
                    .fill(Theme.gold)
                    .frame(width: 16, height: 16)
            }
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            if page.practice != nil {
                Text("Reset puts the picture back whenever you like.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("refine-guide-try")
    }

    // MARK: Names

    static func title(_ topic: RefineGuideTopic) -> Text {
        switch topic {
        case .basics: Text("The Basics")
        case .views: Text("Views")
        case .tool(let tool): RefineView.toolName(tool)
        }
    }

    static func symbol(_ topic: RefineGuideTopic) -> String {
        switch topic {
        case .basics: "hand.draw"
        case .views: "eye"
        case .tool(let tool): RefineView.symbol(tool, shape: .star)
        }
    }
}

/// Tells a guide page that the transition bringing it in has finished: UIKit calls `viewDidAppear`
/// once a cover or a push has landed (SwiftUI's `onAppear` comes as it starts), and at once for a
/// page that takes another's place in the detail column.
private struct GuidePageArrival: UIViewControllerRepresentable {
    var onArrival: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.onArrival = onArrival
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) { controller.onArrival = onArrival }

    final class Controller: UIViewController {
        var onArrival: () -> Void = {}

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // Next turn: SwiftUI may be mid-update when UIKit calls this.
            Task { onArrival() }
        }
    }
}
