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

/// The version 1 French rules: article gender, contractions, adjacent adjective
/// agreement, look-alike words, the ne… plus warning, and idiom suggestions.
///
/// Every rule prefers silence to a guess. A learning app must never flag correct
/// French as wrong, so a rule skips any word the lexicon marks as ambiguous (both
/// genders, or a noun that is also a verb in a verb position) rather than risk a
/// false error. Only known-noun mismatches and the closed rules raise errors; the
/// gender model's guesses are always warnings.
nonisolated struct FrenchGrammar: Grammar {

    let lexicon: Lexicon
    let idioms: [Idiom]
    let lookAlikes: [LookAlike]
    let explanations: ExplanationTemplates
    /// Predicts gender for nouns missing from the lexicon; `nil` until a trained model ships.
    let genderPredictor: (any GenderPredictor)?

    /// The probability a model guess needs before it becomes a warning.
    ///
    /// The nouns that reach the model are mostly loanwords and new words, which
    /// follow French endings less often than the nouns it was tested on: at 0.8 it
    /// called "un selfie" and "une appli" wrong. A high bar keeps it to the cases
    /// where the ending rule really holds.
    static let predictionThreshold = 0.95

    /// Returns every grammar issue in `text`, ordered by position.
    func check(_ text: String) -> [Issue] {
        let tokens = FrenchTokenizer.tokens(in: text)
        var issues: [Issue] = []
        issues += articleIssues(in: tokens)
        issues += contractionIssues(in: tokens)
        issues += agreementIssues(in: tokens)
        issues += lookAlikeIssues(in: tokens)
        issues += negationIssues(in: tokens)
        issues += idiomIssues(in: tokens)
        return issues.sorted { $0.offset < $1.offset }
    }

    // MARK: - Word lists

    /// Singular articles and the gender each one marks.
    private static let articles: [String: (gender: Gender, isDefinite: Bool)] = [
        "le": (.masculine, true), "la": (.feminine, true),
        "un": (.masculine, false), "une": (.feminine, false)
    ]

    /// Words after which le or la is an object pronoun, as in "je le porte".
    private static let pronounContext: Set<String> = [
        "je", "j'", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "ne", "n'", "me", "m'", "te", "t'", "se", "s'", "y"
    ]

    /// Prepositions that take an infinitive, as in "pour le faire".
    private static let infinitivePrepositions: Set<String> = [
        "pour", "de", "d'", "à", "sans", "après", "avant", "par"
    ]

    /// Subject pronouns that can open "il dort plus".
    private static let subjectPronouns: Set<String> = [
        "je", "j'", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles"
    ]

    /// Preposition + article pairs that French always contracts.
    private static let contractions: [String: String] = [
        "à le": "au", "à les": "aux", "de le": "du", "de les": "des"
    ]

    /// Determiners that can open a noun phrase, with the gender and number each marks.
    /// Possessives such as mon also precede feminine nouns (mon amie), so they mark no gender.
    private static let determiners: [String: (gender: Gender?, number: GrammaticalNumber?)] = [
        "le": (.masculine, .singular), "la": (.feminine, .singular), "l'": (nil, .singular),
        "les": (nil, .plural), "un": (.masculine, .singular), "une": (.feminine, .singular),
        "des": (nil, .plural), "du": (.masculine, .singular), "au": (.masculine, .singular),
        "aux": (nil, .plural), "ce": (.masculine, .singular), "cet": (.masculine, .singular),
        "cette": (.feminine, .singular), "ces": (nil, .plural),
        "mon": (nil, .singular), "ton": (nil, .singular), "son": (nil, .singular),
        "ma": (.feminine, .singular), "ta": (.feminine, .singular), "sa": (.feminine, .singular),
        "mes": (nil, .plural), "tes": (nil, .plural), "ses": (nil, .plural),
        "notre": (nil, .singular), "votre": (nil, .singular), "leur": (nil, .singular),
        "nos": (nil, .plural), "vos": (nil, .plural), "leurs": (nil, .plural),
        "quelques": (nil, .plural), "plusieurs": (nil, .plural)
    ]

    // MARK: - Article gender

    /// Flags le/la/un/une before a noun of the other gender.
    private func articleIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropLast() {
            let article = tokens[index]
            let noun = tokens[index + 1]
            guard let marked = Self.articles[article.normalized], article.isAdjacentToNext else { continue }
            // Before a vowel or h, le and la elide to l', which is a separate rule.
            if marked.isDefinite && noun.startsWithVowelOrH { continue }
            if isPronounPosition(of: tokens, articleAt: index) { continue }
            // "une petit maison": the word after the article is an adjective before the real noun.
            if modifiesFollowingNoun(tokens, at: index + 1) { continue }

            let word = noun.normalized
            let expected = { (gender: Gender) in
                marked.isDefinite ? gender.definiteArticle : gender.indefiniteArticle
            }

            if let entry = lexicon.noun(word) {
                guard let gender = entry.gender, entry.number != .plural, gender != marked.gender else { continue }
                let fix = matchingCase(of: article.text, expected(gender))
                issues.append(issue(
                    .gender, .error, from: index, through: index + 1, in: tokens,
                    replacement: fix + article.gap + noun.text,
                    explanation: explanations.render(.articleGender, [
                        "noun": noun.text, "gender": gender.rawValue, "article": expected(gender)
                    ]),
                    source: "Lexique · known noun"
                ))
            } else if !lexicon.contains(word),
                      let prediction = genderPredictor?.gender(of: word),
                      prediction.gender != marked.gender,
                      prediction.probability >= Self.predictionThreshold,
                      // Without an ending of two letters or more, there's no rule to teach.
                      let ending = prediction.ending.map({ "-\($0)" }) {
                let fix = matchingCase(of: article.text, expected(prediction.gender))
                issues.append(issue(
                    .gender, .warning, from: index, through: index + 1, in: tokens,
                    replacement: fix + article.gap + noun.text,
                    explanation: explanations.render(.articleGenderPredicted, [
                        "noun": noun.text,
                        "gender": prediction.gender.rawValue,
                        "reason": "words ending in \(ending) usually are.",
                        "article": expected(prediction.gender)
                    ]),
                    source: "Quiver prediction · ending \(ending)"
                ))
            }
        }
        return issues
    }

    /// Whether le/la at `index` is likely an object pronoun before a verb, as in
    /// "je le porte" or "pour la voir", rather than an article.
    private func isPronounPosition(of tokens: [Token], articleAt index: Int) -> Bool {
        let word = tokens[index + 1].normalized
        guard lexicon.isVerb(word), index > 0 else { return false }
        let previous = tokens[index - 1].normalized
        if Self.pronounContext.contains(previous) { return true }
        return isInfinitive(word) && Self.infinitivePrepositions.contains(previous)
    }

    /// Whether a word is a verb form with an infinitive ending, such as faire or voir.
    private func isInfinitive(_ word: String) -> Bool {
        lexicon.isVerb(word) && ["er", "ir", "re", "oir"].contains { word.hasSuffix($0) }
    }

    /// Whether the word at `index` is an adjective directly followed by a known noun.
    private func modifiesFollowingNoun(_ tokens: [Token], at index: Int) -> Bool {
        guard index + 1 < tokens.count, tokens[index].isAdjacentToNext else { return false }
        return !lexicon.adjectiveLemmas(of: tokens[index].normalized).isEmpty
            && lexicon.noun(tokens[index + 1].normalized) != nil
    }

    // MARK: - Contractions

    /// Flags "à le", "à les", "de le" and "de les" before a noun or adjective.
    private func contractionIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        guard tokens.count >= 3 else { return issues }
        for index in 0..<(tokens.count - 2) {
            let preposition = tokens[index]
            let article = tokens[index + 1]
            let next = tokens[index + 2]
            let pair = preposition.normalized + " " + article.normalized
            guard let contraction = Self.contractions[pair],
                  preposition.isAdjacentToNext, article.isAdjacentToNext else { continue }
            // "de l'arbre" and "à l'hôtel" elide instead of contracting.
            if article.normalized == "le" && next.startsWithVowelOrH { continue }
            // "de le faire": le is a pronoun before an infinitive, and no contraction applies.
            let word = next.normalized
            let isNominal = lexicon.noun(word) != nil || !lexicon.adjectiveLemmas(of: word).isEmpty
            guard isNominal, !isInfinitive(word) else { continue }

            issues.append(issue(
                .contraction, .error, from: index, through: index + 1, in: tokens,
                replacement: matchingCase(of: preposition.text, contraction),
                explanation: explanations.render(.contraction, [
                    "preposition": preposition.normalized,
                    "article": article.normalized,
                    "contraction": contraction
                ]),
                source: "Contraction rule"
            ))
        }
        return issues
    }

    // MARK: - Adjective agreement

    /// Flags an adjective directly after its noun that doesn't agree with it, as in
    /// "des pommes rouge".
    private func agreementIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        guard tokens.count >= 3 else { return issues }
        for index in 0..<(tokens.count - 2) {
            let determiner = tokens[index]
            let noun = tokens[index + 1]
            let adjective = tokens[index + 2]
            guard let marked = Self.determiners[determiner.normalized],
                  determiner.isAdjacentToNext, noun.isAdjacentToNext,
                  let entry = lexicon.noun(noun.normalized) else { continue }
            // "je le porte tous les jours": le is a pronoun, so porte is a verb with no adjective.
            if Self.articles[determiner.normalized] != nil, isPronounPosition(of: tokens, articleAt: index) { continue }

            let word = adjective.normalized
            // Past participles ("des pommes achetées") are verb forms with their own rules.
            guard !lexicon.isVerb(word) else { continue }
            let lemmas = lexicon.adjectiveLemmas(of: word)
            guard lemmas.count == 1, let lemma = lemmas.first,
                  let gender = entry.gender ?? marked.gender,
                  let number = entry.number ?? marked.number,
                  let expected = lexicon.adjective(lemma: lemma, gender: gender, number: number),
                  expected != word else { continue }

            let readings = lexicon.readings(of: word, lemma: lemma)
            let key: ExplanationKey
            if readings.contains(where: { $0.number == number }) {
                key = .agreementGender
            } else if readings.contains(where: { $0.gender == gender }) {
                key = .agreementNumber
            } else {
                key = .agreementGenderAndNumber
            }

            issues.append(issue(
                .agreement, .error, from: index + 2, through: index + 2, in: tokens,
                replacement: matchingCase(of: adjective.text, expected),
                explanation: explanations.render(key, [
                    "noun": noun.text, "gender": gender.rawValue, "number": number.rawValue
                ]),
                source: "Agreement rule · Lexique"
            ))
        }
        return issues
    }

    // MARK: - Negation

    /// Warns on "il dort plus" at the end of a clause, where written French means
    /// "no longer" only with ne.
    private func negationIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        guard tokens.count >= 3 else { return issues }
        for index in 0..<(tokens.count - 2) {
            let subject = tokens[index]
            let verb = tokens[index + 1]
            let plus = tokens[index + 2]
            guard Self.subjectPronouns.contains(subject.normalized),
                  lexicon.isVerb(verb.normalized), plus.normalized == "plus",
                  subject.isAdjacentToNext, verb.isAdjacentToNext,
                  // "plus tard" or "plus que moi" mean later and more; only a bare plus is ambiguous.
                  index + 3 == tokens.count || plus.endsClause,
                  // Mute and aspirated h decide between n' and ne; skip rather than guess.
                  verb.normalized.first != "h" else { continue }

            let negated = verb.startsWithVowel ? "n'" + verb.text : "ne " + verb.text
            let start: Int
            let replacement: String
            if subject.normalized == "j'" {
                // "j'aime plus" becomes "je n'aime plus": the subject loses its elision.
                start = index
                replacement = matchingCase(of: subject.text, "je") + " " + negated + verb.gap + plus.text
            } else {
                start = index + 1
                replacement = negated + verb.gap + plus.text
            }
            let corrected = (subject.normalized == "j'" ? "je" : subject.normalized) + " " + negated.lowercased() + " plus"

            issues.append(issue(
                .negation, .warning, from: start, through: index + 2, in: tokens,
                replacement: replacement,
                explanation: explanations.render(.negation, ["corrected": corrected]),
                source: "Negation rule · won't block play"
            ))
        }
        return issues
    }

    // MARK: - Look-alikes

    /// Flags words that are each French, or sound like it, but are wrong together, such as
    /// "comment cava". Each entry is wrong wherever it appears, apart from its listed
    /// exceptions, so these are errors.
    private func lookAlikeIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for lookAlike in lookAlikes {
            let phrase = FrenchTokenizer.tokens(in: lookAlike.phrase).map(\.normalized)
            guard !phrase.isEmpty, tokens.count >= phrase.count else { continue }
            for start in 0...(tokens.count - phrase.count) {
                let window = tokens[start..<(start + phrase.count)]
                let matches = zip(window, phrase).allSatisfy { $0.normalized == $1 }
                let isContiguous = window.dropLast().allSatisfy(\.isAdjacentToNext)
                guard matches, isContiguous else { continue }
                // "il cava" is the verb caver, which is correct French.
                if start > 0, tokens[start - 1].isAdjacentToNext,
                   lookAlike.unlessAfter.contains(tokens[start - 1].normalized) {
                    continue
                }
                issues.append(issue(
                    .lookAlike, .error, from: start, through: start + phrase.count - 1, in: tokens,
                    replacement: matchingCase(of: tokens[start].text, lookAlike.fix),
                    explanation: explanations.render(.lookAlike, ["note": lookAlike.note, "fix": lookAlike.fix]),
                    source: "Look-alike list"
                ))
            }
        }
        return issues
    }

    // MARK: - Idioms

    /// Suggests the more natural wording for phrases in the idiom list.
    private func idiomIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for idiom in idioms {
            let phrase = FrenchTokenizer.tokens(in: idiom.phrase).map(\.normalized)
            guard !phrase.isEmpty, tokens.count >= phrase.count else { continue }
            for start in 0...(tokens.count - phrase.count) {
                let window = tokens[start..<(start + phrase.count)]
                let matches = zip(window, phrase).allSatisfy { $0.normalized == $1 }
                let isContiguous = window.dropLast().allSatisfy(\.isAdjacentToNext)
                guard matches, isContiguous else { continue }
                issues.append(issue(
                    .idiom, .suggestion, from: start, through: start + phrase.count - 1, in: tokens,
                    replacement: matchingCase(of: tokens[start].text, idiom.suggestion),
                    explanation: explanations.render(.idiom, ["suggestion": idiom.suggestion, "note": idiom.note]),
                    source: "Idiom list"
                ))
            }
        }
        return issues
    }

    // MARK: - Helpers

    /// Builds an issue spanning tokens `first` through `last`, gaps included.
    private func issue(
        _ kind: IssueKind,
        _ severity: Severity,
        from first: Int,
        through last: Int,
        in tokens: [Token],
        replacement: String,
        explanation: Explanation,
        source: String
    ) -> Issue {
        var original = ""
        for index in first..<last {
            original += tokens[index].text + tokens[index].gap
        }
        original += tokens[last].text
        return Issue(
            kind: kind,
            severity: severity,
            offset: tokens[first].offset,
            length: tokens[last].end - tokens[first].offset,
            original: original,
            replacement: replacement,
            reason: explanation.reason,
            hint: explanation.hint,
            source: source
        )
    }

    /// Capitalizes `replacement` when `original` starts with a capital, as in "Le" → "La".
    private func matchingCase(of original: String, _ replacement: String) -> String {
        guard let first = original.first, first.isUppercase else { return replacement }
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}
