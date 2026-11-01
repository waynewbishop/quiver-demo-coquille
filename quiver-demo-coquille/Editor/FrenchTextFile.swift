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

import SwiftUI
import UniformTypeIdentifiers

/// The learner's French as a plain-text file, for journal entries, Import… and Export a Copy….
///
/// Only the words are saved, never the issues or their fixes: Coquille lints a file
/// again when it opens, and any text editor or teacher can read it.
struct FrenchTextFile: FileDocument {

    static let readableContentTypes: [UTType] = [.plainText]

    var text: String

    /// Wraps the editor's text for saving.
    init(text: String) {
        self.text = text
    }

    /// Reads a file's text, as UTF-8 or, failing that, the encoding Windows editors often use.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try Self.decode(data)
    }

    /// Writes the text as UTF-8.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }

    /// Reads the text of a file the learner picked, which may sit outside the app's own folders.
    static func text(at url: URL) throws -> String {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodes UTF-8 first, then Windows Latin, which accepts any bytes.
    private static func decode(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            return text
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// The suggested name for an exported copy: the story's title from the window, such as
    /// "Une journée au marché", or the date, such as "2026-10-31", as a journal dates
    /// its entries, until there's a title.
    ///
    /// Slashes and colons are left out, since the Finder and Files can't use them in a name.
    static func suggestedFilename(for title: String?, on date: Date = .now) -> String {
        let name = (title ?? "")
            .filter { $0 != "/" && $0 != ":" }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()) : name
    }
}

/// A File menu command for the focused window to carry out.
enum FileRequest {
    case new
    case importFile
    case save
    case saveAsNewEntry
    case renameEntry
    case duplicateEntry
    case deleteEntry
    case export
}

/// What the focused window's File menu can do right now.
struct FileMenuState: Equatable {
    /// Whether there's writing Save can keep.
    var canSave = false
    /// Whether there's French to export.
    var canExport = false
    /// Whether a saved entry is open, for Rename, Duplicate and Delete.
    var hasOpenEntry = false
}

extension FocusedValues {
    /// The focused window's pending File menu command.
    @Entry var fileRequest: Binding<FileRequest?>?
    /// What the focused window's File menu can do.
    @Entry var fileMenuState: FileMenuState?
}

/// The File menu on the Mac and iPad, arranged as in Xcode: new, import, save, then the
/// open entry's Rename, Duplicate and Delete, then export.
///
/// Nothing is saved to the journal without Save. New takes ⌘N from New Window, since
/// each window would only show the same journal.
struct FileCommands: Commands {

    @FocusedValue(\.fileRequest) private var fileRequest
    @FocusedValue(\.fileMenuState) private var state

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            button("New", .new, enabled: fileRequest != nil)
                .keyboardShortcut("n", modifiers: .command)
            button("Import…", .importFile, enabled: fileRequest != nil)
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            button("Save", .save, enabled: state?.canSave == true)
                .keyboardShortcut("s", modifiers: .command)
            button("Save as New Entry…", .saveAsNewEntry, enabled: state?.canSave == true)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            button("Rename Entry…", .renameEntry, enabled: state?.hasOpenEntry == true)
            button("Duplicate Entry", .duplicateEntry, enabled: state?.hasOpenEntry == true)
            button("Delete Entry…", .deleteEntry, enabled: state?.hasOpenEntry == true)
            Divider()
            button("Export a Copy…", .export, enabled: state?.canExport == true)
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }

    /// A menu item that hands `request` to the focused window.
    private func button(_ title: String, _ request: FileRequest, enabled: Bool) -> some View {
        Button(title) { fileRequest?.wrappedValue = request }
            .disabled(!enabled)
    }
}
