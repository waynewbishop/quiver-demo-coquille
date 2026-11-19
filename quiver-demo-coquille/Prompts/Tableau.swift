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

/// One painting in the collection, with the French word it teaches.
///
/// Paintings are data, not code: each one is an entry in `fr.paintings.json` and an image
/// set named `Tableau-<id>` in `Paintings.xcassets`. Adding a painting needs no Swift.
nonisolated struct Tableau: Equatable, Sendable, Decodable {

    /// The permanent ID, the title as a slug such as `le-parc`. Never changed or reused.
    let id: String
    /// The painting's short French title. Permanent too, since entries store it.
    let title: String
    /// The one French word the painting carries, with its article, as in "le parc".
    let word: String
    /// The word in English, as in "the park".
    let wordEnglish: String
    /// The ID of the theme the painting belongs to.
    let theme: String
    /// The genre in French, as in "Paysage" or "Nature morte".
    let genre: String
    /// The painter whose style the painting follows.
    let painter: String
    /// What the painting shows, in English, for VoiceOver.
    let description: String
    /// The catalog ID of the daily prompt this painting belongs to, if it has one.
    let promptID: String?
    /// That prompt in French, which leads on the widget with the English beneath it.
    let french: String?
    /// A retired painting leaves the picker but still shows on entries that have it.
    let retired: Bool

    /// The asset catalog's image for this painting, shared by the app and the widget.
    var imageName: String { "Tableau-\(id)" }

    /// The genre and painter in French, as in "Paysage · à la Monet".
    var style: String { "\(genre) · à la \(painter)" }

    /// The keys in `fr.paintings.json`; `retired` may be left out.
    private enum CodingKeys: String, CodingKey {
        case id, title, word, wordEnglish, theme, genre, painter, description, promptID, french, retired
    }

    /// Decodes one painting, treating a missing `retired` as false.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        word = try container.decode(String.self, forKey: .word)
        wordEnglish = try container.decode(String.self, forKey: .wordEnglish)
        theme = try container.decode(String.self, forKey: .theme)
        genre = try container.decode(String.self, forKey: .genre)
        painter = try container.decode(String.self, forKey: .painter)
        description = try container.decode(String.self, forKey: .description)
        promptID = try container.decodeIfPresent(String.self, forKey: .promptID)
        french = try container.decodeIfPresent(String.self, forKey: .french)
        retired = try container.decodeIfPresent(Bool.self, forKey: .retired) ?? false
    }
}

/// A group of paintings in the picker, such as "À table · Food and cafés".
nonisolated struct TableauTheme: Equatable, Sendable, Decodable {
    let id: String
    /// The theme's name in French.
    let french: String
    /// The theme's name in English.
    let english: String
    /// A one-word English name for the picker's buttons, such as "Food"; the full name without one.
    let short: String?

    /// The name on the theme's picker button.
    var buttonTitle: String { short ?? english }
}

/// Loads the bundled painting collection from `fr.paintings.json`.
nonisolated enum TableauCatalog {

    /// The file's shape: the themes, then every painting ever shipped.
    struct Contents: Decodable, Sendable {
        let themes: [TableauTheme]
        let paintings: [Tableau]
    }

    /// Decodes the collection, throwing so tests can show what's wrong with the file.
    static func decode(_ data: Data) throws -> Contents {
        try JSONDecoder().decode(Contents.self, from: data)
    }

    /// The main bundle's collection, decoded once per process.
    private static let mainBundled = load(from: .main)

    /// Reads `fr.paintings.json` from `bundle`, or an empty collection when it can't be read.
    private static func load(from bundle: Bundle) -> Contents {
        guard let url = bundle.url(forResource: "fr.paintings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let contents = try? decode(data) else {
            return Contents(themes: [], paintings: [])
        }
        return contents
    }

    /// Every painting, retired ones included, in the file's order.
    static var all: [Tableau] { mainBundled.paintings }

    /// The paintings a writer can choose, in the file's order.
    static var available: [Tableau] { all.filter { !$0.retired } }

    /// The picker's themes, in the file's order.
    static var themes: [TableauTheme] { mainBundled.themes }

    /// Returns the painting with a permanent ID, or `nil` for an unknown ID.
    static func tableau(withID id: String) -> Tableau? {
        all.first { $0.id == id }
    }

    /// Returns the painting for `prompt`, or `nil` for a prompt with no painting yet.
    static func tableau(for prompt: WritingPrompt) -> Tableau? {
        all.first { $0.promptID == prompt.id }
    }

    /// Returns the painting whose title matches `title` as typed, ignoring capitals,
    /// accents, apostrophe style and extra spaces, or `nil` when none does.
    /// Retired paintings still match, so older entries keep showing them.
    static func tableau(titled title: String) -> Tableau? {
        let key = matchKey(title)
        guard !key.isEmpty else { return nil }
        return all.first { matchKey($0.title) == key }
    }

    /// `title` folded for matching, so "les nympheas" and "Les  Nymphéas" agree.
    static func matchKey(_ title: String) -> String {
        title.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
