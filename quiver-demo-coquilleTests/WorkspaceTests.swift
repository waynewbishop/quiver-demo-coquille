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
final class WorkspaceTests: XCTestCase {

    /// The test's own temporary folder, removed when the test ends.
    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WorkspaceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Fresh defaults for the test alone.
    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "WorkspaceTests-\(UUID().uuidString)"))
    }

    /// Returns a model as a fresh launch creates it, with last time's writing put back.
    private func relaunch(journal: Journal, workspace: Workspace) -> EditorModel {
        let model = EditorModel(stats: StatsStore(fileURL: nil), journal: journal, workspace: workspace)
        model.restore()
        return model
    }

    /// Replaces the text as typing would.
    private func type(_ text: String, into model: EditorModel) {
        model.text = AttributedString(text)
        model.textDidChange()
    }

    // A draft that can't be written is flagged, and the next save tries again rather than
    // skipping the unchanged text.
    func testFailedDraftWriteIsRetried() throws {
        let folder = try makeFolder()
        let journal = Journal(folderURL: folder.appending(path: "Journal"))
        // A file where the workspace folder's parent should be, so the folder can't be made.
        let blocker = folder.appending(path: "Blocked")
        try Data().write(to: blocker)
        let workspace = Workspace(folderURL: blocker.appending(path: "Workspace"), defaults: try makeDefaults())

        let model = relaunch(journal: journal, workspace: workspace)
        type("Il pleut.", into: model)
        model.saveNow()
        XCTAssertTrue(model.cannotKeepDraft)

        try FileManager.default.removeItem(at: blocker)
        model.saveNow()
        XCTAssertFalse(model.cannotKeepDraft)
        XCTAssertEqual(relaunch(journal: journal, workspace: workspace).plainText, "Il pleut.")
    }

    // A draft kept for one document is never restored into another, as when forgetting
    // it failed before the editor moved on; a draft for the open entry still returns.
    func testDraftsStayWithTheirDocument() throws {
        let folder = try makeFolder()
        let journal = Journal(folderURL: folder.appending(path: "Journal"))
        let workspace = Workspace(folderURL: folder.appending(path: "Workspace"), defaults: try makeDefaults())
        let entry = try journal.createEntry(text: "Il neige.", on: .now)

        try workspace.writeUnsaved("Brouillon.", for: .unsaved, entryDate: .now)
        workspace.setOpenDocument(.entry(entry))
        let stale = relaunch(journal: journal, workspace: workspace)
        XCTAssertEqual(stale.document, .entry(entry))
        XCTAssertEqual(stale.plainText, "Il neige.")
        XCTAssertFalse(stale.isEdited)

        try workspace.writeUnsaved("Il neige encore.", for: .entry(entry), entryDate: .now)
        let edited = relaunch(journal: journal, workspace: workspace)
        XCTAssertEqual(edited.plainText, "Il neige encore.")
        XCTAssertTrue(edited.isEdited)
    }

    // Writing kept before drafts named their document still comes back.
    func testDraftWithoutAnOwnerStillRestores() throws {
        let folder = try makeFolder()
        let journal = Journal(folderURL: folder.appending(path: "Journal"))
        let workspaceFolder = folder.appending(path: "Workspace")
        try FileManager.default.createDirectory(at: workspaceFolder, withIntermediateDirectories: true)
        try Data("Il fait beau.".utf8).write(to: workspaceFolder.appending(path: "Unsaved Writing.txt"))
        let workspace = Workspace(folderURL: workspaceFolder, defaults: try makeDefaults())

        XCTAssertEqual(relaunch(journal: journal, workspace: workspace).plainText, "Il fait beau.")
    }

    // A guided entry begun before midnight keeps that day's name after a relaunch.
    func testRestoredDraftKeepsItsEntryDate() throws {
        let folder = try makeFolder()
        let journal = Journal(folderURL: folder.appending(path: "Journal"))
        let workspace = Workspace(folderURL: folder.appending(path: "Workspace"), defaults: try makeDefaults())
        let lateEvening = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23, minute: 50)))

        let first = relaunch(journal: journal, workspace: workspace)
        first.newEntry(for: ExercisePrompt(title: "Le soir", prompts: ["What did you eat?"], hint: nil), on: lateEvening)
        first.saveNow()

        let second = relaunch(journal: journal, workspace: workspace)
        XCTAssertEqual(second.proposedName(title: ""), "2026-11-09")
    }
}
