#if DEBUG
import Foundation
import StoreKit
import SwiftUI

/// Debug launches' stand-in for the App Store in demos and the test host, so no test or CI run
/// asks it for anything (`UnlimitedPaintings.forLaunch`). The free paintings are counted in memory
/// on a clock stopped at launch: each launch starts over, and a test that runs past midnight isn't
/// given one back. Its launch arguments:
///
/// - `-demoFreePaintings <n>`: the free paintings left at launch (three, or the scenario's
///   `ShellDemo.freePaintings`, when not given);
/// - `-demoUnlocked YES`: Unlimited Paintings already bought;
/// - `-demoPurchase fail|pending|cancel`: what buying does (by default it unlocks, after a moment).
///
/// Debug builds only: Release has neither this type nor the arguments (`ci/check_release.sh`).
final class UnlockStoreStub: UnlockStore {
    enum Purchase: String {
        case unlocks, fails = "fail", pending, cancelled = "cancel"
    }

    private(set) var owned: Bool
    var purchase: Purchase
    /// What Restore Purchases finds.
    var restorable: Bool
    private(set) var purchases = 0

    init(owned: Bool = false, purchase: Purchase = .unlocks, restorable: Bool = false) {
        self.owned = owned
        self.purchase = purchase
        self.restorable = restorable
    }

    func price() async throws -> String { "$4.99" }

    func isOwned() async -> Bool { owned }

    func buy(with _: PurchaseAction?) async throws -> UnlimitedPaintings.Outcome {
        purchases += 1
        try await Task.sleep(for: .milliseconds(300))
        switch purchase {
        case .unlocks:
            owned = true
            return .unlocked
        case .fails: throw UnlockError.unavailable
        case .pending: return .pending
        case .cancelled: return .cancelled
        }
    }

    func restore() async throws {
        if restorable { owned = true }
    }

    func followChanges(_: @escaping @MainActor () async -> Void) async {}

    /// The launch's, as its arguments and scenario say.
    static func paintingsForLaunch() -> UnlimitedPaintings {
        let arguments = UserDefaults.standard
        let stub = UnlockStoreStub(
            owned: arguments.bool(forKey: "demoUnlocked"),
            purchase: arguments.string(forKey: "demoPurchase").flatMap(Purchase.init(rawValue:)) ?? .unlocks)
        let launch = Date.now
        let left = arguments.string(forKey: "demoFreePaintings").flatMap(Int.init) ?? ShellDemo.current?.freePaintings
        let free = left.map { FreePaintings(left: $0, since: Calendar.autoupdatingCurrent.startOfDay(for: launch)) }
        let paintings = UnlimitedPaintings(store: stub, defaults: nil, free: free, now: { launch })
        paintings.follow()
        return paintings
    }
}
#endif
