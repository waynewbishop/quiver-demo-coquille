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
    init(fileURL: URL? = StatsStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(LearnerStats.self, from: data) {
            stats = saved
        } else {
            stats = LearnerStats()
        }
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
    func reset() {
        stats = LearnerStats()
        save()
    }

    /// Writes the stats file. A failed write loses only this update, which the next one retries.
    private func save() {
        guard let fileURL, let data = try? JSONEncoder().encode(stats) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// The stats file inside the app's Application Support folder.
    static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "LearnerStats.json")
    }
}
