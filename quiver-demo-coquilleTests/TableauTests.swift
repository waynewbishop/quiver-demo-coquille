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

/// Checks the widget's paintings and the link that opens today's prompt.
@MainActor
final class TableauTests: XCTestCase {

    // Every prompt has exactly one painting, in the catalog's order.
    func testEveryPromptHasOnePainting() {
        let prompts = PromptCatalog.bundled()
        XCTAssertEqual(TableauCatalog.all.map(\.promptID), prompts.map(\.id))
        for prompt in prompts {
            XCTAssertNotNil(TableauCatalog.tableau(for: prompt), prompt.id)
        }
        XCTAssertNotNil(TableauCatalog.tableau(for: PromptCatalog.fallback))
    }

    // French prompts keep "?" on the same line, and titles stay short enough for the small face.
    func testFrenchPromptsAndTitlesFitTheFace() {
        for tableau in TableauCatalog.all {
            XCTAssertTrue(tableau.french.hasSuffix("\u{00A0}?"), tableau.promptID)
            XCTAssertFalse(tableau.french.contains("’"), tableau.promptID)
            XCTAssertLessThanOrEqual(tableau.title.count, 24, tableau.promptID)
            XCTAssertEqual(tableau.imageName, "Tableau-\(tableau.promptID)")
        }
    }

    // Monet paints outdoor prompts and Cézanne the still lifes, except the mountain landscape.
    func testStyleNamesGenreAndPainter() throws {
        let weather = try XCTUnwrap(TableauCatalog.all.first { $0.promptID == "weather-outside" })
        XCTAssertEqual(weather.style, "Paysage · à la Monet")
        let meal = try XCTUnwrap(TableauCatalog.all.first { $0.promptID == "food-favorite-meal" })
        XCTAssertEqual(meal.style, "Nature morte · à la Cézanne")
    }

    // The control's bare link opens whichever prompt is today's.
    func testTodayLinkOpensTodaysPrompt() throws {
        let url = try XCTUnwrap(URL(string: CoquilleRoute.todayLink))
        XCTAssertEqual(CoquilleRoute.parse(url), .today(PromptCatalog.prompt()))
        XCTAssertNil(CoquilleRoute.parse(try XCTUnwrap(URL(string: "coquille://today?"))))
    }
}
