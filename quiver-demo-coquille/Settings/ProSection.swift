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

/// The top section of Settings: the learner's plan and what it allows, one layout per
/// state `ProStore` publishes.
struct ProSection: View {

    let store: ProStore
    let journal: Journal
    @State private var showsPaywall = false
    @State private var showsManage = false
    @State private var showsRedeem = false
    #if os(macOS)
    @Environment(\.openURL) private var openURL
    #endif
    /// Why Restore Purchases failed, for the alert.
    @State private var restoreFailure: String?

    var body: some View {
        Section {
            rows
        } header: {
            Text("Coquille Pro")
        } footer: {
            Text(footer)
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallView(store: store)
                .tint(.brand)
        }
        #if !os(macOS)
        .manageSubscriptionsSheet(isPresented: $showsManage, subscriptionGroupID: ProductIDs.groupID)
        #endif
        .offerCodeRedemption(options: [], isPresented: $showsRedeem) { _ in }
        .alert("Purchases couldn't be restored", isPresented: showsRestoreFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreFailure ?? "")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        switch store.access {
        case .trial(let ends):
            LabeledContent("Plan", value: "Pro · Free Trial")
            LabeledContent("Trial Ends", value: dateText(ends))
            manageButton
        case .renewing(let renews):
            LabeledContent("Plan", value: "Coquille Pro · Annual")
            LabeledContent("Renews", value: dateText(renews))
            LabeledContent("Journal Entries", value: "Unlimited")
            manageButton
            restoreButton
        case .cancelledButActive(let expires):
            LabeledContent("Plan", value: "Coquille Pro")
            LabeledContent("Expires", value: dateText(expires))
            manageButton
        case .billingProblem:
            LabeledContent("Plan", value: "Coquille Pro")
            LabeledContent("Payment") {
                Text("Didn't go through").foregroundStyle(.red)
            }
            Button("Update Payment…", action: manageSubscription)
                .fontWeight(.semibold)
        case .purchasePending:
            LabeledContent("Plan", value: "Free")
            LabeledContent("Pro Purchase", value: "Pending")
            restoreButton
        case .free, .expired:
            freeRows
        }
    }

    /// The Free and Pro-ended layouts: the plan, the entry meter, and the ways to upgrade.
    @ViewBuilder
    private var freeRows: some View {
        if case .expired(let ended) = store.access {
            LabeledContent("Plan", value: ended.map { "Free · Pro ended \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Free · Pro ended")
        } else {
            LabeledContent("Plan", value: "Free")
        }
        EntryMeter(allowance: EntryAllowance(savedCount: journal.entries.count))
        // The paywall shows the price and any trial the App Store offers this learner.
        Button("See Coquille Pro…") {
            showsPaywall = true
        }
        .fontWeight(.semibold)
        Button("Redeem Code…") { showsRedeem = true }
        restoreButton
    }

    private var manageButton: some View {
        Button("Manage Subscription…", action: manageSubscription)
    }

    /// Opens the system's subscription management: a sheet on iPhone and iPad, and the
    /// App Store's subscriptions page on the Mac.
    private func manageSubscription() {
        #if os(macOS)
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
        #else
        showsManage = true
        #endif
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task {
                do {
                    try await store.restore()
                } catch {
                    restoreFailure = error.localizedDescription
                }
            }
        }
    }

    private var showsRestoreFailure: Binding<Bool> {
        Binding(get: { restoreFailure != nil }, set: { if !$0 { restoreFailure = nil } })
    }

    // MARK: - Text

    /// A date as Settings shows it, or a dash when StoreKit doesn't give one.
    private func dateText(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .omitted) ?? "—"
    }

    /// The line under the rows, which explains the state.
    private var footer: String {
        let count = journal.entries.count
        switch store.access {
        case .trial(let ends):
            let date = dateText(ends)
            return "Cancel before \(date) and you won't be charged. Your entries stay either way."
        case .renewing:
            return "Your Apple Account manages the subscription. Progress stats stay on each device."
        case .cancelledButActive(let expires):
            return "Pro stays on until \(dateText(expires)). After that, every entry you wrote stays visible, editable and exportable."
        case .billingProblem:
            return "Pro stays on while Apple tries again. Update the payment method in your Apple Account to keep it."
        case .purchasePending:
            return "This purchase needs another step before Pro turns on, such as an approval. Pro turns on as soon as it's complete."
        case .expired:
            return "All \(count) entries stay yours to read, edit, export and delete. Saving a new entry needs Pro, or fewer than \(EntryAllowance.freeLimit) saved entries."
        case .free:
            return "Free keeps \(EntryAllowance.freeLimit) saved entries at a time; deleting one frees a slot."
        }
    }
}

/// The free plan's entries meter: how many of the free slots are left, as a bar.
private struct EntryMeter: View {

    let allowance: EntryAllowance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Journal Entries", value: allowance.summary)
            ProgressView(value: Double(min(allowance.savedCount, allowance.limit)), total: Double(allowance.limit))
                .tint(allowance.isFull ? .secondary : .accentColor)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}
