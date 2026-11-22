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

import StoreKit
import StoreKitTest
import XCTest
@testable import quiver_demo_coquille

/// Drives `ProStore` against the local `Coquille.storekit` file: buy, trial, expire, refund.
@MainActor
final class ProStoreTests: XCTestCase {

    /// The local StoreKit file at the repository's root.
    private static let configuration = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Coquille.storekit")

    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(contentsOf: Self.configuration)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        session.timeRate = .realTime
        addTeardownBlock {
            session.clearTransactions()
            session.resetToDefaultState()
        }
        return session
    }

    /// Refreshes until `done` holds or about eight seconds pass, since the test session
    /// applies an expiry or refund a moment after it's asked.
    private func refresh(_ store: ProStore, until done: (ProStore) -> Bool) async {
        for _ in 0..<80 {
            await store.refresh()
            if done(store) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // Access states decide Pro the way the plan says.
    func testWhichStatesGrantPro() {
        XCTAssertTrue(ProAccess.trial(ends: nil).hasPro)
        XCTAssertTrue(ProAccess.renewing(renews: nil).hasPro)
        XCTAssertTrue(ProAccess.cancelledButActive(expires: nil).hasPro)
        XCTAssertTrue(ProAccess.billingProblem.hasPro)
        XCTAssertFalse(ProAccess.free.hasPro)
        XCTAssertFalse(ProAccess.purchasePending.hasPro)
        XCTAssertFalse(ProAccess.expired(ended: nil).hasPro)
    }

    // With no purchase, the learner is Free. (Intro-offer eligibility isn't asserted: the test
    // session remembers a used offer between tests, so only real sandbox testing can prove it.)
    func testStartsFree() async throws {
        _ = try makeSession()
        let store = ProStore(listensForUpdates: false)
        await store.refresh()
        XCTAssertEqual(store.access, .free)
        XCTAssertTrue(store.hasLoaded)
    }

    // Buying starts the two-week trial.
    func testBuyingStartsTheTrial() async throws {
        let session = try makeSession()
        try await session.buyProduct(identifier: ProductIDs.annual)
        let store = ProStore(listensForUpdates: false)
        await refresh(store, until: { $0.hasPro })
        guard case .trial = store.access else { return XCTFail("Expected a trial, got \(store.access)") }
        XCTAssertTrue(store.hasPro)
    }

    // A purchase made through the same path as the paywall is verified, applied and finished.
    func testPaywallPurchasePathUnlocksAndFinishes() async throws {
        _ = try makeSession()
        let store = ProStore(listensForUpdates: false)
        await store.refresh()
        XCTAssertFalse(store.hasPro)
        let products = try await Product.products(for: [ProductIDs.annual])
        let product = try XCTUnwrap(products.first)
        let purchase = try await product.purchase()
        guard case .success(let verification) = purchase else {
            return XCTFail("The purchase didn't succeed")
        }
        try await store.handle(verification)
        XCTAssertTrue(store.hasPro)
        // A finished transaction no longer waits among the unfinished ones.
        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        XCTAssertEqual(unfinished, 0)
    }

    // A pending purchase survives a refresh, and Pro turning on clears it.
    func testPendingPurchaseSurvivesRefresh() async throws {
        let session = try makeSession()
        let store = ProStore(listensForUpdates: false)
        await store.refresh()
        store.notePurchasePending()
        await store.refresh()
        XCTAssertEqual(store.access, .purchasePending)
        try await session.buyProduct(identifier: ProductIDs.annual)
        await refresh(store, until: { $0.hasPro })
        XCTAssertTrue(store.hasPro)
        XCTAssertFalse(store.hasPendingPurchase)
    }

    // The gates stay open until the first look at the entitlements finishes.
    func testGatesStayOpenUntilLoaded() async throws {
        _ = try makeSession()
        let store = ProStore(listensForUpdates: false)
        XCTAssertTrue(store.grantsFeatures)
        await store.refresh()
        XCTAssertFalse(store.grantsFeatures)
    }

    // A refunded purchase ends Pro. (Expiry isn't tested here: the test session sometimes keeps a
    // trial active after `expireSubscription`, so it needs a real sandbox account.)
    func testRefundEndsPro() async throws {
        let session = try makeSession()
        try await session.buyProduct(identifier: ProductIDs.annual)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        let store = ProStore(listensForUpdates: false)
        await refresh(store, until: { $0.hasPro })
        XCTAssertTrue(store.hasPro)
        try session.refundTransaction(identifier: transaction.identifier)
        await refresh(store, until: { !$0.hasPro })
        XCTAssertFalse(store.hasPro)
    }
}
