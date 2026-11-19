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
import SwiftUI
@testable import quiver_demo_coquille

/// Checks the painting collection in `fr.paintings.json`, and the link that opens today's prompt.
///
/// These tests guard the file rather than a count, so adding a painting needs no test changes.
@MainActor
final class TableauTests: XCTestCase {

    /// Every painting ID that has shipped. Each must stay in the file, retired or not,
    /// because saved entries name them. Add new IDs here once they ship.
    private static let shippedIDs = [
        "le-the-du-matin", "pommes-et-pichet", "meules-en-ete", "la-montagne-au-loin",
        "le-jardin-en-fleurs", "le-lac-de-montagne", "le-bureau", "les-voiliers", "au-cafe",
        "le-chemin-des-peupliers", "les-nympheas", "le-chapeau-de-paille", "le-bouquet", "soleil-couchant",
    ]

    // The bundled file decodes, so a typo shows up here with the decoder's message.
    func testCatalogFileDecodes() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "fr.paintings", withExtension: "json"))
        let contents = try TableauCatalog.decode(Data(contentsOf: url))
        XCTAssertEqual(contents.paintings, TableauCatalog.all)
        XCTAssertFalse(TableauCatalog.available.isEmpty)
    }

    // IDs and titles are unique, and each ID is a plain lowercase slug.
    func testIDsAndTitlesAreUnique() {
        let all = TableauCatalog.all
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "duplicate ID")
        XCTAssertEqual(Set(all.map(\.title)).count, all.count, "duplicate title")
        XCTAssertEqual(Set(TableauCatalog.themes.map(\.id)).count, TableauCatalog.themes.count, "duplicate theme")
        for theme in TableauCatalog.themes {
            XCTAssertFalse(theme.buttonTitle.contains(" "), "\(theme.id): the picker button needs a one-word short name")
        }
        let slug = /[a-z0-9]+(-[a-z0-9]+)*/
        for tableau in all {
            XCTAssertNotNil(tableau.id.wholeMatch(of: slug), tableau.id)
        }
    }

    // No painting that has shipped is ever deleted from the file.
    func testShippedPaintingsAreNeverRemoved() {
        for id in Self.shippedIDs {
            XCTAssertNotNil(TableauCatalog.tableau(withID: id), "\(id) was removed; mark it retired instead")
        }
    }

    // Every painting has its image, a known theme and text for its caption and VoiceOver.
    func testEveryPaintingIsComplete() {
        let themeIDs = Set(TableauCatalog.themes.map(\.id))
        for tableau in TableauCatalog.all {
            #if os(macOS)
            XCTAssertNotNil(Bundle.main.image(forResource: tableau.imageName), tableau.imageName)
            #else
            XCTAssertNotNil(UIImage(named: tableau.imageName), tableau.imageName)
            #endif
            XCTAssertTrue(themeIDs.contains(tableau.theme), "\(tableau.id): unknown theme \(tableau.theme)")
            for text in [tableau.title, tableau.word, tableau.wordEnglish, tableau.genre, tableau.painter, tableau.description] {
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, tableau.id)
            }
            XCTAssertLessThanOrEqual(tableau.title.count, 24, "\(tableau.id): title too long for the small widget")
        }
    }

    // Every prompt has exactly one painting, and a painting's prompt ID names a real prompt.
    func testEveryPromptHasOnePainting() {
        let prompts = PromptCatalog.bundled()
        for prompt in prompts {
            XCTAssertEqual(TableauCatalog.all.filter { $0.promptID == prompt.id }.count, 1, prompt.id)
        }
        let promptIDs = Set(prompts.map(\.id))
        for tableau in TableauCatalog.all {
            guard let promptID = tableau.promptID else { continue }
            XCTAssertTrue(promptIDs.contains(promptID), "\(tableau.id): unknown prompt \(promptID)")
        }
        XCTAssertNotNil(TableauCatalog.tableau(for: PromptCatalog.fallback))
    }

    // A prompt painting has its French prompt, with "?" kept on the same line.
    func testFrenchPromptsFitTheFace() {
        for tableau in TableauCatalog.all {
            XCTAssertEqual(tableau.promptID == nil, tableau.french == nil, "\(tableau.id): promptID and french go together")
            guard let french = tableau.french else { continue }
            XCTAssertTrue(french.hasSuffix("\u{00A0}?"), tableau.id)
            XCTAssertFalse(french.contains("’"), tableau.id)
        }
    }

    // The style line joins genre and painter, as the widget and About show it.
    func testStyleNamesGenreAndPainter() throws {
        let weather = try XCTUnwrap(TableauCatalog.tableau(withID: "meules-en-ete"))
        XCTAssertEqual(weather.style, "Paysage · à la Monet")
        let meal = try XCTUnwrap(TableauCatalog.tableau(withID: "pommes-et-pichet"))
        XCTAssertEqual(meal.style, "Nature morte · à la Cézanne")
        XCTAssertEqual(meal.imageName, "Tableau-pommes-et-pichet")
    }

    // A painting with no prompt and "retired" decodes, and only retired paintings leave the picker.
    func testOptionalFieldsDecode() throws {
        let json = Data("""
        {"themes": [{"id": "dehors", "french": "Dehors", "english": "Outdoors and sport"}],
         "paintings": [{"id": "le-parc", "title": "Le parc", "word": "le parc", "wordEnglish": "the park",
                        "theme": "dehors", "genre": "Paysage", "painter": "Monet",
                        "description": "A bench under tall trees", "retired": true}]}
        """.utf8)
        let painting = try XCTUnwrap(TableauCatalog.decode(json).paintings.first)
        XCTAssertNil(painting.promptID)
        XCTAssertNil(painting.french)
        XCTAssertTrue(painting.retired)
        XCTAssertTrue(TableauCatalog.available.allSatisfy { !$0.retired })
    }

    // The control's bare link opens whichever prompt is today's.
    func testTodayLinkOpensTodaysPrompt() throws {
        let url = try XCTUnwrap(URL(string: CoquilleRoute.todayLink))
        XCTAssertEqual(CoquilleRoute.parse(url), .today(PromptCatalog.prompt()))
        XCTAssertNil(CoquilleRoute.parse(try XCTUnwrap(URL(string: "coquille://today?"))))
    }
}
