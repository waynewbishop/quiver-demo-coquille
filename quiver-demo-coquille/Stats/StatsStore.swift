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

/// Keeps the learner's stats in a JSON file in Application Support. Nothing leaves the device.
@Observable
final class StatsStore {

    private(set) var stats: LearnerStats
    @ObservationIgnored private let fileURL: URL?

    /// Loads saved stats, or starts fresh when there are none.
    ///
    /// A file that's there but can't be read or decoded is moved aside, not overwritten,
    /// so the learner's history can still be recovered from it.
    init(fileURL: URL? = StatsStore.defaultFileURL()) {
        self.fileURL = fileURL
        stats = LearnerStats()
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            stats = try JSONDecoder().decode(LearnerStats.self, from: Data(contentsOf: fileURL))
        } catch {
            try? FileManager.default.moveItem(at: fileURL, to: Self.asideURL(for: fileURL))
        }
    }

    /// Where an unreadable stats file is kept, as in "LearnerStats unreadable 2026-11-18T20-15-04Z.json".
    static func asideURL(for fileURL: URL, at date: Date = .now) -> URL {
        let stamp = date.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let name = fileURL.deletingPathExtension().lastPathComponent
        return fileURL.deletingLastPathComponent().appending(path: "\(name) unreadable \(stamp).json")
    }

    /// Logs a lint pass and saves.
    func record(text: String, issues: [Issue], editingAt caret: Int? = nil) {
        stats.record(text: text, issues: issues, on: .now, editingAt: caret)
        save()
    }

    /// Counts a fixed error, typed or applied, logs it with its sentence from `text`, and saves.
    func recordFix(byLearner: Bool, issue: Issue? = nil, in text: String? = nil) {
        stats.recordFix(byLearner: byLearner, issue: issue, in: text, on: .now)
        save()
    }

    /// Starts the stats over, as on first launch, and saves.
    ///
    /// - Throws: The write's error if the reset couldn't be saved, with the stats left as they were.
    func reset() throws {
        let previous = stats
        stats = LearnerStats()
        do {
            try write()
        } catch {
            stats = previous
            throw error
        }
    }

    /// Writes the stats file. A failed write loses only this update, which the next one retries.
    private func save() {
        try? write()
    }

    /// Writes the stats file, or throws why it couldn't be written.
    private func write() throws {
        guard let fileURL else { return }
        let data = try JSONEncoder().encode(stats)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// The stats file inside the app's Application Support folder.
    static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "LearnerStats.json")
    }
}
