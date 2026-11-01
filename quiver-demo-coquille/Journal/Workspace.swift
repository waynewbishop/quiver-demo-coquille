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

    /// The editor's writing since it was last saved, or `nil` without any.
    func unsavedText() -> String? {
        try? FrenchTextFile.text(at: unsavedURL)
    }

    /// Keeps the editor's writing until the learner saves or discards it.
    func writeUnsaved(_ text: String) {
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: unsavedURL, options: .atomic)
    }

    /// Forgets the editor's writing, once it's saved or discarded.
    func clearUnsaved() {
        try? FileManager.default.removeItem(at: unsavedURL)
    }

    /// What the editor had open, or unsaved writing when that entry is gone.
    func openDocument(in journal: Journal) -> EditorDocument {
        guard let value = defaults?.string(forKey: Self.documentKey), value.hasPrefix("entry:") else { return .unsaved }
        let url = journal.folderURL.appending(path: String(value.dropFirst("entry:".count)))
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? .entry(url) : .unsaved
    }

    /// Remembers what the editor has open.
    func setOpenDocument(_ document: EditorDocument) {
        let value: String
        switch document {
        case .unsaved: value = "unsaved"
        case .entry(let url): value = "entry:" + url.lastPathComponent
        }
        defaults?.set(value, forKey: Self.documentKey)
    }
}
