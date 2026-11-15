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

/// Explain shows a hand-checked note for each false friend and idiom on the list.
@MainActor
final class CheckedNotesTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns the bundled checked notes, failing the test if they don't load.
    private func notes() throws -> CheckedNotes {
        try XCTUnwrap(Self.pack?.checkedNotes, "fr.explain-notes.json should load")
    }

    /// Returns the French of each checked note found in `text`.
    private func found(_ text: String) throws -> [String] {
        try notes().notes(in: text).map(\.french)
    }

    // Each listed phrase is found in its evaluation sentence, through any form of its verb.
    func testListedPhrasesAreFoundInTheirSentences() throws {
        let expected: [(String, String)] = [
            ("J'ai assisté à la réunion ce matin.", "assister à"),
            ("Ma librairie préférée est près du lac.", "librairie"),
            ("Mon fils est très sensible.", "sensible"),
            ("Actuellement, je travaille sur une application.", "actuellement"),
            ("Éventuellement, nous irons à Annecy.", "éventuellement"),
            ("Je vais rester à l'hôtel ce soir.", "rester"),
            ("Demain, je passe un examen.", "passer un examen"),
            ("J'ai hâte de voir le mont Blanc.", "avoir hâte de"),
            ("Il pleut des cordes.", "il pleut des cordes"),
            ("Mon ami m'a posé un lapin.", "poser un lapin"),
            ("Ce n'est pas la mer à boire.", "ce n'est pas la mer à boire"),
            ("J'ai la flemme d'aller courir.", "avoir la flemme"),
            ("Elle est tombée dans les pommes.", "tomber dans les pommes"),
            ("J'ai le cafard depuis lundi.", "avoir le cafard"),
        ]
        for (sentence, french) in expected {
            XCTAssertEqual(try found(sentence), [french], sentence)
        }
        XCTAssertEqual(try found("Elle a demandé l'addition."), ["demander", "l'addition"])
    }

    // An elided de still matches, as in "hâte d'arriver".
    func testElidedDeMatches() throws {
        XCTAssertEqual(try found("J'ai hâte d'arriver à Lyon."), ["avoir hâte de"])
    }

    // A verb form after a determiner is a noun, so it gets no verb note.
    func testNounAfterDeterminerIsNotMatched() throws {
        XCTAssertEqual(try found("Le reste du temps, la demande est forte."), [])
    }

    // The checked note takes the place of an overlapping model phrase, and the total stays at the limit.
    func testCheckedNotesReplaceOverlappingModelPhrases() throws {
        let text = "Mon ami m'a posé un lapin samedi soir au café."
        let checked = try notes().notes(in: text)
        let model = [
            PassageExplainer.Phrase(french: "posé un lapin", meaning: "put a rabbit", note: "Past tense."),
            PassageExplainer.Phrase(french: "samedi soir", meaning: "Saturday evening", note: "A time."),
            PassageExplainer.Phrase(french: "au café", meaning: "at the café", note: "à + le."),
            PassageExplainer.Phrase(french: "mon ami", meaning: "my friend", note: "Possessive."),
            PassageExplainer.Phrase(french: "soir", meaning: "evening", note: "A noun."),
        ]
        let phrases = PassageExplainer.combined(checked: checked, model: model, in: text)
        XCTAssertEqual(phrases.map(\.french), ["mon ami", "poser un lapin", "samedi soir", "au café"])
        XCTAssertEqual(phrases[1].meaning, "to stand someone up")
    }

    // Copy words each phrase as the panel shows it, one bulleted line per phrase.
    func testCopiedTextMatchesThePanel() {
        let phrases = [
            PassageExplainer.Phrase(french: "librairie", meaning: "bookshop.", note: "Looks like \"library\", but a library is une bibliothèque."),
            PassageExplainer.Phrase(french: "près du lac", meaning: "near the lake", note: "A place"),
        ]
        XCTAssertEqual(
            ExplanationPanel.plainText(for: phrases),
            "• librairie means bookshop. Looks like \"library\", but a library is une bibliothèque.\n• près du lac means near the lake. A place."
        )
    }
}
