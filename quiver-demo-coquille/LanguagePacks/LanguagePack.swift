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

/// Everything language-specific, loaded from one language's bundled files.
///
/// French is the only pack. Spellcheck, speech and translation take their locale
/// from the active pack, so nothing else in the app hard-codes "fr".
nonisolated struct LanguagePack: Sendable {

    /// Thrown when a bundled file is missing.
    struct MissingResource: Error, Equatable {
        let name: String
    }

    /// The pack's language, such as French.
    let language: Locale.Language
    /// The spellchecker language identifier.
    let spellCheckerLanguage: String
    /// The speech voice language, such as "fr-FR".
    let voiceLanguage: String
    let lexicon: Lexicon
    let explanations: ExplanationTemplates
    let grammar: any Grammar
    /// The trained gender model, or `nil` when no `fr.gender-model.json` is bundled yet.
    let genderModel: EndingGenderModel?

    /// Loads the French pack from the app bundle.
    ///
    /// - Throws: `MissingResource` when a required file is absent, or a decoding error.
    static func french(in bundle: Bundle = .main) throws -> LanguagePack {
        let lexicon = try Lexicon(contentsOf: url(of: "fr.lexicon", in: bundle))
        let explanations = try ExplanationTemplates(data: Data(contentsOf: url(of: "fr.explanations", in: bundle)))
        let idioms = try JSONDecoder().decode([Idiom].self, from: Data(contentsOf: url(of: "fr.idioms", in: bundle)))

        // The model is optional: until it is trained, unknown nouns simply go unchecked.
        let genderModel = try bundle.url(forResource: "fr.gender-model", withExtension: "json").map {
            try JSONDecoder().decode(EndingGenderModel.self, from: Data(contentsOf: $0))
        }

        return LanguagePack(
            language: Locale.Language(identifier: "fr"),
            spellCheckerLanguage: "fr",
            voiceLanguage: "fr-FR",
            lexicon: lexicon,
            explanations: explanations,
            grammar: FrenchGrammar(
                lexicon: lexicon,
                idioms: idioms,
                explanations: explanations,
                genderPredictor: genderModel
            ),
            genderModel: genderModel
        )
    }

    /// Returns the URL of a bundled JSON file.
    private static func url(of name: String, in bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw MissingResource(name: name + ".json")
        }
        return url
    }
}
