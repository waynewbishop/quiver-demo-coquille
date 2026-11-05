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
import XCTest
@testable import quiver_demo_coquille

/// The two capital-letter rules: a capital to start a sentence, and none on the words
/// English capitalizes but French doesn't.
final class CapitalLetterTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns the issues one rule raises on `text`.
    private func issues(_ rule: String, in text: String) throws -> [Issue] {
        let grammar = try XCTUnwrap(Self.pack, "The French language pack failed to load").grammar
        let check = try XCTUnwrap(grammar.rules.first { $0.identifier == rule }, "No rule named \(rule)")
        return check.check(grammar.tag(FrenchTokenizer.tokens(in: text)))
    }

    /// Returns each fix the rule offers on `text`, as "original → replacement".
    private func fixes(_ rule: String, in text: String) throws -> [String] {
        try issues(rule, in: text).map { "\($0.original) → \($0.replacement ?? "")" }
    }

    // MARK: - Sentence starts

    // The first word of the text and the first after a sentence's end take a capital.
    func testSentenceStartsTakeACapital() throws {
        XCTAssertEqual(try fixes("grammar.sentenceCapital", in: "il pleut. je reste ici !"), ["il → Il", "je → Je"])
        XCTAssertEqual(try fixes("grammar.sentenceCapital", in: "j'ai faim."), ["j' → J'"])
        XCTAssertEqual(try fixes("grammar.sentenceCapital", in: "Bonjour\nje suis là."), ["je → Je"])
    }

    // Abbreviations, ellipses, decimals, web addresses, closing quotes and list dashes don't end a sentence.
    func testMarksThatDontEndASentenceAreLeftAlone() throws {
        for text in [
            "Je vois M. dupont demain.", "Il dort… elle lit.", "Ça coûte 3.5 euros.",
            "Va sur coquille.fr ce soir.", "« Viens ! » dit-il.", "Courses :\n- du pain et du lait",
            "Chère Marie,\nje pense à toi."
        ] {
            XCTAssertEqual(try issues("grammar.sentenceCapital", in: text), [], text)
        }
    }

    // A brand written its own way and a word standing alone are left alone.
    func testBrandsAndLoneWordsAreLeftAlone() throws {
        XCTAssertEqual(try issues("grammar.sentenceCapital", in: "iPhone est cher."), [])
        XCTAssertEqual(try issues("grammar.sentenceCapital", in: "boulangère"), [])
    }

    // MARK: - Capitals inside a sentence

    // Days, months, languages, nationality adjectives and je lose their capital.
    func testEnglishCapitalsAreLowercased() throws {
        XCTAssertEqual(try fixes("grammar.lowercase", in: "Je viens Samedi."), ["Samedi → samedi"])
        XCTAssertEqual(try fixes("grammar.lowercase", in: "C'est le 3 Mai."), ["Mai → mai"])
        XCTAssertEqual(try fixes("grammar.lowercase", in: "Je ne parle pas bien l'Espagnol."), ["Espagnol → espagnol"])
        XCTAssertEqual(try fixes("grammar.lowercase", in: "Elle est Française."), ["Française → française"])
        XCTAssertEqual(try fixes("grammar.lowercase", in: "Des touristes Japonais arrivent."), ["Japonais → japonais"])
        XCTAssertEqual(try fixes("grammar.lowercase", in: "Hier, J'ai dormi."), ["J' → j'"])
    }

    // Holidays, names, the people and the planet keep their capital.
    func testNamesKeepTheirCapital() throws {
        for text in [
            "On mange des crêpes le Mardi gras.", "Le lundi de Pâques est férié.", "Le 14 Juillet, on danse.",
            "Il parle de Mai 68.", "Les Français aiment le pain.", "Un Canadien est arrivé.",
            "Elle travaille à l'Alliance Française.", "On ira sur Mars.", "La surface de Mars est rouge.",
            "Il a dit : « Je viens. »"
        ] {
            XCTAssertEqual(try issues("grammar.lowercase", in: text), [], text)
        }
    }
}
