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

/// Article and preposition errors learners make, and the correct French that looks like them.
final class ArticlePrepositionTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns each issue as "original → replacement".
    private func fixes(_ text: String) throws -> [String] {
        try XCTUnwrap(Self.pack).grammar.check(text).map { "\($0.original) → \($0.replacement ?? "")" }
    }

    /// Asserts that every sentence is left alone.
    private func assertSilent(_ sentences: [String], line: UInt = #line) throws {
        for sentence in sentences {
            XCTAssertEqual(try fixes(sentence), [], sentence, line: line)
        }
    }

    // Demonstratives take the noun's gender, and cet comes before a masculine vowel sound.
    func testDemonstratives() throws {
        XCTAssertEqual(try fixes("Ce maison est belle."), ["Ce maison → Cette maison"])
        XCTAssertEqual(try fixes("Ce ami est gentil."), ["Ce ami → Cet ami"])
        XCTAssertEqual(try fixes("Cette garçon est petit."), ["Cette garçon → Ce garçon"])
        XCTAssertEqual(try fixes("Cet garçon est petit."), ["Cet garçon → Ce garçon"])
    }

    // Quel and aucun follow the noun's gender too.
    func testQuelAndAucun() throws {
        XCTAssertEqual(try fixes("Quel maison est belle?"), ["Quel maison → Quelle maison"])
        XCTAssertEqual(try fixes("Quelle garçon est là?"), ["Quelle garçon → Quel garçon"])
        XCTAssertEqual(try fixes("Il n'a aucun maison."), ["aucun maison → aucune maison"])
    }

    // Ce as a pronoun and quelle before être aren't determiners of a noun.
    func testCorrectDeterminersStaySilent() throws {
        try assertSilent([
            "Cette maison est belle.", "Cet ami est gentil.", "Ce garçon est petit.", "Cet homme est grand.",
            "Ce sont mes amis.", "Ce que je veux.", "Ce sera difficile.",
            "Quelle est ta maison?", "Quel est ton nom?", "Il n'a aucune maison.",
            "Quelle a été la réponse?",
        ])
    }

    // En doesn't take le, la or les before a noun.
    func testEnBeforeAnArticle() throws {
        XCTAssertEqual(try fixes("Je cours en les montagnes."), ["en les → dans les"])
        XCTAssertEqual(try fixes("Je marche en le parc."), ["en le → dans le"])
        XCTAssertEqual(try fixes("Il habite en la ville."), ["en la → dans la"])
        XCTAssertTrue(try fixes("Je voudrais courir en les montages a Chamonix.").contains("en les → dans les"))
    }

    // Gerunds, l' and a few fixed phrases are correct after en.
    func testEnPhrasesThatAreCorrect() throws {
        try assertSilent([
            "En les voyant, je ris.", "En le faisant, il sourit.", "Il saute en l'air.",
            "Il est expert en la matière.", "Je pense en la personne de Marie.", "Je vais en ville.",
            "Je crois en la science.", "Elle rit en la voyant.", "Il joue en la majeur.",
        ])
    }

    // After aller or habiter, a country needs its preposition; after aller, so does a place name.
    func testMissingPrepositionBeforeAPlace() throws {
        XCTAssertEqual(try fixes("Je vais France."), ["France → en France"])
        XCTAssertEqual(try fixes("Je vais Canada."), ["Canada → au Canada"])
        XCTAssertEqual(try fixes("Nous allons États-Unis."), ["États-Unis → aux États-Unis"])
        XCTAssertEqual(try fixes("Je vais Paris."), ["Paris → à Paris"])
        XCTAssertEqual(try fixes("J'habite France."), ["France → en France"])
    }

    // Habiter takes a city directly, and a verb with no subject may be a cheer.
    func testPlacesThatAreCorrect() throws {
        try assertSilent([
            "J'habite Paris.", "Je vais à Paris.", "Je vais en France.", "Allez Marseille!", "Je vais bien.",
        ])
    }

    // Seasons and vehicles use their own prepositions.
    func testSeasonsAndVehicles() throws {
        XCTAssertEqual(try fixes("Il neige en printemps."), ["en printemps → au printemps"])
        XCTAssertEqual(try fixes("Je skie dans l'hiver."), ["dans l'hiver → en hiver"])
        XCTAssertEqual(try fixes("Il dort dans l'été."), ["dans l'été → en été"])
        XCTAssertEqual(try fixes("Je lis sur le train."), ["sur le train → dans le train"])
        XCTAssertEqual(try fixes("Je dors sur l'avion."), ["sur l'avion → dans l'avion"])
        try assertSilent(["Il neige au printemps.", "Je skie dans l'hiver canadien."])
    }

    // These verbs take a different preposition before an infinitive.
    func testVerbsBeforeAnInfinitive() throws {
        XCTAssertEqual(try fixes("Je décide à partir."), ["décide à → décide de"])
        XCTAssertEqual(try fixes("J'ai décidé à partir."), ["décidé à → décidé de"])
        XCTAssertEqual(try fixes("J'oublie à manger."), ["oublie à → oublie de"])
        XCTAssertEqual(try fixes("Je finis à manger."), ["finis à → finis de"])
        XCTAssertEqual(try fixes("J'arrête à fumer."), ["arrête à → arrête de"])
        XCTAssertEqual(try fixes("J'aide de faire."), ["aide de → aide à"])
    }

    // The same verbs are correct before a time, a place, or as se décider à.
    func testThoseVerbsWhenCorrect() throws {
        try assertSilent([
            "Je finis à cinq heures.", "Je me décide à partir.", "J'arrête à la gare.",
            "Elle est décidée à partir.",
        ])
    }

    // Pour plus a length of time asks what the learner meant, keeping their own numbers.
    func testPourALengthOfTimeAsks() throws {
        let issue = try XCTUnwrap(XCTUnwrap(Self.pack).grammar.check("Je reste pour deux ans.").first)
        XCTAssertEqual(issue.severity, .suggestion)
        XCTAssertEqual(issue.choices.map(\.text), ["pour deux ans", "pendant deux ans", "depuis deux ans"])
    }
}
