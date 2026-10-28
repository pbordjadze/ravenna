import MosaicCore
import SwiftUI

/// Settings › Acknowledgements › The Paints' Names: every material a paint can be named after, with
/// its colour, what it is and its source (`PaintNames.credits`, written with the names from
/// docs/paint-names.json). Ravenna's seam (#16). The credits are English data, as `library.json`'s
/// are; only the screen's own words are in the catalog.
struct PaintNamesView: View {
    var body: some View {
        Form {
            Section {
                Text("Each paint is named after a stone, pigment or glass of Roman and Byzantine mosaic and wall painting whose color is near it. A paint with none near keeps its plain name.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(Self.credits(.stone)) { PaintNameRow(credit: $0) }
            } header: {
                Text("Stones, Marbles and Gems")
            }
            Section {
                ForEach(Self.credits(.pigment)) { PaintNameRow(credit: $0) }
            } header: {
                Text("Pigments")
            }
            Section {
                ForEach(Self.credits(.glass)) { PaintNameRow(credit: $0) }
            } header: {
                Text("Glass, Metal and Clay")
            }
        }
        .navigationTitle("The Paints’ Names")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func credits(_ kind: PaintNames.Credit.Kind) -> [PaintNames.Credit] {
        PaintNames.credits.filter { $0.kind == kind }
    }
}

/// A material: its swatch (decorative, hidden from VoiceOver), its name, what it is and its
/// citation, read as one; then its source's page, a link of its own. Stacked at accessibility
/// text sizes.
private struct PaintNameRow: View {
    let credit: PaintNames.Credit
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var swatch: CGFloat = 30

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.outline, lineWidth: 1))
                .frame(width: swatch, height: swatch)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: credit.name)
                        .font(.headline)
                    Text(verbatim: credit.what)
                        .font(.subheadline)
                    Text(verbatim: credit.citation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                if let link = credit.link.flatMap({ URL(string: $0) }) {
                    Link(destination: link) {
                        Label(String(localized: "paintNames.source", defaultValue: "See the Source",
                                     comment: "Settings › Acknowledgements › The Paints’ Names: the link to the page of the source a paint’s name is credited to"),
                              systemImage: "building.columns")
                    }
                    .font(.footnote)
                    .padding(.top, 2)
                    .accessibilityLabel(String(localized: "paintNames.source.accessibility", defaultValue: "Source of \(credit.name)",
                                               comment: "VoiceOver label of the link to a paint name’s source in Settings › Acknowledgements › The Paints’ Names; the argument is the name, e.g. “Source of Giallo Antico”"))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        Color(red: Double(credit.hex >> 16 & 0xFF) / 255, green: Double(credit.hex >> 8 & 0xFF) / 255,
              blue: Double(credit.hex & 0xFF) / 255)
    }
}
