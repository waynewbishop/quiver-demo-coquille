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
import SwiftUI

/// The Coquille Pro offer: what Pro adds, then the annual plan with its free trial.
///
/// `SubscriptionStoreView` draws the price, the trial wording and the buy button from the
/// App Store, so the terms shown are always the ones that will be charged.
struct PaywallView: View {

    let store: ProStore
    @Environment(\.dismiss) private var dismiss
    /// Why a purchase failed, for the alert.
    @State private var purchaseFailure: String?

    var body: some View {
        NavigationStack {
            SubscriptionStoreView(groupID: ProductIDs.groupID) {
                header
            }
            .subscriptionStoreButtonLabel(.automatic)
            .storeButton(.visible, for: .restorePurchases)
            .subscriptionStorePolicyDestination(for: .termsOfService) {
                PolicyPlaceholder(title: "Terms of Use")
            }
            .subscriptionStorePolicyDestination(for: .privacyPolicy) {
                PolicyPlaceholder(title: "Privacy Policy")
            }
            .onInAppPurchaseCompletion { _, result in
                await finished(result)
            }
            .alert("The purchase couldn't be completed", isPresented: showsPurchaseFailure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(purchaseFailure ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 640)
        #endif
    }

    /// Handles a finished purchase. Giving a completion handler replaces StoreKit's own
    /// handling, so this verifies and finishes the transaction, says when a purchase fails,
    /// and notes one that is pending. Pro closes the paywall.
    private func finished(_ result: Result<Product.PurchaseResult, any Error>) async {
        switch result {
        case .success(.success(let verification)):
            do {
                try await store.handle(verification)
                if store.hasPro { dismiss() }
            } catch {
                purchaseFailure = error.localizedDescription
            }
        case .success(.pending):
            store.notePurchasePending()
            dismiss()
        case .success:
            // The learner cancelled; nothing to report.
            break
        case .failure(let error):
            purchaseFailure = error.localizedDescription
        }
    }

    private var showsPurchaseFailure: Binding<Bool> {
        Binding(get: { purchaseFailure != nil }, set: { if !$0 { purchaseFailure = nil } })
    }

    /// The headline and the four things Pro adds.
    private var header: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Coquille Pro")
                    .font(.largeTitle.bold())
                Text("Keep the writing habit going.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("doc.text", "Unlimited journal", "Save as many entries as you write.")
                feature("icloud", "iCloud sync", "Your journal on iPhone, iPad and Mac. Progress stats stay on each device.")
                feature("chart.bar", "Detailed progress", "Weak spots, tricky words and your corrections history.")
                feature("rectangle.and.pencil.and.ellipsis", "Share as Postcard", "Send an entry with its painting.")
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    /// One row of the feature list.
    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stands in for the Terms of Use and Privacy Policy pages until their addresses exist.
private struct PolicyPlaceholder: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "doc.text", description: Text("This page is added before Coquille Pro is released."))
    }
}
