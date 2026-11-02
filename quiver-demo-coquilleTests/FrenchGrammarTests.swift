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

    // The bundled model rebuilds the Notebook's features exactly: these are the
    // probabilities the training script printed for its trap sentences.
    func testArticleModelMatchesTheNotebook() throws {
        let pack = try XCTUnwrap(Self.pack)
        let model = try XCTUnwrap(pack.articleModel, "fr.article-model.json should be bundled")
        let cases: [(word: String, previous: String?, next: String?, afterNext: String?, pronoun: Double)] = [
            ("le", "je", "porte", ".", 0.64),
            ("la", "il", "porte", "tous", 0.22),
            ("le", "qui", "porte", "?", 0.12),
            ("le", "ouvre", "porte", ".", 0.02),
            ("la", "a", "grippe", ".", 0.01),
            ("l'", "je", "ai", "vu", 1.00),
            ("la", "allons", "visiter", ".", 0.71)
        ]
        for item in cases {
            let pronoun = model.pronounProbability(
                of: item.word, previous: item.previous, next: item.next, afterNext: item.afterNext, lexicon: pack.lexicon
            )
            XCTAssertEqual(pronoun, item.pronoun, accuracy: 0.005, "\(item.previous ?? "") \(item.word) \(item.next ?? "")")
        }
    }

    // A pronoun the hand rule misses, before a word that is also a noun of the other
    // gender: alone, the hand rule calls "le porte" a gender error; the model keeps it silent.
    func testArticleModelSilencesPronounsTheHandRuleMisses() throws {
        let pack = try XCTUnwrap(Self.pack)
        let handRuleOnly = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], wordChoices: [], explanations: pack.explanations, genderPredictor: pack.genderModel)
        XCTAssertEqual(handRuleOnly.check("Qui le porte ?").map(\.original), ["le porte"])

        XCTAssertEqual(try fixes("Qui le porte ?"), [])
        XCTAssertEqual(try fixes("Ça le marque."), [])
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

    // Before a vowel the article elides, which is outside the gender rule.
    func testElisionContextIsSkipped() throws {
        XCTAssertEqual(try fixes("Je vois la arbre."), [])
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

    // MARK: - Être or avoir

    // The être that replaces avoir takes the subject's person, not the person of the avoir typed.
    func testAuxiliaryFixTakesTheSubjectsPerson() throws {
        XCTAssertTrue(try fixes("Ils a allé.").contains("Ils a allé → Ils sont allés"))
        XCTAssertTrue(try fixes("Tu a resté.").contains("Tu a resté → Tu es resté"))
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
        "C'est le moins cher."
    ]

    /// Wrong French, each with the one fix the rules must offer.
    private static let wrongFrench: [(text: String, fix: String)] = [
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
        ("J'aime du vélo.", "J'aime du → J'aime le"),
        ("Tu aimes de la musique?", "Tu aimes de la → Tu aimes la"),
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
        let issue = try XCTUnwrap(grammar().check("Je suis faim.").first)
        XCTAssertEqual(issue.kind, .wordChoice)
        XCTAssertEqual(issue.severity, .error)
    }

    // The French phrasing raises nothing.
    func testCorrectWordChoicePasses() throws {
        XCTAssertEqual(try fixes("J'ai faim et je suis en retard."), [])
        XCTAssertEqual(try fixes("J'ai posé une question au Canada."), [])
        XCTAssertEqual(try fixes("J'ai pris une décision en France."), [])
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
        let grammar = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], wordChoices: [], explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("C'est un frobnication.").count, 0)
    }

    // A confident model guess on an unknown noun is a warning, never an error.
    func testPredictionOnUnknownNounIsAWarning() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.97, ending: "tion"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], wordChoices: [], explanations: pack.explanations, genderPredictor: predictor)

        let issues = grammar.check("C'est un frobnication.")
        XCTAssertEqual(issues.map { "\($0.original) → \($0.replacement ?? "")" }, ["un frobnication → une frobnication"])
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertEqual(issues.first?.source, "Quiver prediction · ending -tion")
    }

    // Known nouns are answered by the lexicon, so the model is never consulted for them.
    func testPredictionNeverOverridesLexicon() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.99, ending: "ette"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], wordChoices: [], explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("Un squelette.").count, 0)
    }

    // An unsure guess raises nothing.
    func testLowConfidencePredictionIsSilent() throws {
        let pack = try XCTUnwrap(Self.pack)
        let predictor = FixedPredictor(prediction: GenderPrediction(gender: .feminine, probability: 0.6, ending: "e"))
        let grammar = FrenchGrammar(lexicon: pack.lexicon, idioms: [], lookAlikes: [], wordChoices: [], explanations: pack.explanations, genderPredictor: predictor)
        XCTAssertEqual(grammar.check("Un frobnication.").count, 0)
    }
}
