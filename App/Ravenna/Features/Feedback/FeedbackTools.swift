import SwiftUI
import UIKit

/// What the markup canvas draws with.
nonisolated enum FeedbackTool: Hashable {
    /// For circling and writing, in the pen's color.
    case pen
    /// A wide yellow stroke over an area.
    case highlighter
    /// Takes whole strokes away.
    case eraser
}

/// The pen's colors: saturated enough to show on light and dark paper, and apart from each
/// other, so one of them stands out on any painting.
nonisolated enum FeedbackInkColor: CaseIterable, Hashable {
    case red, blue, green

    var uiColor: UIColor {
        switch self {
        case .red: .systemRed
        case .blue: .systemBlue
        case .green: .systemGreen
        }
    }

    var name: String {
        switch self {
        case .red:
            String(localized: "feedback.ink.red", defaultValue: "Red",
                   comment: "Feedback mode's tools: VoiceOver label of the button that gives the pen red ink")
        case .blue:
            String(localized: "feedback.ink.blue", defaultValue: "Blue",
                   comment: "Feedback mode's tools: VoiceOver label of the button that gives the pen blue ink")
        case .green:
            String(localized: "feedback.ink.green", defaultValue: "Green",
                   comment: "Feedback mode's tools: VoiceOver label of the button that gives the pen green ink")
        }
    }
}

/// Feedback mode's tools, along the bottom: the pen and its colors, the highlighter and the
/// eraser. The app's own rather than PencilKit's tool picker, which shows only while the canvas
/// is first responder: moving first responder to and from the canvas around the review sheet
/// left the app unresponsive (CI's simulators, iOS 26.5), and without the picker the canvas
/// never takes it.
struct FeedbackTools: View {
    let draft: FeedbackDraft

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 8) {
                toolButton(.pen, systemImage: "pencil.tip", id: "pen", label: Text("Pen"))
                toolButton(.highlighter, systemImage: "highlighter", id: "highlighter", label: Text("Highlighter"))
                toolButton(.eraser, systemImage: "eraser", id: "eraser", label: Text("Eraser"))
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 4)
                    .accessibilityHidden(true)
                ForEach(FeedbackInkColor.allCases, id: \.self) { color in
                    colorButton(color)
                }
            }
        }
        // Like the painting's bars: the controls reach larger text sizes through the Large
        // Content Viewer.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// A tool, prominent while it's the one drawing.
    @ViewBuilder
    private func toolButton(_ tool: FeedbackTool, systemImage: String, id: String, label: Text) -> some View {
        let selected = draft.tool == tool
        let button = Button { pick(tool) } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("feedback-tool-\(id)")
        .accessibilityShowsLargeContentViewer { Label { label } icon: { Image(systemName: systemImage) } }
        if selected {
            button.buttonStyle(.glassProminent).tint(Theme.signature)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private func pick(_ tool: FeedbackTool, color: FeedbackInkColor? = nil) {
        guard tool != draft.tool || (color != nil && color != draft.penColor) else { return }
        FeedbackEngine.shared.selectionChanged()
        if let color { draft.penColor = color }
        draft.tool = tool
    }

    /// A pen color: picking it picks the pen too. The pen's color is ringed.
    private func colorButton(_ color: FeedbackInkColor) -> some View {
        let selected = draft.penColor == color
        return Button { pick(.pen, color: color) } label: {
            Circle()
                .fill(Color(uiColor: color.uiColor))
                .frame(width: 22, height: 22)
                .padding(3)
                .overlay {
                    if selected { Circle().strokeBorder(Color.primary, lineWidth: 2) }
                }
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(Text(color.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityShowsLargeContentViewer { Label(color.name, systemImage: "circle.fill") }
    }
}
