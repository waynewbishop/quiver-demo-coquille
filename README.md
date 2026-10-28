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
tapping one opens a card with the fix and a one-line reason, such as
"fromage is masculine, so the article is un." A play button reads the
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
paragraph with one mistake of each kind.

Playback uses the system's French voices, and translation needs the
French language pack for on-device translation. The app can't download
either itself:

- **Voices.** iPhone and iPad: Settings › Accessibility › Spoken
  Content › Voices › French. Mac: System Settings › Accessibility ›
  Spoken Content › System voice › Manage Voices. The enhanced and
  premium voices sound much more natural.
- **Translation.** Download French under the system's translation
  languages. Until it's installed, the English area says so.

## What it checks

```
Nous avons acheté une fromage et des pommes rouge.
                  ~~~~~~~~~~~            ~~~~~
                  un fromage             rouges
```

| Check | Example | Severity | Source |
|---|---|---|---|
| Spelling | gentile → gentille | Error | System spellchecker, guesses ranked by Quiver |
| Article gender | une fromage → un fromage | Error | Lexique, known noun |
| Contractions | à le marché → au marché | Error | Contraction rule |
| Adjective agreement | des pommes rouge → rouges | Error | Lexique adjective forms |
| Missing ne | il dort plus → il ne dort plus | Warning | Negation rule |
| Idioms | bon pour ta santé → bon pour la santé | Suggestion | Idiom list |
| Unknown nouns | a gender guess from the word's ending | Warning | Quiver model |

Errors block play and English; warnings and suggestions never do, and
every card has **Ignore**, so a false positive can never trap the
learner. A narrow linter that's always right beats a broad one that
cries wolf, so each rule stays silent when it isn't sure. Nouns Lexique
lists with both genders (le livre, la livre) are skipped. A le or la in
front of a verb is read as a pronoun ("je le porte"), not an article.
"plus tard" and "plus que" are left alone. Tapping the error chip opens
every issue at once, like Xcode's issue navigator.

## Quiver APIs used

- `LogisticRegression` — the gender classifier. Each feature is 1.0 when
  a noun ends with one ending (-tion, -ment, -ette…), and the model is
  trained offline and bundled as JSON through its `Codable`
  conformance.
- `predictProbabilities(_:)` — the model's probability that a noun is
  feminine. Only confident guesses (0.8 or more) become warnings.
- `coefficients` and `hasIntercept` — the open weights. A positive
  weight leans feminine and a negative one masculine, so every
  prediction names the ending that decided it: "boulangère is probably
  feminine: words ending in -ère usually are."
- `cosineSimilarities(to:)` — ranks the spellchecker's guesses by
  letter-pair similarity to the typo, so "gentile" suggests "gentille"
  before "gentil".

## The gender model

The model isn't bundled yet: training and comparing models happens in
the Quiver Notebook first. Until `fr.gender-model.json` exists, nouns
Lexique doesn't know simply go unchecked; known nouns never need the
model, because the lexicon answers them exactly. Dropping in a trained
file turns the warnings on, with no code changes. The file holds the
ending vocabulary and the encoded `LogisticRegression`, with endings in
the same order as the features and class 1 meaning feminine:

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
- `LanguagePacks/French/` — the lexicon, explanation templates and
  idiom list as readable JSON. Changing a template changes the
  explanation without touching code.
- `Speech/`, `Translation/`, `Stats/`, `Editor/` — playback, on-device
  translation, the learner's progress (stored only on the device) and
  the SwiftUI views.
- `Fonts/` — IBM Plex Sans and Mono, registered at launch, so there's
  no Info.plist entry.
- `Tools/BuildLexicon.swift` — rebuilds the lexicon from the full
  Lexique table.
- `quiver-demo-coquilleTests/` — 34 XCTest cases, including the
  false-positive traps above.

## Data

Word data comes from [Lexique 3.83](http://www.lexique.org) by Boris
New and Christophe Pallier, licensed
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). The
full table (142,000 rows) never ships. The app bundles a 2.2 MB slice
of nouns with gender and number, adjectives with their four forms, and
verb forms. Because it's derived from Lexique, `fr.lexicon.json`
carries the same license. To rebuild it:

```bash
swift Tools/BuildLexicon.swift /path/to/Lexique383.tsv \
  quiver-demo-coquille/LanguagePacks/French/fr.lexicon.json
```

The fonts are [IBM Plex](https://github.com/IBM/plex), licensed under the
SIL Open Font License 1.1; the license ships beside them as
`Fonts/IBMPlex-OFL.txt`.

## Learn more

- [Quiver](https://github.com/waynewbishop/quiver) — the framework
- [Quiver Cookbook](https://github.com/waynewbishop/quiver-cookbook) — interactive recipes
- [Quiver Documentation](https://waynewbishop.github.io/quiver/documentation/quiver/) — API reference and conceptual guides
- [Swift Algorithms & Data Structures](https://waynewbishop.github.io/swift-algorithms/) — the companion book
