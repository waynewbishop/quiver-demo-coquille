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
import Quiver
@testable import quiver_demo_coquille

/// Scores each grammar rule as a classifier, with Quiver's classification report.
///
/// Every sentence in the corpus is labelled by hand with the one rule that should
/// flag it, or with no rule when it is correct French. Each rule then answers one
/// question per sentence, "is there an error here?", and the report compares its
/// answers with the labels. Precision says how often the rule is right when it
/// speaks; recall says how many of its own errors it finds.
///
/// The rules run one at a time, before the resolution matrix, so a rule that also
/// fires on another rule's sentence shows up as lower precision.
final class RuleScorecardTests: XCTestCase {

    private static let pack: LanguagePack? = try? LanguagePack.french()

    /// Sentences with one error each, labelled with the rule that should catch it.
    private static let labelledErrors: [(text: String, rule: String)] = [
        ("Il a un maison.", "grammar.gender"),
        ("Le voiture est rouge.", "grammar.gender"),
        ("Il lève le main.", "grammar.gender"),
        ("Une espace libre.", "grammar.gender"),
        ("Il y a vingt et deux élèves.", "grammar.number"),
        ("Il a dix sept ans.", "grammar.number"),
        ("Il est deux heure.", "grammar.number"),
        ("Le train part à 6 pm.", "grammar.number"),
        ("Ce maison est belle.", "grammar.gender"),
        ("Quel maison est belle?", "grammar.gender"),
        ("Il n'a aucun maison.", "grammar.gender"),
        ("Je cours en les montagnes.", "grammar.preposition"),
        ("Je vais France.", "grammar.preposition"),
        ("Je vais Paris.", "grammar.preposition"),
        ("Il neige en printemps.", "grammar.preposition"),
        ("Je lis sur le train.", "grammar.preposition"),
        ("Je décide à partir.", "grammar.preposition"),
        ("Il ouvre le porte.", "grammar.gender"),
        ("C'est un influenceuse.", "grammar.gender.predicted"),
        ("Je vais à le marché.", "grammar.contraction"),
        ("Il parle de les enfants.", "grammar.contraction"),
        ("Je pense qu'il va a Paris.", "grammar.accent"),
        ("Je sais qu'elle va a la plage.", "grammar.accent"),
        ("J'ai allé à la gare.", "grammar.auxiliary"),
        ("J'ai arrivé à l'hôtel.", "grammar.auxiliary"),
        ("Il a resté à la maison.", "grammar.auxiliary"),
        ("Elle a tombé.", "grammar.auxiliary"),
        ("Ils ont venu.", "grammar.auxiliary"),
        ("Il a mangée.", "grammar.auxiliary"),
        ("Elle a finie.", "grammar.auxiliary"),
        ("Nous avons faites un gâteau.", "grammar.auxiliary"),
        ("Je va à la gare.", "grammar.conjugation"),
        ("Ils mange.", "grammar.conjugation"),
        ("Tu est fatigué.", "grammar.conjugation"),
        ("Nous allez au cinéma.", "grammar.conjugation"),
        ("Il ont mangé.", "grammar.conjugation"),
        ("Elle sont gentilles.", "grammar.conjugation"),
        ("Si tu viendras, je serai content.", "grammar.siClause"),
        ("Si j'aurais le temps, je viendrais.", "grammar.siClause"),
        ("Demain, s'il pleuvra, je reste.", "grammar.siClause"),
        ("Si nous irons à la plage, il fera beau.", "grammar.siClause"),
        ("Si tu ne viendras pas, je reste.", "grammar.siClause"),
        ("Elles sont allé.", "grammar.participle"),
        ("Elle est tombé.", "grammar.participle"),
        ("Ils sont venu.", "grammar.participle"),
        ("Elle est fatigué.", "grammar.participle"),
        ("Elle est mort.", "grammar.participle"),
        ("Je suis allés.", "grammar.participle"),
        ("Nous sommes allé.", "grammar.participle"),
        ("J'aime fromage.", "grammar.article"),
        ("Il adore musique.", "grammar.article"),
        ("Je préfère thé.", "grammar.article"),
        ("J'aime pommes.", "grammar.article"),
        ("Je déteste eau.", "grammar.article"),
        ("Je n'aime pas fromage.", "grammar.article"),
        ("J'aime bien chocolat.", "grammar.article"),
        ("Une maison nouveau.", "grammar.agreement"),
        ("Des filles jolie.", "grammar.agreement"),
        ("Une chaise mou.", "grammar.agreement"),
        ("Des questions global.", "grammar.agreement"),
        ("Des filles impoli.", "grammar.agreement"),
        ("Comment cava?", "grammar.lookAlike"),
        ("Sa va bien.", "grammar.lookAlike"),
        ("Ça vas bien?", "grammar.lookAlike"),
        ("Comment sava?", "grammar.lookAlike"),
        ("Il fait une décision.", "grammar.wordChoice"),
        ("J'ai fait une décision.", "grammar.wordChoice"),
        ("Elle avait fait une décision.", "grammar.wordChoice"),
        ("Je fais une décision.", "grammar.wordChoice"),
        ("Ils font une décision.", "grammar.wordChoice"),
        ("Il va faire pleuvoir.", "grammar.wordChoice"),
        ("Il y a pleuvoir.", "grammar.wordChoice"),
        ("J'ai mal aux têtes.", "grammar.wordChoice"),
        ("J'ai fait le vélo.", "grammar.wordChoice"),
        ("Je vais du sport.", "grammar.wordChoice"),
        ("J'aime du vélo.", "grammar.wordChoice"),
        ("Tu aimes de la musique?", "grammar.wordChoice"),
        ("Il est venu en pied.", "grammar.preposition"),
        ("Je voudrais un du billet.", "grammar.wordChoice"),
        ("Ça va, et tu?", "grammar.wordChoice"),
        ("Je vais à montagne.", "grammar.wordChoice"),
        ("Je joue le foot.", "grammar.preposition"),
        ("Je joue la guitare.", "grammar.preposition"),
        ("Je téléphone ma mère.", "grammar.preposition"),
        ("Je manque toi.", "grammar.wordChoice"),
        ("J'ai pris une marche.", "grammar.wordChoice"),
        ("J'ai eu un bon temps.", "grammar.wordChoice"),
        ("Il fait pluie.", "grammar.wordChoice"),
        ("Je suis sur vacances.", "grammar.preposition"),
        ("Je bois un thé dans le matin.", "grammar.preposition"),
        ("Il fait beau dans juillet.", "grammar.preposition"),
        ("Je travaille sur lundi.", "grammar.preposition"),
        ("Je suis faim.", "grammar.wordChoice"),
        ("J'ai demandé une question.", "grammar.wordChoice"),
        ("Il habite à Canada.", "grammar.preposition"),
        ("J'aime plus.", "grammar.negation"),
        ("Je vais au dentiste.", "grammar.idiom"),
        ("J'ai regardé un match de basketball.", "grammar.idiom"),
        ("Hier, c'était froid.", "grammar.idiom"),
        ("Je suis froid.", "grammar.idiom")
    ]

    /// Correct French that looks like a rule's error, beyond the shared correct corpus.
    private static let traps = [
        "Qui le porte ?",
        "Ça le marque.",
        "Je la porte.",
        "Il essaie de les voir.",
        "Il a décidé de le faire.",
        "Il dort plus tard.",
        "Il ne dort plus.",
        "J'ai pris un selfie.",
        "C'est une appli.",
        "Il fait froid."
    ]

    /// Every tuning sentence with its label: the rule that should flag it, or nil.
    ///
    /// These come from the other tests, so the rules were written to pass them. Their
    /// scores show nothing has regressed, not how well the rules will do on new text.
    private static var tuningCorpus: [(text: String, rule: String?)] {
        labelledErrors.map { ($0.text, $0.rule) }
            + (FrenchGrammarTests.correctFrench + traps).map { ($0, nil) }
    }

    /// Sentences written after the rules, which no rule was adjusted to pass, so
    /// their scores are the honest estimate. Labelled by hand, like the tuning set.
    private static let unseenCorpus: [(text: String, rule: String?)] = [
        ("J'achète un table.", "grammar.gender"),
        ("Elle mange le pomme.", "grammar.gender"),
        ("C'est une problème.", "grammar.gender"),
        ("Il lit la journal.", "grammar.gender"),
        ("Il revient de le bureau.", "grammar.contraction"),
        ("Je parle à les voisins.", "grammar.contraction"),
        ("Il est a l'école.", "grammar.accent"),
        ("Nous avons parti tôt.", "grammar.auxiliary"),
        ("Tu as né en mai.", "grammar.auxiliary"),
        ("Vous avez arrivé.", "grammar.auxiliary"),
        ("Nous mange du pain.", "grammar.conjugation"),
        ("Tu vont bien?", "grammar.conjugation"),
        ("Si elle viendra demain, on ira.", "grammar.siClause"),
        ("Si vous auriez faim, mangez.", "grammar.siClause"),
        ("Elles sont parti.", "grammar.participle"),
        ("Marie est arrivé.", "grammar.participle"),
        ("J'adore chocolat.", "grammar.article"),
        ("Il aime chats.", "grammar.article"),
        ("Une robe blanc.", "grammar.agreement"),
        ("Des voitures rapide.", "grammar.agreement"),
        ("Les maisons grand.", "grammar.agreement"),
        ("Le chat la regarde.", nil),
        ("Je les vois souvent.", nil),
        ("Elle le dit toujours.", nil),
        ("La porte est fermée.", nil),
        ("Nous sommes partis tôt.", nil),
        ("Elle a descendu les valises.", nil),
        ("Il est à la maison.", nil),
        ("Je vais au marché.", nil),
        ("Si elle vient, on ira.", nil),
        ("Les maisons sont grandes.", nil),
        ("Une robe blanche.", nil),
        ("Il a pris une photo.", nil),
        ("Tu vas bien?", nil),
        ("Il revient du bureau.", nil),
        ("Marie est arrivée hier.", nil),
        ("J'adore le chocolat.", nil),
        // Written after the first scorecard found the named-subject gap, and before
        // the participle rule learned noun subjects.
        ("La fille est arrivé.", "grammar.participle"),
        ("Les enfants sont parti.", "grammar.participle"),
        ("Ma sœur est venu.", "grammar.participle"),
        ("Le train est arrivée.", "grammar.participle"),
        ("Les filles sont allé.", "grammar.participle"),
        ("Mes parents sont resté.", "grammar.participle"),
        ("Cette femme est tombé.", "grammar.participle"),
        ("L'actrice est né à Lyon.", "grammar.participle"),
        ("La fille est arrivée.", nil),
        ("Les enfants sont partis.", nil),
        ("Le livre est tombé.", nil),
        ("Le chat de ma sœur est arrivé.", nil),
        ("Les photos de la fête sont arrivées.", nil),
        ("La mère de Paul est venue.", nil),
        ("Le professeur est arrivé.", nil),
        ("Mes amies sont venues.", nil),
        // Written before the conjugation rule learned nous and vous as objects after a
        // noun, and before ils son and elles son joined the look-alike list.
        ("Le médecin nous a reçus.", nil),
        ("Ma tante vous appelle ce soir.", nil),
        ("Les voisins nous ont invités.", nil),
        ("Ce professeur nous donne des devoirs.", nil),
        ("Nous va à la plage.", "grammar.conjugation"),
        ("Vous mange trop.", "grammar.conjugation"),
        ("Ils son fatigués.", "grammar.lookAlike"),
        ("Elles son ici.", "grammar.lookAlike"),
        ("Elles adorent son gâteau.", nil),
        ("Ils connaissent son frère.", nil),
        // Written after the et-or-est model was trained and tuned, and never used to tune it.
        ("Mon père et professeur.", "grammar.etOrEst"),
        ("Ma chambre et petite.", "grammar.etOrEst"),
        ("Le film et intéressant.", "grammar.etOrEst"),
        ("Elle et très gentille.", "grammar.etOrEst"),
        ("J'ai un chien est un chat.", "grammar.etOrEst"),
        ("Il parle français est anglais.", "grammar.etOrEst"),
        ("Mon père est professeur.", nil),
        ("J'ai un chien et un chat.", nil),
        ("Il parle français et anglais.", nil),
        ("Le film est intéressant.", nil),
        ("Elle est très gentille et drôle.", nil),
        // Written before the accent rule learned the à-for-a direction and the
        // participle and adjective contexts for a.
        ("Il à faim.", "grammar.accent"),
        ("On à mangé au restaurant.", "grammar.accent"),
        ("Il y à un problème.", "grammar.accent"),
        ("Qu'est-ce qu'il y à dans le frigo?", "grammar.accent"),
        ("Elle à soif.", "grammar.accent"),
        ("Elle à fini ses devoirs.", "grammar.accent"),
        ("Il est allé a Paris.", "grammar.accent"),
        ("Je suis né a Lyon.", "grammar.accent"),
        ("Nous sommes arrivés a la gare.", "grammar.accent"),
        ("C'est facile a faire.", "grammar.accent"),
        ("C'est difficile a comprendre.", "grammar.accent"),
        ("Il pense a sa mère.", "grammar.accent"),
        ("Il a faim.", nil),
        ("Elle a fini ses devoirs.", nil),
        ("C'est à elle.", nil),
        ("Un cadeau pour elle à Noël.", nil),
        ("Il y a un problème.", nil),
        ("Il pense à elle.", nil),
        ("Elle est née à Lyon.", nil),
        ("Ce qui est arrivé a changé ma vie.", nil),
        ("La police qui est intervenue a tiré.", nil),
        ("Lui à pied, elle à vélo.", nil),
        ("On a tout à gagner.", nil),
        ("À demain!", nil),
        // Written after the preposition rule was built and never used to tune it.
        ("Mes cousins habitent à Portugal.", "grammar.preposition"),
        ("Nous partons en Brésil demain.", "grammar.preposition"),
        ("Elle travaille à Allemagne.", "grammar.preposition"),
        ("Ils reviennent de Maroc.", "grammar.preposition"),
        ("Le prix dépend sur la saison.", "grammar.preposition"),
        ("Tu as réussi de trouver la gare?", "grammar.preposition"),
        ("Il ressemble son père.", "grammar.preposition"),
        ("Nous écoutons à la musique.", "grammar.preposition"),
        ("Je téléphone mon frère ce soir.", "grammar.preposition"),
        ("Elle participe dans le concours.", "grammar.preposition"),
        ("Mes cousins habitent au Portugal.", nil),
        ("Nous partons au Brésil demain.", nil),
        ("Elle travaille en Allemagne.", nil),
        ("Ils reviennent du Maroc.", nil),
        ("Le prix dépend de la saison.", nil),
        ("Il ressemble à son père.", nil),
        ("Nous écoutons la musique.", nil),
        ("La demande sur le site est longue.", nil),
        ("Elle participe au concours dans la ville.", nil),
        ("J'attends pour voir.", nil),
        // Written before the elision, possessive, reflexive and age rules were built,
        // and never used to tune them.
        ("Je habite à Lyon.", "grammar.elision"),
        ("Il ne aime pas le café.", "grammar.elision"),
        ("Je pense que elle est malade.", "grammar.elision"),
        ("C'est le hôtel de mon frère.", "grammar.elision"),
        ("Elle se appelle Marie.", "grammar.elision"),
        ("Un verre de eau, s'il vous plaît.", "grammar.elision"),
        ("Nous allons au hôpital.", "grammar.elision"),
        ("Je le ai vu hier.", "grammar.elision"),
        ("J'habite à Lyon.", nil),
        ("Le héros arrive.", nil),
        ("Je le hais.", nil),
        ("Il mange le yaourt.", nil),
        ("Je vais à l'hôpital.", nil),
        ("Le onze novembre, il pleut.", nil),
        ("Il a dit que oui.", nil),
        ("Ma tante est là.", nil),
        ("Mon grand-mère habite ici.", "grammar.gender"),
        ("Son voiture est rouge.", "grammar.gender"),
        ("Ma oncle est médecin.", "grammar.gender"),
        ("Ta école est loin.", "grammar.gender"),
        ("Sa histoire est triste.", "grammar.gender"),
        ("Sa maison est grande.", nil),
        ("Ta copine est sympa.", nil),
        ("Mon amie est française.", nil),
        ("Son école est loin.", nil),
        ("Le son de la radio est fort.", nil),
        ("Elle s'a couchée tôt.", "grammar.auxiliary"),
        ("Je me ai brossé les dents.", "grammar.auxiliary"),
        ("Vous vous avez trompés.", "grammar.auxiliary"),
        ("Ils se ont rencontrés à Paris.", "grammar.auxiliary"),
        ("Elle s'est couchée tôt.", nil),
        ("Vous nous avez vus.", nil),
        ("Il m'a aidé.", nil),
        ("Mon frère est 12 ans.", "grammar.wordChoice"),
        ("Elle est trente ans.", "grammar.wordChoice"),
        ("Nous sommes 15 ans.", "grammar.wordChoice"),
        ("Mon frère a 12 ans.", nil),
        ("C'est vingt ans de travail.", nil),
        ("Il y a beaucoup des touristes en été.", "grammar.wordChoice"),
        ("J'ai trop de les devoirs.", "grammar.wordChoice"),
        ("Je ne veux pas rien.", "grammar.wordChoice"),
        ("Il ne sort pas jamais.", "grammar.wordChoice"),
        ("Beaucoup des étudiants de la classe sont partis.", nil),
        ("Il parle beaucoup des vacances.", nil),
        ("Ce n'est pas rien.", nil),
        ("Il ne sort jamais.", nil),
        // Written before the two capital-letter rules were built, and never used to tune them.
        ("il fait beau aujourd'hui.", "grammar.sentenceCapital"),
        ("j'habite à Lyon.", "grammar.sentenceCapital"),
        ("J'ai faim. je vais manger.", "grammar.sentenceCapital"),
        ("Tu viens ? oui, je viens.", "grammar.sentenceCapital"),
        ("Quelle belle journée ! nous allons à la plage.", "grammar.sentenceCapital"),
        ("Il pleut.\nelle reste à la maison.", "grammar.sentenceCapital"),
        ("C'est fini. après, on dort.", "grammar.sentenceCapital"),
        ("Bonjour ! comment ça va ?", "grammar.sentenceCapital"),
        ("Je travaille le Lundi.", "grammar.lowercase"),
        ("Mon anniversaire est en Mars.", "grammar.lowercase"),
        ("Nous partons en Juillet.", "grammar.lowercase"),
        ("Je parle Anglais.", "grammar.lowercase"),
        ("Elle apprend le Français.", "grammar.lowercase"),
        ("J'ai un cours de Français.", "grammar.lowercase"),
        ("J'ai un ami Américain.", "grammar.lowercase"),
        ("Il est Canadien.", "grammar.lowercase"),
        ("Mais Je ne sais pas.", "grammar.lowercase"),
        ("Le 14 Juillet, on danse.", nil),
        ("Les Français aiment le pain.", nil),
        ("J'ai vu un Américain à Paris.", nil),
        ("Il a dit : « Je viens demain. »", nil),
        ("« Viens ! » dit-il.", nil),
        ("M. Dupont arrive lundi.", nil),
        ("Le prix est de 3.5 euros.", nil),
        ("Je suis allé chez Marie… elle dormait.", nil),
        ("Chère Marie,\nje pense à toi.", nil),
        ("Il travaille à l'Alliance Française.", nil),
        ("Je parle français avec Paul.", nil),

        // Added for the rules that had few unseen errors or none. Some of these are
        // common learner mistakes no rule may cover yet, so a miss here is a measured
        // gap rather than a broken test.
        ("C'est un youtubeuse.", "grammar.gender.predicted"),
        ("Il suit un tiktokeuse.", "grammar.gender.predicted"),
        ("Je connais un blogueuse.", "grammar.gender.predicted"),
        ("Le géolocalisation ne marche pas.", "grammar.gender.predicted"),
        ("Un digitalisation coûte cher.", "grammar.gender.predicted"),
        ("Le téléconsultation est gratuite.", "grammar.gender.predicted"),
        ("C'est une podcasteur.", "grammar.gender.predicted"),
        ("C'est une télétravailleur.", "grammar.gender.predicted"),
        ("J'écoute un podcast.", nil),
        ("C'est une startup.", nil),
        ("J'ai un smartphone.", nil),

        ("Les table sont propres.", "grammar.articleNumber"),
        ("Le chiens aboient.", "grammar.articleNumber"),
        ("La filles chantent.", "grammar.articleNumber"),
        ("Un chats dort sur le lit.", "grammar.articleNumber"),
        ("Une pommes suffit.", "grammar.articleNumber"),
        ("Des maison sont à vendre.", "grammar.articleNumber"),
        ("J'ai acheté des fleur.", "grammar.articleNumber"),
        ("Il lit les journal.", "grammar.articleNumber"),
        ("La souris dort.", nil),
        ("Le bras me fait mal.", nil),
        ("Mon fils a des prix.", nil),

        ("Je fume plus depuis mai.", "grammar.negation"),
        ("Elle vient plus ici.", "grammar.negation"),
        ("Je sais plus.", "grammar.negation"),
        ("Il pleut plus.", "grammar.negation"),
        ("Je ne mange pas rien.", "grammar.negation"),
        ("Je ne veux pas jamais partir.", "grammar.negation"),
        ("Je pas mange.", "grammar.negation"),
        ("Je n'ai mangé pas.", "grammar.negation"),
        ("Je mange plus de légumes.", nil),
        ("Elle travaille plus que moi.", nil),
        ("Je n'ai rien mangé.", nil),

        ("Ça fait du sens pour moi.", "grammar.idiom"),
        ("Je suis excité pour le voyage.", "grammar.idiom"),
        ("Je regarde un film sur la télé.", "grammar.idiom"),
        ("Je suis froide ce matin.", "grammar.idiom"),
        ("Je vais au docteur.", "grammar.idiom"),
        ("Je vais à la toilette.", "grammar.idiom"),
        ("La réunion prend place samedi.", "grammar.idiom"),
        ("Il a pris avantage de la situation.", "grammar.idiom"),
        ("J'ai froid ce matin.", nil),
        ("Je vais chez le médecin.", nil),
        ("La réunion a lieu samedi.", nil),

        ("J'habite à Lyon pour deux ans.", "grammar.meaning"),
        ("Il travaille ici pour trois mois.", "grammar.meaning"),
        ("Nous étudions le français pour six ans.", "grammar.meaning"),
        ("Je vis en France pour cinq semaines.", "grammar.meaning"),
        ("Je ne fume pas encore.", "grammar.meaning"),
        ("Elle n'habite pas encore ici.", "grammar.meaning"),
        ("Il n'a pas encore faim.", "grammar.meaning"),
        ("Je ne suis pas encore fatigué.", "grammar.meaning"),
        ("J'habite à Lyon depuis deux ans.", nil),
        ("J'ai acheté un cadeau pour deux enfants.", nil),
        ("Je n'ai pas encore mangé.", nil),

        ("Il y a trente et trois places.", "grammar.number"),
        ("J'ai quarante cinq ans.", "grammar.number"),
        ("Il y a soixante dix élèves.", "grammar.number"),
        ("Il est trois heure.", "grammar.number"),
        ("Il est cinq heure et demie.", "grammar.number"),
        ("Le bus part à 8 am.", "grammar.number"),
        ("Elle a vingt et une ans.", "grammar.number"),
        ("Il y a vingt et un filles.", "grammar.number"),
        ("Il est une heure.", nil),
        ("Il est midi et demi.", nil),
        ("Le bus part à 8 h 30.", nil),
        ("Elle a vingt et un ans.", nil),

        ("Si elle aura faim, elle mangera.", "grammar.siClause"),
        ("Si vous pourrez venir, appelez-moi.", "grammar.siClause"),
        ("Si je serais riche, j'achèterais une maison.", "grammar.siClause"),
        ("S'il fera froid, je resterai ici.", "grammar.siClause"),
        ("Si elle a faim, elle mangera.", nil),
        ("Je ne sais pas s'il viendra.", nil),

        ("Sa va très bien.", "grammar.lookAlike"),
        ("Ils son contents.", "grammar.lookAlike"),
        ("Elles on faim.", "grammar.lookAlike"),
        ("Il ce lave.", "grammar.lookAlike"),
        ("Il peu venir.", "grammar.lookAlike"),
        ("Ils sont contents.", nil),
        ("Elles ont faim.", nil),
        ("Il se lave.", nil),

        ("Elle va à les magasins.", "grammar.contraction"),
        ("Je viens de le parc.", "grammar.contraction"),
        ("Il pense à le travail.", "grammar.contraction"),
        ("Nous parlons de les vacances.", "grammar.contraction"),
        ("Je commence à le comprendre.", nil),
        ("Il a peur de les perdre.", nil),

        ("Je déteste lait.", "grammar.article"),
        ("Elle aime chats.", "grammar.article"),
        ("Nous adorons cinéma.", "grammar.article"),
        ("Il n'aime pas café.", "grammar.article"),
        ("Je déteste le lait.", nil),

        ("Une fille grand.", "grammar.agreement"),
        ("Des livres intéressant.", "grammar.agreement"),
        ("Un garçon petite.", "grammar.agreement"),
        ("Des livres intéressants.", nil),

        ("Tu parle français.", "grammar.conjugation"),
        ("Nous finis à midi.", "grammar.conjugation"),
        ("Tu parles français.", nil)
    ]

    /// One rule's report on the corpus, with any sentence it got wrong.
    private struct RuleScore {
        let identifier: String
        let report: ClassificationReport
        let misses: [String]
        let falseAlarms: [String]
    }

    /// Runs each rule on every sentence and scores its yes-or-no answers against the labels.
    private func scores(on corpus: [(text: String, rule: String?)]) throws -> [RuleScore] {
        let grammar = try XCTUnwrap(Self.pack, "The French language pack failed to load").grammar
        let tokenized = corpus.map { (tagged: grammar.tag(FrenchTokenizer.tokens(in: $0.text)), text: $0.text, rule: $0.rule) }
        return grammar.rules.map { rule in
            var predicted: [Int] = []
            var actual: [Int] = []
            var misses: [String] = []
            var falseAlarms: [String] = []
            for sentence in tokenized {
                let fires = !rule.check(sentence.tagged).isEmpty
                let labelled = sentence.rule == rule.identifier
                predicted.append(fires ? 1 : 0)
                actual.append(labelled ? 1 : 0)
                if labelled && !fires { misses.append(sentence.text) }
                if fires && !labelled { falseAlarms.append(sentence.text) }
            }
            return RuleScore(
                identifier: rule.identifier,
                report: predicted.classificationReport(actual: actual),
                misses: misses,
                falseAlarms: falseAlarms
            )
        }
    }

    /// Formats an optional metric to two places, or a dash when it is undefined.
    private func format(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "–"
    }

    /// Renders one corpus's scores as a Markdown table, followed by every sentence a
    /// rule missed or flagged without its label.
    private func table(_ title: String, _ scores: [RuleScore], sentences: Int) -> String {
        var lines = [
            "\(title): \(sentences) sentences",
            "| Rule | Precision | Recall | F1 | Errors |",
            "| --- | --- | --- | --- | --- |"
        ]
        for score in scores {
            let errors = score.report.perClass[1]
            lines.append("| \(score.identifier) | \(format(errors?.precision)) | \(format(errors?.recall)) | \(format(errors?.f1Score)) | \(errors?.support ?? 0) |")
        }
        for score in scores {
            for text in score.misses { lines.append("  missed by \(score.identifier): \(text)") }
            for text in score.falseAlarms { lines.append("  flagged by \(score.identifier): \(text)") }
        }
        return lines.joined(separator: "\n")
    }

    // Prints the scorecard for the tuning sentences and for the unseen ones.
    func testRuleScorecard() throws {
        let tuning = try scores(on: Self.tuningCorpus)
        let unseen = try scores(on: Self.unseenCorpus)
        let scorecard = table("Tuning sentences", tuning, sentences: Self.tuningCorpus.count)
            + "\n\n" + table("Unseen sentences", unseen, sentences: Self.unseenCorpus.count)
        print(scorecard)
        // Kept in the test results, where Xcode's report navigator shows it.
        let attachment = XCTAttachment(string: scorecard)
        attachment.name = "Rule scorecard"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The scorecard describes the rules rather than passing or failing them; these
        // checks only keep the corpus itself sound.
        XCTAssertEqual(tuning.count, 22)
        let identifiers = Set(tuning.map(\.identifier))
        for (text, rule) in Self.tuningCorpus + Self.unseenCorpus {
            guard let rule else { continue }
            XCTAssertTrue(identifiers.contains(rule), "\(text) is labelled with an unknown rule, \(rule)")
        }
    }
}
