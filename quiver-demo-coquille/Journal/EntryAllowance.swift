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

/// How many journal entries the free plan keeps, and whether a new one fits.
///
/// Saved entries count at any time, so deleting one frees a slot. Entries past the limit
/// are never blocked or hidden: a learner who already has more than the limit keeps every
/// one, and only creating another waits for a free slot or Pro.
struct EntryAllowance: Equatable {

    /// The free plan's saved-entry limit.
    static let freeLimit = 7

    /// The entries saved now.
    let savedCount: Int
    /// The limit being checked, which is `freeLimit` unless a test says otherwise.
    var limit = EntryAllowance.freeLimit

    /// Free slots left, never below zero.
    var slotsLeft: Int { max(limit - savedCount, 0) }

    /// Whether one more entry fits the free plan.
    var canAddEntry: Bool { savedCount < limit }

    /// Whether no free slot is left.
    var isFull: Bool { !canAddEntry }

    /// Whether the learner has more saved entries than the free plan keeps.
    var isOver: Bool { savedCount > limit }

    /// The line the Settings meter shows, such as "3 of 7 left" or "12 saved · 0 of 7 left".
    var summary: String {
        isOver ? "\(savedCount) saved · 0 of \(limit) left" : "\(slotsLeft) of \(limit) left"
    }

    /// Whether a new entry may be created, given Pro: Pro always may, Free needs a slot.
    func allowsNewEntry(hasPro: Bool) -> Bool {
        hasPro || canAddEntry
    }
}
