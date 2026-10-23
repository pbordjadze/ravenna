import SwiftUI
import UIKit

/// A mosaic from the painter's photo: how many pieces (the detail slider, issue #11) and how the
/// eyes are coloured (issue #9), then the tiles are laid on the device. The photo never leaves it.
struct NewMosaicView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let data: Data
    let made: (Work) -> Void

    @State private var pieces = 0.4
    @State private var eyes = MosaicEngine.Eyes.asTheyLook
    @State private var progress = MakeProgress()
    @State private var job: Task<Void, Never>?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let preview = UIImage(data: data) {
                        // The photo as the setter's cartoon, pinned on the bench.
                        Image(uiImage: preview).resizable().scaledToFit()
                            .frame(maxHeight: 340)
                            .padding(6)
                            .background(Theme.panel)
                            .overlay { Rectangle().stroke(Theme.rule, lineWidth: 1) }
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Eyes").font(Theme.title(18)).foregroundStyle(Theme.plaster)
                        Picker("Eyes", selection: $eyes) {
                            Text("As they look").tag(MosaicEngine.Eyes.asTheyLook)
                            Text("The photo's colours").tag(MosaicEngine.Eyes.asInThePhoto)
                        }
                        .pickerStyle(.segmented)
                        .disabled(progress.stage != nil)
                        Text("Mixed brighter, as an eye catches the light, or kept as the photo has them.")
                            .font(Theme.body(13)).foregroundStyle(Theme.muted)
                    }
                    if let stage = progress.stage {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: progress.done).tint(Theme.tint)
                            Text(stage.rawValue).font(Theme.body(15)).foregroundStyle(Theme.plaster)
                        }
                    } else if let failure {
                        Text(failure).font(Theme.body(14)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(20)
            }
            // The button stays in reach however large the text, the rest scrolls.
            .safeAreaInset(edge: .bottom) {
                Button {
                    lay()
                } label: {
                    Text("Lay the tiles").font(Theme.title(18)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(progress.stage != nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.ground)
            }
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
        progress.done = 0
        let data = data, pieces = pieces, eyes = eyes, progress = progress
        job = Task {
            do {
                // Detached, so cancelling this task (Cancel) must be passed on to it.
                let worker = Task.detached(priority: .userInitiated) {
                    try Maker.make(from: data, pieces: pieces, eyes: eyes) { s, done in
                        Task { @MainActor in
                            // A hop that lands after the job has ended (cancelled, failed) changes nothing.
                            guard progress.stage != nil, done >= progress.done else { return }
                            progress.stage = s; progress.done = done
                        }
                    }
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

/// Which stage the maker is at and how much of the job is done, for the sheet (main-actor isolated,
/// so the maker's thread can hand it both; `done` only rises, whatever order the hops arrive in).
@Observable
final class MakeProgress {
    var stage: Maker.Stage?
    var done = 0.0
}
