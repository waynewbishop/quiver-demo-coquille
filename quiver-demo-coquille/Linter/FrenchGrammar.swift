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
    let explanations: ExplanationTemplates
    /// Predicts gender for nouns missing from the lexicon; `nil` until a trained model ships.
    let genderPredictor: (any GenderPredictor)?
    /// Decides whether le, la, les or l' is an article or a pronoun from the words
    /// around it; `nil` leaves the decision to the hand rule alone.
    var articleModel: ContextDecider? = nil
    /// Decides whether a word Lexique lists as both is an adjective or a noun.
    var adjectiveOrNounModel: ContextDecider? = nil
    /// Decides whether a form of avoir or être is a helper verb or a main verb.
    var helperOrMainModel: ContextDecider? = nil
    /// Decides whether a word Lexique lists as both is a noun or a verb.
    var nounOrVerbModel: ContextDecider? = nil
    /// Every listed phrase, from `fr.patterns.json`: look-alikes, word choices, idioms and meaning questions.
    var patterns = PhrasePatterns()
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

    /// How sure the tagger must be of a word's part of speech before a rule acts on it.
    static let tagCertainty = 0.95

    /// How strongly the tagger must lean toward adjective before "difficile a comprendre"
    /// counts as an adjective, an a and an infinitive. The infinitive already rules out
    /// avoir after a noun subject in correct French, so this check only needs to keep a
    /// noun subject ("le malade a dormi") out of the rule.
    static let adjectiveLean = 0.8

    /// The part-of-speech layer built from this grammar's lexicon and deciders.
    var tagger: FrenchTagger {
        FrenchTagger(
            lexicon: lexicon, articleOrPronoun: articleModel, adjectiveOrNoun: adjectiveOrNounModel,
            helperOrMain: helperOrMainModel, nounOrVerb: nounOrVerbModel
        )
    }

    /// Decides the ambiguous words once, for every rule in a pass to read.
    func tag(_ tokens: [Token]) -> TaggedText {
        tagger.tag(tokens)
    }

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
        // Each kind of listed phrase becomes a word trie once, when the pipeline is built,
        // so a lint pass walks the text once per kind instead of trying every phrase.
        let lists = [PhrasePattern.Kind.lookAlike, .wordChoice, .idiom, .meaning, .preposition].map { kind in
            let entries = patterns.entries(of: kind)
            return (kind: kind, entries: entries, trie: PhraseTrie(phrases: entries.map(\.matchWords)))
        }
        let countries = patterns.countries.sorted { $0.key < $1.key }
        let countryTrie = PhraseTrie(phrases: countries.map { PhrasePattern.words(of: $0.key) })
        return [
            GrammarRule(identifier: "grammar.gender", layer: .localMorphosyntax, targetLevel: .a1) {
                articleGenderIssues(in: $0) + contractedGenderIssues(in: $0) + possessiveGenderIssues(in: $0)
                    + determinerGenderIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.gender.predicted", layer: .localMorphosyntax, targetLevel: .a1) {
                predictedGenderIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.contraction", layer: .localMorphosyntax, targetLevel: .a1) {
                contractionIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.elision", layer: .orthography, targetLevel: .a1) {
                elisionIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.accent", layer: .localMorphosyntax, targetLevel: .a1) {
                accentIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.auxiliary", layer: .relationalGrammar, targetLevel: .a2) {
                auxiliaryIssues(in: $0) + reflexiveAuxiliaryIssues(in: $0.tokens)
            },
            // Before conjugation, so "il faut que je va" gets the subjunctive aille, not vais.
            GrammarRule(identifier: "grammar.subjunctive", layer: .relationalGrammar, targetLevel: .b1) {
                subjunctiveIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.conjugation", layer: .relationalGrammar, targetLevel: .a1) {
                conjugationIssues(in: $0.tokens) + nearFutureIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.siClause", layer: .relationalGrammar, targetLevel: .b1) {
                siClauseIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.participle", layer: .relationalGrammar, targetLevel: .a2) {
                participleWithEtreIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.article", layer: .localMorphosyntax, targetLevel: .a2) {
                generalArticleIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.articleNumber", layer: .localMorphosyntax, targetLevel: .a1) {
                articleNumberIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.agreement", layer: .localMorphosyntax, targetLevel: .a1) {
                agreementIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.lookAlike", layer: .orthography, targetLevel: .a1) {
                patternIssues(in: $0, list: lists[0])
            },
            GrammarRule(identifier: "grammar.wordChoice", layer: .contextualSemantics, targetLevel: .a2) {
                patternIssues(in: $0, list: lists[1]) + ageIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.negation", layer: .relationalGrammar, targetLevel: .a2) {
                negationIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.idiom", layer: .contextualSemantics, targetLevel: .b2) {
                patternIssues(in: $0, list: lists[2])
            },
            GrammarRule(identifier: "grammar.meaning", layer: .contextualSemantics, targetLevel: .a2) {
                patternIssues(in: $0, list: lists[3])
            },
            GrammarRule(identifier: "grammar.etOrEst", layer: .orthography, targetLevel: .a1) {
                etOrEstIssues(in: $0)
            },
            GrammarRule(identifier: "grammar.preposition", layer: .relationalGrammar, targetLevel: .a1) {
                countryIssues(in: $0.tokens, countries: countries, trie: countryTrie)
                    + missingPlacePrepositionIssues(in: $0.tokens, countries: countries, trie: countryTrie)
                    + enArticleIssues(in: $0.tokens)
                    + patternIssues(in: $0, list: lists[4])
            },
            GrammarRule(identifier: "grammar.sentenceCapital", layer: .orthography, targetLevel: .a1) {
                sentenceCapitalIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.lowercase", layer: .orthography, targetLevel: .a1) {
                lowercaseIssues(in: $0.tokens)
            },
            GrammarRule(identifier: "grammar.number", layer: .orthography, targetLevel: .a1) {
                numberWordIssues(in: $0.tokens) + oneAgreementIssues(in: $0)
                    + heureIssues(in: $0.tokens) + timeFormatIssues(in: $0.tokens)
            }
        ]
    }

    // MARK: - Word lists

    /// Singular articles and the gender each one marks.
    private static let articles: [String: (gender: Gender, isDefinite: Bool)] = [
        "le": (.masculine, true), "la": (.feminine, true),
        "un": (.masculine, false), "une": (.feminine, false)
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
    private func articleGenderIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        return articleNounPairs(in: text).compactMap { index, marked in
            let article = tokens[index]
            let noun = tokens[index + 1]
            guard let gender = knownGender(of: noun), gender != marked.gender else { return nil }
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

    /// The gender of a singular noun the rules can be sure of, or nil.
    ///
    /// A capitalised country takes its gender from its own article, whatever Lexique says
    /// about the common noun: Lexique lists canada as feminine, but it's le Canada.
    private func knownGender(of noun: Token) -> Gender? {
        if noun.text.first?.isUppercase == true, let article = patterns.countries[noun.text] {
            switch article {
            case "le": return .masculine
            case "la": return .feminine
            default: return nil
            }
        }
        guard let entry = lexicon.noun(noun.normalized), entry.number != .plural else { return nil }
        return entry.gender
    }

    /// Demonstratives, quel and aucun, each with the gender it marks and its two forms.
    private static let otherDeterminers: [String: (masculine: String, feminine: String)] = [
        "ce": ("ce", "cette"), "cet": ("ce", "cette"), "cette": ("ce", "cette"),
        "quel": ("quel", "quelle"), "quelle": ("quel", "quelle"),
        "aucun": ("aucun", "aucune"), "aucune": ("aucun", "aucune")
    ]

    /// Words whose listed gender misleads after a determiner: slang, loanwords, and "tombait pile".
    private static let unjudgedAfterDeterminer: Set<String> = ["putain", "pile", "team"]

    /// Flags ce, cet, cette, quel, quelle, aucun or aucune that doesn't suit a known singular
    /// noun: "ce maison" → "cette maison", "ce ami" → "cet ami", "quel maison" → "quelle maison".
    ///
    /// Ce is also a pronoun and quelle often comes before être or avoir, so their forms stay
    /// silent, and a word that can also be an adjective counts only when the tagger is sure,
    /// except that ce before a masculine vowel sound is wrong either way. An h word that
    /// isn't a known mute h leaves ce and cet alone, as Lexique doesn't record which it takes.
    private func determinerGenderIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        return tokens.indices.dropLast().compactMap { index in
            let determiner = tokens[index]
            let noun = tokens[index + 1]
            let word = noun.normalized
            guard let forms = Self.otherDeterminers[determiner.normalized], determiner.isAdjacentToNext,
                  noun.text.first?.isUppercase == false, !word.hasSuffix("'"), Self.articles[word] == nil,
                  !isForm(word, of: "être"), !isForm(word, of: "avoir"), !Self.unjudgedAfterDeterminer.contains(word),
                  !Self.superlativeMarkers.contains(word), !lexicon.isInfinitive(word),
                  let gender = knownGender(of: noun) else { return nil }
            let needsCet = determiner.normalized == "ce" && gender == .masculine && takesElision(noun)
            guard needsCet || lexicon.adjectiveLemmas(of: word).isEmpty
                    || text.isNoun(index + 1, certainty: Self.tagCertainty) else { return nil }
            var expected = gender == .masculine ? forms.masculine : forms.feminine
            if expected == "ce" {
                if word.first == "h", !takesElision(noun) { return nil }
                if takesElision(noun) { expected = "cet" }
            }
            guard expected != determiner.normalized else { return nil }
            return issue(
                .gender, .error, from: index, through: index + 1, in: tokens,
                replacement: matchingCase(of: determiner.text, expected) + determiner.gap + noun.text,
                explanation: explanations.render(.articleGender, [
                    "noun": noun.text, "gender": gender.rawValue, "article": expected
                ]),
                source: "Lexique · determiner"
            )
        }
    }

    /// Each possessive that marks a gender, with its masculine and feminine forms.
    private static let possessives: [String: (gender: Gender, masculine: String, feminine: String)] = [
        "mon": (.masculine, "mon", "ma"), "ton": (.masculine, "ton", "ta"), "son": (.masculine, "son", "sa"),
        "ma": (.feminine, "mon", "ma"), "ta": (.feminine, "ton", "ta"), "sa": (.feminine, "son", "sa")
    ]

    /// Flags mon, ton or son before a known feminine noun ("mon mère" → "ma mère"), ma, ta
    /// or sa before a known masculine one ("sa frère" → "son frère"), and ma, ta or sa
    /// before a vowel sound, where French uses mon, ton and son even for a feminine noun
    /// ("ma amie" → "mon amie").
    ///
    /// A word starting with h is judged only when it's a known mute h, since "ma hache" is
    /// correct and Lexique doesn't record which h is which.
    private func possessiveGenderIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        return tokens.indices.dropLast().compactMap { index in
            let possessive = tokens[index]
            let noun = tokens[index + 1]
            let word = noun.normalized
            guard let forms = Self.possessives[possessive.normalized], possessive.isAdjacentToNext,
                  noun.text.first?.isLowercase == true else { return nil }
            // "le son de la radio", "un ton sec": son and ton are nouns after a determiner.
            if index > 0, tokens[index - 1].isAdjacentToNext, Self.determiners[tokens[index - 1].normalized] != nil { return nil }
            // "sa va" and "sa fait" are ça, which the look-alike list fixes. The tagger can't
            // help here, since after a possessive it reads almost any word as a noun, so a verb
            // form after sa is skipped. After the other possessives it's judged as a noun:
            // voiture is also a form of voiturer.
            if possessive.normalized == "sa", lexicon.isVerb(word) { return nil }

            let fix: String
            let explanation: Explanation
            if takesElision(noun) {
                guard forms.gender == .feminine,
                      lexicon.noun(word) != nil || !lexicon.adjectiveLemmas(of: word).isEmpty else { return nil }
                fix = forms.masculine
                explanation = explanations.render(.possessiveBeforeVowel, ["fix": fix + " " + word])
            } else {
                guard !noun.startsWithVowelOrH, let gender = knownGender(of: noun), gender != forms.gender else { return nil }
                // A word that can also be an adjective counts only when the tagger is sure it's the noun.
                if !lexicon.adjectiveLemmas(of: word).isEmpty,
                   !text.isNoun(index + 1, certainty: Self.tagCertainty) { return nil }
                fix = gender == .masculine ? forms.masculine : forms.feminine
                explanation = explanations.render(.possessiveGender, [
                    "noun": noun.text, "gender": gender.rawValue, "fix": fix + " " + word
                ])
            }
            return issue(
                .gender, .error, from: index, through: index + 1, in: tokens,
                replacement: matchingCase(of: possessive.text, fix) + possessive.gap + noun.text,
                explanation: explanation,
                source: "Lexique · known noun"
            )
        }
    }

    /// Warns when the gender model is sure an unknown noun takes the other article.
    ///
    /// Only nouns missing from the lexicon reach the model, so this rule never
    /// disagrees with `articleGenderIssues`; it covers the words that rule can't.
    private func predictedGenderIssues(in text: TaggedText) -> [Issue] {
        guard let genderPredictor else { return [] }
        let tokens = text.tokens
        return articleNounPairs(in: text).compactMap { index, marked in
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
    private func articleNounPairs(in text: TaggedText) -> [(index: Int, marked: (gender: Gender, isDefinite: Bool))] {
        let tokens = text.tokens
        return tokens.indices.dropLast().compactMap { index in
            let article = tokens[index]
            let noun = tokens[index + 1]
            guard let marked = Self.articles[article.normalized], article.isAdjacentToNext else { return nil }
            // Before a vowel or h, le and la elide to l', which is a separate rule.
            if marked.isDefinite && noun.startsWithVowelOrH { return nil }
            // "à la garçon" needs au, not "à le", so the contracted rule takes le and la after à and de.
            if marked.isDefinite, followsContractingPreposition(index, in: tokens) { return nil }
            // "je le porte": the tagger can't rule out a pronoun.
            if text.mayBePronoun[index] { return nil }
            if Self.superlativeMarkers.contains(noun.normalized) { return nil }
            // A word that can also be an adjective counts only when the tagger is sure it's
            // the noun: "une petit maison" and "la rouge" stay silent.
            if !lexicon.adjectiveLemmas(of: noun.normalized).isEmpty,
               !text.isNoun(index + 1, certainty: Self.tagCertainty) { return nil }
            return (index, marked)
        }
    }

    /// Whether the word at `index` follows à or de directly, which le and les contract with.
    private func followsContractingPreposition(_ index: Int, in tokens: [Token]) -> Bool {
        guard index >= 1 else { return false }
        let preposition = tokens[index - 1]
        return ["à", "de"].contains(preposition.normalized) && preposition.isAdjacentToNext
    }

    /// The singular article that à or de takes before a consonant: au, à la, du or de la.
    private static func contractedArticle(_ preposition: String, _ gender: Gender) -> String {
        switch (preposition, gender) {
        case ("à", .masculine): "au"
        case ("à", .feminine): "à la"
        case (_, .masculine): "du"
        case (_, .feminine): "de la"
        }
    }

    /// Flags au, du, à la and de la before a known singular noun of the other gender:
    /// "au maison" → "à la maison", "de la pain" → "du pain".
    ///
    /// "à le" before a feminine noun is caught here too, as "à le maison" → "à la maison",
    /// since contracting it to au would still be wrong. Before a vowel or h the elision
    /// rule takes over, and the same skips as the plain gender rule apply.
    private func contractedGenderIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        var issues: [Issue] = []
        for index in tokens.indices.dropLast() {
            let article = tokens[index]
            let noun = tokens[index + 1]
            guard article.isAdjacentToNext else { continue }

            let first: Int
            let preposition: String
            let marked: Gender
            switch article.normalized {
            case "au", "du":
                (first, preposition, marked) = (index, article.normalized == "au" ? "à" : "de", .masculine)
            case "le", "la":
                guard followsContractingPreposition(index, in: tokens) else { continue }
                // "il essaie de la voir": la is a pronoun, and no article is there to fix.
                if text.mayBePronoun[index] { continue }
                (first, preposition, marked) = (index - 1, tokens[index - 1].normalized,
                                                article.normalized == "le" ? .masculine : .feminine)
            default:
                continue
            }

            let word = noun.normalized
            if noun.startsWithVowelOrH || Self.superlativeMarkers.contains(word) || lexicon.isInfinitive(word) { continue }
            // "à la mi-2009" is a fixed phrase, and "à la l'…" is a typo with no noun to judge.
            if word == "mi" || word.hasSuffix("'") { continue }
            // A capital inside a sentence is a name, unless it's a country the patterns know.
            if noun.text.first?.isUppercase == true, patterns.countries[noun.text] == nil { continue }
            if !lexicon.adjectiveLemmas(of: word).isEmpty, !text.isNoun(index + 1, certainty: Self.tagCertainty) { continue }
            guard let gender = knownGender(of: noun), gender != marked else { continue }

            let expected = Self.contractedArticle(preposition, gender)
            issues.append(issue(
                .gender, .error, from: first, through: index + 1, in: tokens,
                replacement: matchingCase(of: tokens[first].text, expected) + article.gap + noun.text,
                explanation: explanations.render(.contractedGender, [
                    "noun": noun.text, "gender": gender.rawValue, "preposition": preposition, "article": expected
                ]),
                source: "Lexique · known noun"
            ))
        }
        return issues
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
            // "à le maison" and "à le livres" need à la and aux, which the gender and number rules give.
            if article.normalized == "le",
               knownGender(of: next) == .feminine || isSurelyPlural(word) { continue }
            let isNominal = lexicon.noun(word) != nil || !lexicon.adjectiveLemmas(of: word).isEmpty
            guard isNominal, !lexicon.isInfinitive(word) else { continue }
            // "j'ai trop de les devoirs" drops the article, which the word-choice list fixes;
            // contracting would give "trop des devoirs", which is still wrong.
            if index >= 2, Self.quantityWords.contains(tokens[index - 1].normalized),
               Self.avoirTenses[tokens[index - 2].normalized] != nil { continue }

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

    /// Words of quantity that take de alone: "beaucoup de livres", "trop de devoirs".
    private static let quantityWords: Set<String> = ["beaucoup", "trop", "assez", "tellement"]

    // MARK: - Elision

    /// Words that lose their last vowel before a vowel sound, with the form they take.
    private static let elisions: [String: String] = [
        "je": "j'", "me": "m'", "te": "t'", "se": "s'", "le": "l'", "la": "l'",
        "de": "d'", "ne": "n'", "que": "qu'"
    ]

    /// Words with a mute h, which elide like a vowel: l'homme, d'habitude. Any other h is
    /// left alone, since an aspirated h keeps the full word (le héros, je hais) and Lexique
    /// doesn't record which h is which.
    private static let muteHWords: Set<String> = [
        "homme", "hommes", "hôtel", "hôtels", "heure", "heures", "histoire", "histoires", "hiver",
        "hivers", "hôpital", "hôpitaux", "habitude", "habitudes", "herbe", "herbes", "huile", "horaire",
        "horaires", "humeur", "honneur", "hier", "habit", "habits", "hélicoptère", "héroïne", "hommage",
        "horizon", "horloge", "humain", "humains", "humour", "hygiène", "héritage", "harmonie", "hôte",
        "hôtesse", "huître", "huîtres", "humanité", "hypothèse"
    ]

    /// Verbs with a mute h, every form of which elides: j'habite, je m'habille.
    private static let muteHVerbs = ["habiter", "habiller", "hésiter", "hériter"]

    /// Words starting with a vowel that keep a whole word in front of them: le onze, que oui,
    /// la une (a newspaper's front page), and the sounds people make while thinking.
    private static let noElisionWords: Set<String> = [
        "onze", "onzième", "oui", "ouistiti", "ouate", "un", "une",
        "euh", "oh", "ah", "eh", "ouais", "ouf", "aïe", "oups"
    ]

    /// Words a pronoun such as le or la never stands before, so a vowel after them isn't
    /// the noun or verb that would make it elide.
    private static let notElidingAfterArticle: Set<String> = [
        "et", "ou", "où", "en", "au", "aux", "à", "il", "elle", "on", "ils", "elles", "eux",
        "avec", "après", "avant", "encore", "ainsi", "alors", "aussi", "ici", "enfin", "entre"
    ]

    /// Whether a word begins with a vowel sound that makes the word before it elide.
    private func takesElision(_ token: Token) -> Bool {
        let word = token.normalized
        if word.first == "h" {
            return Self.muteHWords.contains(word) || Self.muteHVerbs.contains { isForm(word, of: $0) }
        }
        // Only y itself and yeux elide: j'y vais, beaucoup d'yeux, but le yaourt.
        if word.first == "y" { return word == "y" || word == "yeux" }
        guard token.startsWithVowel, !Self.noElisionWords.contains(word) else { return false }
        // "de A à Z", "le ONU": letters and acronyms are read out, so they're left alone.
        return !token.text.allSatisfy(\.isUppercase)
    }

    /// Flags je, me, te, se, le, la, de, ne and que written whole before a vowel sound, as
    /// in "je aime" → "j'aime", "le ami" → "l'ami" and "que il" → "qu'il", and au and du
    /// before one, as in "au école" → "à l'école".
    ///
    /// Each word is judged only before what can follow it: je, me, te, se and ne before a
    /// verb, y or en; le and la before a noun, adjective or verb; de and que before any
    /// word Lexique knows. A capitalised word is left alone: a name after de keeps its first
    /// letter whole as often as not, and au before a country is the country rule's.
    private func elisionIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropLast() {
            let token = tokens[index]
            let next = tokens[index + 1]
            let word = token.normalized
            let nextWord = next.normalized
            guard token.isAdjacentToNext, takesElision(next) else { continue }
            // A capital inside a sentence is a name or a title, as Me for Maître.
            if token.text.first?.isUppercase == true, index > 0, !tokens[index - 1].endsClause { continue }
            // A name after de or que keeps its first letter whole as often as not: "de Ernest".
            if next.text.first?.isUppercase == true { continue }
            let isVerb = lexicon.isVerb(nextWord)
            let isNominal = lexicon.noun(nextWord) != nil || !lexicon.adjectiveLemmas(of: nextWord).isEmpty

            if word == "au" || word == "du" {
                guard isNominal,
                      lexicon.noun(nextWord)?.number != .plural else { continue }
                let fix = word == "au" ? "à l'" : "de l'"
                issues.append(issue(
                    .elision, .error, from: index, through: index + 1, in: tokens,
                    replacement: matchingCase(of: token.text, fix) + next.text,
                    explanation: explanations.render(.elisionContraction, ["word": word, "fix": fix + nextWord]),
                    source: "Elision rule"
                ))
                continue
            }

            guard let elided = Self.elisions[word] else { continue }
            // A single letter after these is a/à or y: "qu'à", "n'a", "il l'a", "j'y".
            if nextWord.count == 1, nextWord != "y" {
                let allowed = nextWord == "a" ? ["ne", "le", "la", "me", "te", "que"].contains(word) : word == "que"
                guard allowed else { continue }
            }
            switch word {
            case "je", "me", "te", "se", "ne":
                guard isVerb || ["y", "en"].contains(nextWord) else { continue }
                // "je me ai levé" needs être, not an elision; the auxiliary rule fixes it.
                if isReflexiveBeforeAvoir(at: index, in: tokens) { continue }
            case "le", "la":
                guard !Self.notElidingAfterArticle.contains(nextWord),
                      isVerb || isNominal || nextWord == "a" else { continue }
            default:
                guard lexicon.contains(nextWord) else { continue }
            }
            issues.append(issue(
                .elision, .error, from: index, through: index + 1, in: tokens,
                replacement: matchingCase(of: token.text, elided) + next.text,
                explanation: explanations.render(.elision, ["word": word, "fix": elided + nextWord]),
                source: "Elision rule"
            ))
        }
        return issues
    }

    // MARK: - The accent on à

    /// Nouns that take avoir where English uses "to be", as in "elle a faim".
    private static let avoirNouns: Set<String> = [
        "faim", "soif", "peur", "froid", "chaud", "raison", "tort", "besoin",
        "envie", "sommeil", "mal", "honte", "hâte"
    ]

    /// Flags a and à written for each other, in both directions.
    ///
    /// a, the verb avoir, is flagged where only the preposition fits: after a subject and
    /// its verb ("je vais a Paris"), after être and a participle ("il est allé a Paris"),
    /// between an adjective and an infinitive ("facile a faire"), after jusqu', and after
    /// dans. à is flagged where only avoir fits: right after il or on ("il à faim"), in
    /// "il y à", and after elle when a participle or an avoir noun follows ("elle à soif").
    ///
    /// Anywhere else either word can be right, as in "il a la maison" or "un cadeau pour
    /// elle à Noël", so the rule stays silent. On the UD French treebanks the new contexts
    /// raise no false alarm across 8,281 à and 3,211 a.
    private func accentIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        var issues: [Issue] = []
        for index in tokens.indices.dropFirst() {
            switch tokens[index].normalized {
            case "a": issues += missingAccentIssues(at: index, in: text)
            case "à": issues += extraAccentIssues(at: index, in: tokens)
            default: continue
            }
        }
        return issues
    }

    /// Flags the a at `index` when only the preposition à fits there.
    private func missingAccentIssues(at index: Int, in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        let previous = tokens[index - 1]
        guard previous.isAdjacentToNext else { return [] }
        let next = index + 1 < tokens.count && tokens[index].isAdjacentToNext ? tokens[index + 1] : nil

        if previous.normalized == "jusqu'" {
            return [accentIssue(from: index, through: index, in: tokens, explanation: .accentAfterJusqu)]
        } else if previous.normalized == "dans" {
            // Two prepositions can't share one noun, so à replaces dans rather than joining it.
            return [accentIssue(from: index - 1, through: index, in: tokens, explanation: .accentAfterDans)]
        } else if index >= 2, lexicon.isVerb(previous.normalized),
                  // "il y a", "il l'a", "il n'a": a pronoun or ne before a makes it avoir.
                  !Self.preverbalWords.contains(previous.normalized),
                  tokens[index - 2].isAdjacentToNext,
                  Self.subjectPronouns.contains(tokens[index - 2].normalized),
                  !isRelativeClauseSubject(tokens, before: index - 2) {
            return [accentIssue(
                from: index, through: index, in: tokens,
                explanation: .accentAfterVerb, ["verb": previous.text]
            )]
        } else if index >= 3, !lexicon.participles(previous.normalized).isEmpty,
                  tokens[index - 2].isAdjacentToNext,
                  Self.etreForms.contains(tokens[index - 2].normalized),
                  // "ce qui est arrivé a changé": the tagger sees a as avoir, helping changé.
                  !text.isHelperVerb(index, certainty: Self.tagCertainty) {
            return [accentIssue(
                from: index, through: index, in: tokens,
                explanation: .accentAfterVerb, ["verb": previous.text]
            )]
        } else if lexicon.isInfinitive(previous.normalized), completesConjugatedVerb(index - 1, in: tokens),
                  // "modifier a posteriori": Latin phrases keep a without an accent.
                  !Self.latinAfterA.contains(next?.normalized ?? "") {
            // "je voudrais aller a la plage": the infinitive belongs to voudrais, so it
            // can't be the subject of avoir the way it is in "voyager a changé ma vie".
            return [accentIssue(
                from: index, through: index, in: tokens,
                explanation: .accentAfterVerb, ["verb": previous.text]
            )]
        } else if let next, lexicon.isInfinitive(next.normalized),
                  !lexicon.adjectiveLemmas(of: previous.normalized).isEmpty,
                  // A noun or verb before a could be avoir's subject, as in "le chat a mangé",
                  // so a word that can be a noun counts only when the tagger leans adjective.
                  !lexicon.isVerb(previous.normalized),
                  lexicon.noun(previous.normalized) == nil || text.isAdjective(index - 1, certainty: Self.adjectiveLean) {
            return [accentIssue(
                from: index, through: index, in: tokens,
                explanation: .accentAfterAdjective, ["adjective": previous.text]
            )]
        }
        return []
    }

    /// Flags the à at `index` when only the verb avoir fits there.
    private func extraAccentIssues(at index: Int, in tokens: [Token]) -> [Issue] {
        let previous = tokens[index - 1]
        guard previous.isAdjacentToNext else { return [] }
        let next = index + 1 < tokens.count && tokens[index].isAdjacentToNext ? tokens[index + 1] : nil

        switch previous.normalized {
        case "il", "on":
            // Il and on are only ever subjects, and a preposition never follows a subject.
            return [graveIssue(at: index, in: tokens, explanation: .graveAfterSubject, ["subject": previous.text])]
        case "y" where index >= 2 && tokens[index - 2].normalized == "il" && tokens[index - 2].isAdjacentToNext:
            return [graveIssue(at: index, in: tokens, explanation: .graveInIlYA)]
        case "elle":
            // Elle can follow a preposition ("pour elle à Noël"), so only what comes next decides.
            guard let next, !lexicon.participles(next.normalized).isEmpty || Self.avoirNouns.contains(next.normalized) else {
                return []
            }
            return [graveIssue(at: index, in: tokens, explanation: .graveAfterSubject, ["subject": previous.text])]
        default:
            return []
        }
    }

    /// Words that end a negation between a verb and its infinitive, as in "je ne veux pas aller".
    private static let negationEndings: Set<String> = ["pas", "plus", "jamais"]

    /// Latin words that follow a written without an accent: a priori, a posteriori, a fortiori.
    private static let latinAfterA: Set<String> = ["priori", "posteriori", "fortiori", "contrario", "minima", "maxima"]

    /// Relative words that make the clause before them a subject, as in "ce dont il veut parler a".
    private static let relativeOpeners: Set<String> = ["qui", "dont", "où"]

    /// Whether the infinitive at `infinitive` completes a conjugated verb that has a
    /// subject pronoun, as in "je voudrais aller" or "il ne peut pas venir".
    ///
    /// An infinitive can be the subject of avoir ("voyager a changé ma vie"), but not
    /// one that already belongs to a conjugated verb. A relative clause is left out,
    /// since in "ce qu'il veut faire a changé" the whole clause is the subject.
    private func completesConjugatedVerb(_ infinitive: Int, in tokens: [Token]) -> Bool {
        var verb = infinitive - 1
        if verb >= 0, Self.negationEndings.contains(tokens[verb].normalized), tokens[verb].isAdjacentToNext {
            verb -= 1
        }
        guard verb >= 1, tokens[verb].isAdjacentToNext else { return false }
        let verbWord = tokens[verb].normalized
        guard !lexicon.conjugations(verbWord).isEmpty, !lexicon.isInfinitive(verbWord) else { return false }

        // Walk back past ne, y, en and object pronouns to the subject.
        var subject = verb - 1
        while subject >= 0, !Self.subjectPronouns.contains(tokens[subject].normalized),
              Self.preverbalWords.contains(tokens[subject].normalized), tokens[subject].isAdjacentToNext {
            subject -= 1
        }
        guard subject >= 0, tokens[subject].isAdjacentToNext,
              Self.subjectPronouns.contains(tokens[subject].normalized) else { return false }
        if subject >= 1, Self.relativeOpeners.contains(tokens[subject - 1].normalized) { return false }
        return !isRelativeClauseSubject(tokens, before: subject)
    }

    /// Builds an accent issue that replaces the à at `index` with a.
    private func graveIssue(
        at index: Int,
        in tokens: [Token],
        explanation key: ExplanationKey,
        _ values: [String: String] = [:]
    ) -> Issue {
        issue(
            .accent, .error, from: index, through: index, in: tokens,
            replacement: matchingCase(of: tokens[index].text, "a"),
            explanation: explanations.render(key, values),
            source: "Accent rule"
        )
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
    private func auxiliaryIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        var issues: [Issue] = []
        guard tokens.count >= 3 else { return issues }
        for index in 0..<(tokens.count - 2) {
            let subject = tokens[index]
            let auxiliary = tokens[index + 1]
            let participle = tokens[index + 2]
            guard Self.subjectPronouns.contains(subject.normalized),
                  subject.isAdjacentToNext, auxiliary.isAdjacentToNext,
                  !isCoordinated(tokens, subjectAt: index),
                  // "vous nous avez vus": nous is the object, and the participle agrees with it.
                  index == 0 || !tokens[index - 1].isAdjacentToNext
                    || !Self.subjectPronouns.contains(tokens[index - 1].normalized),
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
                      // "elle a vue sur la mer": vue is a noun there, not a participle. A form
                      // that is also a noun counts only when the tagger is sure avoir is the
                      // helper and an object follows: "elle a prise une photo".
                      lexicon.noun(participle.normalized) == nil || isPastTenseWithObject(text, avoirAt: index + 1),
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

    /// Whether avoir at `index` is surely a helper verb whose participle is followed by a
    /// determiner, as in "il a faite ses devoirs".
    private func isPastTenseWithObject(_ text: TaggedText, avoirAt index: Int) -> Bool {
        let tokens = text.tokens
        guard text.isHelperVerb(index, certainty: Self.tagCertainty),
              index + 2 < tokens.count, tokens[index + 1].isAdjacentToNext else { return false }
        return Self.determiners[tokens[index + 2].normalized] != nil
    }

    /// The reflexive pronouns each subject takes: je me, tu te, il se, nous nous.
    private static let reflexivePronouns: [String: Set<String>] = [
        "je": ["me", "m'"], "tu": ["te", "t'"],
        "il": ["se", "s'"], "elle": ["se", "s'"], "on": ["se", "s'"], "ils": ["se", "s'"], "elles": ["se", "s'"],
        "nous": ["nous"], "vous": ["vous"]
    ]

    /// Each reflexive pronoun written whole and elided.
    private static let reflexiveForms: [String: (whole: String, elided: String)] = [
        "me": ("me", "m'"), "m'": ("me", "m'"), "te": ("te", "t'"), "t'": ("te", "t'"),
        "se": ("se", "s'"), "s'": ("se", "s'"), "nous": ("nous", "nous"), "vous": ("vous", "vous")
    ]

    /// Returns the subject of the reflexive pronoun at `index`, when the pronoun matches it,
    /// with at most ne between: "il s'", "je ne me", "nous nous". Returns nil otherwise.
    private func reflexiveSubject(at index: Int, in tokens: [Token]) -> Int? {
        var subject = index - 1
        if subject >= 0, ["ne", "n'"].contains(tokens[subject].normalized), tokens[subject].isAdjacentToNext { subject -= 1 }
        guard subject >= 0, tokens[subject].isAdjacentToNext,
              Self.reflexivePronouns[tokens[subject].normalized]?.contains(tokens[index].normalized) == true,
              !isCoordinated(tokens, subjectAt: subject) else { return nil }
        return subject
    }

    /// Whether the word at `index` is a reflexive pronoun followed by a form of avoir, as in
    /// "je me ai levé", which the reflexive auxiliary rule fixes.
    private func isReflexiveBeforeAvoir(at index: Int, in tokens: [Token]) -> Bool {
        index + 1 < tokens.count && tokens[index].isAdjacentToNext
            && Self.avoirTenses[tokens[index + 1].normalized] != nil
            && reflexiveSubject(at: index, in: tokens) != nil
    }

    /// Flags avoir after a reflexive pronoun, since a reflexive verb always takes être in
    /// the compound past: "il s'a trompé" → "il s'est trompé", "nous nous avons couchés"
    /// → "nous nous sommes couchés".
    ///
    /// The pronoun must match its subject, so "il m'a vu" and "vous nous avez vus", where it
    /// is an object, are left alone, and a past participle must follow, after at most one
    /// negation word. The learner's participle is kept.
    private func reflexiveAuxiliaryIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropLast(2) {
            let reflexive = tokens[index]
            let auxiliary = tokens[index + 1]
            guard let forms = Self.reflexiveForms[reflexive.normalized],
                  isReflexiveBeforeAvoir(at: index, in: tokens), auxiliary.isAdjacentToNext,
                  let subjectIndex = reflexiveSubject(at: index, in: tokens),
                  let tense = Self.avoirTenses[auxiliary.normalized],
                  let person = Self.subjectPersons[tokens[subjectIndex].normalized],
                  let etre = lexicon.conjugate("être", tense + person) else { continue }
            var participleIndex = index + 2
            if ["pas", "jamais", "plus", "rien"].contains(tokens[participleIndex].normalized),
               tokens[participleIndex].isAdjacentToNext, participleIndex + 1 < tokens.count {
                participleIndex += 1
            }
            guard !lexicon.participles(tokens[participleIndex].normalized).isEmpty else { continue }

            // "s'a" becomes "s'est", but "s'ont" becomes "se sont".
            let elides = etre.first.map { "aeiouéèê".contains($0) } == true && forms.elided.hasSuffix("'")
            let pronoun = elides ? forms.elided : forms.whole + " "
            let replacement = matchingCase(of: reflexive.text, pronoun) + etre
            let subject = tokens[subjectIndex].normalized
            issues.append(issue(
                .auxiliary, .error, from: index, through: index + 1, in: tokens,
                replacement: replacement,
                explanation: explanations.render(.reflexiveAuxiliary, ["fix": subject + " " + pronoun + etre]),
                source: "Auxiliary rule · reflexive verb"
            ))
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
            // "le boulanger nous a donné": mid-clause, nous or vous before a third-person verb is the object.
            if ["nous", "vous"].contains(subject.normalized), index > 0, !tokens[index - 1].endsClause,
               readings.contains(where: { $0.codes.contains { $0.hasSuffix("3s") || $0.hasSuffix("3p") } }) { continue }
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

    /// Words that can sit between aller and its infinitive: "il va peut-être pleuvoir".
    private static let wordsBeforeNearFutureVerb: Set<String> = [
        "peut-être", "bien", "encore", "déjà", "toujours", "vraiment", "aussi", "pas", "plus", "jamais"
    ]

    /// Words Lexique lists as verb forms that aren't verbs after aller: "il va entre les
    /// arbres", "je vais puis je reviens", "il va soit à Paris, soit à Lyon".
    private static let notNearFutureVerbs: Set<String> = ["entre", "puis", "soit"]

    /// Flags a conjugated verb where aller needs an infinitive: "il va pleut" → "pleuvoir".
    ///
    /// The word must be a verb form and nothing else, with one verb behind it, so "elle va
    /// mieux" and "je vais lui parler" are never in doubt. Punctuation ends the search,
    /// which keeps "je vais bien, mange ta soupe" silent.
    private func nearFutureIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices {
            guard let person = Self.subjectPersons[tokens[index].normalized], tokens[index].isAdjacentToNext else { continue }
            var position = index + 1
            if position < tokens.count, ["ne", "n'"].contains(tokens[position].normalized), tokens[position].isAdjacentToNext {
                position += 1
            }
            guard position < tokens.count, tokens[position].isAdjacentToNext,
                  lexicon.conjugations(tokens[position].normalized).contains(where: { $0.verb == "aller" && $0.codes.contains("ip" + person) }) else { continue }
            position += 1
            while position < tokens.count, Self.wordsBeforeNearFutureVerb.contains(tokens[position].normalized),
                  tokens[position].isAdjacentToNext {
                position += 1
            }
            guard position < tokens.count else { continue }

            let verbToken = tokens[position]
            let word = verbToken.normalized
            // A capital marks a name, and Lexique lists some as verb forms: Marie, Calais, Vienne.
            guard verbToken.text.first?.isLowercase == true,
                  !Self.preverbalWords.contains(word), !Self.notNearFutureVerbs.contains(word),
                  !lexicon.isInfinitive(word), lexicon.noun(word) == nil, lexicon.adjectiveLemmas(of: word).isEmpty else { continue }
            let readings = lexicon.conjugations(word)
            guard readings.count == 1, let reading = readings.first else { continue }

            issues.append(issue(
                .conjugation, .error, from: position, through: position, in: tokens,
                replacement: matchingCase(of: verbToken.text, reading.verb),
                explanation: explanations.render(.nearFutureInfinitive, ["fix": reading.verb]),
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

    // MARK: - Subjunctive

    /// Fixed phrases that put the verb after their que in the subjunctive, as the words
    /// before que, with the name the explanation gives each one.
    ///
    /// Bien que is left out here: "je sais bien que tu viens" is correct, so it only counts
    /// at the start of a clause, which `subjunctiveTrigger(before:in:)` checks.
    private static let subjunctivePhrases: [(words: [String], name: String)] = [
        (["il", "faut"], "il faut que"),
        (["pour"], "pour que"),
        (["avant"], "avant que"),
        (["sans"], "sans que"),
        (["à", "moins"], "à moins que"),
        (["jusqu'", "à", "ce"], "jusqu'à ce que"),
        (["il", "est", "important"], "il est important que"),
        (["il", "est", "nécessaire"], "il est nécessaire que"),
        (["c'", "est", "dommage"], "c'est dommage que")
    ]

    /// Adjectives of feeling that take the subjunctive after être and que, by the name the
    /// explanation gives each.
    private static let subjunctiveFeelings: [String: String] = [
        "content": "être content que", "contente": "être content que",
        "contents": "être content que", "contentes": "être content que",
        "triste": "être triste que", "tristes": "être triste que"
    ]

    /// Returns the `count` words just before `index`, when nothing but spaces separates
    /// them from each other and from the word at `index`; returns nil otherwise.
    private func adjacentWords(_ count: Int, before index: Int, in tokens: [Token]) -> [String]? {
        guard index - count >= 0 else { return nil }
        let range = (index - count)..<index
        guard range.allSatisfy({ tokens[$0].isAdjacentToNext }) else { return nil }
        return range.map { tokens[$0].normalized }
    }

    /// Returns the name of the subjunctive trigger that ends right before the que or qu' at
    /// `index`, such as "il faut que" or "vouloir que", or nil when there is none.
    ///
    /// The list is closed and every phrase must sit directly before que, so penser que,
    /// espérer que, après que and a relative que ("le livre que je lis") never match. A
    /// vouloir or aimer after ne is the restrictive ne… que ("je ne veux que du pain"), so
    /// it doesn't count.
    private func subjunctiveTrigger(before index: Int, in tokens: [Token]) -> String? {
        for phrase in Self.subjunctivePhrases where adjacentWords(phrase.words.count, before: index, in: tokens) == phrase.words {
            return phrase.name
        }
        guard let previous = adjacentWords(1, before: index, in: tokens)?.first else { return nil }

        // Bien que only at the start of a clause: "Bien qu'il ait froid, il court."
        if previous == "bien", index == 1 || tokens[index - 2].endsClause {
            return "bien que"
        }
        let isAfterNe = (1...2).contains { distance in
            adjacentWords(distance, before: index - 1, in: tokens).map { ["ne", "n'"].contains($0[0]) } == true
        }
        if isForm(previous, of: "vouloir"), !isAfterNe {
            return "vouloir que"
        }
        if ["aimerais", "aimerait"].contains(previous), !isAfterNe {
            return "aimer que"
        }
        guard let before = adjacentWords(2, before: index, in: tokens)?.first else { return nil }
        if previous == "peur", isForm(before, of: "avoir") {
            return "avoir peur que"
        }
        if let feeling = Self.subjunctiveFeelings[previous], isForm(before, of: "être") {
            return feeling
        }
        if previous == "doute", before == "je" {
            return "douter que"
        }
        return nil
    }

    /// Returns the present subjunctive of `verb` for `person`, such as "fasse" for faire and "1s".
    ///
    /// With nous and vous, the present subjunctive of nearly every verb is spelled like the
    /// imperfect (nous allions, vous parliez), and Lexique tags most of those forms as
    /// imperfect only. The imperfect stands in when no subjunctive is listed, except for the
    /// verbs whose forms differ. Lexique tags fassions and soyez, but not refassions, so
    /// their whole families are left out.
    private func presentSubjunctive(of verb: String, _ person: String) -> String? {
        if let form = lexicon.conjugate(verb, "sp" + person) { return form }
        guard ["1p", "2p"].contains(person),
              !Self.irregularSubjunctiveEndings.contains(where: { verb.hasSuffix($0) }) else { return nil }
        return lexicon.conjugate(verb, "ii" + person)
    }

    /// Infinitive endings of the verbs whose nous and vous subjunctive isn't the imperfect:
    /// faire and its compounds (satisfaire), pouvoir, savoir, être and avoir.
    private static let irregularSubjunctiveEndings = ["faire", "pouvoir", "savoir", "être", "avoir"]

    /// Flags an indicative verb where a trigger needs the present subjunctive: "il faut que je
    /// fais" → "fasse", "je veux que tu viens" → "viennes".
    ///
    /// The subject must be a pronoun right after que, with only ne or object pronouns before
    /// the verb. A form with any subjunctive reading is left alone, so "il faut que je parle"
    /// (the same in both moods), a literary "qu'il vînt" and a subjunctive in the wrong person,
    /// which the conjugation rule fixes, are never flagged. When the verb could belong to two
    /// verbs whose subjunctives differ, as suis (être or suivre), the rule stays silent.
    private func subjunctiveIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropLast(2) {
            let que = tokens[index]
            let subjectIndex = index + 1
            let subject = tokens[subjectIndex]
            guard ["que", "qu'"].contains(que.normalized), que.isAdjacentToNext, subject.isAdjacentToNext,
                  let person = Self.subjectPersons[subject.normalized],
                  let trigger = subjunctiveTrigger(before: index, in: tokens) else { continue }

            // Look past ne and object pronouns: "avant que je ne parte", "pour que tu me le dises".
            var verbIndex = subjectIndex + 1
            while verbIndex < tokens.count - 1, verbIndex < subjectIndex + 4,
                  Self.preverbalWords.contains(tokens[verbIndex].normalized), tokens[verbIndex].isAdjacentToNext {
                verbIndex += 1
            }
            let verbToken = tokens[verbIndex]
            guard !Self.preverbalWords.contains(verbToken.normalized), !verbToken.normalized.hasSuffix("'") else { continue }
            let readings = lexicon.conjugations(verbToken.normalized)
            guard !readings.isEmpty,
                  !readings.contains(where: { $0.codes.contains { $0.hasPrefix("sp") || $0.hasPrefix("si") } }) else { continue }
            let fixes = Set(readings.map { presentSubjunctive(of: $0.verb, person) })
            guard fixes.count == 1, let only = fixes.first, let fix = only, fix != verbToken.normalized else { continue }

            // "que je va" becomes "que j'aille", and "que j'" loses its elision before a consonant.
            let fixStartsWithVowel = fix.first.map { "aeiouyàâéèêëîïôûh".contains($0) } == true
            let changesElision = verbIndex == subjectIndex + 1
                && (subject.normalized == "je" && fixStartsWithVowel || subject.normalized == "j'" && !fixStartsWithVowel)
            let first = changesElision ? subjectIndex : verbIndex
            let replacement = !changesElision
                ? matchingCase(of: verbToken.text, fix)
                : subject.normalized == "je"
                    ? matchingCase(of: subject.text, "j'") + fix
                    : matchingCase(of: subject.text, "je") + " " + fix
            issues.append(issue(
                .subjunctive, .error, from: first, through: verbIndex, in: tokens,
                replacement: replacement,
                explanation: explanations.render(.subjunctive, ["trigger": trigger, "fix": fix]),
                source: "Subjunctive rule"
            ))
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

    /// The verbs of liking, whose present forms Lexique supplies.
    private static let likingVerbs: Set<String> = ["aimer", "adorer", "détester", "préférer"]

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
            guard let verb = lexicon.conjugations(verbToken.normalized).first(where: { reading in
                      Self.likingVerbs.contains(reading.verb) && reading.codes.contains { $0.hasPrefix("ip") }
                  })?.verb, verbToken.isAdjacentToNext,
                  // "le fromage que j'aime est bon": the object came before, so the next word is the main verb.
                  !tokens[max(0, index - 2)..<index].contains(where: { ["que", "qu'"].contains($0.normalized) }) else { continue }
            // Look past one adverb: "je n'aime pas fromage", "j'aime bien chocolat".
            var nounIndex = index + 1
            if Self.likingAdverbs.contains(tokens[nounIndex].normalized), tokens[nounIndex].isAdjacentToNext, nounIndex + 1 < tokens.count {
                nounIndex += 1
            }
            let noun = tokens[nounIndex]
            let word = noun.normalized
            // "j'aime son chien": before a noun phrase, son is the possessive, not the noun for a sound.
            if word == "son", startsNounPhrase(after: nounIndex, in: tokens) { continue }
            guard !Self.bareAfterLiking.contains(word),
                  noun.text.first?.isUppercase == false,
                  word.first != "h",
                  // "j'aime dîner": an infinitive, even one that is also a noun, takes no article.
                  !lexicon.isInfinitive(word),
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

    /// Whether a noun, or an adjective and then a noun, directly follows the word at `index`.
    private func startsNounPhrase(after index: Int, in tokens: [Token]) -> Bool {
        let next = index + 1
        guard next < tokens.count, tokens[index].isAdjacentToNext else { return false }
        if lexicon.noun(tokens[next].normalized) != nil { return true }
        return next + 1 < tokens.count && tokens[next].isAdjacentToNext
            && !lexicon.adjectiveLemmas(of: tokens[next].normalized).isEmpty
            && lexicon.noun(tokens[next + 1].normalized) != nil
    }

    // MARK: - Article and noun number

    /// Singular articles with the plural each becomes: "la montages" → "les montages".
    private static let pluralOfArticle: [String: String] = [
        "le": "les", "la": "les", "l'": "les", "un": "des", "une": "des", "au": "aux", "du": "des"
    ]

    /// Plural articles, which need a plural noun after them.
    private static let pluralArticles: Set<String> = ["les", "des", "aux"]

    /// Singular nouns that Lexique lists only as the plural of another word: une fois, not
    /// une foi, and le vers, the worm, not a plural of ver.
    private static let singularDespitePluralReading: Set<String> = ["fois", "vers"]

    /// Words a learner writes after des when they mean dès, "from": "des demain".
    private static let afterDes: Set<String> = ["demain", "maintenant", "lors", "aujourd'hui"]

    /// Returns the noun readings of the singular a plural form comes from: montage for
    /// montages, journal for journaux.
    private func singulars(of plural: String) -> [(word: String, noun: Lexicon.Noun)] {
        var candidates: [String] = []
        if plural.hasSuffix("aux") { candidates += [String(plural.dropLast(3)) + "al", String(plural.dropLast(3)) + "ail"] }
        if plural.hasSuffix("s") || plural.hasSuffix("x") { candidates.append(String(plural.dropLast())) }
        return candidates.compactMap { word in
            guard let noun = lexicon.noun(word), noun.number != .plural else { return nil }
            return (word, noun)
        }
    }

    /// Whether a noun is surely plural: Lexique lists it only as a plural, and its singular
    /// is a noun whose gender fits.
    ///
    /// The gender check keeps out a singular noun that happens to share its spelling with
    /// another word's plural. Lexique gives cours both genders, since it's the masculine
    /// noun and the plural of the feminine cour, so "le cours" stays correct. A singular
    /// that takes both genders fits any plural, as enfant does enfants.
    private func isSurelyPlural(_ word: String) -> Bool {
        guard let entry = lexicon.noun(word), entry.number == .plural,
              !Self.singularDespitePluralReading.contains(word) else { return false }
        return singulars(of: word).contains { $0.noun.gender == nil || $0.noun.gender == entry.gender }
    }

    /// Returns a singular noun's plural form, if Lexique lists one whose gender fits:
    /// pommes for pomme, journaux for journal, chapeaux for chapeau, enfants for enfant.
    private func plural(of singular: String, gender: Gender?) -> String? {
        var candidates: [String] = []
        if singular.hasSuffix("al") { candidates.append(String(singular.dropLast(2)) + "aux") }
        if singular.hasSuffix("eau") || singular.hasSuffix("au") || singular.hasSuffix("eu") { candidates.append(singular + "x") }
        candidates.append(singular + "s")
        return candidates.first { word in
            guard let noun = lexicon.noun(word), noun.number != .singular else { return false }
            return gender == nil || noun.gender == nil || noun.gender == gender
        }
    }

    /// Flags an article whose number doesn't match the noun after it.
    ///
    /// A singular article before a plural noun takes the plural article, so "la montages"
    /// becomes "les montages" and "à la plages" becomes "aux plages". A plural article
    /// before a singular noun keeps the article and makes the noun plural, as in "des
    /// pomme" → "des pommes", since des could stand for either un or du in the singular.
    /// Nouns that serve both numbers, such as bras and temps, and names are skipped.
    private func articleNumberIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        var issues: [Issue] = []
        for index in tokens.indices.dropLast() {
            let article = tokens[index]
            let noun = tokens[index + 1]
            let word = noun.normalized
            guard article.isAdjacentToNext,
                  noun.text.first?.isUppercase == false,
                  !Self.superlativeMarkers.contains(word),
                  !lexicon.isInfinitive(word),
                  let entry = lexicon.noun(word) else { continue }
            // "vingt et un élèves": this un is a number, not an article.
            if isPartOfNumber(index, in: tokens) { continue }
            // "je les porte": the tagger can't rule out a pronoun. A word that is also a verb
            // counts only when the tagger is sure it's the noun: "il les finance".
            if ["le", "la", "l'", "les"].contains(article.normalized) {
                if text.mayBePronoun[index] { continue }
                if lexicon.isVerb(word), !text.isNounNotVerb(index + 1, certainty: Self.tagCertainty) { continue }
            }
            // A word that can also be an adjective counts only when the tagger is sure it's the noun.
            if !lexicon.adjectiveLemmas(of: word).isEmpty, !text.isNoun(index + 1, certainty: Self.tagCertainty) { continue }

            if let pluralArticle = Self.pluralOfArticle[article.normalized], isSurelyPlural(word) {
                // After à or de, le, la and l' contract with them in the plural: aux and des.
                var first = index
                var fix = pluralArticle
                if ["le", "la", "l'"].contains(article.normalized), followsContractingPreposition(index, in: tokens) {
                    first = index - 1
                    fix = tokens[first].normalized == "à" ? "aux" : "des"
                }
                issues.append(issue(
                    .article, .error, from: first, through: index + 1, in: tokens,
                    replacement: matchingCase(of: tokens[first].text, fix) + " " + noun.text,
                    explanation: explanations.render(.articleNumberPlural, ["noun": noun.text, "article": fix]),
                    source: "Article rule · Lexique"
                ))
            } else if Self.pluralArticles.contains(article.normalized), entry.number == .singular,
                      // Words ending in s, x or z are mostly the same in both numbers: les temps, les prix.
                      !["s", "x", "z"].contains(where: { word.hasSuffix($0) }),
                      // "les samedi 18 et dimanche 19": a day before its date stays singular.
                      !Self.days.contains(word),
                      !(article.normalized == "des" && Self.afterDes.contains(word)),
                      let plural = plural(of: word, gender: entry.gender) {
                let fix = article.text + article.gap + matchingCase(of: noun.text, plural)
                issues.append(issue(
                    .article, .error, from: index, through: index + 1, in: tokens,
                    replacement: fix,
                    explanation: explanations.render(.articleNumberSingular, [
                        "article": article.normalized, "fix": article.normalized + " " + plural
                    ]),
                    source: "Article rule · Lexique"
                ))
            }
        }
        return issues
    }

    // MARK: - Adjective agreement

    /// Flags an adjective directly after its noun that doesn't agree with it, as in
    /// "des pommes rouge".
    private func agreementIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
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
            if text.mayBePronoun[index] { continue }

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

    // MARK: - Age

    /// Each present and imperfect form of être with the form of avoir in its person and tense.
    private static let etreToAvoir: [String: String] = [
        "suis": "ai", "es": "as", "est": "a", "sommes": "avons", "êtes": "avez", "sont": "ont",
        "étais": "avais", "était": "avait", "étions": "avions", "étiez": "aviez", "étaient": "avaient"
    ]

    /// The words French numbers are built from, so "vingt-cinq" and "trente et un" count.
    private static let numberWords: Set<String> = [
        "un", "une", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "onze",
        "douze", "treize", "quatorze", "quinze", "seize", "vingt", "vingts", "trente", "quarante",
        "cinquante", "soixante", "cent", "cents", "et"
    ]

    /// Flags an age given with être, which copies English "I am 20": "je suis 20 ans" →
    /// "j'ai 20 ans", "mon frère est douze ans" → "a douze ans".
    ///
    /// The age is digits or number words right after être, then an or ans. The subject must be
    /// a subject pronoun or a determiner and noun, so "c'est vingt ans de travail" stays correct.
    private func ageIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices.dropFirst().dropLast() {
            let etre = tokens[index]
            guard let avoir = Self.etreToAvoir[etre.normalized] else { continue }
            // The digits sit in the gap after être, since the tokenizer keeps only words.
            var years = index + 1
            if etre.gap.wholeMatch(of: /\s+\d+\s+/) == nil {
                guard etre.isAdjacentToNext else { continue }
                while years < tokens.count, tokens[years - 1].isAdjacentToNext,
                      tokens[years].normalized.split(separator: "-").allSatisfy({ Self.numberWords.contains(String($0)) }) {
                    years += 1
                }
                guard years > index + 1, years < tokens.count, tokens[years - 1].isAdjacentToNext else { continue }
            }
            guard years < tokens.count, ["an", "ans"].contains(tokens[years].normalized) else { continue }

            let subject = tokens[index - 1]
            guard subject.isAdjacentToNext else { continue }
            let isPronounSubject = Self.subjectPronouns.contains(subject.normalized)
            let isNounSubject = index >= 2 && tokens[index - 2].isAdjacentToNext
                && Self.determiners[tokens[index - 2].normalized] != nil && lexicon.noun(subject.normalized) != nil
            guard isPronounSubject || isNounSubject else { continue }

            // "je suis" becomes "j'ai": the subject elides before avoir.
            let isJe = subject.normalized == "je"
            let first = isJe ? index - 1 : index
            let replacement = isJe ? matchingCase(of: subject.text, "j'") + avoir : matchingCase(of: etre.text, avoir)
            var age = etre.gap
            for position in (index + 1)..<years { age += tokens[position].text + tokens[position].gap }
            let fix = (isJe ? "j'" : subject.normalized + " ") + avoir + age + tokens[years].text
            issues.append(issue(
                .avoirExpression, .error, from: first, through: index, in: tokens,
                replacement: replacement,
                explanation: explanations.render(.wordChoice, [
                    "note": "French gives an age with avoir: you have your years.", "fix": fix
                ]),
                source: "Word-choice rule"
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

    // MARK: - Listed phrases

    /// Flags each listed phrase of one kind: look-alikes such as "comment cava" and English
    /// patterns such as "je suis faim" are errors, idioms are suggestions, and meaning
    /// questions ask which wording the learner meant. Each entry is wrong (or worth a
    /// question) wherever it appears, apart from its listed exceptions.
    private func patternIssues(
        in text: TaggedText,
        list: (kind: PhrasePattern.Kind, entries: [PhrasePattern], trie: PhraseTrie)
    ) -> [Issue] {
        let tokens = text.tokens
        return list.trie.matches(in: tokens, keys: { patternKeys(at: $0, in: text) }).compactMap { match in
            let entry = list.entries[match.entry]
            guard allowsMatch(match, in: tokens, entry: entry) else { return nil }
            if list.kind == .meaning {
                let last = match.start + match.length - 1
                var question = issue(
                    .meaning, .suggestion, from: match.start, through: last, in: tokens,
                    replacement: nil,
                    explanation: explanations.render(.meaning, ["note": entry.note]),
                    source: "Meaning list"
                )
                let first = tokens[match.start].text
                question.choices = (entry.choices ?? []).map { choice in
                    let wording = renderedFix(choice.text, for: entry, match: match, in: tokens) ?? choice.text
                    return Choice(text: matchingCase(of: first, wording), meaning: choice.meaning)
                }
                return question
            }
            guard let fix = entry.fix,
                  let rendered = renderedFix(fix, for: entry, match: match, in: tokens) else { return nil }
            let (first, elision) = elided(rendered, before: match.start, in: tokens)
            let (contractedLast, contraction) = contracted(elision, after: match.start + match.length - 1, in: tokens)
            let (last, replacement) = elidedEnding(contraction, after: contractedLast, in: tokens)
            let caseMatched = matchingCase(of: tokens[first].text, replacement)
            switch list.kind {
            case .lookAlike, .wordChoice:
                let isLookAlike = list.kind == .lookAlike
                let kind: IssueKind = isLookAlike ? .lookAlike : entry.swapsEtreForAvoir ? .avoirExpression : .wordChoice
                return issue(
                    kind, .error, from: first, through: last, in: tokens,
                    replacement: caseMatched,
                    explanation: explanations.render(isLookAlike ? .lookAlike : .wordChoice, ["note": entry.note, "fix": replacement]),
                    source: isLookAlike ? "Look-alike list" : "Word-choice list"
                )
            case .preposition:
                return issue(
                    .preposition, .error, from: first, through: last, in: tokens,
                    replacement: caseMatched,
                    explanation: explanations.render(.preposition, ["note": entry.note, "fix": replacement]),
                    source: "Preposition list"
                )
            case .idiom, .meaning:
                return issue(
                    .idiom, .suggestion, from: first, through: last, in: tokens,
                    replacement: caseMatched,
                    explanation: explanations.render(.idiom, ["suggestion": replacement, "note": entry.note]),
                    source: "Idiom list"
                )
            }
        }
    }

    /// Returns every pattern word token `index` can stand for: itself, each `$class` that lists
    /// it, and `@verb` and `@verb:tense` for each verb Lexique says it is a form of, unless the
    /// tagger is sure it's a noun here, as demande in "la demande sur le site".
    private func patternKeys(at index: Int, in text: TaggedText) -> [String] {
        let word = text.tokens[index].normalized
        var keys = [word] + patterns.classKeys(of: word)
        guard !text.isNounNotVerb(index, certainty: Self.tagCertainty) else { return keys }
        for reading in lexicon.conjugations(word) {
            keys.append("@" + reading.verb)
            keys += reading.codes.map { "@\(reading.verb):\($0.prefix(2))" }
        }
        for reading in lexicon.participles(word) {
            keys += ["@" + reading.verb, "@\(reading.verb):pp"]
        }
        if lexicon.isInfinitive(word) {
            keys += ["@" + word, "@\(word):inf"]
        }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// Fills a fix's `@verb` and `$class` words from the learner's own words, or returns
    /// `nil` when Lexique has no form of the new verb for the learner's person and tense.
    private func renderedFix(_ fix: String, for entry: PhrasePattern, match: PhraseTrie.Match, in tokens: [Token]) -> String? {
        let pattern = entry.matchWords
        let classTokens = pattern.indices.filter { pattern[$0].hasPrefix("$") }.map { tokens[match.start + $0] }
        let verbPosition = pattern.firstIndex { $0.hasPrefix("@") }
        var nextClass = 0
        var words: [String] = []
        for word in fix.split(separator: " ").map(String.init) {
            if word.hasPrefix("$") {
                guard nextClass < classTokens.count else { return nil }
                words.append(classTokens[nextClass].text)
                nextClass += 1
            } else if word.hasPrefix("@"), let verbPosition {
                let token = tokens[match.start + verbPosition]
                let source = Self.lemma(of: pattern[verbPosition])
                let target = Self.lemma(of: word)
                if source == target {
                    words.append(token.text)
                } else {
                    guard let form = inflect(token.normalized, of: source, as: target, at: match.start + verbPosition, in: tokens) else { return nil }
                    words.append(form)
                }
            } else {
                words.append(word)
            }
        }
        return words.joined(separator: " ")
    }

    /// The verb a `@verb` or `@verb:ip` pattern word names.
    private static func lemma(of patternWord: String) -> String {
        String(patternWord.dropFirst().prefix { $0 != ":" })
    }

    /// Returns `target` in the person and tense of `form`, a form of `source`: "fait" of faire
    /// becomes "prend" of prendre, or "pris" after avoir.
    private func inflect(_ form: String, of source: String, as target: String, at index: Int, in tokens: [Token]) -> String? {
        if form == source, lexicon.isInfinitive(form) { return target }
        let participle = lexicon.participles(form).first { $0.verb == source }
        let conjugation = lexicon.conjugations(form).first { $0.verb == source }
        // "pris" is also a passé simple, which learners rarely mean; "fait" is also a
        // present, so it's a participle only after avoir or être.
        let everydayTense = conjugation?.codes.contains { code in Self.tensePriority.prefix(5).contains { code.hasPrefix($0) } } ?? false
        if let participle, !everydayTense || followsAuxiliary(index, in: tokens) {
            return lexicon.participle(of: target, gender: participle.gender ?? .masculine, number: participle.number ?? .singular)
        }
        guard let conjugation,
              let code = Self.tensePriority.lazy.compactMap({ tense in conjugation.codes.sorted().first { $0.hasPrefix(tense) } }).first
        else { return nil }
        return lexicon.conjugate(target, code)
    }

    /// Whether a form of avoir or être comes within three words before `index`, as in "j'ai
    /// fait" or "je n'ai pas fait".
    private func followsAuxiliary(_ index: Int, in tokens: [Token]) -> Bool {
        tokens[max(0, index - 3)..<index].contains { Self.avoirTenses[$0.normalized] != nil || Self.etreForms.contains($0.normalized) }
    }

    /// Adjusts je and j' before a fix whose first word changes: "je suis faim" becomes
    /// "j'ai faim", and "j'ai un bon temps" becomes "je passe un bon moment". Returns the
    /// first token the fix covers and its text.
    private func elided(_ replacement: String, before start: Int, in tokens: [Token]) -> (first: Int, text: String) {
        guard start > 0, tokens[start - 1].isAdjacentToNext, let initial = replacement.first else { return (start, replacement) }
        let subject = tokens[start - 1]
        let startsWithVowel = "aeiouyàâéèêëîïôûh".contains(initial)
        if subject.normalized == "je", startsWithVowel {
            return (start - 1, matchingCase(of: subject.text, "j'") + replacement)
        }
        if subject.normalized == "j'", !startsWithVowel {
            return (start - 1, matchingCase(of: subject.text, "je") + " " + replacement)
        }
        return (start, replacement)
    }

    /// Whether a trie match stands, given the words around it: some listed phrases are
    /// correct French after or before particular words.
    private func allowsMatch(_ match: PhraseTrie.Match, in tokens: [Token], entry: PhrasePattern) -> Bool {
        let start = match.start
        let end = start + match.length
        let before = start > 0 && tokens[start - 1].isAdjacentToNext ? tokens[start - 1].normalized : nil
        let after = end < tokens.count && tokens[end - 1].isAdjacentToNext ? tokens[end].normalized : nil
        // "il cava" is the verb caver, which is correct French.
        if let before, entry.unlessAfter?.contains(before) == true { return false }
        // A subject pronoun belongs to the verb after it, so "ce que j'aime du roman" checks
        // the word before j' too.
        if let before, Self.subjectPronouns.contains(before), start > 1, tokens[start - 2].isAdjacentToNext,
           entry.unlessAfter?.contains(tokens[start - 2].normalized) == true { return false }
        if let onlyAfter = entry.onlyAfter, !onlyAfter.contains(before ?? "") { return false }
        // "Pierre cava un trou": caver takes an object, so the phrase is correct here.
        if let after, entry.unlessBefore?.contains(after) == true { return false }
        // "et tu ?" is wrong; "et tu vas bien" is correct French.
        if entry.onlyAtClauseEnd == true, end < tokens.count, !tokens[end - 1].endsClause { return false }
        // "je n'ai pas encore fini": only "not yet" makes sense, so the question would be noise.
        if entry.unlessBeforeParticiple == true, let after, !lexicon.participles(after).isEmpty { return false }
        // "essaie à faire" is wrong, but "essaie à Paris" says where.
        let infinitiveFollows = infinitiveFollows(end, in: tokens)
        if entry.onlyBeforeInfinitive == true, !infinitiveFollows { return false }
        // "j'attends pour voir" and "attendre pour en savoir" are correct; "j'attends pour le bus" copies "wait for".
        if entry.unlessBeforeInfinitive == true, infinitiveFollows { return false }
        return true
    }

    /// Whether an infinitive starts at token `index`, after at most one object pronoun, as in
    /// "pour voir" or "pour en savoir".
    private func infinitiveFollows(_ index: Int, in tokens: [Token]) -> Bool {
        guard index > 0, index < tokens.count, tokens[index - 1].isAdjacentToNext else { return false }
        if lexicon.isInfinitive(tokens[index].normalized) { return true }
        guard Self.preverbalWords.contains(tokens[index].normalized), tokens[index].isAdjacentToNext,
              index + 1 < tokens.count else { return false }
        return lexicon.isInfinitive(tokens[index + 1].normalized)
    }

    /// Contracts a fix that ends in à or de with a le or les right after the phrase, so
    /// "dépend sur le temps" becomes "dépend du temps" rather than "dépend de le temps".
    /// Returns the last token the fix covers and its text.
    private func contracted(_ replacement: String, after last: Int, in tokens: [Token]) -> (last: Int, text: String) {
        guard last + 1 < tokens.count, tokens[last].isAdjacentToNext else { return (last, replacement) }
        let words = replacement.split(separator: " ").map(String.init)
        guard let preposition = words.last,
              let contraction = Self.contractions[preposition + " " + tokens[last + 1].normalized],
              // "de le faire": le is a pronoun before an infinitive, and no contraction applies.
              last + 2 >= tokens.count || !lexicon.isInfinitive(tokens[last + 2].normalized) else { return (last, replacement) }
        return (last + 1, (words.dropLast() + [contraction]).joined(separator: " "))
    }

    /// Elides a fix that ends in de or que before a vowel sound right after the phrase, so
    /// "beaucoup des amis" becomes "beaucoup d'amis" rather than "beaucoup de amis".
    /// Returns the last token the fix covers and its text.
    private func elidedEnding(_ replacement: String, after last: Int, in tokens: [Token]) -> (last: Int, text: String) {
        var words = replacement.split(separator: " ").map(String.init)
        guard last + 1 < tokens.count, tokens[last].isAdjacentToNext, takesElision(tokens[last + 1]),
              let final = words.last, ["de", "que"].contains(final),
              let elided = Self.elisions[final] else { return (last, replacement) }
        words.removeLast()
        return (last + 1, (words + [elided + tokens[last + 1].text]).joined(separator: " "))
    }

    // MARK: - Countries

    /// Verbs of coming from somewhere, after which de before a country is about origin.
    private static let originVerbs = ["venir", "revenir", "rentrer", "arriver", "partir", "sortir", "retourner", "repartir"]

    /// Whether `word` is a conjugated form, participle or infinitive of `verb`.
    private func isForm(_ word: String, of verb: String) -> Bool {
        word == verb || lexicon.conjugations(word).contains { $0.verb == verb } || lexicon.participles(word).contains { $0.verb == verb }
    }

    /// Flags the wrong preposition before a country: "à France" → "en France", "en Canada"
    /// → "au Canada", "de Canada" → "du Canada". The country's article settles it: la and
    /// l' take en (de, d'), le takes au (du), and les takes aux (des).
    ///
    /// Only a capitalised name with no article of its own is judged, so "à la France" and
    /// "la chine" (porcelain) stay silent. Countries listed without an article, such as Cuba
    /// and Israël, vary in usage and are left alone.
    private func countryIssues(in tokens: [Token], countries: [(key: String, value: String)], trie: PhraseTrie) -> [Issue] {
        trie.matches(in: tokens).compactMap { match in
            let (name, article) = countries[match.entry]
            let start = match.start
            guard start > 0, tokens[start].text.first?.isUppercase == true,
                  tokens[start - 1].isAdjacentToNext, !article.isEmpty else { return nil }
            let preposition = tokens[start - 1]
            let isOrigin: Bool
            switch preposition.normalized {
            case "à", "en", "au", "aux", "dans": isOrigin = false
            case "de", "d'", "du", "des": isOrigin = true
            default: return nil
            }
            // "la République de Vanuatu", "Frédéric II de Danemark": after a noun, de can belong
            // to a fixed title, so a missing du or des counts only after a verb of coming.
            if isOrigin, ["de", "d'"].contains(preposition.normalized), ["le", "les"].contains(article),
               !(start >= 2 && Self.originVerbs.contains { isForm(tokens[start - 2].normalized, of: $0) }) { return nil }
            let expected: String
            let reason: String
            switch article {
            case "la":
                (expected, reason) = (isOrigin ? "de" : "en", "a feminine country")
            case "l'":
                (expected, reason) = (isOrigin ? "d'" : "en", "a country starting with a vowel")
            case "le":
                (expected, reason) = (isOrigin ? "du" : "au", "a masculine country")
            case "les":
                (expected, reason) = (isOrigin ? "des" : "aux", "a plural country")
            default:
                return nil
            }
            guard expected != preposition.normalized else { return nil }
            let last = start + match.length - 1
            var nameText = ""
            for index in start..<last { nameText += tokens[index].text + tokens[index].gap }
            nameText += tokens[last].text
            let fix = expected + (expected.hasSuffix("'") ? "" : " ") + nameText
            return issue(
                .preposition, .error, from: start - 1, through: last, in: tokens,
                replacement: matchingCase(of: preposition.text, fix),
                explanation: explanations.render(.placePreposition, ["place": name, "reason": reason, "fix": fix]),
                source: "Country list"
            )
        }
    }

    /// Nouns that keep la after en: "en la matière", "en la personne de", and "en la majeur", the key.
    private static let nounsAfterEnLa: Set<String> = ["matière", "personne", "majeur", "mineur"]

    /// Verbs after which en before an article is a mistake for dans.
    private static let placeVerbs = [
        "aller", "courir", "marcher", "habiter", "vivre", "voyager", "rester", "travailler",
        "venir", "partir", "arriver", "entrer", "jouer", "dormir", "manger", "lire"
    ]

    /// Flags en before le, la or les and a noun, where French uses dans: "en les montagnes".
    ///
    /// L' is left alone for "en l'air", and any -ant word for "en les voyant", where les is a
    /// pronoun. Only after a verb of movement, place or activity: "croire en la science",
    /// "consister en la direction" and "en la majeur" are correct.
    private func enArticleIssues(in tokens: [Token]) -> [Issue] {
        tokens.indices.dropLast(2).compactMap { index in
            let article = tokens[index + 1]
            let noun = tokens[index + 2]
            let word = noun.normalized
            guard tokens[index].normalized == "en", tokens[index].isAdjacentToNext, article.isAdjacentToNext,
                  ["le", "la", "les"].contains(article.normalized), noun.text.first?.isUppercase == false,
                  lexicon.noun(word) != nil, !Self.nounsAfterEnLa.contains(word), !word.hasSuffix("ant"),
                  index > 0, tokens[index - 1].isAdjacentToNext,
                  Self.placeVerbs.contains(where: { isForm(tokens[index - 1].normalized, of: $0) }) else { return nil }
            let fix = "dans " + article.text
            return issue(
                .preposition, .error, from: index, through: index + 1, in: tokens,
                replacement: matchingCase(of: tokens[index].text, fix),
                explanation: explanations.render(.enArticle, ["fix": fix]),
                source: "En + article rule"
            )
        }
    }

    /// Flags a place with no preposition after a subject and a form of aller or habiter:
    /// "je vais France" → "en France", "je vais Paris" → "à Paris".
    ///
    /// A bare city is judged after aller only, since "j'habite Paris" is correct French.
    /// The subject is required, so the cheer "Allez Marseille!" stays silent.
    private func missingPlacePrepositionIssues(
        in tokens: [Token],
        countries: [(key: String, value: String)],
        trie: PhraseTrie
    ) -> [Issue] {
        /// Whether the word at `index` follows a subject and a form of one of `verbs`.
        func followsSubjectAndVerb(_ index: Int, verbs: [String]) -> Bool {
            guard index >= 2, tokens[index - 1].isAdjacentToNext, tokens[index - 2].isAdjacentToNext,
                  Self.subjectPronouns.contains(tokens[index - 2].normalized) else { return false }
            return lexicon.conjugations(tokens[index - 1].normalized).contains { verbs.contains($0.verb) }
        }
        var issues: [Issue] = []
        var countryStarts = Set<Int>()
        for match in trie.matches(in: tokens) {
            let (name, article) = countries[match.entry]
            guard tokens[match.start].text.first?.isUppercase == true, !article.isEmpty,
                  let expected = ["la": "en", "l'": "en", "le": "au", "les": "aux"][article] else { continue }
            countryStarts.insert(match.start)
            guard followsSubjectAndVerb(match.start, verbs: ["aller", "habiter"]) else { continue }
            let last = match.start + match.length - 1
            var nameText = ""
            for index in match.start..<last { nameText += tokens[index].text + tokens[index].gap }
            nameText += tokens[last].text
            let reason = ["la": "a feminine country", "l'": "a country starting with a vowel",
                          "le": "a masculine country", "les": "a plural country"][article] ?? "a country"
            let fix = expected + " " + nameText
            issues.append(issue(
                .preposition, .error, from: match.start, through: last, in: tokens,
                replacement: fix,
                explanation: explanations.render(.placePreposition, ["place": name, "reason": reason, "fix": fix]),
                source: "Missing place rule"
            ))
        }
        for index in tokens.indices where !countryStarts.contains(index) {
            let place = tokens[index]
            guard place.text.first?.isUppercase == true, followsSubjectAndVerb(index, verbs: ["aller"]),
                  !Self.likingAdverbs.contains(place.normalized),
                  patterns.classKeys(of: place.normalized).isEmpty else { continue }
            let fix = "à " + place.text
            issues.append(issue(
                .preposition, .error, from: index, through: index, in: tokens,
                replacement: fix,
                explanation: explanations.render(.placePreposition, ["place": place.text, "reason": "a place name", "fix": fix]),
                source: "Missing place rule"
            ))
        }
        return issues
    }

    // MARK: - Numbers and times

    /// The tens that form compounds with et or a hyphen.
    private static let numberTens: Set<String> = ["vingt", "trente", "quarante", "cinquante", "soixante"]

    /// Two to nine, the units that join a ten with a hyphen.
    private static let numberUnits: Set<String> = ["deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf"]

    /// Single number words of two or more.
    private static let pluralNumbers: Set<String> = numberUnits.union(numberTens).union([
        "dix", "onze", "douze", "treize", "quatorze", "quinze", "seize", "cent", "mille"
    ])

    /// Whether the un or une at `index` belongs to a larger number: "vingt et un", "cent un".
    private func isPartOfNumber(_ index: Int, in tokens: [Token]) -> Bool {
        guard ["un", "une"].contains(tokens[index].normalized), index > 0 else { return false }
        let previous = tokens[index - 1].normalized
        if ["cent", "cents", "mille"].contains(previous) { return true }
        guard previous == "et", index > 1 else { return false }
        return Self.numberTens.contains(tokens[index - 2].normalized) || tokens[index - 2].normalized == "mille"
    }

    /// Whether a hyphenated word names a number above two, such as dix-huit.
    private func isCompoundNumber(_ word: String) -> Bool {
        guard let first = word.split(separator: "-").first, word.contains("-") else { return false }
        return first == "dix" || Self.numberTens.contains(String(first)) || first == "quatre"
    }

    /// Flags how compound numbers join: "vingt et deux" → "vingt-deux", "vingt-un" →
    /// "vingt et un", "dix sept" → "dix-sept", "vingt deux" → "vingt-deux".
    private func numberWordIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for (index, token) in tokens.enumerated() {
            let word = token.normalized
            let parts = word.split(separator: "-").map(String.init)
            if parts.count == 2, Self.numberTens.contains(parts[0]), ["un", "une"].contains(parts[1]) {
                let fix = "\(parts[0]) et \(parts[1])"
                issues.append(numberIssue(from: index, through: index, in: tokens, fix: fix,
                                          note: "Before un or une, tens take et, with no hyphen."))
                continue
            }
            guard index + 1 < tokens.count, token.isAdjacentToNext else { continue }
            let next = tokens[index + 1].normalized
            if (word == "dix" && ["sept", "huit", "neuf"].contains(next))
                || (Self.numberTens.contains(word) && Self.numberUnits.contains(next)) {
                issues.append(numberIssue(from: index, through: index + 1, in: tokens, fix: "\(word)-\(next)",
                                          note: "Compound numbers take a hyphen."))
            } else if Self.numberTens.contains(word), next == "et", tokens[index + 1].isAdjacentToNext, index + 2 < tokens.count,
                      Self.numberUnits.contains(tokens[index + 2].normalized) {
                let fix = "\(word)-\(tokens[index + 2].normalized)"
                issues.append(numberIssue(from: index, through: index + 2, in: tokens, fix: fix,
                                          note: "Et only comes before un or une; other compounds take a hyphen."))
            }
        }
        return issues
    }

    /// Builds a numbers error whose fix keeps the first word's capital.
    private func numberIssue(from first: Int, through last: Int, in tokens: [Token], fix: String, note: String) -> Issue {
        let replacement = matchingCase(of: tokens[first].text, fix)
        return issue(
            .number, .error, from: first, through: last, in: tokens,
            replacement: replacement,
            explanation: explanations.render(.wordChoice, ["note": note, "fix": replacement]),
            source: "Number rule"
        )
    }

    /// Flags the un of "vingt et un" that doesn't match a known noun: "vingt et un heures" →
    /// "vingt et une heures".
    private func oneAgreementIssues(in text: TaggedText) -> [Issue] {
        let tokens = text.tokens
        return tokens.indices.dropLast().compactMap { index in
            let one = tokens[index]
            let noun = tokens[index + 1]
            let word = noun.normalized
            guard index > 1, tokens[index - 1].normalized == "et", Self.numberTens.contains(tokens[index - 2].normalized),
                  ["un", "une"].contains(one.normalized), one.isAdjacentToNext, noun.text.first?.isUppercase == false,
                  lexicon.adjectiveLemmas(of: word).isEmpty || text.isNoun(index + 1, certainty: Self.tagCertainty),
                  let gender = lexicon.noun(word)?.gender else { return nil }
            let expected = gender == .feminine ? "une" : "un"
            guard expected != one.normalized else { return nil }
            return issue(
                .number, .error, from: index, through: index + 1, in: tokens,
                replacement: expected + one.gap + noun.text,
                explanation: explanations.render(.articleGender, ["noun": noun.text, "gender": gender.rawValue, "article": expected]),
                source: "Number rule"
            )
        }
    }

    /// Flags heure after a number of two or more, in words or figures: "deux heure" → "deux heures".
    private func heureIssues(in tokens: [Token]) -> [Issue] {
        tokens.indices.dropFirst().compactMap { index in
            let previous = tokens[index - 1]
            guard tokens[index].normalized == "heure" else { return nil }
            let isWord = previous.isAdjacentToNext
                && (Self.pluralNumbers.contains(previous.normalized) || isCompoundNumber(previous.normalized))
            var isFigure = false
            if let match = previous.gap.firstMatch(of: /(\d+)\s*$/), let value = Int(match.output.1) { isFigure = value >= 2 }
            guard isWord || isFigure else { return nil }
            return numberIssue(from: index, through: index, in: tokens, fix: "heures", note: "Heure takes an s from deux upward.")
        }
    }

    /// Flags English time formats: "at 18h" → "à 18h", "6 pm" → "18h", and, as a warning
    /// because timetables do use it, "6:00" → "6h". Figures sit in the gaps between words.
    private func timeFormatIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for (index, token) in tokens.enumerated() {
            let word = token.normalized
            let numberFollows = index + 1 < tokens.count && token.isAdjacentToNext
                && Self.pluralNumbers.contains(tokens[index + 1].normalized)
            if word == "at", token.gap.firstMatch(of: /^\s*\d/) != nil || numberFollows {
                issues.append(numberIssue(from: index, through: index, in: tokens, fix: "à",
                                          note: "At is English; before a time, French says à."))
            }
            if ["pm", "am"].contains(word), index > 0,
               let match = tokens[index - 1].gap.firstMatch(of: /(\d{1,2})\s*$/),
               let hour = Int(match.output.1), (1...12).contains(hour) {
                let clock = word == "pm" ? (hour == 12 ? 12 : hour + 12) : (hour == 12 ? 0 : hour)
                let gap = tokens[index - 1].gap
                let figures = gap.distance(from: match.range.lowerBound, to: gap.endIndex)
                let fix = "\(clock)h"
                let explanation = explanations.render(.wordChoice, ["note": "French writes times on the 24-hour clock.", "fix": fix])
                issues.append(Issue(
                    kind: .number, severity: .error, offset: token.offset - figures, length: figures + token.text.count,
                    original: String(gap[match.range]) + token.text, replacement: fix,
                    reason: explanation.reason, hint: explanation.hint, source: "Time format rule"
                ))
            }
            // Only right after a time word: "Ct 4:12" is a citation and "2:00.531" a lap time.
            let timeWords: Set<String> = ["à", "vers", "dès", "avant", "après", "de"]
            for match in token.gap.matches(of: /(\d{1,2}):(\d{2})/) where timeWords.contains(word) {
                let gap = token.gap
                let before = match.range.lowerBound > gap.startIndex ? gap[gap.index(before: match.range.lowerBound)] : " "
                let after = match.range.upperBound < gap.endIndex ? gap[match.range.upperBound] : " "
                guard !before.isNumber, before != ":", !after.isNumber, after != ":",
                      gap[match.range.upperBound...].firstMatch(of: /^[.,]\d/) == nil,
                      let hour = Int(match.output.1), hour < 24, let minutes = Int(match.output.2), minutes < 60 else { continue }
                let fix = minutes == 0 ? "\(hour)h" : "\(hour)h\(match.output.2)"
                let explanation = explanations.render(.wordChoice, ["note": "In everyday French, times are written with h.", "fix": fix])
                issues.append(Issue(
                    kind: .number, severity: .warning,
                    offset: token.end + gap.distance(from: gap.startIndex, to: match.range.lowerBound),
                    length: match.output.0.count, original: String(match.output.0), replacement: fix,
                    reason: explanation.reason, hint: explanation.hint, source: "Time format rule"
                ))
            }
        }
        return issues
    }

    // MARK: - Et or est

    /// What each word means, shown when the learner is asked which one they meant.
    private static let etOrEstMeanings = ["et": "and: joins two things", "est": "is: as in il est grand"]

    /// Flags et written for est, or est for et, using the Quiver model. When the other
    /// word is almost certain it's an error with a fix; when the model only leans
    /// toward it, the learner is asked which word they meant.
    private func etOrEstIssues(in text: TaggedText) -> [Issue] {
        guard let etOrEstModel else { return [] }
        let tokens = text.tokens
        var issues: [Issue] = []
        for (index, token) in tokens.enumerated() {
            let written = token.normalized
            guard written == "et" || written == "est" else { continue }
            // "vingt et un" and "vingt et deux": the numbers rule judges et between number words.
            if written == "et", index > 0, index + 1 < tokens.count, Self.numberTens.contains(tokens[index - 1].normalized),
               (["un", "une", "onze", "dix"].contains(tokens[index + 1].normalized)
                || Self.numberUnits.contains(tokens[index + 1].normalized)) { continue }
            let other = written == "et" ? "est" : "et"
            let place = text.places[index]
            let words = text.sentences[place.sentence]
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

    // MARK: - Capital letters

    /// Abbreviations whose full stop doesn't end the sentence, as in "M. Dupont".
    private static let abbreviations: Set<String> = [
        "m", "mm", "mme", "mmes", "mlle", "mlles", "dr", "pr", "st", "ste",
        "etc", "cf", "ex", "p", "env", "av", "apr", "bd", "vs"
    ]

    /// Whether token `index` opens a sentence: the first word of the text, or the first
    /// after a full stop, question mark or exclamation mark and a space, or after a line
    /// break that no comma, colon or other mark holds open.
    ///
    /// Anything unusual between the words counts as no sentence start, so a closing
    /// quotation mark ("« Viens ! » dit-il"), an ellipsis, a list dash, a decimal
    /// ("3.5 euros") or a web address ("coquille.fr") never asks for a capital.
    private func opensSentence(_ index: Int, in tokens: [Token]) -> Bool {
        // Before the first word, only the very start of the text is known to be a sentence start.
        guard index > 0 else { return tokens[index].offset == 0 }
        let previous = tokens[index - 1]
        let gap = previous.gap
        guard gap.last?.isWhitespace == true else { return false }
        let marks = gap.filter { !$0.isWhitespace }
        guard let last = marks.last else { return gap.contains(where: \.isNewline) }
        guard ".!?".contains(last), !marks.hasSuffix("..") else { return false }
        if marks == "." {
            // An initial, as in "J. Dupont", or an abbreviation, as in "M. Dupont".
            if previous.text.count == 1, previous.text.first?.isUppercase == true { return false }
            if Self.abbreviations.contains(previous.normalized) { return false }
        }
        return true
    }

    /// Whether token `index` sits inside a sentence, after a word with nothing but spaces,
    /// a comma or a number between them, so a capital there can't come from punctuation,
    /// a quotation or a new line.
    private func isInsideSentence(_ index: Int, in tokens: [Token]) -> Bool {
        guard index > 0 else { return false }
        let gap = tokens[index - 1].gap
        return gap.allSatisfy { ($0.isWhitespace && !$0.isNewline) || $0 == "," || $0.isNumber }
    }

    /// Flags a sentence that starts with a lowercase letter, as in "il fait beau" → "Il".
    ///
    /// A word with a capital inside it, such as iPhone, is a brand written its own way
    /// and is left alone, and so is a word standing alone, such as a list item or a
    /// first word still being typed.
    private func sentenceCapitalIssues(in tokens: [Token]) -> [Issue] {
        tokens.indices.compactMap { index in
            let token = tokens[index]
            guard let first = token.text.first, first.isLowercase,
                  !token.text.dropFirst().contains(where: \.isUppercase),
                  opensSentence(index, in: tokens),
                  index + 1 < tokens.count, !opensSentence(index + 1, in: tokens) else { return nil }
            let fix = first.uppercased() + token.text.dropFirst()
            return issue(
                .capitalization, .warning, from: index, through: index, in: tokens,
                replacement: fix,
                explanation: explanations.render(.sentenceCapital, ["word": token.text, "fix": fix]),
                source: "Capital letter rule"
            )
        }
    }

    /// Days of the week, which French writes in lowercase.
    private static let days: Set<String> = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    /// Months, which French writes in lowercase.
    private static let months: Set<String> = [
        "janvier", "février", "mars", "avril", "mai", "juin",
        "juillet", "août", "septembre", "octobre", "novembre", "décembre"
    ]

    /// Words before a month that show it's the month and not a name, as in "en mars"
    /// rather than "sur Mars" or "de Mars".
    private static let monthCues: Set<String> = ["en", "début", "fin", "mi", "mois", "depuis", "dès", "er", "jusqu'en"]

    /// Words after a day that make it a holiday's name, as in "Mardi gras" and "Vendredi saint".
    private static let holidayWords: Set<String> = ["gras", "saint", "saints"]

    /// Languages, which French writes in lowercase: "je parle anglais".
    private static let languages: Set<String> = [
        "français", "anglais", "espagnol", "allemand", "italien", "portugais", "chinois",
        "japonais", "coréen", "arabe", "russe", "néerlandais", "grec", "polonais", "suédois",
        "turc", "vietnamien", "hébreu", "latin", "hindi"
    ]

    /// Verbs whose object can be a language, as in "j'apprends le français".
    private static let languageVerbs = ["parler", "apprendre", "étudier", "enseigner", "comprendre", "traduire"]

    /// Words that can stand between a language verb and the language, as in "je ne parle pas bien le français".
    private static let languageVerbFillers: Set<String> = ["le", "l'", "pas", "bien", "mal", "un", "peu", "couramment", "aussi", "très"]

    /// Nouns after which de names a language, as in "un cours de français".
    private static let languageNouns: Set<String> = [
        "cours", "classe", "classes", "professeur", "professeure", "prof", "profs", "leçon", "leçons",
        "examen", "examens", "dictionnaire", "livre", "livres", "devoir", "devoirs", "exercice", "exercices"
    ]

    /// Nationality adjectives in the masculine singular. French capitalizes the noun for
    /// the people ("les Français") but never the adjective ("un ami français").
    private static let nationalityLemmas = [
        "américain", "anglais", "français", "canadien", "québécois", "espagnol", "allemand",
        "italien", "portugais", "chinois", "japonais", "coréen", "mexicain", "brésilien",
        "argentin", "russe", "belge", "suisse", "irlandais", "écossais", "australien", "indien",
        "marocain", "algérien", "tunisien", "sénégalais", "africain", "européen", "asiatique",
        "grec", "turc", "néerlandais", "hollandais", "polonais", "suédois", "norvégien", "danois",
        "vietnamien", "libanais", "égyptien", "haïtien", "cubain", "colombien", "péruvien",
        "chilien", "parisien", "britannique", "arabe"
    ]

    /// Every form of the nationality adjectives, masculine and feminine, singular and plural.
    private static let nationalityForms: Set<String> = {
        var forms: Set<String> = []
        for lemma in nationalityLemmas {
            switch lemma {
            case "grec": forms.formUnion(["grec", "grecs", "grecque", "grecques"])
            case "turc": forms.formUnion(["turc", "turcs", "turque", "turques"])
            case _ where lemma.hasSuffix("s"): forms.formUnion([lemma, lemma + "e", lemma + "es"])
            case _ where lemma.hasSuffix("ien"): forms.formUnion([lemma, lemma + "s", lemma + "ne", lemma + "nes"])
            case _ where lemma.hasSuffix("e"): forms.formUnion([lemma, lemma + "s"])
            default: forms.formUnion([lemma, lemma + "s", lemma + "e", lemma + "es"])
            }
        }
        return forms
    }()

    /// Words before a nationality that can't be the noun it describes, so "les Français"
    /// and "un Américain" keep their capital as the people.
    private static let nonNounsBeforeNationality: Set<String> = [
        "le", "la", "les", "l'", "un", "une", "des", "du", "de", "d'", "ce", "cet", "cette", "ces",
        "mon", "ton", "son", "ma", "ta", "sa", "mes", "tes", "ses", "notre", "votre", "leur",
        "nos", "vos", "leurs", "deux", "trois", "quelques", "plusieurs", "beaucoup", "aux", "au"
    ]

    /// Flags a capital that French doesn't use inside a sentence, in the places English
    /// speakers add one: days and months ("le Lundi"), languages ("je parle Anglais"),
    /// nationality adjectives ("un ami Américain", "il est Canadien") and je ("et Je").
    ///
    /// Every other capital inside a sentence is taken for a name, as the other rules
    /// take it, so this rule speaks only when the words around it rule a name out.
    private func lowercaseIssues(in tokens: [Token]) -> [Issue] {
        var issues: [Issue] = []
        for index in tokens.indices where isInsideSentence(index, in: tokens) {
            let token = tokens[index]
            let letters = token.text.filter(\.isLetter)
            guard letters.first?.isUppercase == true,
                  !letters.dropFirst().contains(where: \.isUppercase) else { continue }
            let word = token.normalized
            let previous = tokens[index - 1]
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            let key: ExplanationKey
            if word == "je" || word == "j'" {
                key = .lowercaseJe
            } else if Self.days.contains(word) {
                if let next, Self.holidayWords.contains(next.normalized) { continue }
                // "le lundi de Pâques" is a holiday's name.
                if let next, next.normalized == "de", index + 2 < tokens.count,
                   tokens[index + 2].text.first?.isUppercase == true { continue }
                key = .lowercaseDayOrMonth
            } else if Self.months.contains(word) {
                // "le 14 Juillet" is the national holiday and "Mai 68" the events of that year.
                if word == "juillet", previous.gap.contains("14") { continue }
                if word == "mai", token.gap.hasPrefix(" 68") { continue }
                let afterNumber = previous.gap.contains(where: \.isNumber)
                let beforeYear = token.gap.prefix(2).last?.isNumber == true
                guard afterNumber || beforeYear || Self.monthCues.contains(previous.normalized) else { continue }
                key = .lowercaseDayOrMonth
            } else if Self.languages.contains(word), isLanguagePosition(index, in: tokens) {
                key = .lowercaseLanguage
            } else if Self.nationalityForms.contains(word), describesNoun(at: index, in: tokens) {
                key = .lowercaseNationality
            } else {
                continue
            }
            let fix = token.text.lowercased()
            issues.append(issue(
                .capitalization, .warning, from: index, through: index, in: tokens,
                replacement: fix,
                explanation: explanations.render(key, ["word": token.text, "fix": fix]),
                source: "Capital letter rule"
            ))
        }
        return issues
    }

    /// Whether token `index` names a language: after en ("en français"), after a language
    /// verb ("je parle anglais", "j'apprends le français"), or after de following a word
    /// such as cours ("un cours de français").
    private func isLanguagePosition(_ index: Int, in tokens: [Token]) -> Bool {
        let previous = tokens[index - 1].normalized
        if previous == "en" { return true }
        if previous == "de" || previous == "d'" {
            return index >= 2 && Self.languageNouns.contains(tokens[index - 2].normalized)
        }
        var position = index - 1
        // Step back over at most three words such as le, pas and bien to reach the verb.
        while position > index - 4, position > 0, Self.languageVerbFillers.contains(tokens[position].normalized) {
            position -= 1
        }
        let word = tokens[position].normalized
        return Self.languageVerbs.contains { isForm(word, of: $0) }
    }

    /// Whether the nationality at token `index` is an adjective: right after a form of
    /// être ("il est Canadien") or right after a lowercase noun ("un ami Américain").
    /// After an article it's the people ("les Français"), and after a capital it's part
    /// of a name ("l'Alliance Française"), so both stay as written.
    private func describesNoun(at index: Int, in tokens: [Token]) -> Bool {
        let previous = tokens[index - 1]
        guard previous.text.first?.isLowercase == true, !Self.nonNounsBeforeNationality.contains(previous.normalized) else { return false }
        if isForm(previous.normalized, of: "être") { return true }
        return lexicon.noun(previous.normalized) != nil && !lexicon.isVerb(previous.normalized)
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
