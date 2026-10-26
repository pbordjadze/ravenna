import SwiftUI

/// Settings › Acknowledgements: the sample pictures and where they come from, then the
/// open-source code, machine-learning models and published methods behind the template
/// engine, with the licenses the ported code and model weights are used under.
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
