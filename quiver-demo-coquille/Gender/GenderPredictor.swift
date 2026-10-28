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

/// A guess at a noun's gender, with the evidence behind it.
nonisolated struct GenderPrediction: Equatable, Sendable {
    let gender: Gender
    /// The model's probability for `gender`, in (0, 1).
    let probability: Double
    /// The word ending that pushed hardest toward `gender`, such as "ère".
    let ending: String?
}

/// Predicts the gender of a noun the lexicon doesn't know.
///
/// Known nouns never reach a predictor: the lexicon answers them exactly. A
/// predictor's verdicts only ever produce warnings.
nonisolated protocol GenderPredictor: Sendable {
    /// Returns a prediction for a normalized noun, or `nil` when the model has no evidence.
    func gender(of noun: String) -> GenderPrediction?
}
