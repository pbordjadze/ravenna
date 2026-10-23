import SwiftUI
import UIKit

/// A mosaic from the painter's photo: how much of it (the panel), how many pieces (the detail
/// slider, issue #11), how the eyes are coloured (issue #9) and how the mouth is set (issue #1),
/// then the tiles are laid on the device. The photo never leaves it.
struct NewMosaicView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let data: Data
    let made: (Work) -> Void

    @State private var preview: UIImage?
    @State private var panel = Panel.whole
    @State private var centre = CGPoint(x: 0.5, y: 0.5)
    @State private var pieces = Maker.standardPieces
    @State private var eyes = MosaicEngine.Eyes.asTheyLook
    @State private var mouth = MosaicEngine.Mouth.asInThePhoto
    @State private var progress = MakeProgress()
    @State private var job: Task<Void, Never>?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let preview {
                        // The photo as the setter's cartoon, pinned on the bench.
                        FramingView(image: preview, panel: panel, centre: $centre)
                            .frame(maxHeight: 340)
                            .padding(6)
                            .background(Theme.panel)
                            .overlay { Rectangle().stroke(Theme.rule, lineWidth: 1) }
                            .disabled(progress.stage != nil)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Panel").font(Theme.title(18)).foregroundStyle(Theme.plaster)
                            .accessibilityAddTraits(.isHeader)
                        Group {
                            if typeSize.isAccessibilitySize {
                                panelPicker.pickerStyle(.menu)
                            } else {
                                panelPicker.pickerStyle(.segmented)
                            }
                        }
                        .disabled(progress.stage != nil)
                        Text(panel == .whole ? "All of the photo is laid." : "Drag the panel over the part to lay.")
                            .font(Theme.body(13)).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pieces").font(Theme.title(18)).foregroundStyle(Theme.plaster)
                            .accessibilityAddTraits(.isHeader)
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
                            .accessibilityAddTraits(.isHeader)
                        // Segments truncate at the accessibility sizes; a menu keeps the words whole.
                        Group {
                            if typeSize.isAccessibilitySize {
                                eyesPicker.pickerStyle(.menu)
                            } else {
                                eyesPicker.pickerStyle(.segmented)
                            }
                        }
                        .disabled(progress.stage != nil)
                        Text("Mixed brighter, as an eye catches the light, or kept as the photo has them.")
                            .font(Theme.body(13)).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mouth").font(Theme.title(18)).foregroundStyle(Theme.plaster)
                            .accessibilityAddTraits(.isHeader)
                        Group {
                            if typeSize.isAccessibilitySize {
                                mouthPicker.pickerStyle(.menu)
                            } else {
                                mouthPicker.pickerStyle(.segmented)
                            }
                        }
                        .disabled(progress.stage != nil)
                        Text("Kept as the photo has it, or set small and closed, as Byzantine faces were.")
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
            .task {
                let data = data
                // Small enough to redraw as the panel moves.
                preview = await Task.detached { Maker.oriented(data, longSide: 1200).map { UIImage(cgImage: $0) } }.value
            }
        }
    }

    private var panelPicker: some View {
        Picker("Panel", selection: $panel) {
            ForEach(Panel.allCases) { Text($0.name).tag($0) }
        }
    }

    private var eyesPicker: some View {
        Picker("Eyes", selection: $eyes) {
            Text("As they look").tag(MosaicEngine.Eyes.asTheyLook)
            Text("The photo's colours").tag(MosaicEngine.Eyes.asInThePhoto)
        }
    }

    private var mouthPicker: some View {
        Picker("Mouth", selection: $mouth) {
            Text("As in the photo").tag(MosaicEngine.Mouth.asInThePhoto)
            Text("Byzantine").tag(MosaicEngine.Mouth.byzantine)
        }
    }

    private func lay() {
        failure = nil
        progress.stage = .reading
        progress.done = 0
        let data = data, pieces = pieces, eyes = eyes, mouth = mouth, progress = progress
        let unit = preview.map { panel.rect(in: $0.size, centre: centre) } ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        job = Task {
            do {
                // Detached, so cancelling this task (Cancel) must be passed on to it.
                let worker = Task.detached(priority: .userInitiated) {
                    guard let cut = Panel.cut(data, to: unit) else { throw Maker.MakerError.unreadable }
                    return try Maker.make(from: cut, pieces: pieces, eyes: eyes, mouth: mouth) { s, done in
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
