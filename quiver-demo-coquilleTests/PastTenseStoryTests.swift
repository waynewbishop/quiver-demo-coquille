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

/// The B1 past-tense milestone: participle agreement with a preceding direct object, a
/// suggestion for the imparfait in a scene told after a past anchor, and a whole journal
/// entry checked in a clean, an agreement-error and an ambiguous-tense version.
@MainActor
final class PastTenseStoryTests: XCTestCase {

    /// Reports no misspellings, so the tests check grammar alone.
    private struct SilentSpellChecker: SpellChecker {
        func misspellings(in text: String) -> [Misspelling] { [] }
    }

    private func linter() throws -> Linter {
        let pack = try LanguagePack.french()
        return Linter(spellChecker: SilentSpellChecker(), grammar: pack.grammar, lexicon: pack.lexicon, explanations: pack.explanations)
    }

    /// The issues in `text`, each as "original → fix (severity)".
    private func report(_ text: String) throws -> [String] {
        try linter().lint(text).map { "\($0.original) → \($0.replacement ?? "no fix") (\($0.severity.rawValue))" }
    }

    /// Returns `text` with each issue's replacement applied, last issue first.
    private func applying(_ issues: [Issue], to text: String) -> String {
        var characters = Array(text)
        for issue in issues.sorted(by: { $0.offset > $1.offset }) {
            guard let replacement = issue.replacement else { continue }
            characters.replaceSubrange(issue.range, with: Array(replacement))
        }
        return String(characters)
    }

    // MARK: - The pronoun les

    // Les fixes the number but not the gender, so the participle needs a plural form.
    func testLesNeedsAPluralParticiple() throws {
        XCTAssertEqual(try report("Je les ai mangé."), ["mangé → mangés (error)"])
        XCTAssertEqual(try report("Elle ne les a pas regardé."), ["regardé → regardés (error)"])
        XCTAssertEqual(try report("Nous les avons déjà envoyé."), ["envoyé → envoyés (error)"])
    }

    // A participle that already fits, either gender, or one before an infinitive, stays quiet.
    func testLesLeavesCorrectFrenchAlone() throws {
        for text in ["Je les ai mangés.", "Je les ai mangées.", "Je les ai pris.", "Je les ai laissé partir.", "Il les a regardés hier."] {
            XCTAssertEqual(try report(text), [], text)
        }
    }

    // MARK: - A relative que

    // The participle agrees with the noun before que.
    func testRelativeQueAgreement() throws {
        XCTAssertEqual(try report("Les photos que j'ai pris sont belles."), ["pris → prises (error)"])
        XCTAssertEqual(try report("La photo que j'ai pris me plaît."), ["pris → prise (error)"])
        XCTAssertEqual(try report("Voici la robe que j'ai acheté."), ["acheté → achetée (error)"])
        XCTAssertEqual(try report("Voici les fleurs qu'elle n'a pas acheté."), ["acheté → achetées (error)"])
    }

    // Correct agreement, no preceding object, a conjunction que and invariant verbs stay quiet.
    func testRelativeQueLeavesCorrectFrenchAlone() throws {
        let clean = [
            "Les photos que j'ai prises sont belles.",
            "Le livre que j'ai lu me plaît.",
            "J'ai pris les photos hier.",
            "Je pense que j'ai pris la route.",
            "L'idée que j'ai perdu mon téléphone me fait peur.",
            "Les années que j'ai vécu ici étaient belles.",
            "Les photos que j'ai laissé partir étaient floues.",
            "La confirmation qu'elle a réussi a rassuré ses parents.",
            "L'annonce qu'il a réussi son examen a surpris tout le monde.",
            "La preuve qu'ils ont gagné nous rassure."
        ]
        for text in clean {
            XCTAssertEqual(try report(text), [], text)
        }
    }

    // MARK: - Les with a clear antecedent

    // When the sentence before names the only plural noun les can stand for, the fix gets its gender.
    func testLesTakesItsGenderFromAClearAntecedent() throws {
        XCTAssertEqual(try report("J'ai pris des photos. Je les ai envoyé à ma sœur."), ["envoyé → envoyées (error)"])
        XCTAssertEqual(try report("J'ai acheté des livres. Je les ai déjà lu."), ["lu → lus (error)"])
    }

    // A wrong gender on a plural participle is only a warning, since les could stand for something else.
    func testWrongGenderAfterLesIsOnlyAWarning() throws {
        XCTAssertEqual(try report("J'ai pris des photos. Je les ai envoyés à ma sœur."), ["envoyés → envoyées (warning)"])
    }

    // Two plural nouns of different gender, or none, keep both forms in the explanation.
    func testAmbiguousLesShowsBothForms() throws {
        let issues = try linter().lint("J'ai pris des photos et des livres. Je les ai envoyé à ma sœur.")
        XCTAssertEqual(issues.map(\.replacement), ["envoyés"])
        XCTAssertTrue(issues.first?.reason.contains("envoyées") == true)
    }

    // A correct gender after a clear antecedent stays quiet.
    func testLesWithACorrectGenderStaysQuiet() throws {
        XCTAssertEqual(try report("J'ai pris des photos. Je les ai envoyées à ma sœur."), [])
    }

    // MARK: - A relative que after an adjective

    // An adjective between the determiner and the noun, or right after it, doesn't hide the object.
    func testRelativeQueSeesThroughAnAdjective() throws {
        XCTAssertEqual(try report("Les belles photos que j'ai pris sont floues."), ["pris → prises (error)"])
        XCTAssertEqual(try report("Les photos magnifiques que j'ai pris sont floues."), ["pris → prises (error)"])
        XCTAssertEqual(try report("Les belles photos que j'ai prises sont floues."), [])
    }

    // MARK: - Tense in one sentence

    // A present weather clause in the same sentence as a past verb and anchor is suggested too.
    func testPresentSceneInTheAnchorSentence() throws {
        let issues = try linter().lint("Hier, j'ai pris des photos et il fait froid.")
        XCTAssertEqual(issues.map(\.original), ["fait"])
        XCTAssertEqual(issues.map(\.replacement), ["faisait"])
        XCTAssertTrue(issues.allSatisfy { $0.severity == .suggestion })
    }

    // A word that says it's true now keeps the same sentence's present alone.
    func testPresentMarkerInTheAnchorSentenceStaysQuiet() throws {
        XCTAssertEqual(try report("Hier, j'ai pris des photos, mais aujourd'hui il fait froid."), [])
    }

    // A blank line ends the account, so the past cue doesn't reach the next paragraph.
    func testPastCueStopsAtABlankLine() throws {
        XCTAssertEqual(try report("Hier, j'ai pris des photos.\n\nIl fait froid."), [])
        XCTAssertEqual(try report("Hier, j'ai pris des photos.\nIl fait froid.").count, 1)
    }

    // MARK: - Tense after a past anchor

    // A present weather clause after a past anchor gets an imparfait suggestion that never blocks.
    func testPresentSceneAfterAPastAnchorIsASuggestion() throws {
        let text = "Hier, j'ai pris des photos au parc. Il fait froid et il pleut."
        let issues = try linter().lint(text)
        XCTAssertEqual(issues.map(\.original), ["fait", "pleut"])
        XCTAssertEqual(issues.map(\.replacement), ["faisait", "pleuvait"])
        XCTAssertTrue(issues.allSatisfy { $0.severity == .suggestion && $0.kind == .tense })
        XCTAssertFalse(issues.contains { $0.severity.blocksPlayback })
    }

    // Anything that says it's true now, no anchor, or the wrong order leaves the present alone.
    func testPresentIsLeftAloneWhenItCanBeRight() throws {
        let clean = [
            "Hier, j'ai pris des photos. Aujourd'hui, il fait froid.",
            "Hier, j'ai pris des photos. Il fait encore froid.",
            "Ce matin, j'étais photographe. Il fait beau.",
            "Il fait froid. Hier, j'ai pris des photos.",
            "Hier, il faisait froid.",
            "Hier, j'ai pris des photos. Nous sommes rentrés. J'ai mangé. Il fait froid."
        ]
        for text in clean {
            XCTAssertEqual(try report(text), [], text)
        }
    }

    // MARK: - A whole entry

    /// The Parkrun entry told correctly.
    private let cleanEntry = "Samedi dernier, j'étais photographe pour le Parkrun à Redmond. Il faisait beau et il faisait froid. "
        + "J'ai pris beaucoup de photos avec mon portable. Les photos que j'ai prises sont belles."

    // The clean entry passes with nothing at all, not even a suggestion.
    func testCleanEntryStaysSilent() throws {
        XCTAssertEqual(try report(cleanEntry), [])
    }

    // One agreement error is one blocking error on the exact word, and fixing it leaves the entry clean.
    func testAgreementErrorIsOneBlockingIssueAndTheFixCleansIt() throws {
        let broken = cleanEntry.replacingOccurrences(of: "que j'ai prises", with: "que j'ai pris")
        let issues = try linter().lint(broken)
        XCTAssertEqual(issues.map(\.original), ["pris"])
        XCTAssertEqual(issues.first?.replacement, "prises")
        XCTAssertEqual(issues.first?.severity, .error)
        XCTAssertEqual(applying(issues, to: broken), cleanEntry)
        XCTAssertEqual(try report(applying(issues, to: broken)), [])
    }

    // A present scene after a past anchor gets suggestions only, so English and playback stay available.
    func testAmbiguousTenseNeverBlocks() throws {
        let entry = "Hier, j'étais photographe pour le Parkrun à Redmond. Il fait beau et il fait froid. J'ai pris beaucoup de photos."
        let issues = try linter().lint(entry)
        XCTAssertEqual(issues.map(\.original), ["fait", "fait"])
        XCTAssertTrue(issues.allSatisfy { $0.severity == .suggestion })
        XCTAssertFalse(issues.contains { $0.severity.blocksPlayback })
    }
}
