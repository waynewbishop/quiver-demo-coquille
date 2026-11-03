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

@MainActor
final class JournalTests: XCTestCase {

    /// The test's own temporary folder, removed when the test ends.
    private let folder = FileManager.default.temporaryDirectory.appending(path: "JournalTests-\(UUID().uuidString)")
    /// A journal over the test's folder.
    private func makeJournal() throws -> Journal {
        let folder = folder
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return Journal(folderURL: folder)
    }

    /// Returns noon on a day in 2026.
    private func day(_ month: Int, _ number: Int) throws -> Date {
        try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: month, day: number, hour: 12)))
    }

    // Entries are named for their day, and a second one that day gets a number.
    func testEntriesAreNamedByDay() throws {
        let journal = try makeJournal()
        let first = try journal.createEntry(text: "Il pleut.", on: try day(10, 31))
        let second = try journal.createEntry(text: "Il neige.", on: try day(10, 31))
        XCTAssertEqual(first.lastPathComponent, "2026-10-31.txt")
        XCTAssertEqual(second.lastPathComponent, "2026-10-31 (2).txt")
        XCTAssertNil(Journal.title(of: second))
    }

    // A title follows the date in the name, without characters a name can't hold.
    func testEntriesTakeTheirTitle() throws {
        let journal = try makeJournal()
        let url = try journal.createEntry(text: "Il pleut.", title: "Paris: la pluie", on: try day(10, 31))
        XCTAssertEqual(url.lastPathComponent, "2026-10-31 Paris la pluie.txt")
        XCTAssertEqual(Journal.title(of: url), "Paris la pluie")
        XCTAssertEqual(journal.proposedName(title: "", on: try day(10, 31)), "2026-10-31")
    }

    // Renaming keeps the date; the same title changes nothing, and an empty one leaves the date.
    func testRenameKeepsTheDate() throws {
        let journal = try makeJournal()
        let url = try journal.createEntry(text: "Il pleut.", title: "Pluie", on: try day(10, 31))
        let renamed = try journal.rename(url, to: "Averse")
        XCTAssertEqual(renamed.lastPathComponent, "2026-10-31 Averse.txt")
        XCTAssertEqual(try journal.rename(renamed, to: "Averse"), renamed)
        XCTAssertEqual(try journal.rename(renamed, to: "").lastPathComponent, "2026-10-31.txt")
        XCTAssertEqual(journal.entries.count, 1)
    }

    // A duplicate keeps the date and text, with "copy" after the title.
    func testDuplicate() throws {
        let journal = try makeJournal()
        let url = try journal.createEntry(text: "Il pleut.", title: "Pluie", on: try day(10, 31))
        let copy = try journal.duplicate(url)
        XCTAssertEqual(copy.lastPathComponent, "2026-10-31 Pluie copy.txt")
        XCTAssertEqual(try FrenchTextFile.text(at: copy), "Il pleut.")
        XCTAssertEqual(journal.entries.count, 2)
    }

    // An imported file keeps its name after today's date, or its own date if it has one.
    func testImportKeepsTheName() throws {
        let journal = try makeJournal()
        let plain = try journal.importEntry(text: "Bonjour.", originalName: "Devoir", on: try day(11, 2))
        let dated = try journal.importEntry(text: "Salut.", originalName: "2026-09-01 Rentrée", on: try day(11, 2))
        XCTAssertEqual(plain.lastPathComponent, "2026-11-02 Devoir.txt")
        XCTAssertEqual(dated.lastPathComponent, "2026-09-01 Rentrée.txt")
    }

    // The list is newest day first, and reading the folder again finds the same entries.
    func testEntriesAreNewestFirst() throws {
        let journal = try makeJournal()
        try journal.createEntry(text: "Un.", on: try day(10, 29))
        try journal.createEntry(text: "Trois.", on: try day(10, 31))
        try journal.createEntry(text: "Deux.", on: try day(10, 30))
        XCTAssertEqual(journal.entries.map(\.text), ["Trois.", "Deux.", "Un."])
        XCTAssertEqual(try makeJournal().entries.map(\.text), ["Trois.", "Deux.", "Un."])
    }

    // A deleted entry leaves the list and the folder.
    func testDelete() throws {
        let journal = try makeJournal()
        let url = try journal.createEntry(text: "Il pleut.")
        try journal.delete(url)
        XCTAssertTrue(journal.entries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    // A list preview skips a new entry's date line.
    func testPreviewSkipsTheDateLine() throws {
        let journal = try makeJournal()
        try journal.createEntry(text: "Le 31 octobre 2026\n\nIl fait beau.\nJe suis à Paris.", on: try day(10, 31))
        XCTAssertEqual(journal.entries.first?.preview, "Il fait beau.")
    }

    // A list preview skips the notes too, so a new entry's guide never stands in for its French.
    func testPreviewSkipsNotes() throws {
        let journal = try makeJournal()
        let header = EditorModel.entryHeader(for: try day(11, 2)).text
        let text = header.replacingOccurrences(of: "Il fait \n", with: "Il fait froid. // cold\n")
        try journal.createEntry(text: text, on: try day(11, 2))
        XCTAssertEqual(journal.entries.first?.preview, "Il fait froid.")
    }
}
