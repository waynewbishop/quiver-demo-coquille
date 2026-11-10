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

/// What the editor has open.
enum EditorDocument: Hashable {
    /// Writing that isn't in the journal, which is lost unless the learner saves it.
    case unsaved
    /// A saved journal entry.
    case entry(URL)
}

/// Keeps the editor's writing between launches, like the Notebook's editor: the text
/// as it stands, and the entry it came from, if any.
///
/// Its file lives in Application Support, out of sight; the journal holds only what
/// the learner saved.
struct Workspace {

    let folderURL: URL
    let defaults: UserDefaults?

    /// The defaults key for what the editor had open.
    static let documentKey = "openDocument"

    /// A workspace in the app's Application Support folder.
    static func standard() -> Workspace? {
        guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return Workspace(folderURL: folder, defaults: .standard)
    }

    private var unsavedURL: URL { folderURL.appending(path: "Unsaved Writing.txt") }

    /// The defaults key for the document the unsaved writing belongs to, and its entry date.
    static let draftKey = "unsavedDraft"

    /// The editor's writing since it was last saved, and the day a new entry from it is
    /// named for, or `nil` without any.
    ///
    /// Writing kept for one document is never handed to another: if forgetting it ever
    /// failed, it stays on disk but no longer matches what the editor has open.
    func unsavedDraft() -> (text: String, entryDate: Date?)? {
        guard let text = try? FrenchTextFile.text(at: unsavedURL) else { return nil }
        // Writing kept before drafts named their document belongs to whatever is open.
        guard let draft = defaults?.dictionary(forKey: Self.draftKey) else { return (text, nil) }
        guard draft["document"] as? String == storedDocument else { return nil }
        return (text, (draft["entryDate"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)))
    }

    /// Keeps the editor's writing for `document` until the learner saves or discards it.
    func writeUnsaved(_ text: String, for document: EditorDocument, entryDate: Date) throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: unsavedURL, options: .atomic)
        defaults?.set(
            ["document": Self.storedValue(for: document), "entryDate": entryDate.timeIntervalSinceReferenceDate],
            forKey: Self.draftKey
        )
    }

    /// Forgets the editor's writing, once it's saved or discarded.
    func clearUnsaved() throws {
        // Disown the writing first, so writing a failed removal leaves behind is never restored.
        defaults?.set(["document": "discarded"], forKey: Self.draftKey)
        do {
            try FileManager.default.removeItem(at: unsavedURL)
        } catch CocoaError.fileNoSuchFile {
            // Nothing was kept, which is what forgetting asks for.
        }
        defaults?.removeObject(forKey: Self.draftKey)
    }

    /// What the editor last had open, as stored in defaults.
    private var storedDocument: String {
        defaults?.string(forKey: Self.documentKey) ?? Self.storedValue(for: .unsaved)
    }

    /// The defaults value naming `document`.
    private static func storedValue(for document: EditorDocument) -> String {
        switch document {
        case .unsaved: "unsaved"
        case .entry(let url): "entry:" + url.lastPathComponent
        }
    }

    /// What the editor had open, or unsaved writing when that entry is gone.
    func openDocument(in journal: Journal) -> EditorDocument {
        guard let value = defaults?.string(forKey: Self.documentKey), value.hasPrefix("entry:") else { return .unsaved }
        let url = journal.folderURL.appending(path: String(value.dropFirst("entry:".count)))
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? .entry(url) : .unsaved
    }

    /// Remembers what the editor has open.
    func setOpenDocument(_ document: EditorDocument) {
        defaults?.set(Self.storedValue(for: document), forKey: Self.documentKey)
    }

    /// The defaults key for the open exercise's title and hint.
    static let exerciseKey = "openExercise"

    /// The title and hint of the exercise in the unsaved draft, or `nil` without one.
    func exerciseDetails() -> (title: String, hint: String?)? {
        guard let details = defaults?.dictionary(forKey: Self.exerciseKey) as? [String: String],
              let title = details["title"] else { return nil }
        return (title, details["hint"])
    }

    /// Remembers the exercise's title and hint alongside its unsaved draft.
    func setExerciseDetails(title: String, hint: String?) {
        var details = ["title": title]
        details["hint"] = hint
        defaults?.set(details, forKey: Self.exerciseKey)
    }

    /// Forgets the exercise once its draft is replaced.
    func clearExerciseDetails() {
        defaults?.removeObject(forKey: Self.exerciseKey)
    }
}
