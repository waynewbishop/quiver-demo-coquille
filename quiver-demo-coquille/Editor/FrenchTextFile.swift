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

/// The learner's French as a plain-text file, for Open…, Save and Save As….
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

    /// Writes `text` as UTF-8 over the file at `url`, which Open… or Save As… already granted.
    static func write(_ text: String, to url: URL) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    /// Decodes UTF-8 first, then Windows Latin, which accepts any bytes.
    private static func decode(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) {
            return text
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    /// The suggested name for a new save: the story's title from the window, such as
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
    case newEntry
    case open
    case save
    case saveAs
}

extension FocusedValues {
    /// The focused window's pending File menu command.
    @Entry var fileRequest: Binding<FileRequest?>?
    /// Whether the focused window has French to save.
    @Entry var canSaveFile: Bool?
}

/// New Entry, Open…, Save and Save As… in the File menu on the Mac and iPad.
///
/// New Entry takes ⌘N from New Window: every window shares one draft, so a second
/// window would only show the same text.
struct FileCommands: Commands {

    @FocusedValue(\.fileRequest) private var fileRequest
    @FocusedValue(\.canSaveFile) private var canSaveFile

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") { fileRequest?.wrappedValue = .newEntry }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(fileRequest == nil)
            Button("Open…") { fileRequest?.wrappedValue = .open }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(fileRequest == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { fileRequest?.wrappedValue = .save }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(canSaveFile != true)
            Button("Save As…") { fileRequest?.wrappedValue = .saveAs }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(canSaveFile != true)
        }
    }
}
