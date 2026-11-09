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

/// French numbers and clock times: learners' common mistakes and the forms that are correct.
final class NumbersAndTimesTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns each issue as "original → replacement".
    private func fixes(_ text: String) throws -> [String] {
        try XCTUnwrap(Self.pack).grammar.check(text).map { "\($0.original) → \($0.replacement ?? "")" }
    }

    // Numbers, hours and ones in their correct forms are left alone, including the 1990 spelling.
    func testCorrectNumbersAndTimesStaySilent() throws {
        let correct = [
            "Il y a vingt et un élèves.", "Il est vingt et une heures.", "Il a vingt-deux ans.",
            "J'ai soixante et onze ans.", "J'ai quatre-vingt-un ans.", "J'ai vingt-et-un ans.",
            "Il y a soixante et dix élèves.", "Il a dix-sept ans.",
            "Il est une heure.", "Il est deux heures.", "Le train part à 18h.", "Le train part à 18h30.",
            "Il est six heures du soir.", "Je mange à midi.", "Il a travaillé douze heures.",
            "Voir le verset Ct 4:12.", "Il a fait un temps de 2:00.531.",
        ]
        for sentence in correct {
            XCTAssertEqual(try fixes(sentence), [], sentence)
        }
    }

    // Et only comes before un or une.
    func testEtBeforeTwoToNine() throws {
        XCTAssertEqual(try fixes("Il y a vingt et deux élèves."), ["vingt et deux → vingt-deux"])
        XCTAssertEqual(try fixes("Il a trente et cinq ans."), ["trente et cinq → trente-cinq"])
    }

    // Twenty-one to sixty-one need et.
    func testMissingEtBeforeOne() throws {
        XCTAssertEqual(try fixes("Elle a vingt-un ans."), ["vingt-un → vingt et un"])
    }

    // The one in vingt et un agrees with its noun.
    func testOneAgreesWithItsNoun() throws {
        XCTAssertEqual(try fixes("Il reste vingt et un heures."), ["un heures → une heures"])
        XCTAssertEqual(try fixes("Il y a vingt et une garçons."), ["une garçons → un garçons"])
    }

    // Compound numbers are hyphenated.
    func testMissingHyphen() throws {
        XCTAssertEqual(try fixes("Il a dix sept ans."), ["dix sept → dix-sept"])
        XCTAssertEqual(try fixes("Il a vingt deux ans."), ["vingt deux → vingt-deux"])
    }

    // Heure takes an s from two upward, in words or figures.
    func testHeureTakesAnS() throws {
        XCTAssertEqual(try fixes("Il est deux heure."), ["heure → heures"])
        XCTAssertEqual(try fixes("Il est dix-huit heure."), ["heure → heures"])
        XCTAssertEqual(try fixes("Il est 2 heure."), ["heure → heures"])
    }

    // English time formats become French ones.
    func testEnglishTimeFormats() throws {
        XCTAssertEqual(try fixes("Le train part at 18h."), ["at → à"])
        XCTAssertEqual(try fixes("Le train part à 6 pm."), ["6 pm → 18h"])
        XCTAssertEqual(try fixes("Le train part à 12 pm."), ["12 pm → 12h"])
        XCTAssertEqual(try fixes("Le train part à 6:00."), ["6:00 → 6h"])
        XCTAssertEqual(try fixes("Le train part à 18:30."), ["18:30 → 18h30"])
    }

    // A colon time is a warning, since timetables and sites do use it.
    func testColonTimeIsAWarning() throws {
        let issue = try XCTUnwrap(XCTUnwrap(Self.pack).grammar.check("Le train part à 6:00.").first)
        XCTAssertEqual(issue.severity, .warning)
    }

    // Douze heures at a point in time suggests midi, as a preference and not an error.
    func testDouzeHeuresSuggestsMidi() throws {
        XCTAssertEqual(try fixes("Je mange à douze heures."), ["à douze heures → à midi"])
        let issue = try XCTUnwrap(XCTUnwrap(Self.pack).grammar.check("Je mange à douze heures.").first)
        XCTAssertEqual(issue.severity, .suggestion)
    }
}
