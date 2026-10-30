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

/// The learner level at which a filter's feedback is appropriate to introduce.
nonisolated enum CefrLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case a1, a2, b1, b2, c1, c2

    /// Orders levels from beginner to mastery, so a linter can run every filter up to a learner's level.
    static func < (lhs: CefrLevel, rhs: CefrLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    /// The level's position from A1, since enums with raw values get no synthesized ordering.
    private var rank: Int {
        switch self {
        case .a1: 0
        case .a2: 1
        case .b1: 2
        case .b2: 3
        case .c1: 4
        case .c2: 5
        }
    }
}
