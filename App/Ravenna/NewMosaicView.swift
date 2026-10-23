import SwiftUI
import UIKit

/// A mosaic from the painter's photo: how many pieces (the detail slider, issue #11), then the
/// tiles are laid on the device. The photo never leaves it.
struct NewMosaicView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let data: Data
    let made: (Work) -> Void

    @State private var pieces = 0.4
    @State private var progress = MakeProgress()
    @State private var job: Task<Void, Never>?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let preview = UIImage(data: data) {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .frame(maxHeight: 340)
                        .accessibilityLabel("Your photo")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pieces").font(Theme.title(18)).foregroundStyle(Theme.plaster)
                    Slider(value: $pieces, in: 0...1) {
                        Text("Pieces")
                    } minimumValueLabel: {
                        Text("Fewer").font(Theme.body(13))
                    } maximumValueLabel: {
                        Text("More").font(Theme.body(13))
                    }
                    .disabled(progress.stage != nil)
                    Text("More pieces take longer to lay, and to set.").font(Theme.body(13)).foregroundStyle(Theme.muted)
                }
                if let stage = progress.stage {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.tint)
                        Text(stage.rawValue).font(Theme.body(15)).foregroundStyle(Theme.plaster)
                    }
                } else if let failure {
                    Text(failure).font(Theme.body(14)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Button {
                    lay()
                } label: {
                    Text("Lay the tiles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(progress.stage != nil)
            }
            .padding(20)
            .background(Theme.ground)
            .navigationTitle("New mosaic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { job?.cancel(); dismiss() }
                }
            }
            .interactiveDismissDisabled(progress.stage != nil)
        }
    }

    private func lay() {
        failure = nil
        progress.stage = .reading
        let data = data, pieces = pieces, progress = progress
        job = Task {
            do {
                // Detached, so cancelling this task (Cancel) must be passed on to it.
                let worker = Task.detached(priority: .userInitiated) {
                    try Maker.make(from: data, pieces: pieces) { s in Task { @MainActor in progress.stage = s } }
                }
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                let work = try library.keep(result)
                progress.stage = nil
                dismiss()
                made(work)
            } catch is CancellationError {
                progress.stage = nil
            } catch {
                progress.stage = nil
                failure = "Couldn't lay this photo's tiles. Try another photo."
            }
        }
    }
}

/// Which stage the maker is at, for the sheet (main-actor isolated, so the maker's thread can hand
/// it a stage).
@Observable
final class MakeProgress {
    var stage: Maker.Stage?
}
