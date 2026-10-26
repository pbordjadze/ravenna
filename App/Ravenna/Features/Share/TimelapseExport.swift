import Foundation
import Observation
import os
import SwiftUI
import UIKit

/// Makes a time-lapse for sharing: renders it with visible progress, then hands it to the
/// share sheet and deletes it once sharing is over.
@Observable
final class TimelapseExportModel {
    enum Phase: Equatable {
        /// Fraction of the frames encoded.
        case rendering(Double)
        case ready(URL)
        case failed(String)
    }

    let request: TimelapseRequest
    private(set) var phase: Phase = .rendering(0)
    @ObservationIgnored private var cleanedUp = false

    init(request: TimelapseRequest) {
        self.request = request
    }

    /// Renders the movie. Cancelling the calling task stops the render between frames and
    /// removes the partial movie; a movie already made (Try Again was tapped since) is removed
    /// first.
    func run(longSide: Int = 1080) async {
        await finishSharing()
        phase = .rendering(0)
        cleanedUp = false
        // Only the newest value matters: hundreds of per-frame updates coalesce to what the
        // main actor gets round to drawing.
        let (updates, continuation) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
        async let rendered = Self.render(request, longSide: longSide, updates: continuation)
        // Ends when the render finishes, or at once when this task is cancelled.
        for await fraction in updates { phase = .rendering(fraction) }
        do {
            let url = try await rendered
            guard !Task.isCancelled else {
                // Finished just as the sheet went away: nobody will share it.
                await Background.run { ArtworkExporter.removeExport(at: url) }
                return
            }
            phase = .ready(url)
        } catch is CancellationError {
        } catch {
            Log.library.error("Time-lapse failed: \(String(describing: error), privacy: .public)")
            phase = .failed(ArtworkExporter.ExportError.timelapseFailed.localizedDescription)
        }
    }

    /// Sharing is over (the share sheet closed, or this screen went away): the receivers have
    /// their copies, so the movie's folder goes. Runs once per movie, whichever comes first.
    func finishSharing() async {
        guard case .ready(let url) = phase, !cleanedUp else { return }
        cleanedUp = true
        await Background.run { ArtworkExporter.removeExport(at: url) }
    }

    /// The progress closure is formed here, off the main actor: the exporter calls it from its
    /// own thread.
    @concurrent
    private static func render(
        _ request: TimelapseRequest, longSide: Int, updates: AsyncStream<Double>.Continuation
    ) async throws -> URL {
        defer { updates.finish() }
        return try await request.render(longSide: longSide) { updates.yield($0) }
    }
}

/// "Share Time-lapse": the movie's progress with Cancel (which deletes the partial movie),
/// then the share sheet. Present it as a sheet; dismissing it cancels the render.
struct TimelapseExportSheet: View {
    @State private var model: TimelapseExportModel
    /// Try Again starts the render over.
    @State private var attempt = 0
    @Environment(\.dismiss) private var dismiss

    init(request: TimelapseRequest) {
        _model = State(initialValue: TimelapseExportModel(request: request))
    }

    var body: some View {
        // Scrolls when large text makes the sheet's content taller than its detent.
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "timelapse")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: isRendering)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("Making Your Time-lapse")
                        .font(.display(.title3))
                    Text(model.request.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                status
            }
            .padding(28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .background {
            ActivityShareSheet(item: readyURL) {
                Task {
                    await model.finishSharing()
                    dismiss()
                }
            }
        }
        // A progress bar and a button: half a screen is room enough, with nothing to pull up to.
        .presentationDetents([.medium])
        .task(id: attempt) { await model.run() }
        #if DEBUG
        .onChange(of: model.phase) { _, phase in
            if ShellDemo.current?.sharesTimelapse == true, case .rendering(let fraction) = phase, fraction > 0 {
                DemoMode.markReady()
            }
        }
        #endif
        // Swiped away (or tapped outside on iPad) with the movie ready: it mustn't stay behind.
        .onDisappear { Task { await model.finishSharing() } }
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .rendering(let fraction):
            // No label of its own: the title above says what it measures.
            ProgressView(value: fraction) {
                EmptyView()
            } currentValueLabel: {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .accessibilityLabel(Text("Making Your Time-lapse"))
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
        case .ready:
            Label("Ready to Share", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            // The share sheet normally covers this; if it couldn't appear, this still closes.
            Button("Close") { dismiss() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
        case .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Close") { dismiss() }
                    .buttonStyle(.glass)
                Button("Try Again") { attempt += 1 }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
            }
        }
    }

    private var isRendering: Bool {
        if case .rendering = model.phase { true } else { false }
    }

    private var readyURL: URL? {
        if case .ready(let url) = model.phase { url } else { nil }
    }
}
