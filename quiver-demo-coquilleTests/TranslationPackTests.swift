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
import SwiftUI
import Translation
@testable import quiver_demo_coquille

@MainActor
final class TranslationPackTests: XCTestCase {

    /// Reports no misspellings, so only the grammar rules run.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    /// Stands in for Apple's translator, with a pack that can arrive mid-test.
    private final class FakeTranslator: Translator {
        var isInstalled = false

        /// Returns a fixed translation once the pack is installed.
        func translate(_ text: String) async throws -> String {
            guard isInstalled else { throw TranslationUnavailable.notInstalled }
            return "It's raining."
        }
    }

    // Each system answer maps to one label, and only a missing pack offers a download.
    func testStatusLabelsAndDownloadOffer() {
        let installed = TranslationPackStatus(.installed)
        let missing = TranslationPackStatus(.supported)
        let unsupported = TranslationPackStatus(.unsupported)
        XCTAssertEqual([installed, missing, unsupported], [.installed, .notInstalled, .unsupported])
        XCTAssertEqual([installed, missing, unsupported].map(\.label), ["Installed", "Not Installed", "Unsupported"])
        XCTAssertEqual([installed, missing, unsupported].map(\.canDownload), [false, true, false])
    }

    /// A model holding correct French, with its English pane open.
    private func makeModel(translator: FakeTranslator) throws -> EditorModel {
        let pack = try LanguagePack.french()
        let linter = Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
        let model = EditorModel(stats: StatsStore(fileURL: nil), journal: nil, linter: linter, translator: translator)
        model.text = AttributedString("Il pleut.")
        model.textDidChange()
        model.lintNow()
        return model
    }

    /// Lets the translation task finish.
    private func settle(_ model: EditorModel) async {
        for _ in 0..<200 {
            guard case .translating = model.english else { return }
            await Task.yield()
        }
    }

    // A missing pack points to Coquille's Settings, and the English appears once it's installed.
    func testRecheckShowsEnglishAfterThePackArrives() async throws {
        let translator = FakeTranslator()
        let model = try makeModel(translator: translator)
        model.isEnglishOn = true
        await settle(model)
        guard case .unavailable(let message) = model.english else {
            return XCTFail("A missing pack should explain itself")
        }
        XCTAssertTrue(message.contains("Coquille's Settings"))

        translator.isInstalled = true
        model.recheckEnglish()
        await settle(model)
        guard case .translated(let english) = model.english else {
            return XCTFail("The English should appear once the pack is installed")
        }
        XCTAssertEqual(english, "It's raining.")
    }
}
