import StoreKit
import SwiftUI

/// Unlimited Paintings' sheet (`UnlimitedPaintings`): what it unlocks, its price and Restore
/// Purchases. Start Painting opens it when a painting of the painter's own photo finds no free
/// painting left (`fromStart`), Settings at any time. It closes itself once the unlock is bought,
/// and Start Painting then goes on. Present it as a sheet.
struct UnlockSheet: View {
    /// Opened by Start Painting with no free painting left.
    var fromStart = false
    @Environment(UnlimitedPaintings.self) private var paintings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var isBuying = false
    @State private var isRestoring = false
    @State private var note: Note?
    /// The content's height: the sheet is no taller.
    @State private var contentHeight: CGFloat = 420

    private enum Note: Equatable {
        /// Ask to Buy: the purchase waits for approval.
        case pending
        case nothingToRestore
        case failed(String)
    }

    var body: some View {
        // Scrolls when large text makes the sheet's content taller than its detent.
        ScrollView {
            VStack(spacing: 22) {
                MoonMark()
                VStack(spacing: 8) {
                    Text("Unlimited Paintings")
                        .font(.display(.title3))
                        .accessibilityAddTraits(.isHeader)
                    Group {
                        if fromStart {
                            Text("Your next free painting comes tomorrow. One purchase unlocks as many paintings of your own photos as you like.")
                        } else {
                            Text("One purchase unlocks as many paintings of your own photos as you like.")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                if let note {
                    noteText(note)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("unlock-note")
                }
                // Side by side while they fit, the price first once they don't (large text).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        notNowButton
                        buyButton
                    }
                    VStack(spacing: 12) {
                        buyButton
                        notNowButton
                    }
                }
                // One quiet line when it fits (the Lamplit Table: Rikyū).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        samplesNote
                        restoreButton
                    }
                    VStack(spacing: 6) {
                        samplesNote
                        restoreButton
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // At accessibility sizes the content outgrows any sheet: it opens full height, and scrolls.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
        .task { await loadPrice() }
        // Bought here, restored, or approved while the sheet was up (Ask to Buy).
        .onChange(of: paintings.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    private var notNowButton: some View {
        Button("Not Now") { dismiss() }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("unlock-not-now")
    }

    private var buyButton: some View {
        Button(action: buy) { buyLabel }
            .buttonStyle(.glassProminent)
            .tint(Theme.signature)
            .keyboardShortcut(.defaultAction)
            .disabled(isBuying || isRestoring)
            .accessibilityIdentifier("unlock-buy")
    }

    private var samplesNote: some View {
        Text("Everything in Samples is always free.")
            .foregroundStyle(.secondary)
    }

    private var restoreButton: some View {
        Button("Restore Purchases", action: restore)
            .disabled(isBuying || isRestoring)
            .accessibilityIdentifier("unlock-restore")
    }

    /// While buying, the price stays under the spinner, so the button keeps its width and the
    /// buttons their layout.
    @ViewBuilder
    private var buyLabel: some View {
        if let price = paintings.price {
            Text(String(localized: "unlock.buy", defaultValue: "Unlock for \(price)",
                        comment: "The Unlimited Paintings sheet's buy button; the argument is the price as the App Store writes it (\"$4.99\")"))
                .opacity(isBuying ? 0 : 1)
                .accessibilityHidden(isBuying)
                .overlay {
                    if isBuying {
                        ProgressView()
                            .accessibilityLabel(Text("Unlocking…"))
                    }
                }
        } else if case .failed = note {
            Text("Try Again")
        } else {
            ProgressView()
                .accessibilityLabel(Text("Loading…"))
        }
    }

    @ViewBuilder
    private func noteText(_ note: Note) -> some View {
        switch note {
        case .pending:
            Text("Waiting for approval. Your paintings unlock as soon as it comes.")
                .foregroundStyle(.secondary)
        case .nothingToRestore:
            Text("This Apple Account hasn’t bought Unlimited Paintings yet.")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }

    private func loadPrice() async {
        do {
            try await paintings.loadPrice()
            #if DEBUG
            if ShellDemo.current == .createUnlock { DemoMode.markReady() }
            #endif
        } catch {
            note = .failed(error.localizedDescription)
        }
    }

    /// Buys the unlock once the price is there; without it (the App Store out of reach), asks for
    /// the price again.
    private func buy() {
        guard !isBuying else { return }
        note = nil
        guard paintings.price != nil else {
            Task { await loadPrice() }
            return
        }
        isBuying = true
        Task {
            do {
                if try await paintings.buy(with: purchase) == .pending { note = .pending }
            } catch StoreKitError.userCancelled {
                // Closing the App Store's own sheet says enough.
            } catch {
                note = .failed(error.localizedDescription)
            }
            isBuying = false
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        note = nil
        isRestoring = true
        Task {
            do {
                try await paintings.restore()
                if !paintings.isUnlocked { note = .nothingToRestore }
            } catch StoreKitError.userCancelled {
                // The painter didn't sign in: nothing to say.
            } catch {
                note = .failed(error.localizedDescription)
            }
            isRestoring = false
        }
    }
}

/// The design system's crescent inked in gold with two of the Moon's stars, as night brings them
/// over a painting finished by night (`Nightfall`): the app's own moon, not a system symbol (the
/// Lamplit Table: Originality).
private struct MoonMark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 36

    var body: some View {
        let side = side, gold = Theme.gold
        return Canvas { context, _ in
            let moon = CGRect(x: side * 0.05, y: side * 0.2, width: side, height: side)
            context.stroke(Path(Crescent.cgPath(in: moon)), with: .color(gold),
                           style: StrokeStyle(lineWidth: max(2, side * 0.06), lineCap: .round, lineJoin: .round))
            for (centre, size) in [(CGPoint(x: side * 1.3, y: side * 0.3), side * 0.34), (CGPoint(x: side * 1.55, y: side * 0.78), side * 0.24)] {
                let star = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
                context.fill(Path(Sparkle.starPath(in: star)), with: .color(gold))
            }
        }
        .frame(width: side * 1.75, height: side * 1.25)
        .accessibilityHidden(true)
    }
}
