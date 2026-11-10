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
import Observation

/// The learner's saved journal entries: one plain-text file each, in a folder Coquille keeps.
///
/// The file names are the only record, such as "2026-10-31 Une journée au marché.txt",
/// so the Finder, the Files app, any text editor and any teacher see what Coquille sees.
/// A name starts with the entry's date, followed by the title the learner gave it.
///
/// Nothing is written here unless the learner chooses to: Save, Import, Rename,
/// Duplicate and Delete are the only ways in.
@Observable
final class Journal {

    /// One entry as listed: its file, date, title and opening line.
    struct Entry: Identifiable, Equatable {
        let url: URL
        /// The date at the front of the file name, or the file's modification date without one.
        let date: Date
        let modified: Date
        /// The title after the date in the file name, or `nil` until the story has one.
        let title: String?
        /// The entry's French, read when the list was built or last written.
        let text: String

        var id: URL { url }

        /// The first line of French worth showing in a list, skipping the notes and a new
        /// entry's date line, so every entry isn't previewed by the same guide note.
        var preview: String {
            let lines = Notes.removed(text).split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let body = lines.first.map(Journal.isDateLine) == true ? lines.dropFirst() : lines[...]
            return body.first ?? ""
        }
    }

    /// The folder holding the entries.
    let folderURL: URL
    /// Every entry, newest first.
    private(set) var entries: [Entry] = []
    @ObservationIgnored private let calendar: Calendar

    /// Opens the journal in `folderURL`, creating the folder if needed, and lists its entries.
    init(folderURL: URL, calendar: Calendar = .current) {
        self.folderURL = folderURL
        self.calendar = calendar
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        refresh()
    }

    /// The app's Documents folder, which the Files app shows on iPhone and iPad.
    ///
    /// On the Mac the app is sandboxed, so this is inside its container; Show in Finder
    /// reaches it from the entries list.
    static func defaultFolderURL() -> URL {
        URL.documentsDirectory
    }

    // MARK: - Listing

    /// Whether the last `refresh()` couldn't read the folder, so `entries` is the last
    /// listing that could, rather than what's there now.
    private(set) var isUnavailable = false

    /// Reads the folder again, for files added, changed or removed outside Coquille.
    ///
    /// A folder that can't be read keeps its last listing, since an unreadable journal
    /// isn't an empty one; an entry that alone can't be read is left out.
    @discardableResult
    func refresh() -> Bool {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            isUnavailable = true
            return false
        }
        isUnavailable = false
        entries = urls
            .filter { $0.pathExtension.lowercased() == "txt" }
            .compactMap { url in
                guard let text = try? CoordinatedFile.read(url, FrenchTextFile.text(at:)) else { return nil }
                return entry(for: url, text: text)
            }
        sort()
        return true
    }

    /// The listed entry for a file, if it's in the journal.
    func entry(at url: URL) -> Entry? {
        entries.first { $0.url == url }
    }

    // MARK: - Changing entries

    /// Creates an entry file named for `date` and `title`, such as
    /// "2026-10-31 Une journée au marché.txt", or "2026-10-31.txt" with no title.
    /// A name that's taken gets a number, as in "2026-10-31 (2).txt".
    @discardableResult
    func createEntry(text: String, title: String? = nil, on date: Date = .now) throws -> URL {
        let url = uniqueURL(for: Self.baseName(day: dayString(for: date), title: title))
        try write(text, to: url)
        return url
    }

    /// The name an entry would be saved under, without ".txt" or a number.
    func proposedName(title: String?, on date: Date = .now) -> String {
        Self.baseName(day: dayString(for: date), title: title)
    }

    /// Copies an outside file's text in as a new entry, keeping its name after the date,
    /// or its own date when the name already starts with one.
    @discardableResult
    func importEntry(text: String, originalName: String, on date: Date = .now) throws -> URL {
        let name = Self.cleaned(originalName)
        let base: String
        if self.date(fromName: name) != nil {
            base = name
        } else {
            base = name.isEmpty ? dayString(for: date) : "\(dayString(for: date)) \(name)"
        }
        let url = uniqueURL(for: base)
        try write(text, to: url)
        return url
    }

    /// Writes an entry's text and updates its place in the list.
    func write(_ text: String, to url: URL) throws {
        try CoordinatedFile.write(Data(text.utf8), to: url)
        entries.removeAll { $0.url == url }
        entries.append(entry(for: url, text: text))
        sort()
    }

    /// Gives an entry a new title, keeping the date at the front of its name. An empty
    /// title leaves just the date. Returns the entry's file, renamed or not.
    @discardableResult
    func rename(_ url: URL, to title: String) throws -> URL {
        let base = Self.baseName(day: day(of: url), title: title)
        guard base != Self.baseWithoutNumber(of: url) else { return url }
        let renamed = uniqueURL(for: base)
        try CoordinatedFile.move(url, to: renamed)
        if let old = entries.firstIndex(where: { $0.url == url }) {
            let text = entries.remove(at: old).text
            entries.append(entry(for: renamed, text: text))
            sort()
        }
        return renamed
    }

    /// Copies an entry under the same date, with "copy" after its title.
    @discardableResult
    func duplicate(_ url: URL) throws -> URL {
        let text = try CoordinatedFile.read(url, FrenchTextFile.text(at:))
        let title = [Self.title(of: url), "copy"].compactMap { $0 }.joined(separator: " ")
        let copy = uniqueURL(for: Self.baseName(day: day(of: url), title: title))
        try write(text, to: copy)
        return copy
    }

    /// Removes an entry's file.
    func delete(_ url: URL) throws {
        try CoordinatedFile.remove(url)
        entries.removeAll { $0.url == url }
    }

    // MARK: - Names

    /// The title in an entry's file name, after its date, or `nil` for an untitled entry.
    static func title(of url: URL) -> String? {
        var name = url.deletingPathExtension().lastPathComponent
        if name.count >= 10, isDay(String(name.prefix(10))) {
            name = String(name.dropFirst(10))
        }
        // A " (2)" that only keeps two names apart isn't part of the title.
        if let range = name.range(of: #"\s*\(\d+\)$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        let title = name.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }

    /// The French weekday names as a date heading writes them, indexed from Sunday.
    static let frenchWeekdays = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]

    /// Whether a line is a date heading such as "Samedi 31 octobre 2026", or the older
    /// "Le 31 octobre 2026", with no sentence after it.
    static func isDateLine(_ line: String) -> Bool {
        let firstWord = String(line.prefix { $0 != " " })
        return (firstWord == "Le" || frenchWeekdays.contains(firstWord))
            && line.contains(where: \.isNumber)
            && !line.contains(where: { ".!?".contains($0) })
    }

    /// "2026-10-31 Title", or "2026-10-31" when the title is empty.
    private static func baseName(day: String, title: String?) -> String {
        let title = cleaned(title ?? "")
        return title.isEmpty ? day : "\(day) \(title)"
    }

    /// A file's name without ".txt" or the " (2)" that only keeps two names apart.
    private static func baseWithoutNumber(of url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"\s*\(\d+\)$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    /// The "yyyy-MM-dd" at the front of an entry's name, or today's for a name without one.
    private func day(of url: URL) -> String {
        let prefix = String(url.deletingPathExtension().lastPathComponent.prefix(10))
        return Self.isDay(prefix) ? prefix : dayString(for: .now)
    }

    /// Leaves out the characters the Finder and Files can't use in a name.
    private static func cleaned(_ name: String) -> String {
        name.filter { $0 != "/" && $0 != ":" }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether `text` is a "yyyy-MM-dd" day.
    private static func isDay(_ text: String) -> Bool {
        text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// The date at the front of a file name, at noon on that day, or `nil` without one.
    private func date(fromName name: String) -> Date? {
        let prefix = String(name.prefix(10))
        guard Self.isDay(prefix) else { return nil }
        let parts = prefix.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// "2026-10-31" for `date` in the journal's calendar.
    private func dayString(for date: Date) -> String {
        LearnerStats.dayKey(for: date, calendar: calendar)
    }

    /// `base`.txt, or the first of `base` (2).txt, (3).txt and so on that isn't taken.
    private func uniqueURL(for base: String) -> URL {
        var url = folderURL.appending(path: "\(base).txt")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = folderURL.appending(path: "\(base) (\(number)).txt")
            number += 1
        }
        return url
    }

    /// Builds the listed entry for a file and its text.
    private func entry(for url: URL, text: String) -> Entry {
        // A URL caches what it last read about its file, which a write has just changed.
        var url = url
        url.removeAllCachedResourceValues()
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
        let name = url.deletingPathExtension().lastPathComponent
        return Entry(url: url, date: date(fromName: name) ?? modified, modified: modified, title: Self.title(of: url), text: text)
    }

    /// Newest day first, and within a day, the most recently written first.
    private func sort() {
        entries.sort { first, second in
            let firstDay = calendar.startOfDay(for: first.date)
            let secondDay = calendar.startOfDay(for: second.date)
            if firstDay != secondDay { return firstDay > secondDay }
            if first.modified != second.modified { return first.modified > second.modified }
            return first.url.lastPathComponent > second.url.lastPathComponent
        }
    }
}
