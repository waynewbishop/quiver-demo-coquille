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

/// Where a learner stands with Coquille Pro, as the Settings section and the gates need it.
enum ProAccess: Equatable {
    /// No Pro: never subscribed, or the subscription ended.
    case free
    /// In the free introductory period, which ends on `ends`.
    case trial(ends: Date?)
    /// Subscribed, and set to renew on `renews`.
    case renewing(renews: Date?)
    /// Subscribed and cancelled, but still active until `expires`.
    case cancelledButActive(expires: Date?)
    /// A renewal payment failed; Pro stays on while Apple retries.
    case billingProblem
    /// A purchase is pending: it needs another step before Pro turns on, such as an
    /// approval from the person who manages purchases (Ask to Buy), or a payment that
    /// hasn't finished.
    case purchasePending
    /// Pro ended on `ended`, after a subscription that lapsed or was refunded.
    case expired(ended: Date?)

    /// Whether Pro features are on. A billing problem keeps them on during Apple's grace period.
    var hasPro: Bool {
        switch self {
        case .trial, .renewing, .cancelledButActive, .billingProblem: true
        case .free, .purchasePending, .expired: false
        }
    }
}
