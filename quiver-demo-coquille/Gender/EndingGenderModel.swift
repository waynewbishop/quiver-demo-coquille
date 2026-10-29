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
import Quiver

/// A Quiver logistic regression that predicts gender from a noun's last letters.
///
/// Each feature is 1.0 when the noun ends with one ending from `endings` and 0.0
/// otherwise, so feature *i* and weight *i* both belong to `endings[i]`. Class 1 is
/// feminine: a positive weight leans feminine and a negative weight leans masculine.
/// Because the weights are plain numbers, a prediction can name the ending behind it.
///
/// The model is trained outside the app and bundled as `fr.gender-model.json`.
/// Retraining and replacing that file changes predictions without code changes.
nonisolated struct EndingGenderModel: GenderPredictor, Codable, Equatable, Sendable {

    /// The ending vocabulary, in the same order as the model's feature weights.
    let endings: [String]
    /// The trained classifier.
    let model: LogisticRegression

    /// Creates a model from a trained classifier and its ending vocabulary.
    init(endings: [String], model: LogisticRegression) {
        precondition(endings.count == model.featureCount,
            "Expected one ending per feature: \(endings.count) endings, \(model.featureCount) features")
        self.endings = endings
        self.model = model
    }

    private enum CodingKeys: String, CodingKey {
        case endings
        case model
    }

    /// Decodes a bundled model, rejecting a file whose endings don't match its features.
    ///
    /// - Throws: `DecodingError.dataCorrupted` on a mismatch, or any decoding error.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let endings = try container.decode([String].self, forKey: .endings)
        let model = try container.decode(LogisticRegression.self, forKey: .model)
        guard endings.count == model.featureCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .endings,
                in: container,
                debugDescription: "\(endings.count) endings for \(model.featureCount) features"
            )
        }
        self.endings = endings
        self.model = model
    }

    /// Returns the binary ending features for a noun.
    ///
    /// - Complexity: O(*e*) in the number of endings.
    func features(for noun: String) -> [Double] {
        endings.map { noun.hasSuffix($0) ? 1.0 : 0.0 }
    }

    /// Predicts the gender of a noun and names the longest ending behind the guess.
    func gender(of noun: String) -> GenderPrediction? {
        let row = features(for: noun)
        guard row.contains(1.0), let feminine = model.predictProbabilities([row]).first else {
            return nil
        }
        let gender: Gender = feminine >= 0.5 ? .feminine : .masculine
        return GenderPrediction(
            gender: gender,
            probability: gender == .feminine ? feminine : 1.0 - feminine,
            ending: decidingEnding(for: row, toward: gender)
        )
    }

    /// Returns the longest present ending that pushes toward `gender`, such as "ette"
    /// rather than "e" for glimette, or `nil` when only single letters do.
    ///
    /// The heaviest weight usually belongs to a single letter, and "words ending in -e
    /// usually are feminine" is a poor rule to learn (le livre, le musée). A longer
    /// ending is a rule the learner can use; without one, the app raises no warning.
    private func decidingEnding(for row: [Double], toward gender: Gender) -> String? {
        let weightOffset = model.hasIntercept ? 1 : 0
        var best: String?
        for (index, value) in row.enumerated() where value == 1.0 {
            let weight = model.coefficients[index + weightOffset]
            // Feminine predictions want a positive weight; masculine, a negative one.
            let pull = gender == .feminine ? weight : -weight
            let ending = endings[index]
            if pull > 0, ending.count > 1, ending.count > (best?.count ?? 0) {
                best = ending
            }
        }
        return best
    }
}
