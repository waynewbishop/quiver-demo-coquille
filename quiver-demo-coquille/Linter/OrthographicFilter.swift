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

/// The orthographic layer: system spelling, Lexique validation and Quiver suggestion ranking.
struct OrthographicFilter: LinguisticFilter {
    let identifier = "orthography.spelling"
    let layer = LinguisticLayer.orthography
    let targetLevel = CefrLevel.a1

    let spellChecker: any SpellChecker
    let lexicon: Lexicon
    let explanations: ExplanationTemplates

    /// Turns misspellings into issues, skipping any word the lexicon knows.
    ///
    /// Only guesses the lexicon knows are offered: the Mac's French spellchecker also
    /// returns English words, so "fro" would otherwise become "from". A misspelling
    /// with no French guess is still underlined, as a warning with no fix: seeing the
    /// mistake comes first, and a name the system doesn't know never blocks play.
    ///
    /// The system checks an elided word whole, so "l'apres-midi" comes back with the
    /// guess "l'après-midi". The lexicon has neither the article nor every compound, so
    /// words are looked up as `knows(_:)` and `isFrenchGuess(_:)` describe.
    ///
    /// Two words typed as one, such as "mecouche", are split before the system's guesses
    /// are ranked: two exact lexicon words are stronger evidence than a guess a letter or
    /// two away, and the system never suggests a space.
    func evaluate(_ context: LintContext) -> [Issue] {
        spellChecker.misspellings(in: context.text).compactMap { misspelling in
            guard !knows(misspelling.word) else { return nil }
            if mayBeRunTogether(misspelling, in: context.text), let fix = runTogetherFix(for: misspelling.word) {
                return runTogetherIssue(misspelling, fix: fix)
            }
            let frenchGuesses = misspelling.guesses.filter(isFrenchGuess)
            // Quiver ranks the French guesses by letter-pair similarity to the typo.
            guard let best = SuggestionRanker.ranked(frenchGuesses, for: misspelling.word).first else {
                return unknownWordIssue(misspelling)
            }
            let explanation = explanations.render(.spelling, [
                "word": misspelling.word,
                "suggestion": best,
                "where": Self.changedPart(of: misspelling.word, toReach: best)
            ])
            return Issue(
                kind: .spelling,
                severity: .error,
                offset: misspelling.offset,
                length: misspelling.word.count,
                original: misspelling.word,
                replacement: best,
                reason: explanation.reason,
                hint: explanation.hint,
                source: "System spellcheck · ranked by Quiver"
            )
        }
    }

    /// Where `word` must change to become `suggestion`, as the hint names it: "the accents",
    /// "the ending", "the start" or "the middle".
    ///
    /// The hint points the learner at the part to rework without giving the answer,
    /// which stays behind Show fix.
    static func changedPart(of word: String, toReach suggestion: String) -> String {
        let typo = Array(word.lowercased())
        let fix = Array(suggestion.lowercased())
        let unaccented: (String) -> String = { $0.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr")).lowercased() }
        if typo != fix && unaccented(word) == unaccented(suggestion) {
            return "the accents"
        }

        var sharedStart = 0
        while sharedStart < min(typo.count, fix.count) && typo[sharedStart] == fix[sharedStart] {
            sharedStart += 1
        }
        var sharedEnd = 0
        while sharedEnd < min(typo.count, fix.count) - sharedStart
                && typo[typo.count - 1 - sharedEnd] == fix[fix.count - 1 - sharedEnd] {
            sharedEnd += 1
        }

        // The letters of the typo that differ run from `sharedStart` up to `changeEnd`.
        let changeEnd = typo.count - sharedEnd
        if sharedStart >= typo.count * 2 / 3 {
            return "the ending"
        } else if changeEnd <= (typo.count + 2) / 3 {
            return "the start"
        } else {
            return "the middle"
        }
    }

    /// The articles and pronouns French elides before a vowel, as in l'école and jusqu'ici.
    static let elisions: Set<String> = [
        "l", "d", "j", "m", "t", "s", "n", "c", "qu", "jusqu", "lorsqu", "puisqu", "quoiqu"
    ]

    /// `word`, lowercased, with any elided article or pronoun in front set aside: "L'école" becomes "école".
    static func withoutElision(_ word: String) -> String {
        let normalized = FrenchTokenizer.normalize(word)
        guard let apostrophe = normalized.firstIndex(of: "'") else { return normalized }
        let rest = normalized[normalized.index(after: apostrophe)...]
        guard elisions.contains(String(normalized[..<apostrophe])), !rest.isEmpty else { return normalized }
        return String(rest)
    }

    /// Whether the lexicon knows `word` as written or once its elision is set aside.
    private func knows(_ word: String) -> Bool {
        lexicon.contains(FrenchTokenizer.normalize(word)) || lexicon.contains(Self.withoutElision(word))
    }

    /// Whether a system guess is French: a word the lexicon knows, or a compound whose
    /// every part it knows, as in après-midi, which Lexique leaves out.
    ///
    /// Compounds are accepted part by part only as guesses, which the system already
    /// knows as words; a typed compound is still checked whole.
    private func isFrenchGuess(_ guess: String) -> Bool {
        if knows(guess) { return true }
        let parts = Self.withoutElision(guess).split(separator: "-")
        guard parts.count > 1 else { return false }
        return parts.allSatisfy { lexicon.contains(String($0)) }
    }

    // MARK: - Run-together words

    /// The function words a learner most often runs into the next word, as in "mecouche" or "dela".
    static let runOnHeads: Set<String> = [
        "je", "me", "te", "se", "le", "la", "les", "ne", "de", "du", "des", "ce",
        "un", "une", "il", "elle", "on", "nous", "vous", "ils", "elles", "en", "y",
        "tu", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
        "au", "aux", "et", "qui", "que", "très", "si"
    ]

    /// The letters that open a word with a vowel sound, before which French elides.
    private static let vowelSounds = Set("aeiouyhàâäéèêëîïôöùûü")

    /// The one way `word` splits into a function word and a known word, such as
    /// "mecouche" → "me couche" or "jaime" → "j'aime", or nil when there's no such split
    /// or more than one.
    ///
    /// The second word must be at least three letters or a function word itself, because
    /// Lexique lists fragments such as "ya" and "rai" that would otherwise qualify.
    func runTogetherFix(for word: String) -> String? {
        let letters = Array(FrenchTokenizer.normalize(word))
        guard letters.count >= 4, !letters.contains("'") else { return nil }
        var fixes: [String] = []
        for cut in 1..<(letters.count - 1) {
            let head = String(letters[..<cut])
            let tail = String(letters[cut...])
            guard tail.count >= 3 || Self.runOnHeads.contains(tail), lexicon.contains(tail) else { continue }
            if Self.runOnHeads.contains(head) {
                fixes.append(head + " " + tail)
            }
            if Self.elisions.contains(head), let first = tail.first, Self.vowelSounds.contains(first) {
                fixes.append(head + "'" + tail)
            }
        }
        guard fixes.count == 1, let fix = fixes.first else { return nil }
        return Self.matchingCase(fix, of: word)
    }

    /// `fix` with a capital first letter when `word` starts with one: "Jesuis" becomes "Je suis".
    static func matchingCase(_ fix: String, of word: String) -> String {
        guard let first = word.first, first.isUppercase else { return fix }
        return fix.prefix(1).uppercased() + fix.dropFirst()
    }

    /// Whether a misspelling may be two words run together rather than another kind of slip.
    ///
    /// A capital in mid-sentence marks a name the system doesn't know, as in "Lemarchand",
    /// so it's never split. When the system offers the same letters with accents, the word
    /// may be a missing accent ("demanger" for "démanger" rather than "de manger"), so the
    /// split steps aside and the usual ranking decides.
    private func mayBeRunTogether(_ misspelling: Misspelling, in text: String) -> Bool {
        let word = misspelling.word
        if word.first?.isUppercase == true && !Self.opensSentence(at: misspelling.offset, in: text) {
            return false
        }
        let folded = Self.withoutAccents(word)
        return !misspelling.guesses.contains { guess in
            guess.lowercased() != word.lowercased() && Self.withoutAccents(guess) == folded
        }
    }

    /// Whether the word at character `offset` is the first of its sentence.
    private static func opensSentence(at offset: Int, in text: String) -> Bool {
        let before = text.prefix(offset).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "«\"“")))
        guard let last = before.last else { return true }
        return ".!?…".contains(last)
    }

    /// `word`, lowercased, with its accents removed.
    private static func withoutAccents(_ word: String) -> String {
        word.folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr")).lowercased()
    }

    /// A run-together word: a warning whose fix puts back the space or apostrophe.
    ///
    /// It's a warning, not an error, so it never locks playback while the check is new.
    private func runTogetherIssue(_ misspelling: Misspelling, fix: String) -> Issue {
        let explanation = explanations.render(.runTogether, ["word": misspelling.word, "fix": fix])
        return Issue(
            kind: .spelling,
            severity: .warning,
            offset: misspelling.offset,
            length: misspelling.word.count,
            original: misspelling.word,
            replacement: fix,
            reason: explanation.reason,
            hint: explanation.hint,
            source: "System spellcheck · split by Lexique"
        )
    }

    /// A misspelling with no French guess: the word is flagged and the learner finds the fix.
    private func unknownWordIssue(_ misspelling: Misspelling) -> Issue {
        let explanation = explanations.render(.unknownWord, ["word": misspelling.word])
        return Issue(
            kind: .spelling,
            severity: .warning,
            offset: misspelling.offset,
            length: misspelling.word.count,
            original: misspelling.word,
            replacement: nil,
            reason: explanation.reason,
            hint: explanation.hint,
            source: "System spellcheck"
        )
    }
}
