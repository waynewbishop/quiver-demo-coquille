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

extension FrenchGrammar {

    // MARK: - Article and noun number

    /// Singular articles with the plural each becomes: "la montages" → "les montages".
    static let pluralOfArticle: [String: String] = [
        "le": "les", "la": "les", "l'": "les", "un": "des", "une": "des", "au": "aux", "du": "des"
    ]

    /// Plural articles, which need a plural noun after them.
    static let pluralArticles: Set<String> = ["les", "des", "aux"]

    /// Words a learner writes after des when they mean dès, "from": "des demain".
    static let afterDes: Set<String> = ["demain", "maintenant", "lors", "aujourd'hui"]

    /// Returns a singular noun's plural form, if Lexique lists one whose gender fits:
    /// pommes for pomme, journaux for journal, chapeaux for chapeau, enfants for enfant.
    func plural(of singular: String, gender: Gender?) -> String? {
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
    func articleNumberIssues(in text: TaggedText) -> [Issue] {
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
}
