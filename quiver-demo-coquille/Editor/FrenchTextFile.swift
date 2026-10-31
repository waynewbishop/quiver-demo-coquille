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

/// The learner's French as a plain-text file, for Open… and Save As….
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

    /// The suggested name for a new save, such as "2026-10-31", as a journal dates its entries.
    static var defaultFilename: String {
        Date.now.formatted(.iso8601.year().month().day())
    }
}

/// A File menu command for the focused window to carry out.
enum FileRequest {
    case open
    case save
}

extension FocusedValues {
    /// The focused window's pending File menu command.
    @Entry var fileRequest: Binding<FileRequest?>?
    /// Whether the focused window has French to save.
    @Entry var canSaveFile: Bool?
}

/// Open… and Save As… in the File menu on the Mac and iPad.
struct FileCommands: Commands {

    @FocusedValue(\.fileRequest) private var fileRequest
    @FocusedValue(\.canSaveFile) private var canSaveFile

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") { fileRequest?.wrappedValue = .open }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(fileRequest == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save As…") { fileRequest?.wrappedValue = .save }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(canSaveFile != true)
        }
    }
}
