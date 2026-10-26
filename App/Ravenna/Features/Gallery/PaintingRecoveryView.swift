import Foundation
import SwiftUI

/// Shown instead of the canvas when a painting can't be opened: says why, and offers what
/// can still be done (regenerate it from its photo, delete it, or go back). Delete asks first,
/// and the button asks (a dialog is a popover on the view that carries it: this one points at
/// the button).
struct PaintingRecoveryView: View {
    let artwork: Artwork?
    let failure: Library.OpenError
    /// 0…1 while the painting is being regenerated.
    var progress: Double?
    /// The last attempt to regenerate failed.
    var didFail = false
    var onRegenerate: () -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    @State private var confirmsDelete = false

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
                .readableDescription()
        } actions: {
            if let progress {
                VStack(spacing: 10) {
                    ProgressView(value: progress)
                        .frame(maxWidth: 260)
                    Text("Regenerating…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Regenerating")
                .accessibilityValue(String(
                    localized: "gallery.recovery.progressValue", defaultValue: "\(Int((progress * 100).rounded())) percent",
                    comment: "VoiceOver value of the regeneration progress bar: a whole percentage"))
            } else {
                VStack(spacing: 12) {
                    if canRegenerate {
                        Button("Regenerate", systemImage: "arrow.clockwise", action: onRegenerate)
                            .buttonStyle(.glassProminent)
                            .tint(Theme.signature)
                    }
                    Button("Back to Gallery", action: onClose)
                        .buttonStyle(.glass)
                    // Last and set apart: never beside the way out.
                    if let artwork {
                        // Glass draws its label in the tint, whatever the role.
                        Button("Delete Painting", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                            .buttonStyle(.glass)
                            .tint(.red)
                            .confirmationDialog("Delete this painting?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                                Button(DeleteConfirmation.buttonTitle(for: artwork), role: .destructive, action: onDelete)
                            } message: {
                                DeleteConfirmationMessage(artwork: artwork)
                            }
                            .padding(.top, 20)
                    }
                }
            }
        }
    }

    private var canRegenerate: Bool { artwork != nil && failure == .damaged(canRegenerate: true) }

    private var title: String {
        failure == .needsNewerApp ? String(localized: "Needs a Newer Version") : String(localized: "Can’t Open Painting")
    }

    private var systemImage: String {
        failure == .needsNewerApp ? "arrow.up.circle" : "exclamationmark.triangle"
    }

    private var message: String {
        var text: String
        switch failure {
        case .needsNewerApp:
            if let paintingTitle = artwork?.title, !paintingTitle.isEmpty {
                text = String(localized: "gallery.recovery.newer.titled",
                              defaultValue: "“\(paintingTitle)” was made with a newer version of Paint by Moonlight. Update the app to keep painting it.",
                              comment: "Recovery screen text for a painting made by a newer app version; the argument is the painting's title")
            } else {
                text = String(localized: "gallery.recovery.newer.untitled",
                              defaultValue: "This painting was made with a newer version of Paint by Moonlight. Update the app to keep painting it.",
                              comment: "Recovery screen text for an untitled painting made by a newer app version")
            }
        case .damaged(canRegenerate: true) where artwork != nil:
            if artwork?.isStarted == true {
                text = String(localized: "gallery.recovery.damaged.regenerableFresh",
                              defaultValue: "Its file is damaged. It can be made again from its photo, but its paint can’t be saved: it will start fresh.",
                              comment: "Recovery screen text for a damaged painting that has paint on it and can be regenerated from its photo")
            } else {
                text = String(localized: "gallery.recovery.damaged.regenerable",
                              defaultValue: "Its file is damaged. It can be made again from its photo.",
                              comment: "Recovery screen text for a damaged painting that can be regenerated from its photo")
            }
        case .unreadable:
            text = String(localized: "gallery.recovery.unreadable",
                          defaultValue: "It couldn’t be opened just now. Nothing changed: go back and try again.",
                          comment: "Recovery screen text when a painting's files exist but couldn't be read (a passing storage error)")
        case .damaged:
            text = String(localized: "gallery.recovery.damaged.unavailable",
                          defaultValue: "Its file is damaged, and its photo is gone, so it can’t be made again.",
                          comment: "Recovery screen text for a damaged painting whose original photo is gone")
        }
        if didFail {
            text += "\n\n" + String(localized: "gallery.recovery.retry", defaultValue: "Regenerating didn’t work. Try again.",
                                    comment: "Recovery screen text added after a failed regeneration attempt")
        }
        return text
    }
}
