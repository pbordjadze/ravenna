import Foundation
import MakingOf
import SwiftUI

/// A step's card in the making-of show, after Caroline: what the step does in a few plain words
/// (`caption`), and under it, smaller and fainter like a footnote, the credit line of each method
/// it stands on, numbered ¹ ² ³ like the marks after the caption (`credits`). A credit is
/// `Acknowledgements.methods`' line for the spec's method name, letter for letter, its quoted title
/// in italics.
nonisolated struct MakingOfCard: Sendable, Equatable {
    let step: Int
    /// The step's caption with a mark for each credit.
    let caption: String
    /// The caption alone, as VoiceOver announces the card.
    let spoken: String
    let credits: [AttributedString]

    init(step: ShowSpec.Step, index: Int) {
        self.step = index
        let marks = step.methods.indices.map(Self.mark)
        spoken = Self.caption(for: step.id)
        caption = spoken + marks.joined(separator: ",")
        credits = zip(marks, step.methods).map { mark, name in
            var line = AttributedString(mark + " ")
            line += Self.credit(of: name)
            return line
        }
    }

    /// Superscript marks for up to eight credits (the spec's limit), then plain numbers.
    private static func mark(_ i: Int) -> String {
        let marks = Array("¹²³⁴⁵⁶⁷⁸")
        return i < marks.count ? String(marks[i]) : String(i + 1)
    }

    /// The method's credit line from Acknowledgements, the part in quotes (a paper's title) in
    /// italics; the name itself if Acknowledgements has none (`MakingOfShowTests` checks it has
    /// each).
    static func credit(of method: String) -> AttributedString {
        guard let credit = Acknowledgements.methods.first(where: { $0.name == method })?.credit else {
            return AttributedString(method)
        }
        guard let open = credit.firstIndex(of: "\""), let close = credit.lastIndex(of: "\""), open < close else {
            return AttributedString(credit)
        }
        let start = credit.index(after: open)
        var title = AttributedString(String(credit[start..<close]))
        title.inlinePresentationIntent = .emphasized
        return AttributedString(String(credit[..<start])) + title + AttributedString(String(credit[close...]))
    }

    /// Each step's caption, in the catalog: the English is the spec's (`making-of.json`), which
    /// `MakingOfShowTests` keeps the catalog in step with.
    static func caption(for step: ShowSpec.StepID) -> String {
        switch step {
        case .sketch:
            String(localized: "makingOf.caption.sketch", defaultValue: "Finding the shapes under the texture",
                   comment: "Card of the making-of show's first step, under the picture: the photo's texture smears away and pencil lines find its shapes")
        case .shading:
            String(localized: "makingOf.caption.shading", defaultValue: "Shading softly, without crossing edges",
                   comment: "Card of the making-of show's second step: soft grey shading is laid in, stopping at the edges")
        case .paints:
            String(localized: "makingOf.caption.paints", defaultValue: "Choosing the paints",
                   comment: "Card of the making-of show's third step: the painting's paints are picked from the photo")
        case .merged:
            String(localized: "makingOf.caption.merged", defaultValue: "Folding tiny bits into their neighbors",
                   comment: "Card of the making-of show's fourth step: areas too small to paint join the areas beside them")
        case .ink:
            String(localized: "makingOf.caption.ink", defaultValue: "Drawing the lines",
                   comment: "Card of the making-of show's fifth step: the painting's lines are inked")
        case .template:
            String(localized: "makingOf.caption.template", defaultValue: "Smoothing the outlines, adding the numbers",
                   comment: "Card of the making-of show's last step: stair-stepped outlines relax into smooth curves and the paint numbers go in")
        }
    }
}

/// A card as the show draws it, in the band under the picture: the caption in New York italic,
/// the credits smaller in New York, each at its own opacity (`CardDraw`'s, final), in the
/// screen's text color.
struct MakingOfCardView: View {
    let card: MakingOfCard
    let opacity: Double
    let footnoteOpacity: Double

    var body: some View {
        VStack(spacing: 10) {
            Text(card.caption)
                .font(.system(.title3, design: .serif))
                .italic()
                .opacity(opacity)
            VStack(spacing: 4) {
                ForEach(card.credits.indices, id: \.self) { i in
                    Text(card.credits[i])
                }
            }
            .font(.system(.caption, design: .serif))
            .opacity(footnoteOpacity)
        }
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: 640)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("making-of-card")
    }
}
