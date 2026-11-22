// Copyright 2026 Wayne W Bishop. All rights reserved.
//
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not use this
// file except in compliance with the License. You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
// ANY KIND, either express or implied. See the License for the specific language governing
// permissions and limitations under the License.

import Foundation
import Observation
import StoreKit

/// Owns the learner's Coquille Pro state, the way `StatsStore` and `Journal` own theirs.
///
/// Views ask one question, `hasPro`, and never talk to StoreKit themselves. StoreKit 2
/// checks every transaction on the device, so there is no server. It also keeps the
/// entitlements, so a launch with no network still sees Pro.
///
/// Whether the learner has Pro comes from the verified current entitlements. The
/// subscription's status only adds detail: a trial, a renewal date, a cancellation or a
/// billing problem. A status that can't be read never takes Pro away.
@MainActor
@Observable
final class ProStore {

    /// Where the learner stands now.
    private(set) var access: ProAccess = .free
    /// Whether the first look at the entitlements has finished.
    private(set) var hasLoaded = false
    /// Whether a purchase is waiting on another step, kept apart from `access` so a
    /// refresh can't erase it. It clears when Pro turns on.
    private(set) var hasPendingPurchase = false

    /// Whether Pro features are on.
    var hasPro: Bool { access.hasPro }

    /// Whether the gates should let a feature through: the learner has Pro, or the first
    /// look at the entitlements hasn't finished, so a paying learner never sees the paywall
    /// or the free limit for a moment at launch.
    var grantsFeatures: Bool { hasPro || !hasLoaded }

    @ObservationIgnored private var listeners: [Task<Void, Never>] = []

    /// Starts listening for transactions and status changes, then reads the current state.
    ///
    /// Pass `listensForUpdates: false` in tests that drive `refresh()` themselves.
    init(listensForUpdates: Bool = true) {
        guard listensForUpdates else { return }
        // The sequences are made before the first refresh, so nothing that arrives while
        // it runs is missed.
        let transactions = Transaction.updates
        let statuses = Product.SubscriptionInfo.Status.updates
        listeners = [
            Task { [weak self] in
                await self?.refresh()
                for await result in transactions {
                    guard let self else { return }
                    try? await self.handle(result)
                }
            },
            Task { [weak self] in
                for await _ in statuses {
                    guard let self else { return }
                    await self.refresh()
                }
            }
        ]
    }

    deinit {
        listeners.forEach { $0.cancel() }
    }

    // MARK: - Completing transactions

    /// Thrown when StoreKit can't verify a transaction, so Pro isn't turned on for it.
    struct UnverifiedTransaction: LocalizedError {
        var errorDescription: String? {
            "The App Store couldn't verify this purchase. Try Restore Purchases, or contact Apple Support if you were charged."
        }
    }

    /// The one place a transaction is completed, for a purchase made in the paywall and for
    /// one that arrives on its own, such as a renewal, a refund or a purchase on another
    /// device: verify it, apply the access it gives, then finish it.
    ///
    /// - Throws: `UnverifiedTransaction` when StoreKit can't verify it. The transaction is
    ///   left unfinished, so StoreKit offers it again.
    func handle(_ result: VerificationResult<Transaction>) async throws {
        guard case .verified(let transaction) = result else { throw UnverifiedTransaction() }
        await refresh(including: transaction)
        await transaction.finish()
    }

    // MARK: - Reading the state

    /// Reads the entitlements and the subscription's status again. A transaction just
    /// verified counts at once, without waiting for the entitlements to list it.
    func refresh(including verified: Transaction? = nil) async {
        var entitlement = await Self.currentEntitlement()
        if let verified, Self.isEntitling(verified),
           entitlement == nil || verified.purchaseDate > entitlement!.purchaseDate {
            entitlement = verified
        }
        let statuses = (try? await Product.SubscriptionInfo.status(for: ProductIDs.groupID)) ?? []
        access = resolve(entitlement: entitlement, statuses: statuses)
        if access.hasPro { hasPendingPurchase = false }
        hasLoaded = true
    }

    /// The learner's verified, unrevoked and unexpired transaction for the subscription group.
    private static func currentEntitlement() async -> Transaction? {
        var latest: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, isEntitling(transaction) else { continue }
            if latest == nil || transaction.purchaseDate > latest!.purchaseDate { latest = transaction }
        }
        return latest
    }

    /// Whether a transaction is the annual subscription, not revoked and not expired.
    private static func isEntitling(_ transaction: Transaction) -> Bool {
        guard transaction.productID == ProductIDs.annual, transaction.revocationDate == nil else { return false }
        if let expires = transaction.expirationDate, expires <= .now { return false }
        return true
    }

    /// Combines the entitlement, which decides Pro, with the status, which describes it.
    private func resolve(entitlement: Transaction?, statuses: [Product.SubscriptionInfo.Status]) -> ProAccess {
        let verified = statuses.compactMap { status -> (state: Product.SubscriptionInfo.RenewalState, transaction: Transaction, renewal: Product.SubscriptionInfo.RenewalInfo?)? in
            guard case .verified(let transaction) = status.transaction else { return nil }
            var renewal: Product.SubscriptionInfo.RenewalInfo?
            if case .verified(let info) = status.renewalInfo { renewal = info }
            return (status.state, transaction, renewal)
        }

        if let entitlement {
            // Entitled: describe it from the status that matches, or plainly if there is none.
            let match = verified.first { $0.transaction.originalID == entitlement.originalID }
            let end = entitlement.expirationDate
            if match?.state == .inGracePeriod || match?.state == .inBillingRetryPeriod {
                return .billingProblem
            }
            if entitlement.offer?.type == .introductory { return .trial(ends: end) }
            if match?.renewal?.willAutoRenew == false { return .cancelledButActive(expires: end) }
            return .renewing(renews: end)
        }

        if hasPendingPurchase { return .purchasePending }
        // Not entitled: say Pro ended when there is a subscription that lapsed.
        if let ended = verified.first {
            return .expired(ended: ended.transaction.revocationDate ?? ended.transaction.expirationDate)
        }
        return .free
    }

    // MARK: - Buying and restoring

    /// Syncs with the App Store, for Restore Purchases, then reads the state again.
    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    /// Notes that a purchase is pending, since StoreKit reports it only at the moment of
    /// buying. It stays until Pro turns on or the learner restores.
    func notePurchasePending() {
        guard !hasPro else { return }
        hasPendingPurchase = true
        access = .purchasePending
    }
}
