import SwiftUI

/// The painter's options: each a creative fork kept open until Paul narrows it.
struct OptionsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            Form {
                Section {
                    Picker("Finish", selection: $library.finish) {
                        ForEach(Finish.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Finish")
                } footer: {
                    Text("How set tiles look. Painted bed: the joints take the colour of the tiles round them, as the plaster under Byzantine mosaics was painted. Glass and stone: glass catches the light at its edges, faces are matte stone, and gold tilts.")
                }
                Section {
                    Picker("Detail", selection: $library.detail) {
                        ForEach(Detail.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Detail")
                } footer: {
                    Text("How many pieces a picture is laid in. Each detail is its own mosaic, and your work on each is kept.")
                }
                Section("About") {
                    Text("The pictures are in the public domain, from The Metropolitan Museum of Art's Open Access collection. Each mosaic credits its work.")
                    Text("Contours by Holistically-Nested Edge Detection (Saining Xie and Zhuowen Tu, 2015), in Lvmin Zhang's ControlNet annotator (Apache-2.0).")
                    Text("Most Byzantine mosaicists are anonymous. Ravenna is named for the city whose sixth-century mosaics are its touchstone.")
                }
                .font(Theme.body(14))
                .foregroundStyle(Theme.muted)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
