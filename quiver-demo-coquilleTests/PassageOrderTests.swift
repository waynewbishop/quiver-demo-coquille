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

import XCTest
@testable import quiver_demo_coquille

/// The Explain panel lists phrases in the order they appear in the learner's French.
@MainActor
final class PassageOrderTests: XCTestCase {

    private let passage = "Samedi, je vais au stade avec mon frère. J'ai hâte de voir le match. Nous allons manger des frites après."

    /// Sorts plain strings, standing in for the model's phrases.
    private func ordered(_ phrases: [String]) -> [String] {
        PassageExplainer.inPassageOrder(phrases, french: { $0 }, in: passage)
    }

    // Phrases quoted from the passage follow it, whatever order the model gave.
    func testQuotedPhrasesFollowThePassage() {
        XCTAssertEqual(
            ordered(["nous allons manger", "au stade", "Samedi"]),
            ["Samedi", "au stade", "nous allons manger"]
        )
    }

    // A dictionary form is placed by its longest word in the passage, ignoring accents.
    func testDictionaryFormIsPlacedByItsWords() {
        XCTAssertEqual(
            ordered(["nous allons manger", "avoir hâte de", "je vais au stade"]),
            ["je vais au stade", "avoir hâte de", "nous allons manger"]
        )
        XCTAssertEqual(ordered(["frites", "avoir hate de"]), ["avoir hate de", "frites"])
    }

    // A phrase that isn't in the passage goes last, and the model's order breaks ties.
    func testUnfoundPhrasesGoLastInTheModelsOrder() {
        XCTAssertEqual(
            ordered(["le samedi", "être en train de", "après"]),
            ["le samedi", "après", "être en train de"]
        )
    }
}
