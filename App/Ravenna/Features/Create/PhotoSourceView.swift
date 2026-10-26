import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// First step of the create flow: the photo library inline, the camera, and samples.
///
/// The inline picker is the page's primary content and fills the remaining height. Compact
/// windows switch between it and the samples with a segmented control; wide windows show the
/// samples in a scrolling column beside it, in two sections: paintings, then photographs. The
/// picker's own top bar reaches the albums and search; "Browse All…" (iPad's toolbar) presents
/// the full system picker, a way in that doesn't depend on the embedded one taking taps.
///
/// iPhone doesn't embed the picker (`embedsPicker`): on Paul's iPhone its grid never took a tap,
/// though its bar did, after three layouts that each picked photos on the simulator (Sept 30,
/// Oct 4 and 9). The page offers Choose Photo there instead, which presents the full picker.
///
/// The picker meets the page's leading edge: inset from both the window's left and top edge,
/// the embedded picker's photo grid ignores taps on iPhone for its first ten seconds or so (its
/// bar takes them at once), measured on the iOS 26 simulator, where every layout that keeps the
/// picker flush with one of those edges picks a photo on the first tap. Compact widths run it
/// edge to edge; wide windows (600 pt and wider, `isWide`: a full-screen iPad) keep its card,
/// docked to that edge. The iPad simulator takes taps on an inset card, but a painter's iPad
/// didn't, so wide windows follow the same rule.
struct PhotoSourceView: View {
    enum Pane: Hashable { case photos, samples }

    let model: CreateModel
    var onClose: () -> Void
    var onPicked: () -> Void

    @State private var pane: Pane
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var browsedItem: PhotosPickerItem?
    @State private var isBrowsingAll = false
    @State private var isShowingCamera = false
    @State private var width: CGFloat = 0
    /// Tiles widen with the text size, so a caption keeps room at the largest sizes.
    @ScaledMetric(relativeTo: .subheadline) private var tileMinimumWidth: CGFloat = 150

    init(model: CreateModel, initialPane: Pane, onClose: @escaping () -> Void, onPicked: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        self.onPicked = onPicked
        _pane = State(initialValue: initialPane)
    }

    private var isWide: Bool { width >= 600 }
    private var horizontalPadding: CGFloat { isWide ? 32 : 20 }
    private let paneSpacing: CGFloat = 24
    private var showsPhotos: Bool { isWide || pane == .photos }
    private var showsSamples: Bool { isWide || pane == .samples }
    /// Wide windows pad only the samples' side: the picker's card meets the leading edge.
    private var samplesWidth: CGFloat { max(0, (width - horizontalPadding - paneSpacing) * 0.4) }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        // Deliberately not a ScrollView: the inline picker scrolls out of process, and UIKit
        // cannot arbitrate between its pan and an in-process ancestor's pan across that
        // boundary, so a drag that started on the picker moved neither.
        VStack(alignment: .leading, spacing: 14) {
            if !isWide { sourceTabs.padding(.horizontal, horizontalPadding) }
            panes
        }
        .padding(.top, 4)
        .padding(.bottom, isWide ? 24 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.paper)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .navigationTitle("New Painting")
        // Nothing scrolls to collapse a large title, and the picker needs the height.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark", action: onClose)
            }
            // iPhone's Photos pane is Choose Photo, the same picker: no second way to it here.
            if embedsPicker {
                ToolbarItem(placement: .primaryAction) {
                    Button("Browse All…", systemImage: "photo.on.rectangle.angled") { isBrowsingAll = true }
                        .help("Browse all photos and albums")
                        // Give the full picker its own presenter rather than the inline picker's
                        // ancestor: Browse All once stayed on the photo step with no sheet.
                        .photosPicker(isPresented: $isBrowsingAll, selection: $browsedItem, matching: .images, preferredItemEncoding: .current)
                }
            }
            if cameraAvailable {
                ToolbarItem(placement: .primaryAction) {
                    Button("Take Photo", systemImage: "camera") { isShowingCamera = true }
                }
            }
        }
        .onChange(of: libraryItems) { _, items in
            guard let item = items.first else { return }
            // Clearing the selection lets the same photo be picked again after coming back. The
            // item the picker then gives for it has no data (`CreateModel.load(item:)` keeps the
            // first pick's).
            libraryItems = []
            pick(item)
        }
        .onChange(of: browsedItem) { _, item in
            guard let item else { return }
            browsedItem = nil
            pick(item)
        }
        .onAppear { PaintTips.newPaintingOpened() }
        .onDisappear { PaintTips.desk.leave(.newPainting) }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { data in
                PaintTips.photoChosen()
                model.load(imageData: data)
                onPicked()
            } onFailure: {
                model.fail(.cameraCapture)
                onPicked()
            }
            .ignoresSafeArea()
        }
    }

    private var sourceTabs: some View {
        Picker("Photo Source", selection: $pane) {
            Text("Photos").tag(Pane.photos)
            Text("Samples").tag(Pane.samples)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("photo-source")
        // No Photo at Hand: hung below the control that switches to Samples.
        .gentleTip(.newPaintingSamples, arrowEdge: .top)
    }

    /// One layout for both widths, so the picker keeps its identity (and its loaded grid and
    /// scroll position) across rotation and resizing. On compact widths the samples stack on
    /// top of the hidden picker; they are never an ancestor of it, and it takes no touches.
    /// The page's horizontal padding is the samples' alone, so the picker reaches the window's
    /// leading edge: on compact widths it spans the window.
    private var panes: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: paneSpacing))
            : AnyLayout(ZStackLayout(alignment: .top))
        return layout {
            photosPane
                .opacity(showsPhotos ? 1 : 0)
                .allowsHitTesting(showsPhotos)
                .accessibilityHidden(!showsPhotos)
            if showsSamples {
                samplesPane
                    .frame(width: isWide ? samplesWidth : nil)
                    .padding(.horizontal, isWide ? 0 : horizontalPadding)
            }
        }
        .padding(.trailing, isWide ? horizontalPadding : 0)
    }

    private var photosPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isWide { SectionTitle("Your Photos").padding(.leading, horizontalPadding) }
            if embedsPicker { libraryPicker } else { photoChooser }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The embedded picker's grid takes no taps on an iPhone (the type's doc comment).
    private var embedsPicker: Bool { UIDevice.current.userInterfaceIdiom != .phone }

    /// iPhone's Photos pane: the full system picker, the one Browse All presents, a tap away.
    private var photoChooser: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Button("Choose Photo", systemImage: "photo") { isBrowsingAll = true }
                .buttonStyle(.glassProminent)
                .tint(Theme.signature)
                .controlSize(.large)
                .accessibilityIdentifier("choose-photo")
                // The full picker's presenter on iPhone, as Browse All's button is on iPad.
                .photosPicker(isPresented: $isBrowsingAll, selection: $browsedItem, matching: .images, preferredItemEncoding: .current)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, horizontalPadding)
    }

    private var libraryPicker: some View {
        // Continuous selection of at most one photo with the selection actions disabled:
        // a tap picks at once, with no Add button to confirm. The shared library gives the
        // items asset identifiers, which the embedded picker needs to show the reset to `[]`
        // as a deselect (so the same photo can be picked again); it needs no authorization,
        // as the picker still runs out of process.
        PhotosPicker(
            selection: $libraryItems, maxSelectionCount: 1, selectionBehavior: .continuous,
            matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()
        ) {
            Label("Choose Photo", systemImage: "photo.on.rectangle")
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities(.selectionActions)
        // Only the bottom bar goes: it carries selection status and actions, meaningless
        // when a tap picks. The top bar stays for Photos/Albums, search and the album back button.
        .photosPickerAccessoryVisibility(.hidden, edges: .bottom)
        .accessibilityIdentifier("library-picker")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The card only on wide windows, square where it meets the leading edge (see the
        // type's doc comment), through the same modifiers in both cases so the picker keeps
        // its identity when the width changes.
        .background(Theme.surface.opacity(isWide ? 1 : 0))
        .clipShape(cardShape)
        .overlay { cardShape.strokeBorder(Theme.hairline, lineWidth: isWide ? 0.5 : 0) }
    }

    private var cardShape: UnevenRoundedRectangle {
        let radius = isWide ? Theme.cardRadius : 0
        return UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous)
    }

    private var samplesPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isWide {
                // Wide windows show the samples beside the photos: the tip points at their title.
                SectionTitle("Samples")
                    .gentleTip(.newPaintingSamples, arrowEdge: .top)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(Sample.Kind.allCases, id: \.self) { kind in
                            let samples = Sample.all(of: kind)
                            if !samples.isEmpty { samplesSection(kind, samples: samples) }
                        }
                    }
                    // Room for the press scale and hover lift inside the scroll view's clip.
                    .padding(4)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                #if DEBUG
                .onChange(of: isWide, initial: true) {
                    // Again when the width arrives: the pane first lays out compact.
                    if let kind = ShellDemo.current?.samplesSection { proxy.scrollTo(kind, anchor: .top) }
                }
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func samplesSection(_ kind: Sample.Kind, samples: [Sample]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(kind)
                .id(kind)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth), spacing: 14)], spacing: 14) {
                ForEach(samples) { sample in
                    Button {
                        PaintTips.photoChosen()
                        model.load(sample: sample)
                        onPicked()
                    } label: {
                        SampleTile(sample: sample)
                    }
                    .buttonStyle(PressableCardStyle())
                }
            }
        }
    }

    /// Under the wide layout's "Samples" the sections are subheadings; compact windows, where
    /// the segmented control names the pane, give them the title size.
    @ViewBuilder
    private func sectionTitle(_ kind: Sample.Kind) -> some View {
        let style: Font.TextStyle = isWide ? .headline : .title3
        switch kind {
        case .painting: SectionTitle("Paintings", style: style)
        case .photograph: SectionTitle("Photographs", style: style)
        }
    }

    /// The grid's minimum tile width, never wider than the column (the press-scale padding
    /// taken off), so a tile scaled up for a large text size still fits.
    private var tileWidth: CGFloat {
        let column = (isWide ? samplesWidth : width - 2 * horizontalPadding) - 8
        return column > 0 ? min(tileMinimumWidth, column) : tileMinimumWidth
    }

    /// Shared by the inline picker and Browse All.
    private func pick(_ item: PhotosPickerItem) {
        PaintTips.photoChosen()
        model.load(item: item)
        onPicked()
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey
    let style: Font.TextStyle
    init(_ title: LocalizedStringKey, style: Font.TextStyle = .title3) {
        self.title = title
        self.style = style
    }

    var body: some View {
        Text(title)
            .font(.display(style))
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SampleTile: View {
    let sample: Sample
    @State private var image: CGImage?

    var body: some View {
        Color.clear
            .aspectRatio(4 / 3, contentMode: .fit)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                caption
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Starts above the caption and is dark by its first line: white spray or sky
                    // behind a title (The Great Wave's) left it unreadable.
                    .background(alignment: .bottom) {
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.5), location: 0.45),
                                    .init(color: .black.opacity(0.72), location: 1)],
                            startPoint: .top, endPoint: .bottom)
                            .padding(.top, -28)
                    }
            }
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect(cornerRadius: 18, style: .continuous))
            .contentShape(.hoverEffect, .rect(cornerRadius: 18, style: .continuous))
            .hoverEffect(.lift)
            .task {
                let loaded = await SampleImages.shared.load(sample, maxPixelSize: 640)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    /// The title, and under a painting's its painter when the tile has room for both: long
    /// text and large sizes drop the painter first, then truncate the title.
    private var caption: some View {
        ViewThatFits(in: .vertical) {
            if let painter {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    Text(painter)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .opacity(0.9)
                }
            }
            title
        }
    }

    private var title: some View {
        Text(sample.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
    }

    /// A painting's creator, shown under its title: the painter is part of how people know a
    /// painting, a photographer rarely is. VoiceOver hears the creator of both.
    private var painter: String? {
        guard let provenance = sample.provenance, provenance.kind == .painting else { return nil }
        return provenance.creator
    }

    private var accessibilityLabel: String {
        guard let creator = sample.provenance?.creator else {
            return String(localized: "create.sample.label", defaultValue: "Sample: \(sample.title)",
                          comment: "VoiceOver label of a sample picture's tile when nobody is credited for it; the argument is its title")
        }
        return String(localized: "create.sample.labelWithCreator", defaultValue: "Sample: \(sample.title), \(creator)",
                      comment: "VoiceOver label of a sample picture's tile; the arguments are its title and who made it, e.g. “Sample: The Great Wave, Katsushika Hokusai”")
    }
}
