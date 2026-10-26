import CoreGraphics
import Foundation
import os
import PaintCore
import SwiftUI

/// "Send Template…": the page someone else will paint, blank, with the Original Photo switch (on
/// unless the painter turns it off; Paul, October 18: "maybe on by default"), then the share
/// sheet with the `.moonlight` file (`ArtworkExporter.sharedPainting`), deleted once it closes.
/// Present it as a sheet.
struct SendTemplateSheet: View {
    let artwork: Artwork
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var includesPhoto = true
    @State private var preview: CGImage?
    @State private var isPreparing = false
    @State private var file: URL?
    @State private var failed = false
    /// Whether the painting has a photo to send, read off the main actor with the preview.
    @State private var canIncludePhoto = false
    /// Set once the sheet has gone, so a file made after that is deleted, not kept.
    @State private var departure = Departure()
    /// The content's height: the sheet is no taller (the Lamplit Table, October 18: the empty band
    /// below the buttons read as something missing).
    @State private var contentHeight: CGFloat = 560

    var body: some View {
        // Scrolls when large text makes the sheet's content taller than its detent.
        ScrollView {
            VStack(spacing: 22) {
                page
                VStack(spacing: 4) {
                    Text("Send Template")
                        .font(.display(.title3))
                    Text(artwork.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)
                if canIncludePhoto {
                    Toggle(isOn: $includesPhoto) {
                        Label("Original Photo", systemImage: "photo.on.rectangle")
                    }
                    .accessibilityIdentifier("send-photo")
                    .disabled(isPreparing)
                }
                Text(Self.explanation(canIncludePhoto: canIncludePhoto, includesPhoto: includesPhoto,
                                      isPicture: artwork.sampleName != nil))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if failed {
                    Text("The painting couldn’t be prepared for sending.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button(action: send) {
                        if isPreparing {
                            ProgressView()
                                .accessibilityLabel(Text("Preparing…"))
                        } else {
                            Text("Send…")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.signature)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPreparing)
                    .accessibilityIdentifier("send-template")
                }
            }
            .padding(28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight)])
        .background {
            ActivityShareSheet(items: file.map { [$0] } ?? []) { completed in finishSharing(completed: completed) }
        }
        .task { await loadPreview() }
        // Swiped away with the file made, or still being made: it mustn't stay behind.
        .onDisappear {
            departure.hasLeft = true
            removeFile()
        }
    }

    /// The blank page on the canvas sheet's paper, dimmed by night (the Lamplit Table: a white
    /// page glared on the dark sheet, and read as cold).
    @ViewBuilder
    private var page: some View {
        Group {
            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .colorMultiply(paper)
            } else {
                paper
                    .aspectRatio(artwork.aspectRatio, contentMode: .fit)
            }
        }
        .frame(maxHeight: 220)
        .clipShape(.rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement()
        .accessibilityLabel(Text(String(
            localized: "send.preview", defaultValue: "A blank copy of “\(artwork.title)”",
            comment: "VoiceOver label of the page shown in Send Template; the argument is the painting's title")))
    }

    private var paper: Color {
        let tone = CanvasPalette.sheetPaperSRGB * (colorScheme == .dark ? 0.82 : 1)
        return Color(.sRGB, red: Double(tone.x), green: Double(tone.y), blue: Double(tone.z))
    }

    /// The note under the switch. A library picture (`isPicture`) is no one's own photo: sent, it
    /// is "the picture", and kept back there is nothing private to mention.
    static func explanation(canIncludePhoto: Bool, includesPhoto: Bool, isPicture: Bool) -> String {
        #if UNRELEASED
        if !canIncludePhoto || (isPicture && !includesPhoto) {
            String(localized: "send.explanation.noPhoto",
                   defaultValue: "They get a blank copy of this page to paint, your changes to the drawing included.",
                   comment: "Send Template's note when the painting has no photo to send, or is of a library picture with the Original Photo switch off")
        } else if isPicture {
            String(localized: "send.explanation.picture",
                   defaultValue: "They get a blank copy of this page to paint, your changes to the drawing included, and the picture to peek at.",
                   comment: "Send Template's note for a painting of a library picture (not the painter's own photo) with the Original Photo switch on")
        } else if includesPhoto {
            String(localized: "send.explanation.photo",
                   defaultValue: "They get a blank copy of this page to paint, your changes to the drawing included, and your photo to peek at.",
                   comment: "Send Template's note with the Original Photo switch on")
        } else {
            String(localized: "send.explanation.drawingOnly",
                   defaultValue: "They get a blank copy of this page to paint, your changes to the drawing included. Your photo stays on this device.",
                   comment: "Send Template's note with the Original Photo switch off")
        }
        #else
        // The release has no Refine: there are no changes to the drawing to mention.
        if !canIncludePhoto || (isPicture && !includesPhoto) {
            String(localized: "send.explanation.noPhoto.release",
                   defaultValue: "They get a blank copy of this page to paint.",
                   comment: "Send Template's note when the painting has no photo to send, or is of a library picture with the Original Photo switch off, in the release (which has no Refine, so no changes to the drawing to mention)")
        } else if isPicture {
            String(localized: "send.explanation.picture.release",
                   defaultValue: "They get a blank copy of this page to paint, and the picture to peek at.",
                   comment: "Send Template's note for a painting of a library picture (not the painter's own photo) with the Original Photo switch on, in the release (which has no Refine, so no changes to the drawing to mention)")
        } else if includesPhoto {
            String(localized: "send.explanation.photo.release",
                   defaultValue: "They get a blank copy of this page to paint, and your photo to peek at.",
                   comment: "Send Template's note with the Original Photo switch on, in the release (which has no Refine, so no changes to the drawing to mention)")
        } else {
            String(localized: "send.explanation.drawingOnly.release",
                   defaultValue: "They get a blank copy of this page to paint. Your photo stays on this device.",
                   comment: "Send Template's note with the Original Photo switch off, in the release (which has no Refine, so no changes to the drawing to mention)")
        }
        #endif
    }

    /// The blank page, and whether there is a photo to send: the painter's own, which travels as
    /// its bytes (a library picture's name goes with it).
    private func loadPreview() async {
        let store = library.store, id = artwork.id
        (preview, canIncludePhoto) = await Background.run {
            ((try? store.readTemplate(id)).flatMap { TemplateRasterizer.image($0, style: .thumbnail, maxPixelSize: 800) },
             store.hasSource(id))
        }
        #if DEBUG
        if ShellDemo.current?.sendsTemplate == true { DemoMode.markReady() }
        #endif
    }

    /// Writes the file off the main actor; the share sheet presents once it is there.
    private func send() {
        guard !isPreparing else { return }
        isPreparing = true
        failed = false
        let store = library.store, artwork = self.artwork, sendsPhoto = self.includesPhoto && canIncludePhoto
        let departure = self.departure
        Task {
            do {
                let made = try await Background.run {
                    let data = try ArtworkExporter.sharedPainting(store: store, artwork: artwork, includesPhoto: sendsPhoto)
                    return try ArtworkExporter.temporaryFile(
                        data, name: ArtworkExporter.templateName(title: artwork.title), pathExtension: SharedPaintingCodec.fileExtension)
                }
                if departure.hasLeft {
                    await Background.run { ArtworkExporter.removeExport(at: made) }
                } else {
                    file = made
                }
            } catch {
                Log.library.error("Preparing a template to send failed: \(String(describing: error), privacy: .public)")
                failed = true
            }
            isPreparing = false
        }
    }

    /// Sent, the sheet closes; backed out, it stays for another try or Cancel.
    private func finishSharing(completed: Bool) {
        removeFile()
        if completed { dismiss() }
    }

    private func removeFile() {
        guard let file else { return }
        self.file = nil
        Task { await Background.run { ArtworkExporter.removeExport(at: file) } }
    }

    /// Shared by reference with the task that makes the file, which outlives the sheet.
    final class Departure {
        var hasLeft = false
    }
}
