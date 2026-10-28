import SwiftUI

/// Settings › Acknowledgements: the ancient works and where they come from, the materials the paints
/// are named after (`PaintNamesView`), then the open-source code, machine-learning model, type and
/// published methods behind the mosaics, with the licenses the ported code, model weights and fonts
/// are used under. (Ravenna's seam: the paints' names and Type sections.)
struct AcknowledgementsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(Sample.all) { PictureRow(sample: $0) }
            } header: {
                Text("Pictures")
            } footer: {
                Text("With thanks to the museums and archives that share these pictures.")
            }

            Section {
                NavigationLink {
                    PaintNamesView()
                } label: {
                    Text("Their Materials and Sources")
                }
            } header: {
                Text("The Paints’ Names")
            } footer: {
                Text("The stones, pigments and glass of Roman and Byzantine mosaic that the paints are named after.")
            }

            Section {
                ForEach(Acknowledgements.code) { AcknowledgementRow(item: $0) }
            } header: {
                Text("Open-Source Code")
            } footer: {
                Text(Acknowledgements.codeFooter)
            }

            Section {
                ForEach(Acknowledgements.models) { AcknowledgementRow(item: $0) }
            } header: {
                Text("Models")
            } footer: {
                Text(Acknowledgements.modelsFooter)
            }

            Section {
                ForEach(Acknowledgements.typefaces) { AcknowledgementRow(item: $0) }
            } header: {
                Text("Type")
            }

            ForEach(License.allCases, id: \.self) { license in
                Section(license.name) {
                    Text(license.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                ForEach(Acknowledgements.methods) { AcknowledgementRow(item: $0) }
            } header: {
                Text("Methods")
            } footer: {
                Text("Published techniques the template engine builds on.")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AcknowledgementRow: View {
    let item: Acknowledgement

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.headline)
            Text(item.usage)
                .font(.subheadline)
            Text(item.credit)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let copyright = item.copyright {
                Text(copyright)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let license = item.license {
                Text(license.name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A sample picture's credit: its title, who made it and when, the collection the file comes
/// from and its license, the facts shown verbatim as `library.json` records them.
private struct PictureRow: View {
    let sample: Sample

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sample.title)
                .font(.headline)
            if let provenance = sample.provenance {
                Text(Acknowledgements.byline(provenance))
                    .font(.subheadline)
                Text(provenance.credit)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(provenance.license)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
