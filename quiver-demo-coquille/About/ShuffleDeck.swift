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

/// A shuffle bag over the paintings: each one comes up once, at random, before any repeats.
struct ShuffleDeck: Equatable {
    private let count: Int
    /// The paintings' positions in the catalog, the one on top first.
    private(set) var upcoming: [Int]

    /// A fresh shuffle of `count` paintings; an empty catalog leaves an empty deck.
    init(count: Int) {
        self.count = count
        upcoming = Array(0..<count).shuffled()
    }

    /// The painting on top of the stack, or 0 when the catalog is empty.
    var top: Int { upcoming.first ?? 0 }

    /// Drops the top painting. When fewer than four are left, a fresh shuffle goes on the end,
    /// with the one just shown kept out of its first six places.
    mutating func advance() {
        guard count > 1, !upcoming.isEmpty else { return }
        let shown = upcoming.removeFirst()
        guard upcoming.count < 4 else { return }
        let queued = Set(upcoming)
        var fresh = (0..<count).filter { !queued.contains($0) }.shuffled()
        if let at = fresh.firstIndex(of: shown), at < 6 {
            fresh.remove(at: at)
            fresh.append(shown)
        }
        upcoming += fresh
    }
}
