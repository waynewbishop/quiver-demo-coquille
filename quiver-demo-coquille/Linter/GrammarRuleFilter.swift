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

/// Runs one grammar rule family as its own filter, so each rule carries its own layer and level.
struct GrammarRuleFilter: LinguisticFilter {
    let rule: GrammarRule

    var identifier: String { rule.identifier }
    var layer: LinguisticLayer { rule.layer }
    var targetLevel: CefrLevel { rule.targetLevel }

    /// Runs the rule on the pass's shared tokens, so the text is tokenized once.
    func evaluate(_ context: LintContext) -> [Issue] {
        rule.check(context.tokens)
    }
}
