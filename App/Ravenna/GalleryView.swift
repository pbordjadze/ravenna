import PhotosUI
import SwiftUI

/// The collection: the painter's own mosaics and the ancient works, each shown by its painted bed,
/// as a setter finds the wall before the tesserae go in, and how far the painter has set it.
struct GalleryView: View {
    @Environment(Library.self) private var library
    @State private var path: [Work] = []
    @State private var showingOptions = false
    @State private var picked: PhotosPickerItem?
    @State private var photo: PickedPhoto?
    @State private var removing: Work?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ravenna").font(Theme.title(40)).foregroundStyle(Theme.plaster)
                            .accessibilityAddTraits(.isHeader)
                        Text("Pictures laid as mosaics. Choose one and set it, tile by tile.")
                            .font(Theme.body(16)).foregroundStyle(Theme.muted)
                    }
                    shelf("Yours", note: library.own.isEmpty ? "None yet. A photo you choose is laid here, on this device, and never leaves it." : nil) {
                        PhotosPicker(selection: $picked, matching: .images) {
                            VStack(spacing: 10) {
                                Image(systemName: "square.grid.3x3.square").font(.system(size: 34))
                                Text("New from a photo").font(Theme.body(15))
                            }
                            .foregroundStyle(Theme.tint)
                            .frame(maxWidth: .infinity, minHeight: 210)
                            .background(Theme.panel)
                        }
                        ForEach(library.own) { work in
                            NavigationLink(value: work) { WorkCard(work: work) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Remove", systemImage: "trash", role: .destructive) { removing = work }
                                }
                                .accessibilityAction(named: "Remove") { removing = work }
                        }
                    }
                    shelf("From the Met") {
                        ForEach(library.works) { work in
                            NavigationLink(value: work) { WorkCard(work: work) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Theme.ground)
            .navigationDestination(for: Work.self) { SettingView(work: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Options", systemImage: "slider.horizontal.3") { showingOptions = true }
                }
            }
            .sheet(isPresented: $showingOptions) { OptionsView() }
            .sheet(item: $photo) { p in
                NewMosaicView(data: p.data) { work in path.append(work) }
            }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { photo = PickedPhoto(data: data) }
                    picked = nil
                }
            }
            #if DEBUG
            .task { await shoot() }
            #endif
            .confirmationDialog("Remove this mosaic?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) { if let w = removing { library.remove(w) }; removing = nil }
            } message: {
                Text("The mosaic and your work on it go. Your photo stays in your library.")
            }
        }
    }

    #if DEBUG
    /// CI's screenshots (the `[shots]` job): `RAVENNA_SHOT` names the screen to open, with the
    /// state it needs. Debug builds only.
    private func shoot() async {
        guard let shot = ProcessInfo.processInfo.environment["RAVENNA_SHOT"], library.works.count >= 5 else { return }
        let d = UserDefaults.standard, w = library.works
        d.set(shot == "lesson" ? 0 : 2, forKey: Keys.lesson)
        d.set(shot == "gold" ? GroundChoice.gold.rawValue : GroundChoice.picture.rawValue, forKey: Keys.ground)
        func fill(_ work: Work, _ fraction: Double) async {
            guard let m = try? await library.mosaic(work, library.detail) else { return }
            library.save(Setting(set: Set(0..<Int(Double(m.tiles.count) * fraction))), work, library.detail)
        }
        await fill(w[2], 0.4)
        await fill(w[0], 1)
        await fill(w[1], 1)
        await fill(w[4], 0)
        switch shot {
        case "options": showingOptions = true
        case "new": if let data = library.image(w[3], "photo")?.jpegData(compressionQuality: 0.9) { photo = PickedPhoto(data: data) }
        case "wall": path = [w[2]]
        case "lesson": path = [w[4]]
        case "finished": path = [w[0]]
        case "gold": path = [w[1]]
        default: break
        }
    }
    #endif

    private func shelf<Content: View>(_ title: String, note: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.title(20)).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            if let note { Text(note).font(Theme.body(14)).foregroundStyle(Theme.muted) }
            // One column at the largest text sizes, so titles have room.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 300 : 160), spacing: 16, alignment: .top)], spacing: 22) { content() }
        }
    }
}

/// A photo picked for a new mosaic.
struct PickedPhoto: Identifiable {
    let id = UUID()
    let data: Data
}

private struct WorkCard: View {
    @Environment(Library.self) private var library
    @Environment(\.dynamicTypeSize) private var typeSize
    let work: Work

    var body: some View {
        let progress = library.progress(work)
        VStack(alignment: .leading, spacing: 8) {
            Cover(work: work)
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottom) {
                GeometryReader { g in
                    Rectangle().fill(progress >= 1 ? Theme.gold : Theme.tint).frame(width: g.size.width * progress, height: 3)
                }
                .frame(height: 3)
            }
            Text(work.title).font(Theme.body(16).weight(.medium)).foregroundStyle(Theme.plaster)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
            Text(work.isOwn ? work.place : "\(work.place), \(work.date)").font(Theme.body(13)).foregroundStyle(Theme.muted)
            if progress > 0 {
                Text(progress >= 1 ? "Set" : "\(Int((progress * 100).rounded(.down)))% set")
                    .font(.caption.monospacedDigit()).foregroundStyle(progress >= 1 ? Theme.gold : Theme.muted)
            }
        }
        .contentShape(Rectangle())
        // One card, read as one: its title, where it's from, how far it's set.
        .accessibilityElement(children: .combine)
    }
}
