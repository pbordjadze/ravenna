import CoreGraphics
import Foundation
import os
import SwiftUI
import UIKit

/// Feedback's review and send sheet: the painting with its marks, a note, a comment per mark
/// beside its close-up, what goes along (the painter's own photo only if they turn it on), and
/// Send, which writes the bundle (`FeedbackPackage`) and sends it straight to the developers
/// (`FeedbackUploader`). When that fails (offline, a timeout, a refusal) an alert offers Try
/// Again, Share Instead, which opens the share sheet where the painter picks Mail, Messages,
/// AirDrop or Files and who it goes to, and Cancel, which keeps everything written. Back
/// returns to drawing; sending or sharing it ends feedback.
struct FeedbackSheet: View {
    @Bindable var draft: FeedbackDraft
    /// The feedback was sent or shared.
    var onSent: (Delivery) -> Void
    /// Where Send goes: the relay, or in Debug builds a stub (`FeedbackUploads`).
    var uploader: FeedbackUploader = FeedbackUploads.current

    /// How the feedback left.
    enum Delivery {
        /// To the developers, by Send.
        case sent
        /// Through the share sheet, by Share Instead.
        case shared
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.editing
    /// The files written for the Send in progress or just failed, kept for Try Again and Share
    /// Instead and removed when feedback is sent, given up or shared.
    @State private var prepared: FeedbackPackage.Files?

    private enum Phase: Equatable {
        case editing
        /// Writing the bundle (or, for Share Instead, waiting for the alert to leave).
        case packing
        /// The bundle is on its way to the developers.
        case sending
        /// The bundle couldn't be written.
        case failed
        /// It couldn't be sent: the alert asks what to do.
        case notSent
        case sharing([URL])

        var isBusy: Bool { self == .packing || self == .sending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FeedbackPictureView(picture: draft.overview, aspectRatio: aspectRatio)
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                        .accessibilityElement()
                        .accessibilityLabel(Text("Your painting with your marks"))
                }
                Section {
                    TextField("What would make this painting better?", text: $draft.note, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("feedback-note")
                } header: {
                    Text("Note")
                } footer: {
                    Text("Say what looks wrong or right, and why.")
                }
                if !draft.marks.isEmpty { marks }
                included
            }
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.backward") { dismiss() }
                        .accessibilityIdentifier("feedback-back")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase.isBusy {
                        ProgressView()
                            .accessibilityLabel(Text(progressText))
                    } else {
                        Button("Send", systemImage: "paperplane", action: send)
                            .tint(Theme.signature)
                            .disabled(draft.isEmpty)
                            .accessibilityIdentifier("feedback-send")
                    }
                }
            }
            .disabled(phase.isBusy)
            .overlay(alignment: .bottom) {
                if phase.isBusy {
                    Toast(text: progressText, systemImage: phase == .sending ? "paperplane" : "shippingbox")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .animation(.snappy, value: phase)
            .alert("Couldn’t Send Feedback", isPresented: notSent) {
                Button("Try Again", action: tryAgain)
                Button("Share Instead", action: shareInstead)
                Button("Cancel", role: .cancel, action: giveUpSending)
            } message: {
                Text("Check your connection and try again, or share it another way. What you wrote is kept.")
            }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled(phase.isBusy)
        .background {
            ActivityShareSheet(items: sharedFiles) { completed in finishSharing(completed: completed) }
        }
        .alert("Couldn’t Prepare Feedback", isPresented: failed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again in a moment.")
        }
        .onAppear {
            Log.feedback.notice("Review sheet up")
            draft.prepareReview()
        }
    }

    // MARK: Sections

    private var marks: some View {
        Section {
            ForEach(Array(draft.marks.enumerated()), id: \.element.id) { index, mark in
                MarkRow(number: index + 1, picture: draft.closeUps[mark.id], comment: comment(for: mark.id))
            }
        } header: {
            Text("Marks")
        } footer: {
            Text("Each mark gets its own comment.")
        }
    }

    private var included: some View {
        Section {
            Label("The painting with your marks, and each mark close up", systemImage: "photo")
            Label("Its template, settings and progress", systemImage: "square.grid.3x3")
            LabeledContent {
                Text(verbatim: "\(draft.capture.app), \(draft.capture.device), \(draft.capture.system)")
            } label: {
                Label("App and Device", systemImage: "info.circle")
            }
            if draft.canIncludePhoto {
                Toggle(isOn: $draft.includesPhoto) {
                    Label("Original Photo", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("feedback-photo")
            } else if draft.capture.source?.sampleName != nil {
                Label("Made from a library picture: no photo needed", systemImage: "books.vertical")
            }
        } header: {
            Text("Included")
        } footer: {
            if draft.canIncludePhoto {
                Text("Send goes straight to the people who make Paint by Moonlight. Your photo helps us remake the painting; it goes only if you turn it on.")
            } else {
                Text("Send goes straight to the people who make Paint by Moonlight.")
            }
        }
    }

    // MARK: Sending

    private var aspectRatio: CGFloat {
        let canvas = draft.capture.canvasRect
        return canvas.height > 0 ? canvas.width / canvas.height : 1
    }

    private func comment(for mark: Date) -> Binding<String> {
        Binding { draft.comments[mark] ?? "" } set: { draft.comments[mark] = $0 }
    }

    private var failed: Binding<Bool> {
        Binding { phase == .failed } set: { if !$0 { phase = .editing } }
    }

    /// The alert's buttons each move `phase` on, so whichever of them and this setter runs
    /// first, the others find what they expect.
    private var notSent: Binding<Bool> {
        Binding { phase == .notSent } set: { if !$0, phase == .notSent { phase = .editing } }
    }

    private var sharedFiles: [URL] {
        if case .sharing(let files) = phase { files } else { [] }
    }

    private var progressText: String {
        phase == .sending ? String(localized: "Sending…") : String(localized: "Preparing your feedback…")
    }

    private func send() {
        phase = .packing
        Task {
            do {
                let files = try await draft.package()
                prepared = files
                await upload(files)
            } catch {
                Log.feedback.error("Packing feedback failed: \(String(describing: error), privacy: .public)")
                phase = .failed
            }
        }
    }

    /// Sends the written files to the developers: thanks if they took them, the alert if not.
    /// Neither closes the sheet nor shows the alert again sooner than `notBefore`: offline, a
    /// send fails at once.
    private func upload(_ files: FeedbackPackage.Files, notBefore: ContinuousClock.Instant? = nil) async {
        phase = .sending
        do {
            try await uploader.upload(files, app: draft.capture.app)
            Log.feedback.notice("Feedback sent (\(uploader.name, privacy: .public))")
            if let notBefore { try? await Task.sleep(until: notBefore) }
            phase = .editing
            discardPrepared()
            onSent(.sent)
        } catch {
            Log.feedback.error("Sending feedback failed: \(String(describing: error), privacy: .public)")
            if let notBefore { try? await Task.sleep(until: notBefore) }
            phase = .notSent
        }
    }

    /// Sends again at once, but closes the sheet only once the alert has gone: UIKit dismisses
    /// nothing under a presentation still in flight, and a quick send asked it to.
    private func tryAgain() {
        guard let files = prepared else { return }
        // Before the alert's binding hands the sheet back to editing, which would turn Send on.
        phase = .sending
        let alertGone = ContinuousClock.now + Self.alertDismissal
        Task { await upload(files, notBefore: alertGone) }
    }

    /// How long an alert takes to leave, with room to spare.
    private static let alertDismissal = Duration.milliseconds(500)

    /// Opens the share sheet with the files already written, once the alert has gone: UIKit
    /// presents nothing over an alert that is still leaving.
    private func shareInstead() {
        guard let files = prepared else { return }
        phase = .packing
        Task {
            try? await Task.sleep(for: Self.alertDismissal)
            phase = .sharing(files.shared)
        }
    }

    /// Back to the sheet with everything written still in it.
    private func giveUpSending() {
        phase = .editing
        discardPrepared()
    }

    /// The export folder goes: the files are sent, or will be made again.
    private func discardPrepared() {
        guard let files = prepared else { return }
        prepared = nil
        Task { await Background.run { ArtworkExporter.removeExport(at: files.picture) } }
    }

    /// The share sheet closed: the receivers have their copies, so the files go either way;
    /// shared, feedback is done.
    private func finishSharing(completed: Bool) {
        let files = sharedFiles
        phase = .editing
        prepared = nil
        if let first = files.first {
            Task { await Background.run { ArtworkExporter.removeExport(at: first) } }
        }
        if completed { onSent(.shared) }
    }
}

/// A mark in the review sheet: its close-up, its number and its comment.
private struct MarkRow: View {
    let number: Int
    let picture: FeedbackPicture?
    @Binding var comment: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FeedbackPictureView(picture: picture, aspectRatio: 1)
                .frame(width: 72, height: 72)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                TextField("What should we look at here?", text: $comment, axis: .vertical)
                    .lineLimit(1...6)
                    .accessibilityLabel(Text(title))
                    .accessibilityIdentifier("feedback-mark-\(number)")
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        String(localized: "feedback.mark.title", defaultValue: "Mark \(number)",
               comment: "Feedback's review sheet: the name of one of the marks drawn on the painting; the argument is its number")
    }
}

/// A painting picture with the ink over it, fitted; a spinner until it's drawn.
struct FeedbackPictureView: View {
    let picture: FeedbackPicture?
    let aspectRatio: CGFloat

    var body: some View {
        ZStack {
            if let picture {
                Image(decorative: picture.painting, scale: 1)
                    .resizable()
                    .scaledToFit()
                if let ink = picture.ink {
                    Image(decorative: ink, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Color.secondary.opacity(0.12)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .overlay { ProgressView() }
            }
        }
    }
}
