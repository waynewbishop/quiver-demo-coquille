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

/// Adapts the existing grammar implementation to the shared filter contract.
/// Individual rules can move into their own filters as they become teaching examples.
struct LocalGrammarFilter: LinguisticFilter {
    let identifier = "grammar.local"
    let layer = LinguisticLayer.localMorphosyntax
    let targetLevel = CefrLevel.a2

    let grammar: any Grammar

    func evaluate(_ context: LintContext) -> [Issue] {
        grammar.check(context.text)
    }
}
