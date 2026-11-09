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
final class ExerciseRestoreTests: XCTestCase {

    // An unsaved exercise keeps its title and hint across a relaunch, until the draft is replaced.
    func testExerciseDetailsSurviveARelaunch() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CoquilleTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CoquilleTests-\(UUID().uuidString)"))
        let workspace = Workspace(folderURL: folder.appending(path: "Workspace"), defaults: defaults)
        let journal = Journal(folderURL: folder.appending(path: "Journal"))

        /// A model as a fresh launch creates it, with last time's writing put back.
        func relaunch() -> EditorModel {
            let model = EditorModel(stats: StatsStore(fileURL: nil), journal: journal, workspace: workspace)
            model.restore()
            return model
        }

        let first = relaunch()
        first.newEntry(for: ExercisePrompt(title: "Ouvert ou fermé", prompts: ["Is it open?"], hint: "c'était"))
        first.saveNow()

        let second = relaunch()
        XCTAssertEqual(second.exerciseTitle, "Ouvert ou fermé")
        XCTAssertEqual(second.exerciseHint, "c'était")

        second.startNew()
        second.saveNow()
        let third = relaunch()
        XCTAssertNil(third.exerciseTitle)
        XCTAssertNil(third.exerciseHint)
    }
}
