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

/// One self-contained linguistic check. Deterministic rules and model-backed checks share
/// this contract, so the pipeline and resolution policy stay independent of either approach.
/// The synchronous pipeline stays on the main actor with the existing editor and spellchecker.
@MainActor protocol LinguisticFilter {
    var identifier: String { get }
    var layer: LinguisticLayer { get }
    var targetLevel: CefrLevel { get }
    func evaluate(_ context: LintContext) -> [Issue]
}
