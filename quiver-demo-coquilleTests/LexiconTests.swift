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

final class LexiconTests: XCTestCase {

    // Only m, f and x name a gender, and only s, p and x a number; x means both.
    func testGenderAndNumberCodesAreStrict() throws {
        let feminineSingular = try XCTUnwrap(Lexicon.genderAndNumber("fs"))
        XCTAssertEqual(feminineSingular.gender, .feminine)
        XCTAssertEqual(feminineSingular.number, .singular)

        let both = try XCTUnwrap(Lexicon.genderAndNumber("xx"))
        XCTAssertNil(both.gender)
        XCTAssertNil(both.number)

        XCTAssertNil(Lexicon.genderAndNumber("zz"))
        XCTAssertNil(Lexicon.genderAndNumber("fz"))
        XCTAssertNil(Lexicon.genderAndNumber("qs"))
        XCTAssertNil(Lexicon.genderAndNumber("f"))
        XCTAssertNil(Lexicon.genderAndNumber("fsp"))
    }

    // A noun with a malformed code is left out, rather than read as every gender and number.
    func testMalformedNounCodesAreSkipped() throws {
        let file = Lexicon.File(
            source: "", license: "", generatedBy: "",
            nouns: ["chose": "fs", "truc": "zz"],
            adjectives: [:], verbs: [], participles: [:], conjugations: [:], otherWords: []
        )
        let lexicon = Lexicon(file: file)
        XCTAssertEqual(lexicon.noun("chose")?.gender, .feminine)
        XCTAssertNil(lexicon.noun("truc"))
    }
}
