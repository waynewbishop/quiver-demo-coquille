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
    /// Decides whether le, la, les or l' is an article or a pronoun from the words
    /// around it; `nil` leaves the decision to the hand rule alone.
    var articleModel: ArticleOrPronounModel? = nil
    /// Correct phrases whose meaning English speakers often mix up, from `fr.meanings.json`.
    var meaningChecks: [MeaningCheck] = []
    /// Decides whether et or est belongs from the words around it; `nil` leaves both unchecked.
    var etOrEstModel: EtOrEstModel? = nil

    /// How likely the other word must be before et or est is called an error.
    static let etOrEstCertainty = 0.95
    /// How likely the other word must be before the learner is asked which they meant.
    ///
    /// Asking whenever the model is unsure would question most correct et and est. At
    /// this cutoff the Notebook measured, on held-out treebank text, questions on 3.9%
    /// of correct et and est and errors on 0.6%, while a swapped word is caught as an
    /// error 41.3% of the time and asked about 39.5%. The phrasebook's 161 et and est
    /// raise nothing.
    static let etOrEstQuestion = 0.8

    /// How sure the article model must be that a word is an article before a rule
    /// treats it as one. Below this the word may be a pronoun, so the rule stays silent.
    static let articleCertainty = 0.95

    /// The probability a model guess needs before it becomes a warning.
    ///
    /// The nouns that reach the model are mostly loanwords and new words, which
    /// follow French endings less often than the nouns it was tested on: at 0.8 it
    /// called "un selfie" and "une appli" wrong. A high bar keeps it to the cases
    /// where the ending rule really holds.
    static let predictionThreshold = 0.95

    /// The French rule families in the order they run, each with the layer it
    /// demonstrates and the CEFR level at which its feedback is introduced.
    ///
    /// The order matters: when two issues of the same severity cover the same words,
    /// the resolution matrix keeps the one from the earlier rule.
    var rules: [GrammarRule] {
        // Each phrase list becomes a word trie once, when the pipeline is built, so a
        // lint pass walks the text once per list instead of trying every phrase.
        let lookAlikeTrie = PhraseTrie(phrases: lookAlikes.map { Self.words(of: $0.phrase) })
        let wordChoiceTrie = PhraseTrie(phrases: wordChoices.map { Self.words(of: $0.phrase) })
        let idiomTrie = PhraseTrie(phrases: idioms.map { Self.words(of: $0.phrase) })
        let meaningTrie = PhraseTrie(phrases: meaningChecks.map { Self.words(of: $0.phrase) })
        return [
            GrammarRule(identifier: "grammar.gender", layer: .localMorphosyntax, targetLevel: .a1) {
                articleGenderIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.gender.predicted", layer: .localMorphosyntax, targetLevel: .a1) {
                predictedGenderIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.contraction", layer: .localMorphosyntax, targetLevel: .a1) {
                contractionIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.accent", layer: .localMorphosyntax, targetLevel: .a1) {
                accentIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.auxiliary", layer: .relationalGrammar, targetLevel: .a2) {
                auxiliaryIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.conjugation", layer: .relationalGrammar, targetLevel: .a1) {
                conjugationIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.siClause", layer: .relationalGrammar, targetLevel: .b1) {
                siClauseIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.participle", layer: .relationalGrammar, targetLevel: .a2) {
                participleWithEtreIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.article", layer: .localMorphosyntax, targetLevel: .a2) {
                generalArticleIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.agreement", layer: .localMorphosyntax, targetLevel: .a1) {
                agreementIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.lookAlike", layer: .orthography, targetLevel: .a1) {
                phraseFixIssues(in: $0, from: lookAlikes, trie: lookAlikeTrie, kind: .lookAlike, explanation: .lookAlike, source: "Look-alike list")
            },
            GrammarRule(identifier: "grammar.wordChoice", layer: .contextualSemantics, targetLevel: .a2) {
                phraseFixIssues(in: $0, from: wordChoices, trie: wordChoiceTrie, kind: .wordChoice, explanation: .wordChoice, source: "Word-choice list")
            },
            GrammarRule(identifier: "grammar.negation", layer: .relationalGrammar, targetLevel: .a2) {
                negationIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.idiom", layer: .contextualSemantics, targetLevel: .b2) {
                idiomIssues(in: $0, trie: idiomTrie)
            },
            GrammarRule(identifier: "grammar.meaning", layer: .contextualSemantics, targetLevel: .a2) {
                meaningIssues(in: $0, trie: meaningTrie)
            },
            GrammarRule(identifier: "grammar.etOrEst", layer: .orthography, targetLevel: .a1) {
                etOrEstIssues(in: $0)
            }
        ]
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

    /// Words Lexique lists as adjectives that, right after a noun, almost always start
    /// something else: "une douche tous les matins", "des photos sur le mur".
    private static let nonAgreeingAfterNoun: Set<String> = [
        "tout", "toute", "tous", "toutes", "sur"
    ]

    /// Words that, after le or la, start a superlative rather than name a noun:
    /// "la plus belle journée", "le moins cher".
    private static let superlativeMarkers: Set<String> = ["plus", "moins"]

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

    /// Flags le/la/un/une before a known noun of the other gender.
    private func articleGenderIssues(in tokens: [Token]) -> [Issue] {
        articleNounPairs(in: tokens).compactMap { index, marked in
            let article = tokens[index]
            let noun = tokens[index + 1]
            guard let entry = lexicon.noun(noun.normalized),
                  let gender = entry.gender,
                  entry.number != .plural,
                  gender != marked.gender else { return nil }
            let expected = marked.isDefinite ? gender.definiteArticle : gender.indefiniteArticle
            return issue(
                .gender, .error, from: index, through: index + 1, in: tokens,
                replacement: matchingCase(of: article.text, expected) + article.gap + noun.text,
                explanation: explanations.render(.articleGender, [
                    "noun": noun.text, "gender": gender.rawValue, "article": expected
                ]),
                source: "Lexique · known noun"
            )
        }
    }

    /// Warns when the gender model is sure an unknown noun takes the other article.
    ///
    /// Only nouns missing from the lexicon reach the model, so this rule never
    /// disagrees with `articleGenderIssues`; it covers the words that rule can't.
    private func predictedGenderIssues(in tokens: [Token]) -> [Issue] {
        guard let genderPredictor else { return [] }
        return articleNounPairs(in: tokens).compactMap { index, marked in
            let article = tokens[index]
            let noun = tokens[index + 1]
            let word = noun.normalized
            guard lexicon.noun(word) == nil,
                  !lexicon.contains(word),
                  let prediction = genderPredictor.gender(of: word),
                  prediction.gender != marked.gender,
                  prediction.probability >= Self.predictionThreshold,
                  // Without an ending of two letters or more, there's no rule to teach.
                  let ending = prediction.ending.map({ "-\($0)" }) else { return nil }
            let expected = marked.isDefinite ? prediction.gender.definiteArticle : prediction.gender.indefiniteArticle
            return issue(
                .gender, .warning, from: index, through: index + 1, in: tokens,
                replacement: matchingCase(of: article.text, expected) + article.gap + noun.text,
                explanation: explanations.render(.articleGenderPredicted, [
                    "noun": noun.text,
                    "gender": prediction.gender.rawValue,
                    "reason": "words ending in \(ending) usually are.",
                    "article": expected
                ]),
                source: "Quiver prediction · ending \(ending)"
            )
        }
    }

    /// Finds each le/la/un/une that directly marks the gender of the word after it.
    ///
    /// Both gender rules share these skips, so a known noun and a predicted one are
    /// judged in exactly the same positions.
    private func articleNounPairs(in tokens: [Token]) -> [(index: Int, marked: (gender: Gender, isDefinite: Bool))] {
        tokens.indices.dropLast().compactMap { index in
            let article = tokens[index]
            let noun = tokens[index + 1]
            guard let marked = Self.articles[article.normalized], article.isAdjacentToNext else { return nil }
            // Before a vowel or h, le and la elide to l', which is a separate rule.
            if marked.isDefinite && noun.startsWithVowelOrH { return nil }
            if isPronounPosition(of: tokens, articleAt: index) { return nil }
            if Self.superlativeMarkers.contains(noun.normalized) { return nil }
            // "une petit maison": the word after the article is an adjective before the real noun.
            if modifiesFollowingNoun(tokens, at: index + 1) { return nil }
            // "la rouge", as in "la bleue ou la rouge": an adjective that agrees stands in for a noun.
            if isAgreeingAdjective(noun.normalized, gender: marked.gender) { return nil }
            return (index, marked)
        }
    }

    /// Whether le/la at `index` may be an object pronoun, as in "je le porte" or
    /// "pour la voir", so that no rule should treat it as an article.
    ///
    /// The hand rule's pronoun verdict always stands. With a model, an article
    /// also needs the model to be sure of it, so "qui le porte ?" stays silent
    /// where the hand rule alone would call "le porte" a gender error.
    private func isPronounPosition(of tokens: [Token], articleAt index: Int) -> Bool {
        if handRuleSaysPronoun(tokens, at: index) { return true }
        let word = tokens[index].normalized
        guard let articleModel, articleModel.decides(word) else { return false }
        let context = modelContext(of: tokens, at: index)
        // An object pronoun follows its subject, so a sentence never opens with one:
        // the three training treebanks start 4,604 sentences with le, la, les or l',
        // every one an article. The model is unsure of "Le voiture est rouge" only
        // because Lexique also lists voiture as a form of voiturer.
        guard context.previous != nil else { return false }
        let pronoun = articleModel.pronounProbability(
            of: word, previous: context.previous, next: context.next, afterNext: context.afterNext, lexicon: lexicon
        )
        return pronoun > 1.0 - Self.articleCertainty
    }

    /// The hand rule: le or la before a verb is a pronoun after a subject or object
    /// pronoun, or after a preposition when the verb is an infinitive.
    private func handRuleSaysPronoun(_ tokens: [Token], at index: Int) -> Bool {
        let word = tokens[index + 1].normalized
        guard lexicon.isVerb(word), index > 0 else { return false }
        let previous = tokens[index - 1].normalized
        if Self.pronounContext.contains(previous) { return true }
        return isInfinitive(word) && Self.infinitivePrepositions.contains(previous)
    }

    /// Returns the words around `index` as the article model saw them in training,
    /// where punctuation is a word of its own and a sentence starts with nothing before it.
    private func modelContext(of tokens: [Token], at index: Int) -> (previous: String?, next: String?, afterNext: String?) {
        var previous: String?
        if index > 0 {
            let before = tokens[index - 1]
            switch Self.mark(in: before.gap) {
            case .none: previous = before.normalized
            case .some(let mark): previous = Self.sentenceEnds.contains(mark) || mark == "\n" ? nil : mark
            }
        }
        let (next, nextIsMark) = neighbour(after: index, in: tokens)
        var afterNext: String?
        if nextIsMark {
            afterNext = index + 1 < tokens.count ? tokens[index + 1].normalized : nil
        } else if next != nil {
            afterNext = neighbour(after: index + 1, in: tokens).word
        }
        return (previous, next, afterNext)
    }

    /// Returns what follows the token at `index`: a punctuation mark in its gap, the
    /// next word, or `nil` at a line break or the end of the text.
    private func neighbour(after index: Int, in tokens: [Token]) -> (word: String?, isMark: Bool) {
        switch Self.mark(in: tokens[index].gap) {
        case .some("\n"): return (nil, false)
        case .some(let mark): return (mark, true)
        case .none: return (index + 1 < tokens.count ? tokens[index + 1].normalized : nil, false)
        }
    }

    /// Punctuation that ends a sentence, after which the model sees nothing before a word.
    private static let sentenceEnds: Set<String> = [".", "!", "?", "…"]

    /// Returns the first mark in a gap, "\n" for a line break, or `nil` when only spaces separate the words.
    private static func mark(in gap: String) -> String? {
        for character in gap {
            if character.isNewline { return "\n" }
            if character.isWhitespace { continue }
            return String(character)
        }
        return nil
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

    /// Each present and imperfect form of avoir, with its tense code. The être that replaces
    /// it takes that tense and the subject's person, so "ils a allé" becomes "ils sont allés".
    private static let avoirTenses: [String: String] = [
        "ai": "ip", "as": "ip", "a": "ip", "avons": "ip", "avez": "ip", "ont": "ip",
        "avais": "ii", "avait": "ii", "avions": "ii", "aviez": "ii", "avaient": "ii"
    ]

    /// The person and number code each subject pronoun takes, as in "ip1s" for je.
    private static let subjectPersons: [String: String] = [
        "je": "1s", "j'": "1s", "tu": "2s", "il": "3s", "elle": "3s", "on": "3s",
        "nous": "1p", "vous": "2p", "ils": "3p", "elles": "3p"
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
                  !isCoordinated(tokens, subjectAt: index),
                  let tense = Self.avoirTenses[auxiliary.normalized],
                  let person = Self.subjectPersons[subject.normalized],
                  let etre = lexicon.conjugate("être", tense + person),
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

    // MARK: - Conjugation

    /// Tenses in the order a fix prefers them when a form could belong to several.
    private static let tensePriority = ["ip", "ii", "if", "cp", "sp", "is", "si"]

    /// Words after which nous, vous or elle is an object or follows a preposition rather than
    /// being the subject: "il nous parle", "pour vous aider", "lui et elle sont partis".
    private static let notBeforeSubject: Set<String> = [
        "je", "j'", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "ne", "n'",
        "et", "ou", "à", "de", "d'", "pour", "avec", "chez", "sans", "sur", "sous", "par",
        "vers", "contre", "entre", "après", "avant", "devant", "derrière", "comme", "que", "qu'"
    ]

    /// Flags a verb that doesn't take its subject pronoun's person: "je va" → "vais",
    /// "ils mange" → "mangent".
    ///
    /// A form is flagged only when no reading of it, for any verb or tense, fits the subject,
    /// so "je suis" (être or suivre) and "je mange" (present or subjunctive) are never in doubt.
    /// The fix keeps the verb and tense and changes the person.
    private func conjugationIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropLast() {
            let subject = tokens[index]
            let verbToken = tokens[index + 1]
            guard let person = Self.subjectPersons[subject.normalized], subject.isAdjacentToNext,
                  index == 0 || !tokens[index - 1].isAdjacentToNext
                    || !Self.notBeforeSubject.contains(tokens[index - 1].normalized) else { continue }
            // Lexique lists n' and y as verb forms; a pronoun, ne or an elision is never the verb here.
            guard !Self.preverbalWords.contains(verbToken.normalized), !verbToken.normalized.hasSuffix("'") else { continue }
            let readings = lexicon.conjugations(verbToken.normalized)
            guard !readings.isEmpty,
                  !readings.contains(where: { $0.codes.contains { $0.hasSuffix(person) } }),
                  let reading = readings.first, readings.count == 1,
                  let tense = Self.tensePriority.first(where: { tense in reading.codes.contains { $0.hasPrefix(tense) } }),
                  let fix = lexicon.conjugate(reading.verb, tense + person),
                  fix != verbToken.normalized else { continue }

            // "j'va" can't keep its elision: it becomes "je vais".
            let keepsElision = subject.normalized != "j'" || fix.first.map { "aeiouyàâéèêëîïôûh".contains($0) } == true
            let first = keepsElision ? index + 1 : index
            let replacement = keepsElision
                ? matchingCase(of: verbToken.text, fix)
                : matchingCase(of: subject.text, "je") + " " + fix
            issues.append(issue(
                .conjugation, .error, from: first, through: index + 1, in: tokens,
                replacement: replacement,
                explanation: explanations.render(.subjectVerb, [
                    "subject": subject.normalized == "j'" ? "je" : subject.normalized,
                    "verb": reading.verb,
                    "fix": fix
                ]),
                source: "Conjugation rule · Lexique"
            ))
        }
        return issues
    }

    // MARK: - Si clauses

    /// Flags the future or the conditional after si meaning "if": "si tu viendras" → "viens",
    /// "si j'aurais" → "avais". The future becomes the present and the conditional the imperfect.
    ///
    /// Only a si (or s'il) that opens a sentence or follows a comma is judged: after a verb,
    /// "je ne sais pas si tu viendras" means "whether", and the future is correct there.
    private func siClauseIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropLast(2) {
            let si = tokens[index]
            let subject = tokens[index + 1]
            // "s'il" is si elided before il; elsewhere s' is se, as in "il s'est levé".
            let isSi = si.normalized == "si" || (si.normalized == "s'" && ["il", "ils"].contains(subject.normalized))
            guard isSi, si.isAdjacentToNext, subject.isAdjacentToNext,
                  index == 0 || tokens[index - 1].endsClause,
                  let person = Self.subjectPersons[subject.normalized] else { continue }

            // Look past ne and object pronouns: "si tu ne viendras pas", "si tu m'aideras".
            var verbIndex = index + 2
            while verbIndex < tokens.count - 1, verbIndex < index + 4,
                  Self.preverbalWords.contains(tokens[verbIndex].normalized), tokens[verbIndex].isAdjacentToNext {
                verbIndex += 1
            }
            let verbToken = tokens[verbIndex]
            let readings = lexicon.conjugations(verbToken.normalized)
            guard let reading = readings.first, readings.count == 1,
                  reading.codes.allSatisfy({ $0.hasPrefix("if") || $0.hasPrefix("cp") }),
                  reading.codes.contains(where: { $0.hasSuffix(person) }) else { continue }

            let isFuture = reading.codes.contains { $0.hasPrefix("if") }
            guard let fix = lexicon.conjugate(reading.verb, (isFuture ? "ip" : "ii") + person) else { continue }
            issues.append(issue(
                .siClause, .error, from: verbIndex, through: verbIndex, in: tokens,
                replacement: matchingCase(of: verbToken.text, fix),
                explanation: explanations.render(.siClause, ["tense": isFuture ? "present" : "imperfect", "fix": fix]),
                source: "Si clause rule · Lexique"
            ))
        }
        return issues
    }

    /// Whether the pronoun at `index` is only part of the subject, as elle in "lui et elle sont partis".
    private func isCoordinated(_ tokens: [Token], subjectAt index: Int) -> Bool {
        index > 0 && tokens[index - 1].isAdjacentToNext && ["et", "ou", "ni"].contains(tokens[index - 1].normalized)
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

    /// The number each third-person form of être marks, for checking a noun subject.
    private static let etreNumber: [String: GrammaticalNumber] = [
        "est": .singular, "était": .singular, "sont": .plural, "étaient": .plural
    ]

    /// Words that put a noun inside a phrase rather than make it the subject, as in
    /// "le chat de ma sœur est arrivé", where sœur isn't what arrived.
    private static let prepositions: Set<String> = [
        "de", "d'", "à", "en", "pour", "avec", "sans", "sur", "sous", "dans", "par",
        "chez", "entre", "vers", "contre", "après", "avant", "depuis", "pendant"
    ]

    /// Flags a past participle after être that doesn't agree with its subject:
    /// "elles sont allé" → "allées", "la fille est arrivé" → "arrivée".
    ///
    /// The subject is a pronoun right before être, or a determiner and a noun right
    /// before it, so "elle s'est lavé les mains" and "elle n'est pas allée" are left
    /// alone. Where the subject doesn't settle the gender (je, tu, nous, les enfants),
    /// the learner's own gender is kept.
    private func participleWithEtreIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        guard tokens.count >= 3 else { return issues }
        for index in 1..<(tokens.count - 1) {
            let auxiliary = tokens[index]
            let participle = tokens[index + 1]
            guard Self.etreForms.contains(auxiliary.normalized), auxiliary.isAdjacentToNext,
                  let subject = etreSubject(before: index, in: tokens) else { continue }
            let agreement = subject.agreement
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
                .participle, .error, from: index + 1, through: index + 1, in: tokens,
                replacement: matchingCase(of: participle.text, fix),
                explanation: explanations.render(.participleWithEtre, ["subject": subject.name, "fix": fix]),
                source: "Participle rule · Lexique"
            ))
        }
        return issues
    }

    /// Returns the subject of the être form at `index` and what it settles about the
    /// participle, or nil when the words before it aren't a subject the rule can read.
    private func etreSubject(
        before index: Int,
        in tokens: [Token]
    ) -> (name: String, agreement: (gender: Gender?, number: GrammaticalNumber))? {
        // A subject pronoun right before être: "elles sont".
        let pronoun = tokens[index - 1]
        if let agreement = Self.etreSubjectAgreement[pronoun.normalized] {
            guard pronoun.isAdjacentToNext, !isCoordinated(tokens, subjectAt: index - 1) else { return nil }
            return (pronoun.normalized == "j'" ? "je" : pronoun.normalized, agreement)
        }

        // A determiner and a noun right before être: "la fille est", "les enfants sont".
        guard index >= 2, let number = Self.etreNumber[tokens[index].normalized] else { return nil }
        let determiner = tokens[index - 2]
        let noun = tokens[index - 1]
        guard determiner.isAdjacentToNext, noun.isAdjacentToNext,
              !["du", "au", "aux"].contains(determiner.normalized),
              let marked = Self.determiners[determiner.normalized],
              let entry = lexicon.noun(noun.normalized),
              !isCoordinated(tokens, subjectAt: index - 2) else { return nil }
        // "de la fête sont" puts the noun inside a phrase; "la fête sont" disagrees in number.
        if index >= 3, tokens[index - 3].isAdjacentToNext, Self.prepositions.contains(tokens[index - 3].normalized) { return nil }
        guard marked.number == nil || marked.number == number,
              entry.number == nil || entry.number == number else { return nil }
        // A determiner and noun that disagree on gender are the gender rule's to fix first.
        if let markedGender = marked.gender, let nounGender = entry.gender, markedGender != nounGender { return nil }
        let name = determiner.normalized + (determiner.normalized.hasSuffix("'") ? "" : " ") + noun.normalized
        return (name, (marked.gender ?? entry.gender, number))
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
                  !Self.superlativeMarkers.contains(noun.normalized),
                  let entry = lexicon.noun(noun.normalized) else { continue }
            // "je le porte tous les jours": le is a pronoun, so porte is a verb with no adjective.
            if Self.articles[determiner.normalized] != nil, isPronounPosition(of: tokens, articleAt: index) { continue }

            let word = adjective.normalized
            // Past participles ("des pommes achetées") are verb forms with their own rules.
            guard !lexicon.isVerb(word), !Self.nonAgreeingAfterNoun.contains(word) else { continue }
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
        trie: PhraseTrie,
        kind: IssueKind,
        explanation key: ExplanationKey,
        source: String
    ) -> [Issue] {
        trie.matches(in: tokens).compactMap { match in
            let fix = fixes[match.entry]
            guard allowsMatch(
                match, in: tokens,
                unlessAfter: fix.unlessAfter, onlyAfter: fix.onlyAfter,
                unlessBefore: fix.unlessBefore, onlyAtClauseEnd: fix.onlyAtClauseEnd == true
            ) else { return nil }
            return issue(
                kind, .error, from: match.start, through: match.start + match.length - 1, in: tokens,
                replacement: matchingCase(of: tokens[match.start].text, fix.fix),
                explanation: explanations.render(key, ["note": fix.note, "fix": fix.fix]),
                source: source
            )
        }
    }

    /// Splits a listed phrase into the normalized words the tokenizer produces for it.
    private static func words(of phrase: String) -> [String] {
        FrenchTokenizer.tokens(in: phrase).map(\.normalized)
    }

    /// Whether a trie match stands, given the words around it: some listed phrases are
    /// correct French after or before particular words.
    private func allowsMatch(
        _ match: PhraseTrie.Match,
        in tokens: [Token],
        unlessAfter: [String]?,
        onlyAfter: [String]?,
        unlessBefore: [String]?,
        onlyAtClauseEnd: Bool
    ) -> Bool {
        let start = match.start
        let end = start + match.length
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

    // MARK: - Idioms

    /// Suggests the more natural wording for phrases in the idiom list.
    private func idiomIssues(in tokens: [Token], trie: PhraseTrie) -> [Issue] {
        trie.matches(in: tokens).compactMap { match in
            let idiom = idioms[match.entry]
            guard allowsMatch(
                match, in: tokens,
                unlessAfter: idiom.unlessAfter, onlyAfter: idiom.onlyAfter,
                unlessBefore: idiom.unlessBefore, onlyAtClauseEnd: false
            ) else { return nil }
            return issue(
                .idiom, .suggestion, from: match.start, through: match.start + match.length - 1, in: tokens,
                replacement: matchingCase(of: tokens[match.start].text, idiom.suggestion),
                explanation: explanations.render(.idiom, ["suggestion": idiom.suggestion, "note": idiom.note]),
                source: "Idiom list"
            )
        }
    }

    // MARK: - Meaning

    /// Asks which wording the learner meant for correct phrases that English speakers
    /// often mix up, such as "pas encore" for "plus". A suggestion with choices, never
    /// an error, because only the learner knows what they meant.
    private func meaningIssues(in tokens: [Token], trie: PhraseTrie) -> [Issue] {
        trie.matches(in: tokens).compactMap { match in
            let check = meaningChecks[match.entry]
            let end = match.start + match.length
            if check.unlessBeforeParticiple == true, end < tokens.count, tokens[end - 1].isAdjacentToNext,
               !lexicon.participles(tokens[end].normalized).isEmpty {
                return nil
            }
            let first = tokens[match.start].text
            var flagged = issue(
                .meaning, .suggestion, from: match.start, through: match.start + match.length - 1, in: tokens,
                replacement: nil,
                explanation: explanations.render(.meaning, ["note": check.note]),
                source: "Meaning list"
            )
            flagged.choices = check.choices.map { Choice(text: matchingCase(of: first, $0.text), meaning: $0.meaning) }
            return flagged
        }
    }

    // MARK: - Et or est

    /// What each word means, shown when the learner is asked which one they meant.
    private static let etOrEstMeanings = ["et": "and: joins two things", "est": "is: as in il est grand"]

    /// Flags et written for est, or est for et, using the Quiver model. When the other
    /// word is almost certain it's an error with a fix; when the model only leans
    /// toward it, the learner is asked which word they meant.
    private func etOrEstIssues(in tokens: [Token]) -> [Issue] {
        guard let etOrEstModel else { return [] }
        let stream = modelSentences(of: tokens)
        var issues: [Issue] = []
        for (index, token) in tokens.enumerated() {
            let written = token.normalized
            guard written == "et" || written == "est" else { continue }
            let other = written == "et" ? "est" : "et"
            let place = stream.places[index]
            let words = stream.sentences[place.sentence]
            let word = { (offset: Int) -> String? in
                words.indices.contains(place.index + offset) ? words[place.index + offset] : nil
            }
            let context = EtOrEstModel.Context(
                earlier: Array(words[..<place.index]),
                clauseStartsTwoBefore: word(-3).map(EtOrEstModel.isMark) ?? true,
                beforePrevious: word(-2),
                previous: word(-1),
                next: word(1),
                afterNext: word(2)
            )
            if written == "est", etOrEstModel.isOpenQuestion(context, lexicon: lexicon) { continue }
            let est = etOrEstModel.estProbability(context, lexicon: lexicon)
            let otherLikelihood = other == "est" ? est : 1 - est
            let fix = matchingCase(of: token.text, other)
            if otherLikelihood >= Self.etOrEstCertainty, !etOrEstModel.canOnlyAsk(context, lexicon: lexicon) {
                issues.append(issue(
                    .etOrEst, .error, from: index, through: index, in: tokens,
                    replacement: fix,
                    explanation: explanations.render(.etOrEst, ["fix": other]),
                    source: "Quiver prediction · words around it"
                ))
            } else if otherLikelihood >= Self.etOrEstQuestion {
                var question = issue(
                    .meaning, .suggestion, from: index, through: index, in: tokens,
                    replacement: nil,
                    explanation: explanations.render(.meaning, ["note": "Et means and; est means is."]),
                    source: "Quiver prediction · words around it"
                )
                question.choices = [token.text, fix].map { Choice(text: $0, meaning: Self.etOrEstMeanings[$0.lowercased()] ?? "") }
                issues.append(question)
            }
        }
        return issues
    }

    /// Splits the text into sentences of words as the treebank models saw them in
    /// training: punctuation is a word of its own, a sentence keeps its closing mark,
    /// and a line break ends a sentence. Returns where each token landed.
    private func modelSentences(of tokens: [Token]) -> (sentences: [[String]], places: [(sentence: Int, index: Int)]) {
        var sentences: [[String]] = []
        var places: [(sentence: Int, index: Int)] = []
        var current: [String] = []
        for token in tokens {
            places.append((sentences.count, current.count))
            current.append(token.normalized)
            switch Self.mark(in: token.gap) {
            case .none:
                continue
            case .some("\n"):
                sentences.append(current)
                current = []
            case .some(let mark):
                current.append(mark)
                if Self.sentenceEnds.contains(mark) {
                    sentences.append(current)
                    current = []
                }
            }
        }
        sentences.append(current)
        return (sentences, places)
    }

    // MARK: - Helpers

    /// Builds an issue spanning tokens `first` through `last`, gaps included.
    private func issue(
        _ kind: IssueKind,
        _ severity: Severity,
        from first: Int,
        through last: Int,
        in tokens: [Token],
        replacement: String?,
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
