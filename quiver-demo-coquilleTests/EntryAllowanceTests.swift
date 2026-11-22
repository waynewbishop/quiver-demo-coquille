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
final class EntryAllowanceTests: XCTestCase {

    // The free plan keeps seven entries.
    func testFreeLimitIsSeven() {
        XCTAssertEqual(EntryAllowance.freeLimit, 7)
    }

    // Slots left count down, and a seventh entry fills the last one.
    func testSlotsLeftCountDown() {
        XCTAssertEqual(EntryAllowance(savedCount: 0).slotsLeft, 7)
        XCTAssertEqual(EntryAllowance(savedCount: 6).slotsLeft, 1)
        XCTAssertTrue(EntryAllowance(savedCount: 6).canAddEntry)
        XCTAssertEqual(EntryAllowance(savedCount: 7).slotsLeft, 0)
        XCTAssertFalse(EntryAllowance(savedCount: 7).canAddEntry)
    }

    // Deleting an entry frees a slot, because saved entries are counted every time.
    func testDeletingFreesASlot() {
        XCTAssertFalse(EntryAllowance(savedCount: 7).canAddEntry)
        XCTAssertTrue(EntryAllowance(savedCount: 6).canAddEntry)
    }

    // A learner already past the limit keeps every entry; slots never go below zero.
    func testOverTheLimitNeverGoesNegative() {
        let allowance = EntryAllowance(savedCount: 12)
        XCTAssertEqual(allowance.slotsLeft, 0)
        XCTAssertTrue(allowance.isOver)
        XCTAssertEqual(allowance.summary, "12 saved · 0 of 7 left")
        XCTAssertEqual(EntryAllowance(savedCount: 3).summary, "4 of 7 left")
    }

    // Pro always may create an entry; Free needs a slot.
    func testProIgnoresTheLimit() {
        XCTAssertTrue(EntryAllowance(savedCount: 12).allowsNewEntry(hasPro: true))
        XCTAssertFalse(EntryAllowance(savedCount: 12).allowsNewEntry(hasPro: false))
        XCTAssertTrue(EntryAllowance(savedCount: 2).allowsNewEntry(hasPro: false))
    }

    // The allowance reads the journal's real entry count, and the journal itself never refuses
    // a save, so viewing and editing past the limit stay open.
    func testJournalItselfNeverBlocksPastTheLimit() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AllowanceTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let journal = Journal(folderURL: folder)
        for number in 1...9 {
            try journal.createEntry(text: "Entrée \(number).", title: "Jour \(number)")
        }
        XCTAssertEqual(journal.entries.count, 9)
        XCTAssertEqual(EntryAllowance(savedCount: journal.entries.count).slotsLeft, 0)
        let first = try XCTUnwrap(journal.entries.last?.url)
        XCTAssertNoThrow(try journal.write("Changé.", to: first))
        XCTAssertNoThrow(try journal.delete(first))
        XCTAssertEqual(journal.entries.count, 8)
    }

    // The limit is checked at the moment of creation, so a stale sheet can't add an eighth.
    func testJournalRefusesCreationAtTheLimitOnly() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "AllowanceTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let journal = Journal(folderURL: folder)
        journal.mayCreateEntry = { EntryAllowance(savedCount: $0).canAddEntry }
        for number in 1...7 {
            try journal.createEntry(text: "Entrée \(number).", title: "Jour \(number)")
        }
        XCTAssertThrowsError(try journal.createEntry(text: "Huit.", title: "Huit")) { XCTAssertTrue($0 is Journal.EntryLimitReached) }
        XCTAssertThrowsError(try journal.importEntry(text: "Neuf.", originalName: "Neuf"))
        let first = try XCTUnwrap(journal.entries.last?.url)
        XCTAssertThrowsError(try journal.duplicate(first))
        // Existing entries stay open to editing, renaming and deleting.
        XCTAssertNoThrow(try journal.write("Changé.", to: first))
        XCTAssertNoThrow(try journal.rename(first, to: "Nouveau"))
        XCTAssertEqual(journal.entries.count, 7)
        let any = try XCTUnwrap(journal.entries.first?.url)
        try journal.delete(any)
        XCTAssertNoThrow(try journal.createEntry(text: "Huit.", title: "Huit"))
    }
}
