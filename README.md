# Quiver Demo: Coquille, a French Linter

Most language apps grade against an answer key. Type "bon pour votre
santé" when the lesson expected "bon pour ta santé" and it's marked
wrong, even though both are correct French. Coquille works like a code
linter instead. There is no answer key: we write any French we like,
and Coquille checks whether it's valid, the way Xcode underlines code
that won't compile.

This demo uses [Quiver](https://github.com/waynewbishop/quiver) for
the machine learning in a universal SwiftUI app for iPhone, iPad and
Mac. The whole screen is one text editor. Mistakes get a red underline;
tapping one opens a card that names the rule, such as "fromage is
masculine." The underline shows where the mistake is, and the fix stays
hidden until we ask for it, so we get the first try at correcting it.
The progress sheet counts the fixes we typed ourselves.
A play button reads the
French aloud and an English toggle shows an on-device translation, but
both stay locked until every error is fixed or ignored. Apple's
translator is forgiving ("une fromage" still comes out as "a cheese"),
so clean English would hide the mistake. Like a compiler, nothing runs
until the code is right.

Everything runs offline, with native Apple frameworks and Quiver as the
only dependency.

## Run it

Open `quiver-demo-coquille.xcodeproj` in Xcode, pick an iPhone
simulator or My Mac, and run. Tap **Try an example** to load a
short paragraph aimed at one kind of mistake. Each tap picks a different
one.

Playback uses the system's French voices, which the app can't download
itself, and translation needs Apple's French language pack:

- **Voices.** iPhone and iPad: Settings › Accessibility › Spoken
  Content › Voices › French. Mac: System Settings › Accessibility ›
  Read & Speak, then the ⓘ button next to System voice. The enhanced
  and premium voices sound much more natural.
- **Translation.** Choose **Download French…** in Coquille's Settings.
  Until it's installed, the English area says so.

On a Mac with Apple Intelligence, the window title names the story once
the French has no errors; otherwise it reads "Coquille".

## Widgets and exercise links

The `CoquilleWidgets` extension provides a small or medium **Coquille**
widget and two controls, Coquille and Coquille Phrasebook, on iPhone, iPad
and Mac. Add them through the system's widget gallery and Control Center **+** flow.

The bar at the top carries on with the current writing, or starts today's
entry when the editor is empty. Small adds today's prompt and the phrasebook;
medium also adds the journal and corrections. The prompt comes from the
bundled catalog and changes on the local calendar day, including across
daylight-saving changes, and opens that exact English sentence as an unsaved
draft. Everything works offline. The Coquille control behaves like the bar,
and the Phrasebook control opens the phrasebook.

Claude can offer a lesson's writing exercise with a custom link:

```text
coquille://new?title=Nov%203%3A%20C%27est%20ferm%C3%A9&prompt=Is%20it%20open%3F&prompt=It%20was%20closed.&hint=c%27%C3%A9tait
```

A confirmation sheet shows the English prompts before **Start writing**
creates an unsaved entry. Prompts become grey notes above blank answer lines;
no French answer is inserted. An optional hint stays collapsed until the
learner asks for it. Links support 1–10 single-line prompts of up to 300
characters each, an optional 120-character title, and an optional
300-character hint. The complete URL is capped at 2,048 UTF-8 bytes, and
unknown, duplicate, malformed, or oversized fields are rejected without
changing the editor. The same `coquille://` links work on iPhone, iPad and Mac.

The editor supports the system's copy and paste commands, so homework and
Coquille's feedback can be pasted back into a Claude conversation.

## What it checks

```
Nous avons acheté une fromage et des pommes rouge.
                  ~~~~~~~~~~~            ~~~~~
                  un fromage             rouges
```

| Check | Example | Severity | Source |
|---|---|---|---|
| Spelling | gentile → gentille | Error | System spellchecker, guesses ranked by Quiver |
| Unknown words | Ahdourdui, with no fix offered | Warning | System spellchecker, no French guess |
| Run-together words | jesuis → je suis, jaime → j'aime | Warning | System spellchecker, split by Lexique |
| Article gender | une fromage → un fromage, ce maison → cette maison, quel maison → quelle maison | Error | Lexique, known noun |
| Contractions | à le marché → au marché | Error | Contraction rule |
| Elision | je aime → j'aime, au école → à l'école | Error | Elision rule |
| Possessives | mon mère → ma mère, ma amie → mon amie | Error | Lexique, known noun |
| Adjective agreement | des pommes rouge → rouges | Error | Lexique adjective forms |
| Look-alike words | comment cava → comment ça va | Error | Look-alike list |
| A or à | je vais a Paris → à, il à faim → a | Error | Accent rule, Lexique verb forms |
| Prepositions | à Canada → au Canada, je vais France → en France, en les montagnes → dans les montagnes, dépend sur → dépend de, en printemps → au printemps | Error | Country list, preposition list, place and en rules |
| Conjugation | je va → je vais, ils mange → ils mangent | Error | Conjugation rule, Lexique verb forms |
| Être or avoir | j'ai allé → je suis allé, il s'a trompé → il s'est trompé | Error | Auxiliary rule, Lexique participles |
| Participle agreement | il a mangée → mangé, elles sont allé → allées | Error | Participle rule, Lexique participles |
| Articles for things in general | j'aime fromage → j'aime le fromage | Error | Article rule, Lexique gender |
| Si clauses | si tu viendras → si tu viens | Error | Si clause rule, Lexique verb forms |
| Subjunctive | il faut que je fais → il faut que je fasse, je veux que tu viens → je veux que tu viennes | Error | Subjunctive rule, Lexique verb forms |
| Object pronouns | je lui ai vu → je l'ai vu, je le téléphone → je lui téléphone | Error | Object pronoun rule, Lexique verb forms |
| Relative pronouns | un ami qui je connais → un ami que je connais, le livre que j'ai besoin → le livre dont j'ai besoin | Error | Relative pronoun rule, part-of-speech tagger |
| Avoir expressions | je suis faim → j'ai faim, je suis 20 ans → j'ai 20 ans | Error | Word-choice list and age rule |
| Word choice | j'ai demandé une question → posé une question, beaucoup des gens → beaucoup de gens | Error | Word-choice list |
| Missing ne | il dort plus → il ne dort plus | Warning | Negation rule |
| Idioms | ça fait du sens → ça a du sens | Suggestion | Idiom list |
| Unknown nouns | un influenceuse → une influenceuse | Warning | Quiver model, from the word's ending |
| Numbers and times | vingt et deux → vingt-deux, dix sept → dix-sept, deux heure → deux heures, 6 pm → 18h | Error (6:00 is a warning) | Number and time rules |
| Capital letters | il pleut → Il pleut, le Lundi → le lundi, je parle Anglais → anglais | Warning | Capital letter rule |

Errors block play and English; warnings and suggestions never do, and
every card has **Ignore**, so a false positive can never trap the
learner. A narrow linter that's always right beats a broad one that
cries wolf, so each rule stays silent when it isn't sure. Nouns Lexique
lists with both genders (le livre, la livre) are skipped. A le or la in
front of a verb is read as a pronoun ("je le porte"), not an article.
"plus tard" and "plus que" are left alone. Tapping the error chip opens
every issue at once, like Xcode's issue navigator.

## The phrasebook

A blank page is the hardest part of writing in a new language. The
book button opens a phrasebook beside the editor: 104 complete phrases
in eight situations, from greetings and the café to directions, travel
and journal starters. Each row shows the French, an English gloss, a
*tu* or *vous* tag when it matters, and a play button that reads it
aloud. Many carry a one-line note on the pattern, such as "Je voudrais
is the polite way to say I want. Use it to order anything.", so we can
reuse it in a sentence of our own.

There's no copy or insert. In a paper journal a borrowed phrase is
copied out by hand, and the copying is practice, so we type the phrase
ourselves and Coquille checks it like any other French: a slip such as
*cafe* for *café* is caught as usual. On the Mac and iPad the
phrasebook is a side panel; on iPhone it's a half-height sheet with the
editor still usable underneath. Playing a phrase stops the French, and
playing the French stops the phrase.

Search takes French or English and forgives typos and missing accents:
*bonjur* finds *Bonjour !* and *cafe* finds *café*. Each word becomes
the same letter-pair vector that ranks spelling fixes, and Quiver
scores it against every phrase's words. A word still being typed
matches the words it starts, so *addi* already finds *L'addition*.

The phrases live in `LanguagePacks/French/fr.phrases.json`, each with
its situation, French, English, register and optional note. A test
runs every phrase through the whole linter, the platform spellchecker
included, and expects no issues, so a phrase we copy is never flagged.
If the file is missing or won't load, the editor and linter still work
with an empty phrasebook.

## Quiver APIs used

- `LogisticRegression` — the gender classifier. Each feature is 1.0 when
  a noun ends with one ending (-tion, -ment, -ette…), and the model is
  trained offline and bundled as JSON through its `Codable`
  conformance.
- `predictProbabilities(_:)` — the model's probability that a noun is
  feminine. Only guesses of 0.95 or more that can name an ending become
  warnings.
- `coefficients` and `hasIntercept` — the open weights. A positive
  weight leans feminine and a negative one masculine, so a prediction
  can name the ending behind it: "influenceuse is probably feminine:
  words ending in -euse usually are."
- `cosineSimilarities(to:)` — ranks the spellchecker's guesses by
  letter-pair similarity to the typo, so "gentile" suggests "gentille"
  before "gentil". The phrasebook search uses the same vectors, so
  "bonjur" finds "Bonjour !".

## The part-of-speech layer

Nearly 30% of running French has more than one reading in Lexique,
and most of that is two-way. Before the rules run, each pass is tagged
once by small binary `LogisticRegression` deciders, and every rule reads
the verdicts instead of working out its neighbours by hand:

- article or pronoun, for le, la, les and l' ("je la porte");
- adjective or noun, for words Lexique lists as both (malade, jeune);
- helper or main verb, for avoir and être ("il a mangé", "il a faim");
- noun or verb, for words like demande and porte, so "la demande sur le
  site" never matches a pattern for the verb demander.

All four share one recipe, `ContextDecider`: the five words around
the target and what Lexique says each can be. Each is one JSON file of
word lists and weights, trained in the Quiver Notebook
(`coquille-part-of-speech-model.swift`) on the Universal Dependencies
French treebanks. On held-out treebank text, at the 0.95 cutoff the
rules use, article or pronoun decides 97% of cases and is right on
99.8%; adjective or noun decides 54% and is right on 98.9%; helper or
main decides 73% and is right on 99.1%; noun or verb decides 67% and is
right on 98.8%. A word the decider
isn't sure about gets no verdict, and the rules stay silent.

## The phrase list

Every listed phrase lives in `fr.patterns.json`: look-alikes, word
choices, idioms, meaning questions and prepositions, one entry each. An
entry can name a verb instead of a form, so `@jouer le $sport` →
`@jouer au $sport` catches "nous jouons le foot" and "je jouais le
tennis" alike, and "@faire une décision" → "@prendre une décision" turns
"fait" into "prend", or "pris" after avoir. The same file holds each
country's article, which settles its preposition (au Canada, en France,
aux États-Unis).

The verb + preposition entries tagged `"origin": "UD treebanks"` are
generated by `swift Tools/BuildVerbPrepositions.swift ~/Projects/Resources
quiver-demo-coquille/LanguagePacks/French/fr.patterns.json`, which
counts which preposition each verb takes in the treebanks and keeps an
entry only when the flagged word pair never appears there. A rerun
replaces those entries and leaves the hand-written ones alone.

## The gender model

The model only answers for nouns Lexique doesn't know; known nouns never
need it, because the lexicon answers them exactly. It was trained in the
Quiver Notebook on the 26,323 singular nouns Lexique gives exactly one
gender, with a fifth held out for testing. Its 110 features are the
endings of one to four letters shared by at least 100 training nouns.

The nouns that reach it in the app are mostly loanwords and new words,
and those break the ending rules more often than Lexique's nouns do: at
a 0.8 cutoff it called "un selfie" and "une appli" wrong. So it warns
only when it is at least 0.95 sure and can name an ending of two letters
or more, the longest one behind the guess ("influenceuse" cites -euse,
never -e, since "words ending in -e" is no rule to learn). On the
held-out Lexique nouns, that warns on 34.8% of them and is right 99.7%
of the time; everywhere else it stays silent.

To retrain, rebuild the noun list with
`swift Tools/BuildGenderNouns.swift <Lexique383.tsv> Tools/fr.gender-nouns.csv`,
train in the Notebook, and replace `fr.gender-model.json`; no code
changes are needed. Without the file, unknown nouns simply go
unchecked. The file holds the ending vocabulary and the encoded
`LogisticRegression`, with endings in the same order as the features and
class 1 meaning feminine:

```json
{
  "endings": ["e", "on", "ion", "tion", "ment"],
  "model": { "coefficients": [-0.4, 1.2, 0.3, 0.9, 2.1, -2.5], "featureCount": 5, "hasIntercept": true, ... }
}
```

The weights above only show the shape of the file; they aren't trained
values. The app rejects a file whose ending count doesn't match the
model's `featureCount`.

## Project layout

Everything is plain folders in one Xcode project:

- `Linter/` — the tokenizer, the French rules, spellcheck and Quiver
  suggestion ranking. Each role sits behind a small protocol
  (`Grammar`, `SpellChecker`, `GenderPredictor`), so tests swap in
  fakes.
- `Gender/` — the Quiver gender model.
- `LanguagePacks/French/` — the lexicon, explanation templates, the
  look-alike, word-choice and idiom lists, and the phrasebook, all as
  readable JSON. Changing a template changes the explanation without
  touching code.
- `Phrasebook/` — the phrase model, the Quiver-backed search and the
  phrasebook view.
- `Speech/`, `Translation/`, `Stats/`, `Editor/` — playback, on-device
  translation, the learner's progress (stored only on the device) and
  the SwiftUI views.
- `Prompts/`, `Exercises/` — the daily catalog, strict custom-URL router,
  exercise confirmation, and optional hint presentation.
- `CoquilleWidgets/` — the widget timeline and Control Center
  launcher, with shared prompt code but no Quiver dependency.
- `Fonts/` — IBM Plex Sans and Mono, registered at app launch and declared
  under `UIAppFonts` for the widget process.
- `Tools/BuildLexicon.swift` — rebuilds the lexicon from the full
  Lexique table, applying `Tools/fr.noun-gender-overrides.json` and
  `Tools/fr.adjective-overrides.json`.
- `quiver-demo-coquilleTests/` — 243 XCTest cases, including the
  false-positive traps above, correct French that must pass clean,
  phrasebook validation, calendar selection, and hostile-link tests.

## Data

Word data comes from [Lexique 3.83](http://www.lexique.org) by Boris
New and Christophe Pallier, licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The
full table (142,000 rows) never ships. The app bundles a 4.1 MB slice
of nouns with gender and number, adjectives with their four forms, verb
forms with their tense and person, and each past participle's verb,
gender and number. Because it's derived from Lexique, `fr.lexicon.json`
carries the same license. To rebuild it:

```bash
swift Tools/BuildLexicon.swift /path/to/Lexique383.tsv \
  quiver-demo-coquille/LanguagePacks/French/fr.lexicon.json
```

Lexique leaves the gender blank on some common nouns, including maison,
main and voiture, which would otherwise be stored as both genders and
never checked. `Tools/fr.noun-gender-overrides.json` gives 36 of them
their one everyday gender, hand-checked, and the build applies it to
each noun and its regular plural. Nouns that really take either gender,
such as enfant or livre, stay out of the list.

Lexique also splits some adjectives across entries (nouveau and
nouvelle, mou and molle) and leaves gaps in others (globales, animaux).
Agreement only checks a form that belongs to one adjective, so those
went unchecked. `Tools/fr.adjective-overrides.json` completes 15 of them
and removes 8 partial or stray entries; the build refuses a removal
that would drop a spelling the app knows.

The fonts are [IBM Plex](https://github.com/IBM/plex), licensed under the
SIL Open Font License 1.1; the license ships beside them as
`Fonts/IBMPlex-OFL.txt`.

## Learn more

- [Quiver](https://github.com/waynewbishop/quiver) — the framework
- [Quiver Cookbook](https://github.com/waynewbishop/quiver-cookbook) — interactive recipes
- [Quiver Documentation](https://waynewbishop.github.io/quiver/documentation/quiver/) — API reference and conceptual guides
- [Swift Algorithms & Data Structures](https://waynewbishop.github.io/swift-algorithms/) — the companion book
