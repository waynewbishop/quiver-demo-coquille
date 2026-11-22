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
final class JournalArchiveTests: XCTestCase {

    /// A whole-second date, since the manifest keeps times to the second.
    private let modified = Date(timeIntervalSince1970: 1_790_000_000)

    /// A new empty folder, removed when the test ends.
    private func makeFolder(_ name: String = "journal") throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "JournalArchiveTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes an entry file with a modification date.
    @discardableResult
    private func write(_ name: String, _ text: String, in folder: URL, modified date: Date? = nil) throws -> URL {
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date ?? modified], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    /// The text files in a folder, by name.
    private func texts(in folder: URL) throws -> [String: String] {
        var result = [String: String]()
        for url in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            result[JournalArchive.normalized(url.lastPathComponent)] = try String(contentsOf: url, encoding: .utf8)
        }
        return result
    }

    /// A source journal with a dated entry, an accented one and an undated one.
    private func makeSource() throws -> URL {
        let source = try makeFolder("source")
        try write("2026-11-14 Au café.txt", "Ce matin, je suis allée au café.", in: source)
        try write("2026-11-09 Le vent.txt", "Il fait du vent.\nLe ciel est gris.", in: source, modified: modified.addingTimeInterval(86_400))
        try write("Notes sans date.txt", "Des mots à retenir.", in: source, modified: modified.addingTimeInterval(-86_400))
        return source
    }

    // A backup restored into an empty journal brings back every entry's name, text and dates.
    func testBackupAndRestoreRoundTrip() throws {
        let source = try makeSource()
        let backup = try JournalArchive.makeBackup(of: source)
        XCTAssertEqual(backup.entryCount, 3)
        XCTAssertTrue(backup.unreadable.isEmpty)

        let destination = try makeFolder("destination")
        let plan = try JournalArchive.plan(restoring: backup.data, into: destination)
        XCTAssertEqual(plan.toAdd, 3)
        XCTAssertEqual(plan.alreadyHere, 0)
        XCTAssertEqual(plan.recovered, 0)

        let summary = JournalArchive.restore(plan, into: destination)
        XCTAssertEqual(summary.added, 3)
        XCTAssertEqual(try texts(in: destination), try texts(in: source))

        for url in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let original = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let restored = try destination.appending(path: url.lastPathComponent).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            XCTAssertEqual(try XCTUnwrap(restored).timeIntervalSince1970, try XCTUnwrap(original).timeIntervalSince1970, accuracy: 1)
        }
    }

    // Restoring the same backup again adds nothing.
    func testRestoringTwiceAddsNothing() throws {
        let backup = try JournalArchive.makeBackup(of: try makeSource())
        let destination = try makeFolder("destination")
        JournalArchive.restore(try JournalArchive.plan(restoring: backup.data, into: destination), into: destination)

        let again = try JournalArchive.plan(restoring: backup.data, into: destination)
        XCTAssertEqual(again.toAdd, 0)
        XCTAssertEqual(again.recovered, 0)
        XCTAssertEqual(again.alreadyHere, 3)
        XCTAssertFalse(again.hasWork)

        let summary = JournalArchive.restore(again, into: destination)
        XCTAssertEqual(summary.restoredCount, 0)
        XCTAssertEqual(try texts(in: destination).count, 3)
    }

    // An entry of the same name with different writing is kept beside the journal's, once.
    func testDifferentWritingIsKeptAsARecoveredVersionOnce() throws {
        let backup = try JournalArchive.makeBackup(of: try makeSource())
        let destination = try makeFolder("destination")
        try write("2026-11-14 Au café.txt", "Une autre version, écrite plus tard.", in: destination)

        let plan = try JournalArchive.plan(restoring: backup.data, into: destination)
        XCTAssertEqual(plan.toAdd, 2)
        XCTAssertEqual(plan.recovered, 1)
        JournalArchive.restore(plan, into: destination)

        let after = try texts(in: destination)
        XCTAssertEqual(after["2026-11-14 Au café.txt"], "Une autre version, écrite plus tard.")
        XCTAssertEqual(after["2026-11-14 Au café (recovered).txt"], "Ce matin, je suis allée au café.")

        let again = try JournalArchive.plan(restoring: backup.data, into: destination)
        XCTAssertFalse(again.hasWork)
        XCTAssertEqual(again.alreadyHere, 3)
        JournalArchive.restore(again, into: destination)
        XCTAssertEqual(try texts(in: destination).count, 4)
    }

    // The same accented title stored in two Unicode forms is one entry, so a backup moved
    // between a Mac and an iPhone adds no duplicates.
    func testAccentedNamesMatchAcrossUnicodeForms() throws {
        let composed = "2026-11-14 Au caf\u{E9}.txt"
        let decomposed = "2026-11-14 Au cafe\u{301}.txt"
        XCTAssertNotEqual(Array(composed.unicodeScalars), Array(decomposed.unicodeScalars))

        let source = try makeFolder("source")
        try write(composed, "Ce matin, je suis allée au café.", in: source)
        let backup = try JournalArchive.makeBackup(of: source)

        let destination = try makeFolder("destination")
        try write(decomposed, "Ce matin, je suis allée au café.", in: destination)
        let plan = try JournalArchive.plan(restoring: backup.data, into: destination)
        XCTAssertEqual(plan.alreadyHere, 1)
        XCTAssertEqual(plan.toAdd, 0)
        XCTAssertEqual(plan.recovered, 0)
    }

    // Files that aren't Coquille backups are refused, and nothing is written.
    func testNotABackupWritesNothing() throws {
        let destination = try makeFolder("destination")
        let plainZip = try ZipArchive.write([ZipArchive.Member(name: "a.txt", modified: modified, data: Data("Bonjour".utf8))])
        for data in [Data("hello".utf8), plainZip] {
            XCTAssertThrowsError(try JournalArchive.plan(restoring: data, into: destination)) { error in
                XCTAssertEqual(error as? JournalArchive.Failure, .notABackup)
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path(percentEncoded: false)).isEmpty)
    }

    // A backup from a newer format is named as newer, not as damaged.
    func testNewerFormatIsRefused() throws {
        let manifest = ZipArchive.Member(name: "manifest.json", modified: modified, data: Data(#"{"formatVersion": 99}"#.utf8))
        let archive = try ZipArchive.write([manifest])
        XCTAssertThrowsError(try JournalArchive.plan(restoring: archive, into: try makeFolder())) { error in
            XCTAssertEqual(error as? JournalArchive.Failure, .newerFormat)
        }
    }

    // A damaged entry is named, and the rest of the backup still restores.
    func testDamagedEntryIsReportedAndOthersRestore() throws {
        let backup = try JournalArchive.makeBackup(of: try makeSource())
        let range = try XCTUnwrap(backup.data.range(of: Data("Des mots à retenir.".utf8)))
        var tampered = backup.data
        tampered[range.lowerBound] ^= 0xFF

        let destination = try makeFolder("destination")
        let plan = try JournalArchive.plan(restoring: tampered, into: destination)
        XCTAssertEqual(plan.unreadable, ["Notes sans date.txt"])
        XCTAssertEqual(plan.toAdd, 2)

        let summary = JournalArchive.restore(plan, into: destination)
        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(summary.unreadable, ["Notes sans date.txt"])
        XCTAssertNil(try texts(in: destination)["Notes sans date.txt"])
    }

    // Restoring is never held back by the free plan's entry limit.
    func testRestoreIgnoresTheFreeLimit() throws {
        let source = try makeFolder("source")
        for number in 1...9 {
            try write("2026-11-\(String(format: "%02d", number)) Jour.txt", "Entrée \(number).", in: source)
        }
        let backup = try JournalArchive.makeBackup(of: source)

        let destination = try makeFolder("destination")
        let journal = Journal(folderURL: destination)
        journal.mayCreateEntry = { $0 < EntryAllowance.freeLimit }
        JournalArchive.restore(try JournalArchive.plan(restoring: backup.data, into: destination), into: destination)
        journal.refresh()
        XCTAssertEqual(journal.entries.count, 9)
        XCTAssertThrowsError(try journal.createEntry(text: "Une de plus."))
    }

    // A journal with nothing in it has nothing to back up.
    func testBackupOfAnEmptyJournalThrows() throws {
        XCTAssertThrowsError(try JournalArchive.makeBackup(of: try makeFolder())) { error in
            XCTAssertEqual(error as? JournalArchive.Failure, .nothingToBackUp)
        }
    }

    // The archive holds each entry's original file, so any unzip tool can read the writing.
    func testBackupHoldsTheOriginalFiles() throws {
        let source = try makeSource()
        let contents = try ZipArchive.read(try JournalArchive.makeBackup(of: source).data)
        XCTAssertEqual(contents.members.first?.name, "manifest.json")
        let entries = Dictionary(uniqueKeysWithValues: contents.members.filter { $0.name.hasPrefix("entries/") }.map {
            (String($0.name.dropFirst("entries/".count)), String(decoding: $0.data, as: UTF8.self))
        })
        XCTAssertEqual(entries, try texts(in: source))
    }

    // An entry that can't be read is named, and the others are still backed up.
    func testBackupNamesUnreadableEntries() throws {
        let source = try makeSource()
        let locked = try write("2026-11-20 Fermé.txt", "Secret.", in: source)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path(percentEncoded: false))
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path(percentEncoded: false)) }
        try XCTSkipIf(FileManager.default.isReadableFile(atPath: locked.path(percentEncoded: false)), "This account can read files marked unreadable.")

        let backup = try JournalArchive.makeBackup(of: source)
        XCTAssertEqual(backup.unreadable, ["2026-11-20 Fermé.txt"])
        XCTAssertEqual(backup.entryCount, 3)
    }

    // A backup can only create files inside the journal's folder.
    func testRestoreStaysInsideTheJournalFolder() throws {
        let destination = try makeFolder("journal")
        let manifest = JournalArchive.Manifest(
            formatVersion: JournalArchive.formatVersion, created: modified, app: "Coquille", appVersion: "",
            items: [.init(name: "../escape.txt", path: "x.txt", modified: modified, created: nil)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let archive = try ZipArchive.write([
            ZipArchive.Member(name: "manifest.json", modified: modified, data: try encoder.encode(manifest)),
            ZipArchive.Member(name: "entries/x.txt", modified: modified, data: Data("Bonjour.".utf8))
        ])

        let plan = try JournalArchive.plan(restoring: archive, into: destination)
        XCTAssertEqual(plan.unreadable, ["../escape.txt"])
        JournalArchive.restore(plan, into: destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appending(path: "escape.txt").path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().appending(path: "escape.txt").path(percentEncoded: false)))
    }

    // Only plain, visible text files are accepted from a backup.
    func testSafeNames() {
        XCTAssertNil(JournalArchive.safeName("../x.txt"))
        XCTAssertNil(JournalArchive.safeName("a/b.txt"))
        XCTAssertNil(JournalArchive.safeName("a:b.txt"))
        XCTAssertNil(JournalArchive.safeName(" padded.txt"))
        XCTAssertEqual(JournalArchive.safeName("2026-11-22 Paris\\Lyon.txt"), "2026-11-22 Paris\\Lyon.txt")
        XCTAssertEqual(JournalArchive.safeName("C.TXT"), "C.TXT")
        XCTAssertNil(JournalArchive.safeName(".hidden.txt"))
        XCTAssertNil(JournalArchive.safeName("photo.png"))
        XCTAssertNil(JournalArchive.safeName(".txt"))
        XCTAssertNil(JournalArchive.safeName(""))
    }

    // A title with a backslash, which the journal allows, comes back with its name intact.
    func testBackslashTitlesSurvive() throws {
        let source = try makeFolder("source")
        try write("2026-11-22 Paris\\Lyon.txt", "Le train part à huit heures.", in: source)
        let backup = try JournalArchive.makeBackup(of: source)
        let destination = try makeFolder("journal")
        let summary = JournalArchive.restore(try JournalArchive.plan(restoring: backup.data, into: destination), into: destination)
        XCTAssertEqual(summary.added, 1)
        XCTAssertEqual(try texts(in: destination).keys.sorted(), ["2026-11-22 Paris\\Lyon.txt"])
    }

    // Dates keep fractions of a second, so entries saved close together stay in order.
    func testDatesKeepFractionsOfASecond() throws {
        let source = try makeFolder("source")
        let precise = modified.addingTimeInterval(0.25)
        try write("a.txt", "Un.", in: source, modified: precise)
        let backup = try JournalArchive.makeBackup(of: source)
        let destination = try makeFolder("journal")
        JournalArchive.restore(try JournalArchive.plan(restoring: backup.data, into: destination), into: destination)
        let restored = try destination.appending(path: "a.txt").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        XCTAssertEqual(try XCTUnwrap(restored).timeIntervalSince1970, precise.timeIntervalSince1970, accuracy: 0.01)
    }

    // A name taken between the plan and the write is checked again, not assumed to match.
    func testNameTakenAtWriteTimeIsRecoveredNotSkipped() throws {
        let destination = try makeFolder("journal")
        let candidate = JournalArchive.Candidate(name: "a.txt", data: Data("Version du sauvegarde.".utf8), modified: modified, created: nil)
        try write("a.txt", "Version locale.", in: destination)

        XCTAssertEqual(JournalArchive.write(candidate, as: "a.txt", in: destination, retries: 3), .written(datesKept: true))
        XCTAssertEqual(try texts(in: destination), ["a.txt": "Version locale.", "a (recovered).txt": "Version du sauvegarde."])

        // The same writing under the taken name counts as already there.
        try write("b.txt", "Pareil.", in: destination)
        let same = JournalArchive.Candidate(name: "b.txt", data: Data("Pareil.".utf8), modified: modified, created: nil)
        XCTAssertEqual(JournalArchive.write(same, as: "b.txt", in: destination, retries: 3), .alreadyThere)
    }

    // A journal too large for one restorable file is refused when backing up, not later.
    func testBackupRefusesWhatRestoreCouldNotReadBack() {
        let big = Data(count: ZipArchive.maximumFileSize + 1)
        XCTAssertThrowsError(try ZipArchive.write([ZipArchive.Member(name: "a.txt", modified: modified, data: big)])) { error in
            XCTAssertEqual(error as? ZipArchive.Failure, .tooLarge)
        }
    }

    // A file over the limit is refused by its size on disk, before it's read into memory.
    func testBackupRefusesAnOversizedFileBeforeReadingIt() throws {
        let source = try makeFolder("source")
        try write("small.txt", "Un petit mot.", in: source)
        try Data(count: ZipArchive.maximumFileSize + 1).write(to: source.appending(path: "huge.txt"))
        XCTAssertThrowsError(try JournalArchive.makeBackup(of: source)) { error in
            XCTAssertEqual(error as? JournalArchive.Failure, .tooLarge)
        }
    }
}
