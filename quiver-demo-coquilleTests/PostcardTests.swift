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

import ImageIO
import XCTest
import SwiftUI
@testable import quiver_demo_coquille

/// Covers what a postcard shows and the images it becomes.
@MainActor
final class PostcardTests: XCTestCase {

    /// A calendar on Paris time, so dates don't move with the machine's time zone.
    private let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        return calendar
    }()

    /// Noon on a day in Paris.
    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try XCTUnwrap(paris.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    /// A postcard of Le parc with `french` on its back.
    private func content(_ french: String = "Il fait beau.", english: String? = nil, on date: Date = .now) throws -> PostcardContent {
        PostcardContent(tableau: try XCTUnwrap(TableauCatalog.tableau(withID: "le-parc")), french: french, english: english, date: date)
    }

    // MARK: - The back's text

    /// The back is the French alone: no painting line, guide note, date heading or review marker.
    func testBackTextIsTheFrenchAlone() {
        let entry = """
        //: tableau Le parc
        // Write in French, then keep going. Grey notes are never checked.
        Lundi 16 novembre 2026

        Aujourd'hui, je suis allé au parc.
        //: check passé composé
        Il faisait beau.
        """
        XCTAssertEqual(PostcardContent.backText(from: entry), "Aujourd'hui, je suis allé au parc.\nIl faisait beau.")
    }

    /// A sentence that starts with a weekday isn't mistaken for the date heading.
    func testBackTextKeepsASentenceStartingWithAWeekday() {
        XCTAssertEqual(PostcardContent.backText(from: "Lundi, je vais au parc."), "Lundi, je vais au parc.")
    }

    // MARK: - Dates

    /// The heading is the French date in capitals, with "1er" on the first of the month.
    func testHeadingIsTheFrenchDate() throws {
        XCTAssertEqual(try content(on: day(2026, 11, 16)).heading(calendar: paris), "LUNDI 16 NOVEMBRE 2026")
        XCTAssertEqual(try content(on: day(2026, 8, 1)).heading(calendar: paris), "SAMEDI 1ER AOÛT 2026")
    }

    /// The postmark has the weekday, then the date as two-digit day, month and year.
    func testPostmark() throws {
        let mark = try content(on: day(2026, 11, 6)).postmark(calendar: paris)
        XCTAssertEqual(mark.weekday, "VENDREDI")
        XCTAssertEqual(mark.date, "06·11·26")
    }

    // MARK: - Content from the editor

    /// Reports no misspellings, so only the grammar rules can raise issues.
    private struct NoSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Says nothing, so tests stay silent.
    private final class SilentNarrator: Narrator {
        var voiceID = ""
        private(set) var state = PlaybackState.idle
        var spokenRange: Range<Int>?
        func speak(_ text: String) {}
        func pause() {}
        func resume() {}
        func stop() {}
    }

    /// Translates by labelling the French, so a test can tell which text was translated.
    private struct LabelTranslator: Translator {
        func translate(_ text: String) async throws -> String { "EN: " + text }
    }

    // A postcard leaves out English translated from the French as it was before the last edit.
    func testPostcardNeverPairsNewFrenchWithOldEnglish() async throws {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: NoSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        let model = EditorModel(stats: StatsStore(fileURL: nil), narrator: SilentNarrator(), phraseNarrator: SilentNarrator(),
                                linter: linter, translator: LabelTranslator())
        model.text = AttributedString("//: tableau Le parc\nIl fait beau.")
        model.textDidChange()
        model.lintNow()
        model.isEnglishOn = true
        for _ in 0..<50 where model.postcardContent?.english == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(model.postcardContent?.english, "EN: Il fait beau.")

        model.text = AttributedString("//: tableau Le parc\nIl fait froid.")
        model.textDidChange()
        XCTAssertEqual(model.postcardContent?.french, "Il fait froid.")
        XCTAssertNil(model.postcardContent?.english, "the English is from the old French")
    }

    // MARK: - Fonts

    /// Cormorant Garamond ships with the app and registers both weights the titles and postcard use.
    func testCormorantIsBundled() {
        AppFonts.register()
        for name in [Font.CormorantWeight.semibold.rawValue, Font.CormorantWeight.medium.rawValue] {
            #if os(macOS)
            XCTAssertNotNil(NSFont(name: name, size: 20), name)
            #else
            XCTAssertNotNil(UIFont(name: name, size: 20), name)
            #endif
        }
    }

    // MARK: - Images

    /// Each side becomes a 1800 × 1200 JPEG: 6 × 4 inches at 300 dpi.
    func testEachSideIs1800By1200() throws {
        for side in PostcardSide.allCases {
            let view = PostcardView(content: try content(english: "The weather is nice."), side: side)
            let data = try XCTUnwrap(PostcardRenderer.jpeg(of: view), "\(side)")
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.jpeg")
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(image.width, 1800, "\(side)")
            XCTAssertEqual(image.height, 1200, "\(side)")
        }
    }

    /// Back only shares one file; both sides share the back, then the front.
    func testFilesFollowTheSendChoice() throws {
        let postcard = try content()
        let back = try PostcardRenderer.files(for: postcard, sides: [.back], showsWord: true, showsEnglish: true)
        XCTAssertEqual(back.map(\.lastPathComponent), ["Le parc – verso.jpg"])
        let both = try PostcardRenderer.files(for: postcard, sides: [.back, .front], showsWord: true, showsEnglish: true)
        XCTAssertEqual(both.map(\.lastPathComponent), ["Le parc – verso.jpg", "Le parc – recto.jpg"])
        XCTAssertTrue(both.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertNotEqual(back[0].deletingLastPathComponent(), both[0].deletingLastPathComponent(),
                          "each export gets its own folder, so a redraw never replaces a file being shared")
        XCTAssertTrue(FileManager.default.fileExists(atPath: back[0].path))
    }
}
