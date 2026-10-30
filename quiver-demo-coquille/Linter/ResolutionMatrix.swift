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

/// One explicit place that decides which overlapping issue is most useful to the learner.
nonisolated enum ResolutionMatrix {

    /// Keeps one issue per span: the more severe one, or the earlier-raised one on a tie.
    static func resolve(_ issues: [Issue]) -> [Issue] {
        var kept: [Issue] = []
        // Sort by severity, then by input position, since Swift's sort isn't guaranteed stable.
        let ordered = issues.enumerated().sorted { left, right in
            rank(left.element) != rank(right.element) ? rank(left.element) < rank(right.element) : left.offset < right.offset
        }
        for (_, issue) in ordered {
            let overlaps = kept.contains { $0.range.overlaps(issue.range) }
            if !overlaps {
                kept.append(issue)
            }
        }
        return kept.sorted { $0.offset < $1.offset }
    }

    /// Orders issues for overlap resolution: errors before warnings before suggestions.
    ///
    /// A look-alike outranks every other error, because its fix comes from the words
    /// around it: the system spellchecker turns "sava" into "cava", which is the very
    /// mistake the look-alike list catches.
    private static func rank(_ issue: Issue) -> Int {
        guard issue.kind != .lookAlike else { return 0 }
        return switch issue.severity {
        case .error: 1
        case .warning: 2
        case .suggestion: 3
        }
    }
}
