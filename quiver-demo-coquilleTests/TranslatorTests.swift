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

/// Covers keeping the English laid out line for line like the French.
final class TranslatorTests: XCTestCase {

    // The translator adds a blank line after each line, which the French doesn't have.
    func testSingleLineBreaksStaySingle() {
        let result = AppleTranslator.matchingLineBreaks(
            of: "Bonjour.\nJe vais bien.\nIl fait beau.",
            in: "Hello.\n\nI'm doing well.\n\nIt's nice weather."
        )
        XCTAssertEqual(result, "Hello.\nI'm doing well.\nIt's nice weather.")
    }

    // A blank line the learner typed comes through as one blank line.
    func testBlankLinesInTheFrenchAreKept() {
        let result = AppleTranslator.matchingLineBreaks(of: "Bonjour.\n\nJe vais bien.", in: "Hello.\n\nI'm doing well.")
        XCTAssertEqual(result, "Hello.\n\nI'm doing well.")
    }

    // Blank lines at the start keep the first English line beside the first French one.
    func testLeadingBlankLinesAreKept() {
        let result = AppleTranslator.matchingLineBreaks(of: "\n\nBonjour.\nÀ demain.", in: "Hello.\n\nSee you tomorrow.")
        XCTAssertEqual(result, "\n\nHello.\nSee you tomorrow.")
    }

    // When the translator merges lines, there's no safe way to map them, so nothing changes.
    func testDifferentLineCountsLeaveTheTranslationAlone() {
        let translation = "I am going to the market."
        XCTAssertEqual(AppleTranslator.matchingLineBreaks(of: "Je vais\nau marché.", in: translation), translation)
    }

    // A single line has nothing to rebuild.
    func testSingleLineIsUnchanged() {
        XCTAssertEqual(AppleTranslator.matchingLineBreaks(of: "Bonjour.", in: "Hello."), "Hello.")
    }
}
