import Foundation
import Observation
import os
import StoreKit
import SwiftUI

/// Unlimited Paintings, the app's one purchase (Paul, October 22): paid once, it lets a painter
/// make as many paintings of their own photos as they like. Without it they have `FreePaintings`;
/// library pictures, paintings someone sent and paintings made again are always free. Start
/// Painting asks `mayStart(ownPhoto:)` and reports `started(ownPhoto:)`; `UnlockSheet` sells it.
///
/// Purchases are checked on the device by StoreKit 2 (`StoreKitUnlock`): no server and no account
/// of ours, nothing sent but what the App Store itself handles. App Store Connect holds the
/// product, `productID`, a non-consumable with Family Sharing on; `App/UnlimitedPaintings.storekit`
/// stands in for it in Xcode runs (Edit Scheme › Run › Options › StoreKit Configuration).
///
/// SideStore builds sell nothing, a sideloaded app being unable to buy from the App Store: there
/// everything is unlocked (`isSold` false). Debug launches for demos and tests ask
/// `UnlockStoreStub` instead of the App Store.
@Observable
final class UnlimitedPaintings {
    static let productID = "com.pbordjadze.paintbynumber.unlimited"
    /// Where the free paintings are counted (UserDefaults).
    static let freeKey = "freePaintings"

    /// Whether this build sells the unlock: every build but SideStore's.
    let isSold: Bool
    /// Bought, or sold nowhere and so unlimited anyway.
    private(set) var isUnlocked: Bool
    /// The unlock's price as the App Store writes it, once loaded.
    private(set) var price: String?
    private(set) var free: FreePaintings

    @ObservationIgnored private let store: (any UnlockStore)?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    /// The App Store has answered whether the unlock is owned.
    @ObservationIgnored private var hasChecked = false
    @ObservationIgnored private var follower: Task<Void, Never>?

    /// What buying came to.
    enum Outcome: Equatable {
        case unlocked
        /// Waiting for someone's approval (Ask to Buy): `follow` hears when it comes.
        case pending
        case cancelled
    }

    /// `store` nil sells nothing (SideStore). `defaults` nil counts the free paintings in memory.
    init(store: (any UnlockStore)?, defaults: UserDefaults?, free: FreePaintings? = nil,
         calendar: Calendar = .autoupdatingCurrent, now: @escaping () -> Date = { .now }) {
        self.store = store
        isSold = store != nil
        isUnlocked = store == nil
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.free = free ?? Self.stored(in: defaults)
    }

    /// The running app's: the App Store, or nothing to sell in SideStore builds (Debug builds: the
    /// stub for demos and the test host).
    static func forLaunch() -> UnlimitedPaintings {
        #if UNRELEASED && !DEBUG
        return UnlimitedPaintings(store: nil, defaults: nil)
        #else
        #if DEBUG
        if DemoMode.isActive || DemoMode.isTestHost { return UnlockStoreStub.paintingsForLaunch() }
        #endif
        let paintings = UnlimitedPaintings(store: StoreKitUnlock(), defaults: .standard)
        paintings.follow()
        return paintings
        #endif
    }

    /// Free paintings left now.
    var freeLeft: Int { free.at(now(), calendar: calendar).left }

    /// Whether a painting may start: one of a library picture always may, one of the painter's own
    /// photo once the unlock is bought or while a free painting is left. The first time, it asks
    /// the App Store (on the device) what is owned.
    func mayStart(ownPhoto: Bool) async -> Bool {
        guard ownPhoto, isSold else { return true }
        if !hasChecked { await refresh() }
        return isUnlocked || freeLeft > 0
    }

    /// A painting started: one of the painter's own photo took a free painting, unless the unlock
    /// is bought.
    func started(ownPhoto: Bool) {
        guard ownPhoto, isSold, !isUnlocked else { return }
        var free = self.free
        guard free.use(at: now(), calendar: calendar) else { return }
        self.free = free
        guard let defaults, let data = try? JSONEncoder().encode(free) else { return }
        defaults.set(data, forKey: Self.freeKey)
    }

    /// Asks the App Store whether the unlock is owned: bought, shared by the family, not refunded.
    func refresh() async {
        guard let store else { return }
        isUnlocked = await store.isOwned()
        hasChecked = true
    }

    func loadPrice() async throws {
        guard let store, price == nil else { return }
        price = try await store.price()
    }

    /// Buys the unlock with SwiftUI's purchase action (the sheet's; the stub needs none).
    func buy(with purchase: PurchaseAction?) async throws -> Outcome {
        guard let store else { return .unlocked }
        let outcome = try await store.buy(with: purchase)
        if outcome == .unlocked {
            isUnlocked = true
            hasChecked = true
            Log.store.notice("Unlimited Paintings bought")
        }
        return outcome
    }

    /// Asks the App Store for what this Apple Account has bought, then checks again.
    func restore() async throws {
        guard let store else { return }
        try await store.restore()
        await refresh()
    }

    /// Follows the App Store's changes for as long as the app runs (a purchase approved later by
    /// Ask to Buy, made on another device or by the family, or refunded), then checks what is owned.
    func follow() {
        guard let store, follower == nil else { return }
        follower = Task { [weak self] in
            await store.followChanges { [weak self] in await self?.refresh() }
        }
        Task { [weak self] in await self?.refresh() }
    }

    private static func stored(in defaults: UserDefaults?) -> FreePaintings {
        guard let data = defaults?.data(forKey: freeKey) else { return FreePaintings() }
        return (try? JSONDecoder().decode(FreePaintings.self, from: data)) ?? FreePaintings()
    }
}

/// Where the unlock is bought: the App Store (`StoreKitUnlock`) or, in Debug launches for demos and
/// tests, `UnlockStoreStub`.
protocol UnlockStore {
    /// The price as the App Store writes it.
    func price() async throws -> String
    func isOwned() async -> Bool
    func buy(with purchase: PurchaseAction?) async throws -> UnlimitedPaintings.Outcome
    func restore() async throws
    /// Calls `changed` after each transaction the App Store reports; returns only if it stops.
    func followChanges(_ changed: @escaping @MainActor () async -> Void) async
}

/// Why the unlock couldn't be bought.
nonisolated enum UnlockError: LocalizedError, Equatable {
    /// The App Store has no such product for us right now: offline, or not set up.
    case unavailable
    /// The App Store's answer didn't verify as signed by it.
    case unverified

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "unlock.error.unavailable",
                   defaultValue: "Unlimited Paintings can’t be bought right now. Check your connection and try again.",
                   comment: "Message in the Unlimited Paintings sheet when the App Store can't offer the purchase (offline, or the store isn't reachable)")
        case .unverified:
            String(localized: "unlock.error.unverified",
                   defaultValue: "The App Store couldn’t confirm the purchase. Try Restore Purchases in a moment.",
                   comment: "Message in the Unlimited Paintings sheet when a purchase's receipt couldn't be verified; Restore Purchases is the sheet's button")
        }
    }
}

/// The App Store, through StoreKit 2: products, purchases and what this Apple Account owns, all
/// verified on the device.
final class StoreKitUnlock: UnlockStore {
    private var product: Product?

    func price() async throws -> String { try await loadProduct().displayPrice }

    func isOwned() async -> Bool {
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.productID == UnlimitedPaintings.productID, transaction.revocationDate == nil { return true }
        }
        return false
    }

    func buy(with purchase: PurchaseAction?) async throws -> UnlimitedPaintings.Outcome {
        guard let purchase else { throw UnlockError.unavailable }
        let product = try await loadProduct()
        switch try await purchase(product, options: []) {
        case .success(.verified(let transaction)):
            await transaction.finish()
            return .unlocked
        case .success(.unverified):
            throw UnlockError.unverified
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws { try await AppStore.sync() }

    func followChanges(_ changed: @escaping @MainActor () async -> Void) async {
        for await update in StoreKit.Transaction.updates {
            if case .verified(let transaction) = update { await transaction.finish() }
            await changed()
        }
    }

    private func loadProduct() async throws -> Product {
        if let product { return product }
        guard let loaded = try await Product.products(for: [UnlimitedPaintings.productID]).first else {
            Log.store.error("The App Store has no product \(UnlimitedPaintings.productID, privacy: .public)")
            throw UnlockError.unavailable
        }
        product = loaded
        return loaded
    }
}
