import SwiftUI

/// The collection: each work's painted bed, as a setter finds the wall before the tesserae go in,
/// and how far the painter has set it.
struct GalleryView: View {
    @Environment(Library.self) private var library
    @State private var showingOptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ravenna").font(Theme.title(40)).foregroundStyle(Theme.plaster)
                        Text("Ancient pictures, laid as mosaics. Choose one and set it, tile by tile.")
                            .font(Theme.body(16)).foregroundStyle(Theme.muted)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 22) {
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
        }
    }
}

private struct WorkCard: View {
    @Environment(Library.self) private var library
    let work: Work

    var body: some View {
        let progress = library.progress(work)
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let bed = library.image(work, "bed") {
                    Image(uiImage: bed).resizable().scaledToFill()
                } else {
                    Theme.panel
                }
            }
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
                .lineLimit(2)
            Text("\(work.place), \(work.date)").font(Theme.body(13)).foregroundStyle(Theme.muted)
            if progress > 0 {
                Text(progress >= 1 ? "Set" : "\(Int((progress * 100).rounded(.down)))% set")
                    .font(.caption.monospacedDigit()).foregroundStyle(progress >= 1 ? Theme.gold : Theme.muted)
            }
        }
        .contentShape(Rectangle())
    }
}
