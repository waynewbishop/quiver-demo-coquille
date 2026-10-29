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
/// agreement, look-alike words, word choice, the ne… plus warning, and idiom suggestions.
///
/// Every rule prefers silence to a guess. A learning app must never flag correct
/// French as wrong, so a rule skips any word the lexicon marks as ambiguous (both
/// genders, or a noun that is also a verb in a verb position) rather than risk a
/// false error. Only known-noun mismatches and the closed rules raise errors; the
/// gender model's guesses are always warnings.
nonisolated struct FrenchGrammar: Grammar {

    let lexicon: Lexicon
    let idioms: [Idiom]
    let lookAlikes: [PhraseFix]
    let wordChoices: [PhraseFix]
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
        issues += accentIssues(in: tokens)
        issues += auxiliaryIssues(in: tokens)
        issues += participleWithEtreIssues(in: tokens)
        issues += generalArticleIssues(in: tokens)
        issues += agreementIssues(in: tokens)
        issues += phraseFixIssues(in: tokens, from: lookAlikes, kind: .lookAlike, explanation: .lookAlike, source: "Look-alike list")
        issues += phraseFixIssues(in: tokens, from: wordChoices, kind: .wordChoice, explanation: .wordChoice, source: "Word-choice list")
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

    /// Words that sit between a subject and its verb, as in "il y a", "elle l'a" or "il n'a".
    private static let preverbalWords: Set<String> = [
        "y", "en", "le", "la", "les", "l'", "lui", "leur", "me", "m'", "te", "t'", "se", "s'", "nous", "vous",
        "ne", "n'"
    ]

    /// Pronouns that a relative que can follow, as in "ce qu'il dit".
    private static let relativeAntecedents: Set<String> = [
        "ce", "c'", "celui", "celle", "ceux", "celles", "tout"
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
            // "la rouge", as in "la bleue ou la rouge": an adjective that agrees stands in for a noun.
            if isAgreeingAdjective(noun.normalized, gender: marked.gender) { continue }

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

    /// Whether a word is a singular adjective form of `gender`, such as rouge for la.
    private func isAgreeingAdjective(_ word: String, gender: Gender) -> Bool {
        lexicon.adjectiveLemmas(of: word).contains { lemma in
            lexicon.readings(of: word, lemma: lemma).contains { $0.gender == gender && $0.number == .singular }
        }
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

    // MARK: - The accent on à

    /// Flags a, the verb avoir, where only the preposition à fits: after a subject and
    /// its verb ("je vais a Paris"), after jusqu', and after dans ("dans a la maison").
    ///
    /// Anywhere else a can have a subject, as in "il a la maison", so the rule stays silent.
    private func accentIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropFirst() where tokens[index].normalized == "a" {
            let previous = tokens[index - 1]
            guard previous.isAdjacentToNext else { continue }

            if previous.normalized == "jusqu'" {
                issues.append(accentIssue(from: index, through: index, in: tokens, explanation: .accentAfterJusqu))
            } else if previous.normalized == "dans" {
                // Two prepositions can't share one noun, so à replaces dans rather than joining it.
                issues.append(accentIssue(from: index - 1, through: index, in: tokens, explanation: .accentAfterDans))
            } else if index >= 2, lexicon.isVerb(previous.normalized),
                      // "il y a", "il l'a", "il n'a": a pronoun or ne before a makes it avoir.
                      !Self.preverbalWords.contains(previous.normalized),
                      tokens[index - 2].isAdjacentToNext,
                      Self.subjectPronouns.contains(tokens[index - 2].normalized),
                      !isRelativeClauseSubject(tokens, before: index - 2) {
                issues.append(accentIssue(
                    from: index, through: index, in: tokens,
                    explanation: .accentAfterVerb, ["verb": previous.text]
                ))
            }
        }
        return issues
    }

    /// Whether the subject at `subject` opens a relative clause, as in "ce qu'il dit a du sens"
    /// or "le livre qu'il lit a disparu", where the whole clause is the subject of avoir.
    ///
    /// After a verb, que starts a reported clause instead ("je pense qu'il va a Paris"),
    /// so the accent rule still applies there.
    private func isRelativeClauseSubject(_ tokens: [Token], before subject: Int) -> Bool {
        guard subject >= 1, ["que", "qu'"].contains(tokens[subject - 1].normalized) else { return false }
        // At the start of the text there is nothing to tell the two apart, so stay silent.
        guard subject >= 2 else { return true }
        let antecedent = tokens[subject - 2].normalized
        return Self.relativeAntecedents.contains(antecedent) || lexicon.noun(antecedent) != nil
    }

    /// Builds an accent issue that replaces tokens `first` through `last` with à.
    private func accentIssue(
        from first: Int,
        through last: Int,
        in tokens: [Token],
        explanation key: ExplanationKey,
        _ values: [String: String] = [:]
    ) -> Issue {
        issue(
            .accent, .error, from: first, through: last, in: tokens,
            replacement: matchingCase(of: tokens[first].text, "à"),
            explanation: explanations.render(key, values),
            source: "Accent rule"
        )
    }

    // MARK: - Être or avoir

    /// Verbs that always take être in the compound past. Verbs that also take avoir with an
    /// object (sortir, monter, descendre, rentrer, passer, retourner, entrer) are left out,
    /// since "j'ai sorti la poubelle" is correct French.
    private static let etreVerbs: Set<String> = [
        "aller", "venir", "revenir", "devenir", "parvenir", "intervenir", "survenir",
        "arriver", "partir", "repartir", "naître", "mourir", "rester", "tomber", "retomber", "décéder"
    ]

    /// Verbs that take être or avoir depending on whether an object follows.
    private static let eitherAuxiliaryVerbs: Set<String> = [
        "sortir", "ressortir", "monter", "remonter", "descendre", "redescendre",
        "rentrer", "passer", "repasser", "retourner", "entrer"
    ]

    /// Each present and imperfect form of avoir, with the form of être that replaces it.
    private static let avoirToEtre: [String: String] = [
        "ai": "suis", "as": "es", "a": "est", "avons": "sommes", "avez": "êtes", "ont": "sont",
        "avais": "étais", "avait": "était", "avions": "étions", "aviez": "étiez", "avaient": "étaient"
    ]

    /// Subjects that settle a participle's gender and number after être. Je, tu, on and vous
    /// don't, so the learner's own form is kept for them.
    private static let subjectAgreement: [String: (gender: Gender, number: GrammaticalNumber)] = [
        "il": (.masculine, .singular), "elle": (.feminine, .singular),
        "ils": (.masculine, .plural), "elles": (.feminine, .plural), "nous": (.masculine, .plural)
    ]

    /// Flags avoir with a verb that takes être ("j'ai allé" → "je suis allé"), and a past
    /// participle that agrees with the subject after avoir ("il a mangée" → "mangé").
    ///
    /// Only a subject pronoun directly followed by avoir and the participle is judged, so an
    /// object pronoun in between ("il l'a mangée") or ne ("il n'a pas") keeps the rule silent.
    private func auxiliaryIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        guard tokens.count >= 3 else { return issues }
        for index in 0..<(tokens.count - 2) {
            let subject = tokens[index]
            let auxiliary = tokens[index + 1]
            let participle = tokens[index + 2]
            guard Self.subjectPronouns.contains(subject.normalized),
                  subject.isAdjacentToNext, auxiliary.isAdjacentToNext,
                  let etre = Self.avoirToEtre[auxiliary.normalized],
                  // "la pomme qu'il a mangée": the participle agrees with the object before it.
                  index == 0 || !["que", "qu'"].contains(tokens[index - 1].normalized) else { continue }
            let readings = lexicon.participles(participle.normalized)
            guard let verb = readings.first?.verb, readings.allSatisfy({ $0.verb == verb }),
                  !Self.eitherAuxiliaryVerbs.contains(verb) else { continue }

            if Self.etreVerbs.contains(verb) {
                var agreed = participle.text
                if let agreement = Self.subjectAgreement[subject.normalized],
                   let form = lexicon.participle(of: verb, gender: agreement.gender, number: agreement.number) {
                    agreed = form
                }
                // "j'ai" becomes "je suis": the subject loses its elision.
                let isElided = subject.normalized == "j'"
                let subjectText = isElided ? matchingCase(of: subject.text, "je") : subject.text
                let replacement = subjectText + (isElided ? " " : subject.gap) + etre + auxiliary.gap + agreed
                issues.append(issue(
                    .auxiliary, .error, from: index, through: index + 2, in: tokens,
                    replacement: replacement,
                    explanation: explanations.render(.auxiliaryChoice, ["verb": verb, "fix": replacement.lowercased()]),
                    source: "Auxiliary rule · Lexique"
                ))
            } else if readings.allSatisfy({ $0.gender == .feminine || $0.number == .plural }),
                      // "elle a vue sur la mer": vue is a noun there, not a participle.
                      lexicon.noun(participle.normalized) == nil,
                      let base = lexicon.participle(of: verb, gender: .masculine, number: .singular),
                      base != participle.normalized {
                issues.append(issue(
                    .participle, .error, from: index + 2, through: index + 2, in: tokens,
                    replacement: matchingCase(of: participle.text, base),
                    explanation: explanations.render(.participleWithAvoir, ["fix": base]),
                    source: "Participle rule · Lexique"
                ))
            }
        }
        return issues
    }

    // MARK: - Participle agreement with être

    /// The present and imperfect forms of être.
    private static let etreForms: Set<String> = [
        "suis", "es", "est", "sommes", "êtes", "sont", "étais", "était", "étions", "étiez", "étaient"
    ]

    /// What each subject settles about a participle after être: its gender, its number, or
    /// both. Vous can be one person or several, and "on est allés" is normal for "we", so
    /// neither settles anything and both are left out.
    private static let etreSubjectAgreement: [String: (gender: Gender?, number: GrammaticalNumber)] = [
        "il": (.masculine, .singular), "elle": (.feminine, .singular),
        "ils": (.masculine, .plural), "elles": (.feminine, .plural),
        "je": (nil, .singular), "j'": (nil, .singular), "tu": (nil, .singular), "nous": (nil, .plural)
    ]

    /// Flags a past participle after être that doesn't agree with its subject pronoun:
    /// "elles sont allé" → "allées", "elle est fatigué" → "fatiguée".
    ///
    /// Only a subject pronoun directly followed by être and the participle is judged, so
    /// "elle s'est lavé les mains" and "elle n'est pas allée" are left alone. Where the
    /// subject doesn't settle the gender (je, tu, nous), the learner's own gender is kept.
    private func participleWithEtreIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        guard tokens.count >= 3 else { return issues }
        for index in 0..<(tokens.count - 2) {
            let subject = tokens[index]
            let auxiliary = tokens[index + 1]
            let participle = tokens[index + 2]
            guard let agreement = Self.etreSubjectAgreement[subject.normalized],
                  subject.isAdjacentToNext, auxiliary.isAdjacentToNext,
                  Self.etreForms.contains(auxiliary.normalized) else { continue }
            let readings = lexicon.participles(participle.normalized)
            guard let verb = readings.first?.verb, readings.allSatisfy({ $0.verb == verb }) else { continue }

            // A form that serves the subject's gender and number is correct; nil serves both.
            let serves = { (reading: Lexicon.Participle) in
                (agreement.gender == nil || reading.gender == nil || reading.gender == agreement.gender)
                    && (reading.number == nil || reading.number == agreement.number)
            }
            guard !readings.contains(where: serves) else { continue }

            // Keep the learner's gender where the subject doesn't settle it.
            let gender = agreement.gender ?? readings.first?.gender ?? .masculine
            guard let fix = lexicon.participle(of: verb, gender: gender, number: agreement.number),
                  fix != participle.normalized else { continue }
            issues.append(issue(
                .participle, .error, from: index + 2, through: index + 2, in: tokens,
                replacement: matchingCase(of: participle.text, fix),
                explanation: explanations.render(.participleWithEtre, ["subject": subject.normalized == "j'" ? "je" : subject.normalized, "fix": fix]),
                source: "Participle rule · Lexique"
            ))
        }
        return issues
    }

    // MARK: - Articles for things in general

    /// Present forms of the verbs of liking, each with its infinitive.
    private static let likingVerbs: [String: String] = [
        "aime": "aimer", "aimes": "aimer", "aimons": "aimer", "aimez": "aimer", "aiment": "aimer",
        "adore": "adorer", "adores": "adorer", "adorons": "adorer", "adorez": "adorer", "adorent": "adorer",
        "déteste": "détester", "détestes": "détester", "détestons": "détester", "détestez": "détester", "détestent": "détester",
        "préfère": "préférer", "préfères": "préférer", "préférons": "préférer", "préférez": "préférer", "préfèrent": "préférer"
    ]

    /// Words that can sit between the verb and its noun: "je n'aime pas le fromage", "j'aime bien le chocolat".
    private static let likingAdverbs: Set<String> = [
        "pas", "plus", "jamais", "beaucoup", "bien", "vraiment", "aussi", "surtout", "trop"
    ]

    /// Words Lexique also lists as nouns that follow these verbs without an article:
    /// adverbs ("j'aime bien"), pronouns ("j'aime ça"), time words, and family names
    /// used as names ("j'adore maman").
    private static let bareAfterLiking: Set<String> = [
        "bien", "mal", "pas", "plus", "moins", "mieux", "tout", "tous", "rien", "ça", "cela", "ceci",
        "trop", "assez", "beaucoup", "vraiment", "aussi", "surtout", "encore", "toujours", "jamais",
        "autant", "tellement", "demain", "hier", "aujourd'hui", "maintenant", "ici", "là", "maman", "papa"
    ]

    /// Flags a bare noun after aimer, adorer, détester or préférer, which French gives the
    /// definite article for things in general: "j'aime fromage" → "le fromage".
    ///
    /// The article comes from the noun's gender and number in Lexique, so a noun that serves
    /// both, a capitalised name ("j'aime Paris") and an infinitive ("j'aime nager") are skipped.
    /// So are nouns starting with h, where le hockey and l'hôtel differ in a way Lexique doesn't record.
    private func generalArticleIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropLast() {
            let verbToken = tokens[index]
            guard let verb = Self.likingVerbs[verbToken.normalized], verbToken.isAdjacentToNext,
                  // "le fromage que j'aime est bon": the object came before, so the next word is the main verb.
                  !tokens[max(0, index - 2)..<index].contains(where: { ["que", "qu'"].contains($0.normalized) }) else { continue }
            // Look past one adverb: "je n'aime pas fromage", "j'aime bien chocolat".
            var nounIndex = index + 1
            if Self.likingAdverbs.contains(tokens[nounIndex].normalized), tokens[nounIndex].isAdjacentToNext, nounIndex + 1 < tokens.count {
                nounIndex += 1
            }
            let noun = tokens[nounIndex]
            let word = noun.normalized
            guard !Self.bareAfterLiking.contains(word),
                  noun.text.first?.isUppercase == false,
                  word.first != "h",
                  // "j'aime dîner": an infinitive, even one that is also a noun, takes no article.
                  !isInfinitive(word),
                  let entry = lexicon.noun(word) else { continue }

            let article: String
            switch (entry.gender, entry.number) {
            case (_, .plural?): article = "les "
            case (_, .singular?) where noun.startsWithVowel: article = "l'"
            case (.masculine?, .singular?): article = "le "
            case (.feminine?, .singular?): article = "la "
            default: continue
            }
            let fix = article + noun.text
            issues.append(issue(
                .article, .error, from: nounIndex, through: nounIndex, in: tokens,
                replacement: fix,
                explanation: explanations.render(.generalArticle, ["verb": verb, "fix": fix]),
                source: "Article rule · Lexique"
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

    // MARK: - Look-alikes and word choice

    /// Flags each listed phrase: look-alikes such as "comment cava", whose words are each
    /// French but wrong together, and English patterns such as "je suis faim". Each entry
    /// is wrong wherever it appears, apart from its listed exceptions, so these are errors.
    private func phraseFixIssues(
        in tokens: [Token],
        from fixes: [PhraseFix],
        kind: IssueKind,
        explanation key: ExplanationKey,
        source: String
    ) -> [Issue] {
        var issues: [Issue] = []
        for fix in fixes {
            let phrase = FrenchTokenizer.tokens(in: fix.phrase).map(\.normalized)
            let starts = occurrences(
                of: phrase, in: tokens,
                unlessAfter: fix.unlessAfter, onlyAfter: fix.onlyAfter,
                unlessBefore: fix.unlessBefore, onlyAtClauseEnd: fix.onlyAtClauseEnd == true
            )
            for start in starts {
                issues.append(issue(
                    kind, .error, from: start, through: start + phrase.count - 1, in: tokens,
                    replacement: matchingCase(of: tokens[start].text, fix.fix),
                    explanation: explanations.render(key, ["note": fix.note, "fix": fix.fix]),
                    source: source
                ))
            }
        }
        return issues
    }

    /// Returns where `phrase` starts in `tokens`, with its words adjacent, skipping
    /// matches whose neighbouring words make it correct French.
    private func occurrences(
        of phrase: [String],
        in tokens: [Token],
        unlessAfter: [String]?,
        onlyAfter: [String]?,
        unlessBefore: [String]?,
        onlyAtClauseEnd: Bool
    ) -> [Int] {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return [] }
        return (0...(tokens.count - phrase.count)).filter { start in
            let end = start + phrase.count
            let window = tokens[start..<end]
            guard zip(window, phrase).allSatisfy({ $0.normalized == $1 }),
                  window.dropLast().allSatisfy(\.isAdjacentToNext) else { return false }
            let before = start > 0 && tokens[start - 1].isAdjacentToNext ? tokens[start - 1].normalized : nil
            let after = end < tokens.count && tokens[end - 1].isAdjacentToNext ? tokens[end].normalized : nil
            // "il cava" is the verb caver, which is correct French.
            if let before, unlessAfter?.contains(before) == true { return false }
            // "a fait une décision" takes pris; "il fait une décision" takes prend.
            if let onlyAfter, !onlyAfter.contains(before ?? "") { return false }
            // "Pierre cava un trou": caver takes an object, so the phrase is correct here.
            if let after, unlessBefore?.contains(after) == true { return false }
            // "et tu ?" is wrong; "et tu vas bien" is correct French.
            if onlyAtClauseEnd, end < tokens.count, !tokens[end - 1].endsClause { return false }
            return true
        }
    }

    // MARK: - Idioms

    /// Suggests the more natural wording for phrases in the idiom list.
    private func idiomIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for idiom in idioms {
            let phrase = FrenchTokenizer.tokens(in: idiom.phrase).map(\.normalized)
            let starts = occurrences(
                of: phrase, in: tokens,
                unlessAfter: idiom.unlessAfter, onlyAfter: idiom.onlyAfter,
                unlessBefore: idiom.unlessBefore, onlyAtClauseEnd: false
            )
            for start in starts {
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
