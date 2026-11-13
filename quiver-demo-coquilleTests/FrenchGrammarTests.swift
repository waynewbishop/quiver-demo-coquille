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

/// Exercises the French rules against the real bundled lexicon.
final class FrenchGrammarTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Returns the bundled grammar, failing the test if the pack didn't load.
    private func grammar() throws -> any Grammar {
        try XCTUnwrap(Self.pack, "The French language pack failed to load").grammar
    }

    /// Returns each issue as "original → replacement".
    private func fixes(_ text: String) throws -> [String] {
        try grammar().check(text).map { "\($0.original) → \($0.replacement ?? "")" }
    }

    // MARK: - The part-of-speech layer

    // The bundled deciders load, and each settles its own ambiguity in plain cases.
    func testTaggerSettlesTheCommonAmbiguities() throws {
        let pack = try XCTUnwrap(Self.pack)
        let french = try XCTUnwrap(pack.grammar as? FrenchGrammar)
        XCTAssertNotNil(french.adjectiveOrNounModel)
        XCTAssertNotNil(french.helperOrMainModel)

        let pronoun = french.tag(FrenchTokenizer.tokens(in: "Je le porte."))
        XCTAssertTrue(pronoun.mayBePronoun[1])
        let helper = french.tag(FrenchTokenizer.tokens(in: "Il a mangé une pomme."))
        XCTAssertTrue(helper.isHelperVerb(1, certainty: FrenchGrammar.tagCertainty))
        let main = french.tag(FrenchTokenizer.tokens(in: "Il a un chat."))
        XCTAssertEqual(try XCTUnwrap(main.helperProbability[1]), 0, accuracy: 0.05)
        let adjective = french.tag(FrenchTokenizer.tokens(in: "Des pommes rouges."))
        XCTAssertTrue(adjective.isAdjective(2, certainty: FrenchGrammar.tagCertainty))
        // Words with one reading get no verdict: Lexique already settles them.
        let plain = french.tag(FrenchTokenizer.tokens(in: "C'est difficile."))
        XCTAssertNil(plain.adjectiveProbability[2])
    }

    // With avoir surely a helper and an object after it, a participle that is also a noun
    // still agrees wrongly: "elle a prise une photo".
    func testParticipleThatIsAlsoANounWithAnObject() throws {
        XCTAssertEqual(try fixes("Elle a prise une photo."), ["prise → pris"])
        XCTAssertEqual(try fixes("Il a faite ses devoirs."), ["faite → fait"])
        XCTAssertEqual(try fixes("Elle a vue sur la mer."), [])
        XCTAssertEqual(try fixes("Elle a pris une photo."), [])
    }

    // MARK: - The mockup sentence

    // The design's example paragraph: every grammar error it shows, known nouns as errors.
    func testMockupSentence() throws {
        let text = "Nous avons acheté une fromage et des pommes rouge. Le boulangère était très gentille, et la pain sentait bon."
        let issues = try grammar().check(text)
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, [
            "une fromage → un fromage",
            "rouge → rouges",
            "Le boulangère → La boulangère",
            "la pain → le pain"
        ])
        XCTAssertTrue(issues.allSatisfy { $0.severity == .error })
        XCTAssertEqual(issues[0].reason, "fromage is masculine, so the article is un.")
        XCTAssertEqual(issues[1].reason, "The adjective must agree with pommes, which is plural.")
        // The hint names the rule but leaves the fix to the learner.
        XCTAssertEqual(issues[0].hint, "fromage is masculine.")
    }

    // The corrected paragraph raises nothing.
    func testCorrectFrenchPasses() throws {
        let text = "Nous avons acheté un fromage et des pommes rouges. La boulangère était très gentille, et le pain sentait bon."
        XCTAssertEqual(try fixes(text), [])
    }

    // MARK: - Article gender

    // Le and la before a verb are object pronouns, not articles.
    func testObjectPronounsAreNotArticles() throws {
        XCTAssertEqual(try fixes("Je le porte tous les jours."), [])
        XCTAssertEqual(try fixes("Il a décidé de le faire."), [])
        XCTAssertEqual(try fixes("Je viens pour la voir."), [])
    }

    // MARK: - Article or pronoun model

    // The bundled deciders rebuild the Notebook's features exactly: these are the
    // probabilities the training script printed for its trap sentences.
    func testDecidersMatchTheNotebook() throws {
        let pack = try XCTUnwrap(Self.pack)
        let french = try XCTUnwrap(pack.grammar as? FrenchGrammar)
        let article = try XCTUnwrap(pack.articleModel, "fr.article-pronoun-model.json should be bundled")
        let nounOrVerb = try XCTUnwrap(french.nounOrVerbModel, "fr.noun-verb-model.json should be bundled")
        let cases: [(model: ContextDecider, text: String, index: Int, probability: Double)] = [
            (article, "Je le porte.", 1, 0.866),
            (article, "Il la porte.", 1, 0.416),
            (article, "Je ne la vois pas.", 2, 0.962),
            (article, "Il ouvre le porte.", 2, 0.010),
            (article, "Je ferme la porte.", 2, 0.005),
            (nounOrVerb, "Je joue le foot.", 1, 1.000),
            (nounOrVerb, "Elle demande pour le bus.", 1, 0.975),
            (nounOrVerb, "La demande sur le site.", 1, 0.005)
        ]
        for item in cases {
            let tagged = french.tag(FrenchTokenizer.tokens(in: item.text))
            let probability = item.model.probability(of: tagged.window(at: item.index), lexicon: pack.lexicon)
            XCTAssertEqual(probability, item.probability, accuracy: 0.005, item.text)
        }
    }

    // A noun that is also a verb form never matches a verb pattern: "la demande" isn't demander.
    func testNounNeverMatchesAVerbPattern() throws {
        let pack = try XCTUnwrap(Self.pack)
        let french = try XCTUnwrap(pack.grammar as? FrenchGrammar)
        let tagged = french.tag(FrenchTokenizer.tokens(in: "La demande sur le site."))
        XCTAssertTrue(tagged.isNounNotVerb(1, certainty: FrenchGrammar.tagCertainty))
        XCTAssertEqual(try fixes("Je joue le foot."), ["joue le foot → joue au foot"])
    }

    // A pronoun the hand rule misses, before a word that is also a noun of the other
    // gender: alone, the hand rule calls "le porte" a gender error; the model keeps it silent.
    func testArticleModelSilencesPronounsTheHandRuleMisses() throws {
        let pack = try XCTUnwrap(Self.pack)
        let handRuleOnly = FrenchGrammar(lexicon: pack.lexicon, explanations: pack.explanations, genderPredictor: pack.genderModel)
        XCTAssertEqual(handRuleOnly.check("Qui le porte ?").map(\.original), ["le porte"])

        XCTAssertEqual(try fixes("Qui le porte ?"), [])
        XCTAssertEqual(try fixes("Ça le marque."), [])
    }

    // The hand rule needs its words together: a pronoun that ends one sentence doesn't make
    // the next sentence's article a pronoun, while "je le porte" still does.
    func testHandRuleStopsAtPunctuation() throws {
        let pack = try XCTUnwrap(Self.pack)
        let handRuleOnly = FrenchGrammar(lexicon: pack.lexicon, explanations: pack.explanations, genderPredictor: pack.genderModel)
        XCTAssertEqual(handRuleOnly.check("Je le porte.").map(\.original), [])
        XCTAssertEqual(handRuleOnly.check("Je. Le porte est ouverte.").map(\.original), ["Le porte"])
        XCTAssertTrue(try fixes("Je. Le porte est ouverte.").contains("Le porte → La porte"))
    }

    // When the model is sure the word is an article, a real gender error still fires.
    func testArticleModelKeepsRealGenderErrors() throws {
        XCTAssertEqual(try fixes("Il ouvre le porte."), ["le porte → la porte"])
        XCTAssertEqual(try fixes("Hier, il ouvre le porte."), ["le porte → la porte"])
        XCTAssertEqual(try fixes("Je ferme la porte."), [])
    }

    // A noun Lexique lists with both genders is never flagged.
    func testAmbiguousGenderIsSkipped() throws {
        XCTAssertEqual(try fixes("Le livre coûte une livre."), [])
    }

    // An adjective between article and noun takes the noun's gender, so the article isn't judged on it.
    func testAdjectiveBeforeNounIsSkipped() throws {
        XCTAssertEqual(try fixes("Une petite maison."), [])
    }

    // Before a vowel the article elides, which the elision rule fixes, not the gender rule.
    func testElisionContextIsSkipped() throws {
        XCTAssertEqual(try fixes("Je vois la arbre."), ["la arbre → l'arbre"])
    }

    // Nouns typed with œ have a gender, though Lexique spells them with oe.
    func testLigatureSpellingsHaveAGender() throws {
        XCTAssertEqual(try fixes("Le sœur et la cœur."), ["Le sœur → La sœur", "la cœur → le cœur"])
        XCTAssertEqual(try fixes("La soeur et le coeur."), [])
    }

    // MARK: - Contractions

    // à + le and de + les contract before a noun.
    func testContractions() throws {
        XCTAssertEqual(try fixes("Je vais à le marché."), ["à le → au"])
        XCTAssertEqual(try fixes("Il parle de les enfants."), ["de les → des"])
    }

    // Le and les before a verb are pronouns and never contract.
    func testNoContractionBeforeVerb() throws {
        XCTAssertEqual(try fixes("Il essaie de les voir."), [])
    }

    // MARK: - Agreement

    // Adjectives agree in gender as well as number.
    func testGenderAgreement() throws {
        let issues = try grammar().check("C'est une maison grand.")
        XCTAssertEqual(issues.map(\.replacement), ["grande"])
        XCTAssertEqual(issues.first?.reason, "The adjective must agree with maison, which is feminine.")
    }

    // Invariable colour adjectives such as marron never change form.
    func testInvariableAdjectivesPass() throws {
        XCTAssertEqual(try fixes("J'aime les chaussures marron."), [])
    }

    // MARK: - Negation

    // A clause-final "il dort plus" is a warning that restores ne.
    func testMissingNeIsAWarning() throws {
        let issues = try grammar().check("Lui, il dort plus.")
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, ["dort plus → ne dort plus"])
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(issues.first.map { $0.severity.blocksPlayback }, false)
    }

    // Before a vowel, ne elides, and j' becomes je.
    func testMissingNeElides() throws {
        XCTAssertEqual(try fixes("J'aime plus."), ["J'aime plus → Je n'aime plus"])
    }

    // Written negation, comparatives and "plus tard" pass.
    func testValidPlusPasses() throws {
        XCTAssertEqual(try fixes("Il ne dort plus."), [])
        XCTAssertEqual(try fixes("Il dort plus tard."), [])
        XCTAssertEqual(try fixes("Il dort plus que moi."), [])
    }

    // MARK: - The accent on à

    // Where a can't be the verb avoir, it's the preposition à.
    func testMissingAccentOnA() throws {
        XCTAssertEqual(try fixes("Je veux faire du vélo dans a la maison."), ["dans a → à"])
        XCTAssertEqual(try fixes("Je vais a Paris."), ["a → à"])
        XCTAssertEqual(try fixes("Nous restons jusqu'a demain."), ["a → à"])
        XCTAssertEqual(try grammar().check("Je vais a Paris.").first?.kind, .accent)
    }

    // With a subject before it, a is the verb avoir, which is correct French.
    func testAWithASubjectIsTheVerb() throws {
        XCTAssertEqual(try fixes("Il a la maison."), [])
        XCTAssertEqual(try fixes("Il y a un chat."), [])
        XCTAssertEqual(try fixes("Ce qu'il dit a du sens."), [])
        XCTAssertEqual(try fixes("Je vais à Paris."), [])
    }

    // After être and a participle, or between an adjective and an infinitive, a is the preposition.
    func testMissingAccentAfterParticipleOrAdjective() throws {
        XCTAssertEqual(try fixes("Il est allé a Paris."), ["a → à"])
        XCTAssertEqual(try fixes("C'est facile a faire."), ["a → à"])
        // Lexique also lists comprendre as a conjugated form of itself; it's still an infinitive.
        XCTAssertEqual(try fixes("C'est difficile a comprendre."), ["a → à"])
    }

    // A relative clause before être and a participle is avoir's subject, so a stays.
    func testRelativeClauseKeepsA() throws {
        XCTAssertEqual(try fixes("Ce qui est arrivé a changé ma vie."), [])
        XCTAssertEqual(try fixes("La police qui est intervenue a tiré."), [])
    }

    // Right after il or on, or in il y a, à is the verb avoir and loses its accent.
    func testExtraAccentOnA() throws {
        XCTAssertEqual(try fixes("Il à faim."), ["à → a"])
        XCTAssertEqual(try fixes("On à mangé."), ["à → a"])
        XCTAssertEqual(try fixes("Il y à un chat."), ["à → a"])
        XCTAssertEqual(try fixes("Elle à soif."), ["à → a"])
        XCTAssertEqual(try grammar().check("Il à faim.").first?.kind, .accent)
    }

    // Elle can follow a preposition, so à after elle stays unless avoir clearly fits.
    func testAAfterStressedElleStays() throws {
        XCTAssertEqual(try fixes("Un cadeau pour elle à Noël."), [])
        XCTAssertEqual(try fixes("Lui à pied, elle à vélo."), [])
        XCTAssertEqual(try fixes("À demain !"), [])
    }

    // MARK: - Être or avoir

    // The être that replaces avoir takes the subject's person, not the person of the avoir typed.
    func testAuxiliaryFixTakesTheSubjectsPerson() throws {
        XCTAssertTrue(try fixes("Ils a allé.").contains("Ils a allé → Ils sont allés"))
        XCTAssertTrue(try fixes("Tu a resté.").contains("Tu a resté → Tu es resté"))
    }

    // MARK: - Contracted articles and number

    // The learner's sentence: a after an infinitive is à, and la before a plural noun is les.
    func testInfinitiveThenAAndPluralNoun() throws {
        XCTAssertEqual(try fixes("Je voudrais aller a la montages."), ["a → à", "la montages → les montages"])
        XCTAssertEqual(try fixes("Je voudrais aller a la montagne."), ["a → à"])
    }

    // The contracted article names the noun's gender and the preposition it comes from.
    func testContractedGenderExplains() throws {
        let issue = try XCTUnwrap(try grammar().check("Je reste au maison.").first)
        XCTAssertEqual(issue.kind, .gender)
        XCTAssertEqual(issue.reason, "maison is feminine, so à and its article make à la.")
        XCTAssertEqual(issue.hint, "maison is feminine.")
    }

    // A number mismatch is an article issue, explained from the noun or the article.
    func testArticleNumberExplains() throws {
        let plural = try XCTUnwrap(try grammar().check("Je regarde la montagnes.").first)
        XCTAssertEqual(plural.kind, .article)
        XCTAssertEqual(plural.reason, "montagnes is plural, so the article is les.")
        let singular = try XCTUnwrap(try grammar().check("J'achète des pomme.").first)
        XCTAssertEqual(singular.reason, "des is plural, so the noun after it is too: des pommes.")
    }

    // MARK: - Regression corpora

    /// Correct French that must raise nothing. Add every false positive found here.
    static let correctFrench = [
        // Caver, "to dig," in the passé simple.
        "Pierre cava un trou.",
        "Il cava un trou.",
        // A relative clause is the subject of avoir.
        "Ce qu'il dit a du sens.",
        "Le livre qu'il lit a disparu.",
        "Tout ce qu'elle veut a un prix.",
        // A as avoir after a subject or a pronoun.
        "Il a la maison.",
        "Il y a un chat.",
        "Elle en a deux.",
        // Prendre une décision in every tense the rules know.
        "J'ai pris une décision.",
        "Il prend une décision.",
        "Nous prenons une décision.",
        "Il n'a jamais pris une décision.",
        // Nouns Lexique leaves blank that really take either gender.
        "Une enfant joue.",
        "Le livre coûte une livre.",
        // An adjective standing in for a noun agrees with its own article.
        "Tu veux la bleue ou la rouge?",
        "Je prends la gauche.",
        // Hand-checked genders, used correctly.
        "Une maison, une voiture et le plat.",
        // Adjectives Lexique splits or leaves incomplete, now whole.
        "Une maison nouvelle.",
        "Des filles jolies.",
        "Des chaises molles.",
        "Des questions globales.",
        // Natural French the idiom list once questioned.
        "C'est bon pour ta santé.",
        "C'est bon pour votre santé.",
        "C'est très délicieux.",
        // Correct sentences that share words with the word-choice and idiom entries.
        "Il va faire beau.",
        "Il pleut et il va neiger.",
        "J'ai mal à la tête.",
        "Je suis cherché par la police.",
        "Je fais du vélo et du sport.",
        "Je vais du côté de la gare.",
        "J'aime le vélo et la montagne.",
        "Un billet pour Chamonix.",
        "Et tu vas bien?",
        "Je joue au foot et de la guitare.",
        "Je téléphone à ma mère.",
        "Un portrait en pied.",
        "Tu me manques.",
        "Je fais une promenade.",
        "J'ai passé un bon moment.",
        "Je suis en vacances.",
        "Le matin, je bois un thé.",
        "En juillet, il fait beau.",
        "Lundi, je travaille.",
        "Je vais chez le dentiste.",
        // From the second outside review: correct French the new entries first flagged.
        "Ce que j'aime du roman, c'est son rythme.",
        "Ce que tu aimes de la ville, c'est son calme.",
        "Ce qu'il aime du film, c'est la musique.",
        "Une photo en pied.",
        "Un dessin en pied.",
        "Je suis cherché dans tout le pays.",
        "Je suis plein de vie.",
        "Elle est pleine d'énergie.",
        "Mon nom est inscrit sur la liste.",
        "Dans le soir de sa vie, il écrit.",
        // Être or avoir, and participle agreement.
        "Je suis allé à la gare.",
        "Elle est tombée.",
        "La pomme qu'il a mangée.",
        "Il l'a mangée.",
        "Les pommes que j'ai mangées.",
        "J'ai sorti la poubelle.",
        "Il a monté les valises.",
        "Elle a vue sur la mer.",
        "Elle a été malade.",
        "Il a eu froid.",
        "Je n'ai pas mangé.",
        // Participle agreement with être, where the subject settles it or doesn't.
        "Elles sont allées.",
        "Elle est fatiguée.",
        "Ils sont pris.",
        "Je suis allée.",
        "Nous sommes allées.",
        "Vous êtes allé.",
        "On est allés.",
        "Elle s'est lavé les mains.",
        "Elle n'est pas allée.",
        "C'est fini.",
        "Il est interdit de fumer.",
        // Liking verbs followed by words that take no article.
        "J'aime le fromage.",
        "J'aime bien.",
        "J'aime ça.",
        "J'aime nager.",
        "J'aime Paris.",
        "J'adore maman.",
        "Je préfère rester.",
        "J'aime beaucoup.",
        "Je n'aime pas.",
        "Je préfère demain.",
        "Le fromage que j'aime est bon.",
        "J'aime le hockey.",
        "J'aime dîner tard.",
        // Pronouns that aren't the subject of the verb after them.
        "Je le mange.",
        "Nous nous levons.",
        "Il nous parle.",
        "Il vous aime.",
        "Lui et elle sont partis.",
        "Toi et moi, nous sommes amis.",
        "Je pense à vous.",
        "Pour vous aider, je reste.",
        "Ils mangent et tu es fatigué.",
        "Vous êtes là, on a mangé.",
        // Si meaning "whether" or "yes", and si clauses already right.
        "Je ne sais pas si tu viendras.",
        "Je me demande s'il viendra.",
        "Si tu viens, je serai content.",
        "Si j'avais le temps, je viendrais.",
        "Si, je viendrai demain.",
        "Il s'est levé.",
        "Il fera beau si tu viens.",
        // Tous and sur after a noun start a new phrase rather than agreeing with it.
        "Je prends une douche tous les matins.",
        "Il y a des photos sur le mur.",
        // Plus and moins after an article start a superlative, not a noun.
        "C'était la plus belle journée de l'année.",
        "C'est le moins cher.",
        // An infinitive can be the subject of avoir, alone or in a relative clause.
        "Voyager a changé ma vie.",
        "Ce qu'il veut faire a changé.",
        "Le plaisir de voyager a disparu.",
        "On peut le modifier a posteriori.",
        // Contracted and partitive articles that match their noun.
        "Je vais à la montagne.",
        "Je vais au marché.",
        "Je mange du pain et de la confiture.",
        "Il essaie de la voir.",
        "Il revient de la gare.",
        // Nouns that serve both numbers, or look plural but aren't.
        "Une fois, j'ai vu le temps changer.",
        "Le cours commence à huit heures.",
        "Le bras me fait mal.",
        "Il a donné son avis.",
        "Il prend les prix et les bras.",
        "Fermé les samedi 18 et dimanche 19."
    ]

    /// Wrong French, each with the one fix the rules must offer.
    private static let wrongFrench: [(text: String, fix: String)] = [
        // An a after an infinitive that belongs to a conjugated verb.
        ("Je voudrais aller a Paris.", "a → à"),
        ("Il ne peut pas venir a la fête.", "a → à"),
        // Contracted and partitive articles of the wrong gender.
        ("Je reste au maison.", "au maison → à la maison"),
        ("Je parle à la garçon.", "à la garçon → au garçon"),
        ("Je mange de la pain.", "de la pain → du pain"),
        ("Je veux du confiture.", "du confiture → de la confiture"),
        ("Je rentre à le maison.", "à le maison → à la maison"),
        // Articles whose number doesn't match the noun.
        ("Je regarde la montagnes.", "la montagnes → les montagnes"),
        ("Il lit le livres.", "le livres → les livres"),
        ("Je vais à la plages.", "à la plages → aux plages"),
        ("Je parle de l'enfants.", "de l'enfants → des enfants"),
        ("J'achète des pomme.", "des pomme → des pommes"),
        ("Elle lit les journal.", "les journal → les journaux"),
        ("Il fait une décision.", "fait une décision → prend une décision"),
        ("J'ai fait une décision.", "fait une décision → pris une décision"),
        ("Elle avait fait une décision.", "fait une décision → pris une décision"),
        ("Je fais une décision.", "fais une décision → prends une décision"),
        ("Ils font une décision.", "font une décision → prennent une décision"),
        ("Comment cava?", "cava → ça va"),
        ("Je pense qu'il va a Paris.", "a → à"),
        ("Je sais qu'elle va a la plage.", "a → à"),
        // Hand-checked genders for nouns Lexique leaves blank.
        ("Il a un maison.", "un maison → une maison"),
        ("Le voiture est rouge.", "Le voiture → La voiture"),
        ("Il lève le main.", "le main → la main"),
        ("Une espace libre.", "Une espace → Un espace"),
        // Adjectives Lexique splits or leaves incomplete.
        ("Une maison nouveau.", "nouveau → nouvelle"),
        ("Des filles jolie.", "jolie → jolies"),
        ("Une chaise mou.", "mou → molle"),
        ("Des questions global.", "global → globales"),
        ("Des filles impoli.", "impoli → impolies"),
        // Word choice, from the Review List and common calques from English.
        ("Il va faire pleuvoir.", "Il va faire pleuvoir → Il va pleuvoir"),
        ("Il y a pleuvoir.", "Il y a pleuvoir → Il pleut"),
        ("J'ai mal aux têtes.", "mal aux têtes → mal à la tête"),
        ("J'ai fait le vélo.", "fait le vélo → fait du vélo"),
        ("Je vais du sport.", "vais du sport → fais du sport"),
        ("J'aime du vélo.", "aime du → aime le"),
        ("Tu aimes de la musique?", "aimes de la → aimes la"),
        ("Il est venu en pied.", "en pied → à pied"),
        // Être or avoir, from the Review List: "J'ai arrivé à l'hôtel".
        ("J'ai allé à la gare.", "J'ai allé → Je suis allé"),
        ("J'ai arrivé à l'hôtel.", "J'ai arrivé → Je suis arrivé"),
        ("Il a resté à la maison.", "Il a resté → Il est resté"),
        ("Elle a tombé.", "Elle a tombé → Elle est tombée"),
        ("Ils ont venu.", "Ils ont venu → Ils sont venus"),
        // A participle after avoir doesn't agree with the subject.
        ("Il a mangée.", "mangée → mangé"),
        ("Elle a finie.", "finie → fini"),
        ("Nous avons faites un gâteau.", "faites → fait"),
        // A participle after être agrees with its subject.
        ("Elles sont allé.", "allé → allées"),
        ("Elle est tombé.", "tombé → tombée"),
        ("Ils sont venu.", "venu → venus"),
        ("Elle est fatigué.", "fatigué → fatiguée"),
        ("Elle est mort.", "mort → morte"),
        ("Je suis allés.", "allés → allé"),
        ("Nous sommes allé.", "allé → allés"),
        // A noun for something in general takes the definite article.
        ("J'aime fromage.", "fromage → le fromage"),
        ("Il adore musique.", "musique → la musique"),
        ("Je préfère thé.", "thé → le thé"),
        ("J'aime pommes.", "pommes → les pommes"),
        ("Je déteste eau.", "eau → l'eau"),
        ("Je n'aime pas fromage.", "fromage → le fromage"),
        ("J'aime bien chocolat.", "chocolat → le chocolat"),
        // The verb takes its subject pronoun's person.
        ("Je va à la gare.", "va → vais"),
        ("Ils mange.", "mange → mangent"),
        ("Tu est fatigué.", "est → es"),
        ("Nous allez au cinéma.", "allez → allons"),
        ("Il ont mangé.", "ont → a"),
        ("Elle sont gentilles.", "sont → est"),
        // No future or conditional after si meaning "if".
        ("Si tu viendras, je serai content.", "viendras → viens"),
        ("Si j'aurais le temps, je viendrais.", "aurais → avais"),
        ("Demain, s'il pleuvra, je reste.", "pleuvra → pleut"),
        ("Si nous irons à la plage, il fera beau.", "irons → allons"),
        ("Si tu ne viendras pas, je reste.", "viendras → viens"),
        ("Je voudrais un du billet.", "un du → un"),
        ("Ça va, et tu?", "et tu → et toi"),
        ("Je vais à montagne.", "à montagne → à la montagne"),
        ("Je joue le foot.", "joue le foot → joue au foot"),
        ("Je joue la guitare.", "joue la guitare → joue de la guitare"),
        ("Je téléphone ma mère.", "téléphone ma → téléphone à ma"),
        ("Je vais en pied.", "en pied → à pied"),
        ("Je manque toi.", "Je manque toi → Tu me manques"),
        ("J'ai pris une marche.", "pris une marche → fait une promenade"),
        ("J'ai eu un bon temps.", "eu un bon temps → passé un bon moment"),
        ("Il fait pluie.", "Il fait pluie → Il pleut"),
        ("Je suis sur vacances.", "sur vacances → en vacances"),
        ("Je bois un thé dans le matin.", "dans le matin → le matin"),
        ("Il fait beau dans juillet.", "dans juillet → en juillet"),
        ("Je travaille sur lundi.", "sur lundi → lundi"),
        // Idioms, as suggestions.
        ("Je vais au dentiste.", "au dentiste → chez le dentiste"),
        ("J'ai regardé un match de basketball.", "basketball → basket"),
        ("Hier, c'était froid.", "c'était froid → il faisait froid")
    ]

    // Every sentence in the correct-French corpus passes.
    func testCorrectFrenchCorpus() throws {
        for text in Self.correctFrench {
            XCTAssertEqual(try fixes(text), [], text)
        }
    }

    // Every sentence in the wrong-French corpus gets its fix, and applying it leaves nothing to flag.
    func testWrongFrenchCorpus() throws {
        for (text, expected) in Self.wrongFrench {
            let issues = try grammar().check(text)
            XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, [expected], text)
            guard let issue = issues.first, let replacement = issue.replacement else { continue }
            let start = text.index(text.startIndex, offsetBy: issue.offset)
            let end = text.index(start, offsetBy: issue.length)
            let fixed = text.replacingCharacters(in: start..<end, with: replacement)
            XCTAssertEqual(try fixes(fixed), [], fixed)
        }
    }

    // MARK: - Participles after a noun subject

    // A determiner and noun before être settle the participle, as a pronoun does.
    func testParticipleAgreesWithNounSubject() throws {
        XCTAssertEqual(try fixes("La fille est arrivé."), ["arrivé → arrivée"])
        XCTAssertEqual(try fixes("Les enfants sont parti."), ["parti → partis"])
        XCTAssertEqual(try fixes("Le train est arrivée."), ["arrivée → arrivé"])
        XCTAssertEqual(try fixes("L'actrice est né à Lyon."), ["né → née"])
        let issue = try XCTUnwrap(grammar().check("Ma sœur est venu.").first)
        XCTAssertEqual(issue.hint, "With être, the past participle agrees with ma sœur.")
    }

    // A noun inside a phrase isn't the subject, and a first name's gender is unknown.
    func testParticipleIgnoresNounsThatArentTheSubject() throws {
        XCTAssertEqual(try fixes("Le chat de ma sœur est arrivé."), [])
        XCTAssertEqual(try fixes("Les photos de la fête sont arrivées."), [])
        XCTAssertEqual(try fixes("Mes amies sont venues."), [])
        XCTAssertEqual(try fixes("Marie est arrivé."), [])
    }

    // MARK: - Meaning

    // Correct French that English speakers often mean differently asks rather than corrects.
    func testMeaningAsksWhichWordingWasMeant() throws {
        let issue = try XCTUnwrap(grammar().check("Je ne mange pas encore de viande.").first)
        XCTAssertEqual(issue.kind, .meaning)
        XCTAssertEqual(issue.severity, .suggestion)
        XCTAssertEqual(issue.original, "pas encore")
        XCTAssertNil(issue.replacement)
        XCTAssertEqual(issue.choices.map(\.text), ["pas encore", "plus"])
        XCTAssertTrue(issue.isOriginal(issue.choices[0]))
        XCTAssertFalse(issue.isOriginal(issue.choices[1]))
    }

    // Before a past participle only "not yet" makes sense, so nothing is asked.
    func testMeaningStaysSilentBeforeAParticiple() throws {
        XCTAssertEqual(try fixes("Je n'ai pas encore fini mes devoirs."), [])
    }

    // The choices take the capital of the words they would replace.
    func testMeaningChoicesMatchCase() throws {
        let issue = try XCTUnwrap(grammar().check("Pas encore, merci.").first)
        XCTAssertEqual(issue.choices.map(\.text), ["Pas encore", "Plus"])
    }

    // MARK: - Et or est

    /// Returns the bundled et-or-est model, failing the test if it didn't load.
    private func etOrEstModel() throws -> EtOrEstModel {
        let grammar = try XCTUnwrap(Self.pack?.grammar as? FrenchGrammar)
        return try XCTUnwrap(grammar.etOrEstModel, "fr.et-est-model.json failed to load")
    }

    // The app builds the same features as the Notebook script, so it reproduces the
    // probabilities the script printed for its learner sentences.
    func testEtOrEstModelMatchesTheNotebook() throws {
        let model = try etOrEstModel()
        let lexicon = try XCTUnwrap(Self.pack).lexicon
        let cases: [(context: EtOrEstModel.Context, est: Double)] = [
            (.init(earlier: ["il"], clauseStartsTwoBefore: true, beforePrevious: nil, previous: "il", next: "grand", afterNext: "."), 0.9928),
            (.init(earlier: ["la", "maison"], clauseStartsTwoBefore: true, beforePrevious: "la", previous: "maison", next: "belle", afterNext: "."), 0.8984),
            (.init(earlier: ["paul"], clauseStartsTwoBefore: true, beforePrevious: nil, previous: "paul", next: "marie", afterNext: "sont"), 0.0356),
            (.init(earlier: ["j'", "aime", "le", "pain"], clauseStartsTwoBefore: false, beforePrevious: "le", previous: "pain", next: "le", afterNext: "fromage"), 0.0200),
            (.init(earlier: ["il"], clauseStartsTwoBefore: true, beforePrevious: nil, previous: "il", next: "fatigué", afterNext: "et"), 0.9995)
        ]
        for (context, expected) in cases {
            XCTAssertEqual(model.estProbability(context, lexicon: lexicon), expected, accuracy: 0.005, "\(context)")
        }
    }

    // A sure verdict is an error with a fix, in either direction.
    func testEtOrEstErrors() throws {
        XCTAssertEqual(try fixes("Il et grand."), ["et → est"])
        XCTAssertEqual(try fixes("Elle et partie hier."), ["et → est"])
        XCTAssertEqual(try fixes("Paul est Marie sont amis."), ["est → et"])
        let issue = try XCTUnwrap(grammar().check("Il et grand.").first)
        XCTAssertEqual(issue.kind, .etOrEst)
        XCTAssertEqual(issue.severity, .error)
    }

    // When the model only leans toward the other word, the learner is asked.
    func testEtOrEstAsksWhenUnsure() throws {
        let issue = try XCTUnwrap(grammar().check("La maison et belle.").first)
        XCTAssertEqual(issue.kind, .meaning)
        XCTAssertEqual(issue.severity, .suggestion)
        XCTAssertEqual(issue.choices.map(\.text), ["et", "est"])
    }

    // With a noun before and a determiner after, either word can be right, so a sure
    // model still only asks: "un chat et un chien", "le chat est un animal".
    func testEtOrEstOnlyAsksBetweenNounPhrases() throws {
        let issue = try XCTUnwrap(grammar().check("Un chat et un chien.").first)
        XCTAssertEqual(issue.kind, .meaning)
        XCTAssertEqual(issue.choices.map(\.text), ["et", "est"])
        XCTAssertEqual(try fixes("Le chat est un animal."), [])
    }

    // In a question that hasn't had its verb yet, a written est is always left alone.
    func testEtOrEstLeavesOpenQuestionsAlone() throws {
        XCTAssertEqual(try fixes("À quelle heure est le départ ?"), [])
        XCTAssertEqual(try fixes("Quel est ton avis ?"), [])
    }

    // The right word stays silent, including where the model is unsure.
    func testEtOrEstSilentOnCorrectFrench() throws {
        XCTAssertEqual(try fixes("Il est grand."), [])
        XCTAssertEqual(try fixes("Il est fatigué et triste."), [])
        XCTAssertEqual(try fixes("Le chat et le chien dorment."), [])
        XCTAssertEqual(try fixes("Toi et moi."), [])
    }

    // MARK: - Look-alikes

    // Words that are each French but wrong together are errors, fixed to ça va.
    func testCaVaLookAlikes() throws {
        XCTAssertEqual(try fixes("Bonjour, comment cava?"), ["cava → ça va"])
        XCTAssertEqual(try fixes("Sa va bien."), ["Sa va → Ça va"])
        XCTAssertEqual(try fixes("Ça vas bien?"), ["Ça vas → Ça va"])
        XCTAssertEqual(try fixes("Comment sava?"), ["sava → ça va"])
        let issue = try XCTUnwrap(grammar().check("Comment cava?").first)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.hint, "cava is a past form of caver, “to dig,” as in il cava un trou.")
    }

    // After ils or elles, son can only be the verb sont; son the possessive stays correct elsewhere.
    func testSonAfterAPluralSubject() throws {
        XCTAssertEqual(try fixes("Ils son contents."), ["Ils son → Ils sont"])
        XCTAssertEqual(try fixes("Elles son parties."), ["Elles son → Elles sont"])
        XCTAssertEqual(try fixes("Ils voient son chien."), [])
    }

    // Before a noun or an adjective and a noun, son is the possessive; after le, it's the noun.
    func testSonAsPossessiveOrNoun() throws {
        XCTAssertEqual(try fixes("Ils aiment son chien."), [])
        XCTAssertEqual(try fixes("Il aime son petit chien."), [])
        XCTAssertEqual(try fixes("Elle appelle son amie."), [])
        XCTAssertEqual(try fixes("J'aime le son de sa voix."), [])
    }

    // After a noun, nous or vous before a third-person verb is the object, not the subject.
    func testNousAndVousAsObjectsAfterANoun() throws {
        XCTAssertEqual(try fixes("Le facteur nous a donné une lettre."), [])
        XCTAssertEqual(try fixes("Mes amis nous ont parlé."), [])
        XCTAssertEqual(try fixes("Cette dame vous regarde."), [])
        XCTAssertEqual(try fixes("Nous va au marché."), ["va → allons"])
        XCTAssertEqual(try fixes("Hier, nous va au marché."), ["va → allons"])
    }

    // After a subject pronoun, cava is the verb caver, which is correct French.
    func testCavaAfterSubjectIsTheVerb() throws {
        XCTAssertEqual(try fixes("Il cava un trou."), [])
        XCTAssertEqual(try fixes("Ça va bien, merci."), [])
    }

    // MARK: - Word choice

    // English patterns that are wrong in French are errors, with the French phrasing as the fix.
    func testWordChoiceErrors() throws {
        XCTAssertEqual(try fixes("Je suis faim."), ["Je suis faim → J'ai faim"])
        XCTAssertEqual(try fixes("J'ai demandé une question."), ["demandé une question → posé une question"])
        XCTAssertEqual(try fixes("Il habite à Canada."), ["à Canada → au Canada"])
        XCTAssertEqual(try fixes("Je suis tard."), ["Je suis tard → Je suis en retard"])
        let issue = try XCTUnwrap(grammar().check("J'ai demandé une question.").first)
        XCTAssertEqual(issue.kind, .wordChoice)
        XCTAssertEqual(issue.severity, .error)
    }

    // Être where French says avoir, for a feeling or an age, is its own kind, so the card
    // and the weak spots name the avoir expression.
    func testAvoirExpressionsHaveTheirOwnKind() throws {
        let hunger = try XCTUnwrap(grammar().check("Je suis faim.").first)
        XCTAssertEqual(hunger.kind, .avoirExpression)
        XCTAssertEqual(hunger.severity, .error)
        let age = try XCTUnwrap(grammar().check("Mon frère est 12 ans.").first)
        XCTAssertEqual(age.kind, .avoirExpression)
    }

    // MARK: - Subjunctive

    // The subjunctive rule runs before the conjugation rule, so "je va" after il faut que
    // gets the subjunctive, and the learner's je takes its elision before the vowel.
    func testSubjunctiveWinsOverConjugation() throws {
        XCTAssertEqual(try fixes("Il faut que je va au travail."), ["je va → j'aille"])
        let issue = try XCTUnwrap(grammar().check("Il faut que je va au travail.").first)
        XCTAssertEqual(issue.kind, .subjunctive)
        XCTAssertEqual(issue.severity, .error)
        XCTAssertEqual(issue.source, "Subjunctive rule")
    }

    // The hint names the trigger and the rule but never the answer.
    func testSubjunctiveHintNamesTheTriggerNotTheFix() throws {
        let issue = try XCTUnwrap(grammar().check("Je veux que tu viens avec moi.").first)
        XCTAssertEqual(issue.hint, "After vouloir que, French uses the subjunctive.")
        XCTAssertFalse(issue.hint.contains("viennes"))
        XCTAssertEqual(issue.replacement, "viennes")
    }

    // Ne and object pronouns can sit between the subject and the verb.
    func testSubjunctiveLooksPastPronouns() throws {
        XCTAssertEqual(try fixes("Il faut que tu me dis la vérité."), ["dis → dises"])
        XCTAssertEqual(try fixes("Bien qu'il y a du soleil, il fait froid."), ["a → ait"])
    }

    // Restrictive ne… que, bien que mid-clause, a subjunctive already in place, and a form
    // shared by two verbs with different subjunctives all stay silent.
    func testSubjunctiveStaysSilentWhenInDoubt() throws {
        XCTAssertEqual(try fixes("Je ne veux que du pain."), [])
        XCTAssertEqual(try fixes("Je sais bien que tu viens demain."), [])
        XCTAssertEqual(try fixes("Il faut que nous partions avant qu'il ne pleuve."), [])
        XCTAssertEqual(try fixes("Je voulais qu'il vînt."), [])
        XCTAssertEqual(try fixes("Il faut que je suis le cours."), [])
    }

    // MARK: - Si and quand clauses

    // Si elides only before il and ils, never before another vowel or a name.
    func testSiElidesOnlyBeforeIl() throws {
        XCTAssertEqual(try fixes("Je viens si il pleut."), ["si il → s'il"])
        XCTAssertEqual(try fixes("Je viens si elle vient."), [])
        XCTAssertEqual(try fixes("Je viens si on veut."), [])
        XCTAssertEqual(try fixes("Je viens si Isabelle vient."), [])
        XCTAssertEqual(try fixes("Oui, si !"), [])
    }

    // The hint names the si clause's tense and the other clause's, not the answer.
    func testSiResultHintNamesTheTenses() throws {
        let issue = try XCTUnwrap(grammar().check("Si j'avais plus d'argent, j'achèterai un chalet.").first)
        XCTAssertEqual(issue.kind, .siClause)
        XCTAssertEqual(issue.hint, "With si + imperfect, the other half of the sentence uses the conditional.")
        XCTAssertEqual(issue.replacement, "achèterais")
    }

    // A polite conditional, même si, comme si and si after savoir stay silent.
    func testSiResultStaysSilentWhenInDoubt() throws {
        XCTAssertEqual(try fixes("Si tu veux, on pourrait aller au cinéma."), [])
        XCTAssertEqual(try fixes("Il parlera comme s'il savait tout."), [])
        XCTAssertEqual(try fixes("Je viendrai même s'il pleuvait."), [])
        XCTAssertEqual(try fixes("Je saurai demain s'il avait raison."), [])
    }

    // Lorsque and dès que work like quand, and quand after dire asks a question.
    func testFutureAfterQuandTriggers() throws {
        XCTAssertEqual(try fixes("Dès que tu arrives, nous mangerons."), ["arrives → arriveras"])
        XCTAssertEqual(try fixes("Lorsqu'il vient, nous partirons."), ["vient → viendra"])
        XCTAssertEqual(try fixes("Je te dirai quand il arrive."), [])
        let issue = try XCTUnwrap(grammar().check("Je t'appellerai quand j'arrive.").first)
        XCTAssertEqual(issue.kind, .futureAfterQuand)
        XCTAssertEqual(issue.hint, "When the action is still to come, French uses the future after quand.")
    }

    // MARK: - Object pronouns

    // Lui before a vowel has one fix, since le and la both elide; before a consonant the
    // learner chooses between le and la.
    func testDirectObjectPronounFixes() throws {
        XCTAssertEqual(try fixes("Je lui aide."), ["lui aide → l'aide"])
        XCTAssertEqual(try fixes("Je leur invite."), ["leur invite → les invite"])
        let question = try XCTUnwrap(grammar().check("Je lui regarde.").first)
        XCTAssertEqual(question.kind, .objectPronoun)
        XCTAssertEqual(question.severity, .error)
        XCTAssertNil(question.replacement)
        XCTAssertEqual(question.choices.map(\.text), ["le regarde", "la regarde"])
        XCTAssertEqual(question.hint, "Regarder takes a direct object: le, la or les.")
    }

    // Lui with a direct-only verb and a thing after it is correct French: the thing is the
    // object, and lui says who it is for.
    func testObjectPronounSilentBeforeAThing() throws {
        XCTAssertEqual(try fixes("Je lui cherche un cadeau."), [])
        XCTAssertEqual(try fixes("Je lui appelle un taxi."), [])
        XCTAssertEqual(try fixes("Il lui plaît beaucoup."), [])
        XCTAssertEqual(try fixes("Il nous le dit."), [])
    }

    // MARK: - Relative pronouns

    // Qui before il becomes qu'il, and the hint names the subject, not the answer.
    func testRelativeQuiElidesBeforeAVowel() throws {
        XCTAssertEqual(try fixes("Voici la photo qui il a prise."), ["qui il → qu'il"])
        let issue = try XCTUnwrap(grammar().check("La photo qui tu as prise est belle.").first)
        XCTAssertEqual(issue.kind, .relativePronoun)
        XCTAssertEqual(issue.replacement, "que")
        XCTAssertEqual(issue.hint, "Here tu is the subject, so the relative pronoun can't be qui.")
    }

    // Que stays when it is a conjunction, when de follows the verb, or when nous is an object.
    func testRelativePronounStaysSilentWhenInDoubt() throws {
        XCTAssertEqual(try fixes("Le fait que j'ai peur me gêne."), [])
        XCTAssertEqual(try fixes("C'est le livre que j'ai envie de lire."), [])
        XCTAssertEqual(try fixes("L'homme qui nous regarde est grand."), [])
        XCTAssertEqual(try fixes("Je me demande qui tu es."), [])
        XCTAssertEqual(try fixes("C'est la chose qu'il a besoin."), ["qu'il → dont il"])
        XCTAssertEqual(try fixes("De ce que je me souviens, il pleuvait."), [])
    }

    // The French phrasing raises nothing.
    func testCorrectWordChoicePasses() throws {
        XCTAssertEqual(try fixes("J'ai faim et je suis en retard."), [])
        XCTAssertEqual(try fixes("J'ai posé une question au Canada."), [])
        XCTAssertEqual(try fixes("J'ai pris une décision en France."), [])
    }

    // One entry per verb covers every person and tense, and the fix keeps the learner's form.
    func testVerbPatternsMatchEveryForm() throws {
        XCTAssertEqual(try fixes("Nous jouons le foot."), ["jouons le foot → jouons au foot"])
        XCTAssertEqual(try fixes("Il fait une décision."), ["fait une décision → prend une décision"])
        XCTAssertEqual(try fixes("Il a fait une décision."), ["fait une décision → pris une décision"])
        XCTAssertEqual(try fixes("Vous faites une décision."), ["faites une décision → prenez une décision"])
        XCTAssertEqual(try fixes("Nous sommes faim."), ["sommes faim → avons faim"])
        XCTAssertEqual(try fixes("J'ai un bon temps."), ["J'ai un bon temps → Je passe un bon moment"])
        XCTAssertEqual(try fixes("Il est né dans mai."), ["dans mai → en mai"])
        // Only the present of aimer: "j'aimerais du café" is a polite request.
        XCTAssertEqual(try fixes("J'aimerais du café."), [])
        XCTAssertEqual(try fixes("J'adore du chocolat."), ["adore du → adore le"])
    }

    // MARK: - Prepositions

    // A country's article settles its preposition, going there or coming from it.
    func testCountryPrepositions() throws {
        XCTAssertEqual(try fixes("Il habite à Canada."), ["à Canada → au Canada"])
        XCTAssertEqual(try fixes("Je vais à France."), ["à France → en France"])
        XCTAssertEqual(try fixes("Elle habite en Mexique."), ["en Mexique → au Mexique"])
        XCTAssertEqual(try fixes("Je vais à États-Unis."), ["à États-Unis → aux États-Unis"])
        XCTAssertEqual(try fixes("Il vient de Japon."), ["de Japon → du Japon"])
        XCTAssertEqual(try fixes("Je vais à Iran."), ["à Iran → en Iran"])
        let issue = try XCTUnwrap(grammar().check("Il habite à Canada.").first)
        XCTAssertEqual(issue.kind, .preposition)
        XCTAssertEqual(issue.reason, "Canada is a masculine country, so French says au Canada.")
    }

    // The right preposition, an article of its own, or a country without one raises nothing.
    func testCorrectCountryPrepositionsPass() throws {
        XCTAssertEqual(try fixes("J'habite en France, au Canada et aux États-Unis."), [])
        XCTAssertEqual(try fixes("Il vient du Japon et d'Iran."), [])
        XCTAssertEqual(try fixes("Elle parle à la France entière."), [])
        XCTAssertEqual(try fixes("Je vais à Cuba."), [])
    }

    // Verbs that take a fixed preposition, from the treebank counts and the hand list.
    func testVerbPrepositions() throws {
        XCTAssertEqual(try fixes("Ça dépend sur le temps."), ["dépend sur le → dépend du"])
        XCTAssertEqual(try fixes("Je participe dans un cours."), ["participe dans → participe à"])
        XCTAssertEqual(try fixes("J'essaie à comprendre."), ["essaie à → essaie de"])
        XCTAssertEqual(try fixes("Il a réussi de finir."), ["réussi de → réussi à"])
        XCTAssertEqual(try fixes("Elle ressemble sa mère."), ["ressemble sa → ressemble à sa"])
        XCTAssertEqual(try fixes("J'écoute à la radio."), ["écoute à → écoute"])
        XCTAssertEqual(try fixes("J'attends pour le bus."), ["attends pour → attends"])
        XCTAssertEqual(try grammar().check("Ça dépend sur le temps.").first?.kind, .preposition)
    }

    // The same words are correct French in other places.
    func testCorrectVerbPrepositionsPass() throws {
        XCTAssertEqual(try fixes("Ça dépend du temps."), [])
        XCTAssertEqual(try fixes("J'essaie à Paris et j'essaie de comprendre."), [])
        XCTAssertEqual(try fixes("J'attends pour voir."), [])
        XCTAssertEqual(try fixes("Je cherche pour toi."), [])
        XCTAssertEqual(try fixes("Je téléphone à ma mère."), [])
    }

    // Correct sentences from the UD treebanks that an earlier version of the preposition
    // rule flagged: cities that share a country's name, titles, and attendu as an adjective.
    func testTreebankPrepositionTrapsPass() throws {
        for text in [
            "Elle est née à Luxembourg le 22 mai.",
            "Le groupe est présent à Panama.",
            "La route la relie à Grenade.",
            "Il joue en équipe de Samoa depuis 1993.",
            "Il donne à Frédéric II de Danemark le droit.",
            "Il est né dans la République de Vanuatu.",
            "Il faudra encore attendre pour en savoir plus.",
            "Ce film est attendu pour 2012."
        ] {
            XCTAssertEqual(try fixes(text), [], text)
        }
        // Coming from somewhere, a masculine country still takes du.
        XCTAssertEqual(try fixes("Il revient de Japon."), ["de Japon → du Japon"])
    }

    // A country's own article settles its gender, though Lexique lists canada as feminine.
    func testCountryGenderComesFromTheCountryList() throws {
        XCTAssertFalse(try fixes("Je vais en le Canada.").contains("le Canada → la Canada"))
        XCTAssertEqual(try fixes("J'aime la Canada."), ["la Canada → le Canada"])
    }

    // MARK: - Articles after a negative

    // After ne and pas, jamais or plus, un, une, du, de la, de l' and des become de.
    func testArticleAfterNegativeBecomesDe() throws {
        XCTAssertEqual(try fixes("Je ne mange pas du pain."), ["du pain → de pain"])
        XCTAssertEqual(try fixes("Je n'ai pas une voiture."), ["une voiture → de voiture"])
        XCTAssertEqual(try fixes("Je ne mange jamais des bretzels."), ["des bretzels → de bretzels"])
        XCTAssertEqual(try fixes("Il n'y a plus de la salade."), ["de la salade → de salade"])
        XCTAssertEqual(try fixes("Je ne bois pas de l'eau."), ["de l'eau → d'eau"])
        XCTAssertEqual(try fixes("Il ne porte jamais des lunettes."), ["des lunettes → de lunettes"])
        let issue = try XCTUnwrap(grammar().check("Je ne mange pas du pain.").first)
        XCTAssertEqual(issue.kind, .article)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertEqual(issue.reason, "After pas, du becomes de, or d' before a vowel: de pain. Être is the exception: ce n'est pas du pain.")
    }

    // Correct French that keeps its article after a negative raises nothing from this rule.
    func testArticleAfterNegativeExceptionsPass() throws {
        /// The issues the negative-article rule raises in `text`.
        func negativeArticleIssues(_ text: String) throws -> [String] {
            try grammar().check(text).filter { $0.source.hasPrefix("Negative article rule") }.map(\.original)
        }
        for text in [
            "Ce n'est pas du pain, c'est du gâteau.",
            "Je ne parle pas des problèmes.",
            "Je ne joue pas du piano.",
            "Je ne parle pas de la guerre.",
            "Je ne mange plus que du pain.",
            "Il n'y a pas un bruit, c'est le silence.",
            "Utilisez un crayon, pas un stylo.",
            "Je ne mange pas du tout.",
            "Je n'ai pas un seul ami ici.",
            "Je ne mange pas du pain, mais du riz.",
            "Il ne le fait pas de la même façon.",
            "Je n'en veux pas une.",
            // The dû typo isn't an article: "de partir" would be wrong.
            "Je n'ai pas du partir."
        ] {
            XCTAssertEqual(try negativeArticleIssues(text), [], text)
        }
    }

    // MARK: - Elision

    // Je, le, la, de, ne and que lose their vowel before a vowel sound, and au and du become à l' and de l'.
    func testElision() throws {
        XCTAssertEqual(try fixes("Je aime le chocolat."), ["Je aime → J'aime"])
        XCTAssertEqual(try fixes("Le école est grande."), ["Le école → L'école"])
        XCTAssertEqual(try fixes("Il ne aime pas le café."), ["ne aime → n'aime"])
        XCTAssertEqual(try fixes("Je vais au école."), ["au école → à l'école"])
        XCTAssertEqual(try fixes("Je me habille."), ["me habille → m'habille"])
    }

    // An aspirated h, le onze, que oui, a name and the title Me keep the whole word.
    func testElisionSkips() throws {
        XCTAssertEqual(try fixes("Je le hais."), [])
        XCTAssertEqual(try fixes("Le héros arrive."), [])
        XCTAssertEqual(try fixes("Le onze novembre, il pleut."), [])
        XCTAssertEqual(try fixes("Il a dit que oui."), [])
        XCTAssertEqual(try fixes("C'est le livre de Ernest."), [])
        XCTAssertEqual(try fixes("Le dossier de Me Dupont est prêt."), [])
    }

    // MARK: - Possessives

    // A possessive takes the noun's gender, and ma, ta and sa become mon, ton and son before a vowel.
    func testPossessiveGender() throws {
        XCTAssertEqual(try fixes("Mon mère est gentille."), ["Mon mère → Ma mère"])
        XCTAssertEqual(try fixes("Ton sœur est là."), ["Ton sœur → Ta sœur"])
        XCTAssertEqual(try fixes("Ma ami est là."), ["Ma ami → Mon ami"])
        XCTAssertEqual(try fixes("Son voiture est rouge."), ["Son voiture → Sa voiture"])
        XCTAssertEqual(try fixes("Mon amie est là."), [])
        XCTAssertEqual(try fixes("Le son de la radio est fort."), [])
    }

    // MARK: - Reflexive verbs

    // A reflexive verb takes être in the past, and the pronoun elides only before a vowel.
    func testReflexiveAuxiliary() throws {
        XCTAssertEqual(try fixes("Il s'a trompé."), ["s'a → s'est"])
        XCTAssertEqual(try fixes("Nous nous avons couchés."), ["nous avons → nous sommes"])
        XCTAssertEqual(try fixes("Ils se ont rencontrés."), ["se ont → se sont"])
        XCTAssertEqual(try fixes("Je me ai levé."), ["me ai → me suis"])
    }

    // An object pronoun that isn't the subject's own leaves avoir and its agreement alone.
    func testObjectPronounIsNotReflexive() throws {
        XCTAssertEqual(try fixes("Vous nous avez vus."), [])
        XCTAssertEqual(try fixes("Il m'a aidé."), [])
    }

    // MARK: - Age

    // An age takes avoir, given in digits or words.
    func testAgeTakesAvoir() throws {
        XCTAssertEqual(try fixes("Je suis 20 ans."), ["Je suis → J'ai"])
        XCTAssertEqual(try fixes("Mon frère est douze ans."), ["est → a"])
        XCTAssertEqual(try fixes("Elle est vingt-cinq ans."), ["est → a"])
        XCTAssertEqual(try fixes("C'est vingt ans de travail."), [])
    }

    // MARK: - Quantities and negation

    // After beaucoup or trop, de stands alone, eliding before a vowel.
    func testQuantityTakesDeAlone() throws {
        XCTAssertEqual(try fixes("Il y a beaucoup des gens."), ["beaucoup des → beaucoup de"])
        XCTAssertEqual(try fixes("J'ai beaucoup des amis."), ["beaucoup des amis → beaucoup d'amis"])
        XCTAssertEqual(try fixes("J'ai trop de les devoirs."), ["trop de les → trop de"])
        XCTAssertEqual(try fixes("Il parle beaucoup des vacances."), [])
    }

    // Rien, jamais and personne already negate with ne, so pas is doubled.
    func testDoubleNegation() throws {
        XCTAssertEqual(try fixes("Je n'aime pas rien."), ["pas rien → rien"])
        XCTAssertEqual(try fixes("Il ne mange jamais pas."), ["jamais pas → jamais"])
        XCTAssertEqual(try fixes("Ce n'est pas rien."), [])
    }

    // MARK: - Idioms

    // Correct French with a different meaning gets a suggestion, never an error.
    func testMeaningIdioms() throws {
        let issues = try grammar().check("Je suis froid.")
        XCTAssertEqual(issues.map(\.replacement), ["J'ai froid"])
        XCTAssertEqual(issues.first?.severity, .suggestion)
        // The note names the meaning the suggestion is for, rather than calling the original wrong.
        XCTAssertTrue(issues.first?.reason.contains("If you mean you feel cold") == true)
        XCTAssertEqual(try fixes("Il fait froid."), [])
    }

    // A correct but unidiomatic phrase gets a suggestion, never an error.
    func testIdiomSuggestion() throws {
        let issues = try grammar().check("Ça fait du sens.")
        XCTAssertEqual(issues.map(\.replacement), ["a du sens"])
        XCTAssertEqual(issues.first?.severity, .suggestion)
    }

    // MARK: - Model predictions

    /// Always predicts one gender for any word, so the warning path can be tested without a trained model.
    private struct FixedPredictor: GenderPredictor {
        let prediction: GenderPrediction
        func gender(of noun: String) -> GenderPrediction? { prediction }
    }

    // The bundled model catches a noun Lexique doesn't know and names its ending.
    func testBundledModelWarnsOnUnknownNoun() throws {
        let pack = try XCTUnwrap(Self.pack)
        XCTAssertNotNil(pack.genderModel)
        let issues = try grammar().check("C'est un influenceuse.")
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, ["un influenceuse → une influenceuse"])
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(issues.first?.source, "Quiver prediction · ending -euse")
    }

    // Loanwords that break the ending rules stay silent rather than flag correct French.
    func testBundledModelSilentOnLoanwords() throws {
        XCTAssertEqual(try fixes("J'ai pris un selfie."), [])
        XCTAssertEqual(try fixes("C'est une appli."), [])
        XCTAssertEqual(try fixes("C'est un mot-dièse."), [])
    }

    // A confident guess with no ending to name raises nothing, since there's no rule to teach.
    func testPredictionWithoutEndingIsSilent() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.99, ending: nil))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("C'est un frobnication.").count, 0)
    }

    // A confident model guess on an unknown noun is a warning, never an error.
    func testPredictionOnUnknownNounIsAWarning() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.97, ending: "tion"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, explanations: pack.explanations, genderPredictor: predictor)

        let issues = grammar.check("C'est un frobnication.")
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, ["un frobnication → une frobnication"])
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(issues.first?.source, "Quiver prediction · ending -tion")
    }

    // Known nouns are answered by the lexicon, so the model is never consulted for them.
    func testPredictionNeverOverridesLexicon() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.99, ending: "ette"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("Un squelette.").count, 0)
    }

    // An unsure guess raises nothing.
    func testLowConfidencePredictionIsSilent() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.6, ending: "e"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("Un frobnication.").count, 0)
    }
}
