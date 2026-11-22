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

import Foundation

/// Backs the journal up to one ZIP file and restores it, on any device.
///
/// A backup holds each entry's original text file under `entries/`, plus a small
/// `manifest.json` with the file names and dates. Unzip it and any text editor reads the
/// writing. The format is the same on iPhone, iPad and Mac, so a backup made on one
/// restores on another.
///
/// Restoring merges: it adds what's missing, skips what's already there, and never changes
/// or removes an entry. Where the journal has an entry of the same name with different
/// writing, the backup's version is kept beside it as "(recovered)". Restoring the same
/// backup again adds nothing. It works on the journal's folder, so the free plan's
/// entry limit, which only gates creating entries, never stands in its way.
nonisolated enum JournalArchive {

    /// The manifest's version, raised when the format changes in a way older apps can't read.
    static let formatVersion = 1
    static let manifestName = "manifest.json"
    static let entriesFolder = "entries/"
    /// Where Settings remembers when the learner last saved a backup.
    static let lastBackupKey = "lastJournalBackup"

    /// Why a backup or restore couldn't go ahead.
    enum Failure: LocalizedError, Equatable {
        case nothingToBackUp
        case noneReadable
        case folderUnreadable
        case notABackup
        case newerFormat
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .nothingToBackUp: "There are no entries to back up yet."
            case .noneReadable: "Coquille couldn't read any of the entries, so nothing was backed up."
            case .folderUnreadable: "Coquille can't read the journal folder right now."
            case .notABackup: "This file isn't a Coquille journal backup."
            case .newerFormat: "This backup was made by a newer version of Coquille. Update Coquille to restore it."
            case .tooLarge: "The journal is too large for one backup file, or this backup is too large to restore."
            }
        }
    }

    // MARK: - Manifest

    /// What `manifest.json` records about the entries.
    struct Manifest: Codable, Equatable {

        /// One entry: its file name, where its text sits in the archive, and its dates.
        struct Item: Codable, Equatable {
            let name: String
            let path: String
            let modified: Date
            let created: Date?
        }

        let formatVersion: Int
        let created: Date
        let app: String
        let appVersion: String
        let items: [Item]
    }

    /// Just the version, read first so a newer manifest is named as newer, not as damaged.
    private struct Header: Decodable {
        let formatVersion: Int
    }

    // MARK: - Dates

    /// A date as ISO 8601 text with milliseconds, so entries that were saved close together
    /// keep their order.
    static func isoText(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Reads ISO 8601 text with or without fractions of a second.
    static func date(fromISO text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: - Backing up

    /// A finished backup, ready to save.
    struct Backup {
        let data: Data
        /// The entries in the archive.
        let entryCount: Int
        /// The names of entries that couldn't be read and so aren't in the archive.
        let unreadable: [String]
        /// A file name for saving, such as "CoquilleJournal-2026-11-22".
        let suggestedName: String
    }

    /// Reads every entry in `folder` afresh, never from a cached list, and packs them.
    ///
    /// An entry that can't be read is left out and named, so a backup never claims more
    /// than it holds.
    static func makeBackup(of folder: URL, now: Date = .now, calendar: Calendar = .current) throws -> Backup {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            throw Failure.folderUnreadable
        }
        let entryURLs = urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !entryURLs.isEmpty else { throw Failure.nothingToBackUp }

        var members = [ZipArchive.Member]()
        var items = [Manifest.Item]()
        var unreadable = [String]()
        var usedPaths = Set<String>()
        var totalSize = 0

        for url in entryURLs {
            let name = url.lastPathComponent
            // Check the size before loading the file, so one huge file added through Files or
            // the Finder is refused instead of filling memory first.
            let onDisk = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard onDisk <= ZipArchive.maximumFileSize, totalSize + onDisk <= ZipArchive.maximumTotalSize else {
                throw Failure.tooLarge
            }
            let data: Data
            do {
                data = try CoordinatedFile.read(url) { try Data(contentsOf: $0) }
            } catch {
                unreadable.append(name)
                continue
            }
            totalSize += data.count
            guard data.count <= ZipArchive.maximumFileSize, totalSize <= ZipArchive.maximumTotalSize else {
                throw Failure.tooLarge
            }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            let modified = values?.contentModificationDate ?? now
            let path = uniquePath(for: name, used: &usedPaths)
            members.append(ZipArchive.Member(name: entriesFolder + path, modified: modified, data: data))
            items.append(Manifest.Item(name: name, path: path, modified: modified, created: values?.creationDate))
        }
        guard !items.isEmpty else { throw Failure.noneReadable }

        let manifest = Manifest(formatVersion: formatVersion, created: now, app: "Coquille",
                                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                                items: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoText(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestMember = ZipArchive.Member(name: manifestName, modified: now, data: try encoder.encode(manifest))

        let archive: Data
        do {
            archive = try ZipArchive.write([manifestMember] + members)
        } catch {
            throw Failure.tooLarge
        }
        return Backup(data: archive, entryCount: items.count, unreadable: unreadable,
                      suggestedName: "CoquilleJournal-\(dayText(for: now, calendar: calendar))")
    }

    /// A day as "yyyy-MM-dd".
    private static func dayText(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// The name an entry takes inside the archive: the same name, in one Unicode form,
    /// with a number added if two names would otherwise match.
    private static func uniquePath(for name: String, used: inout Set<String>) -> String {
        let base = normalized(name).replacingOccurrences(of: "\\", with: "_")
        var path = base
        var number = 2
        while used.contains(key(path)) {
            path = "\(base.dropLast(4)) (\(number)).txt"
            number += 1
        }
        used.insert(key(path))
        return path
    }

    // MARK: - Restoring

    /// One entry from a backup, with its writing, or `nil` when that couldn't be read.
    struct Candidate {
        let name: String
        let data: Data?
        let modified: Date
        let created: Date?
    }

    /// What restoring would do with one entry.
    enum Outcome: Equatable {
        /// Add it under this name.
        case add(String)
        /// It's already in the journal, word for word.
        case skip
        /// The journal has an entry of that name with different writing, so keep this one
        /// beside it under this name.
        case recovered(String)
        /// The backup's copy is damaged or its name can't be used.
        case unreadable
    }

    /// What restoring a backup would do, shown to the learner before anything is written.
    struct Plan: Identifiable {
        let id = UUID()
        let candidates: [Candidate]
        let outcomes: [Outcome]

        /// Entries that would be added.
        var toAdd: Int { outcomes.filter { if case .add = $0 { true } else { false } }.count }
        /// Entries already in the journal.
        var alreadyHere: Int { outcomes.filter { $0 == .skip }.count }
        /// Entries that would be kept as recovered versions.
        var recovered: Int { outcomes.filter { if case .recovered = $0 { true } else { false } }.count }
        /// The names of entries in the backup that can't be restored.
        var unreadable: [String] {
            zip(candidates, outcomes).filter { $0.1 == .unreadable }.map { $0.0.name }
        }
        /// Whether restoring would write anything.
        var hasWork: Bool { toAdd + recovered > 0 }
    }

    /// What restoring did.
    struct Summary: Identifiable {
        let id = UUID()
        var added = 0
        var recovered = 0
        var skipped = 0
        /// Entries in the backup that couldn't be read.
        var unreadable: [String] = []
        /// Entries that couldn't be written, such as when the device is full.
        var failed: [String] = []
        /// Entries restored whose original dates couldn't be set.
        var datesNotRestored: [String] = []

        /// Entries now in the journal that weren't before.
        var restoredCount: Int { added + recovered }
    }

    /// Reads a backup and works out what restoring it into `folder` would do, writing nothing.
    ///
    /// - Throws: `Failure` when the file isn't a usable Coquille backup.
    static func plan(restoring archive: Data, into folder: URL) throws -> Plan {
        let contents: ZipArchive.Contents
        do {
            contents = try ZipArchive.read(archive)
        } catch ZipArchive.Failure.tooLarge {
            throw Failure.tooLarge
        } catch {
            throw Failure.notABackup
        }

        guard let manifestData = contents.members.first(where: { $0.name == manifestName })?.data else {
            throw Failure.notABackup
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let parsed = date(fromISO: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date"))
            }
            return parsed
        }
        guard let version = try? decoder.decode(Header.self, from: manifestData).formatVersion, version >= 1 else {
            throw Failure.notABackup
        }
        guard version <= formatVersion else { throw Failure.newerFormat }
        guard let manifest = try? decoder.decode(Manifest.self, from: manifestData) else { throw Failure.notABackup }

        var files = [String: ZipArchive.Member]()
        for member in contents.members {
            files[normalized(member.name)] = member
        }
        let candidates = manifest.items.map { item -> Candidate in
            let name = safeName(item.name)
            let member = files[normalized(entriesFolder + item.path)]
            return Candidate(name: name ?? item.name, data: name == nil ? nil : member?.data,
                             modified: item.modified, created: item.created)
        }
        return Plan(candidates: candidates, outcomes: resolve(candidates, in: folder))
    }

    /// Writes what a plan describes into `folder`.
    ///
    /// The journal is read again here, so an entry added since the plan was made is never
    /// overwritten. Each file is written whole or not at all. An entry that can't be
    /// written is reported and the rest carry on.
    @discardableResult
    static func restore(_ plan: Plan, into folder: URL) -> Summary {
        // A journal always has its folder, but a missing one is made rather than failed.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var summary = Summary()
        let outcomes = resolve(plan.candidates, in: folder)

        for (candidate, outcome) in zip(plan.candidates, outcomes) {
            switch outcome {
            case .unreadable:
                summary.unreadable.append(candidate.name)
            case .skip:
                summary.skipped += 1
            case .add(let name), .recovered(let name):
                guard candidate.data != nil else {
                    summary.unreadable.append(candidate.name)
                    continue
                }
                let isRecovered: Bool
                if case .recovered = outcome { isRecovered = true } else { isRecovered = false }
                switch write(candidate, as: name, in: folder, retries: 3) {
                case .written(let datesKept):
                    if isRecovered { summary.recovered += 1 } else { summary.added += 1 }
                    if !datesKept { summary.datesNotRestored.append(candidate.name) }
                case .alreadyThere:
                    summary.skipped += 1
                case .failed:
                    summary.failed.append(candidate.name)
                }
            }
        }
        return summary
    }

    /// What happened to one entry when it was written.
    enum WriteResult: Equatable {
        /// Saved; `true` when its original dates were set too.
        case written(datesKept: Bool)
        /// The same writing is already under that name.
        case alreadyThere
        /// It couldn't be saved.
        case failed
    }

    /// Saves one entry as `name`, checking again inside the coordinated write that nothing
    /// holds the name. If something does, different writing is kept under the next free
    /// recovered name, up to `retries` times, and the same writing counts as already there.
    static func write(_ candidate: Candidate, as name: String, in folder: URL, retries: Int) -> WriteResult {
        guard let data = candidate.data else { return .failed }
        let url = folder.appending(path: name)
        var sameWriting = false
        do {
            let written = try CoordinatedFile.write(data, to: url) { target in
                guard FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else { return true }
                sameWriting = (try? Data(contentsOf: target)) == data
                return false
            }
            if written { return .written(datesKept: stampDates(of: url, from: candidate)) }
            if sameWriting { return .alreadyThere }
        } catch {
            return .failed
        }
        // Someone else took the name after the plan was made: look again and move on.
        guard retries > 0 else { return .failed }
        switch resolve([candidate], in: folder).first {
        case .add(let next), .recovered(let next):
            return write(candidate, as: next, in: folder, retries: retries - 1)
        case .skip:
            return .alreadyThere
        default:
            return .failed
        }
    }

    /// Gives a restored file its original dates, which order the journal and date entries
    /// whose names have none. Returns whether they were set; the file is restored either way.
    private static func stampDates(of url: URL, from candidate: Candidate) -> Bool {
        var attributes: [FileAttributeKey: Any] = [.modificationDate: candidate.modified]
        if let created = candidate.created { attributes[.creationDate] = created }
        do {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path(percentEncoded: false))
            return true
        } catch {
            return false
        }
    }

    /// Works out each entry's outcome against what's in `folder` now.
    ///
    /// Names are compared in one Unicode form and without regard to case, so "café" typed
    /// on a Mac and on an iPhone is the same entry. A name that's taken by different
    /// writing becomes "name (recovered).txt", then "(recovered 2)" and so on, and one of
    /// those holding the same writing counts as already restored.
    private static func resolve(_ candidates: [Candidate], in folder: URL) -> [Outcome] {
        var existing = [String: URL]()
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in urls {
            existing[key(url.lastPathComponent)] = url
        }
        // The names this restore will create, so two entries can't claim one name.
        var claimed = [String: Data]()
        var outcomes = [Outcome]()

        for candidate in candidates {
            guard let data = candidate.data else {
                outcomes.append(.unreadable)
                continue
            }
            let base = String(candidate.name.dropLast(4))
            var outcome = Outcome.unreadable
            for attempt in 0..<1000 {
                let name: String
                switch attempt {
                case 0: name = candidate.name
                case 1: name = "\(base) (recovered).txt"
                default: name = "\(base) (recovered \(attempt)).txt"
                }
                let nameKey = key(name)
                if let taken = claimed[nameKey] {
                    if taken == data {
                        outcome = .skip
                        break
                    }
                    continue
                }
                if let url = existing[nameKey] {
                    if let local = try? CoordinatedFile.read(url, { try Data(contentsOf: $0) }), local == data {
                        outcome = .skip
                        break
                    }
                    continue
                }
                outcome = attempt == 0 ? .add(name) : .recovered(name)
                claimed[nameKey] = data
                break
            }
            outcomes.append(outcome)
        }
        return outcomes
    }

    // MARK: - Names

    /// A file name from a backup that's safe to create in the journal, or `nil`.
    ///
    /// The name must be a single file name, following the same rules as the journal's own:
    /// no `/` or `:`, so a backup can't write outside the journal's folder. Backslashes are
    /// fine, since the journal allows them in titles. Only plain `.txt` files that aren't
    /// hidden are accepted.
    static func safeName(_ raw: String) -> String? {
        let name = normalized(raw)
        guard name.count > 4, name.lowercased().hasSuffix(".txt"), !name.hasPrefix("."),
              !name.contains("/"), !name.contains(":"), !name.contains("\0"),
              name == name.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return name
    }

    /// A name in one Unicode form, since the same accented title can be stored as one
    /// character or as a letter and an accent, depending on the device that made it.
    static func normalized(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
    }

    /// What two names are compared by: one Unicode form, ignoring case.
    private static func key(_ name: String) -> String {
        normalized(name).lowercased()
    }
}
