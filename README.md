# Quiver Demo: Coquille, a French Linter

Most language apps grade against an answer key. Type "bon pour votre
santé" when the lesson expected "bon pour ta santé" and it's marked
wrong, even though both are correct French. Coquille works like a code
linter instead. There is no answer key: we write any French we like,
and Coquille checks whether it's valid, the way Xcode underlines code
that won't compile.

This demo uses [Quiver](https://github.com/waynewbishop/quiver) for
the machine learning in a universal SwiftUI app for iPhone, iPad and
Mac. It's also a worked example of using small, explainable models
beside plain rules: where a rule is exact we use a rule, and where a
word is ambiguous or unknown we ask a Quiver model, then stay silent
unless it's sure.

## What Coquille is

The whole screen is one text editor. Mistakes get a red underline;
tapping one opens a card that names the rule, such as "fromage is
masculine." The underline shows where the mistake is, and the fix stays
hidden until we ask for it, so we always get the first try at correcting
it. The progress sheet counts only the fixes we typed ourselves.

A play button reads the French aloud and an English toggle shows an
on-device translation, but both stay locked until every error is fixed or
ignored. Apple's translator is forgiving ("une fromage" still comes out as
"a cheese"), so clean English would hide the mistake. Like a compiler,
nothing runs until the code is right.

Around the editor sits a small journal. Each entry is a plain text file on
the device, a backup is one ZIP that restores on any device, and Explain
uses Apple's on-device language model to point out the phrases in an
error-free entry that are worth knowing. A finished entry can be shared as
a postcard, with one of the app's paintings, the French and the English.
A short welcome tour opens on first run. Quiver does three jobs here: it
ranks spelling guesses, it guesses the gender of nouns the lexicon doesn't
know, and it settles words that can be read two ways.

Our checking runs on the device, with native Apple frameworks and Quiver
as the only dependency. Explain needs Apple Intelligence, and translation
needs Apple's French language pack, as described below.

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

## Try it

Each experiment below takes a minute. Type the sentence into the editor,
then watch what Coquille does and doesn't do.

1. **See a rule, then earn the fix.** Type "Nous avons acheté une fromage et
   des pommes rouge." Two words are underlined. Tap each one to read the
   rule it names, and try correcting it before choosing **Show fix**. Then
   open the progress sheet: it counts the corrections we typed, not the ones
   we accepted.
2. **Feel the lock.** With an error still on the page, the play button and
   the English toggle are locked. Fix or ignore the last error and both
   unlock. Ignoring is always possible, so a wrong flag never traps us.
3. **Compare an error with a warning.** Type "Il dort plus." and then "Je
   mange une fromage." The first is a warning for a missing *ne*, and
   playback still works. The second is an error, and playback locks. The
   difference is how sure the rule is.
4. **Watch words come apart.** Type "Jemappelle Paul. Moi, jaime le
   fromage. Je nemangepas ici." Each run-together word is flagged with a
   fix that restores the spaces and apostrophes. These are warnings, so they
   never lock playback, and a word the system could have meant as a name or
   as an accent slip is left alone.
5. **Test the silence.** Type "plus tard" and "le livre". Nothing is flagged,
   because each rule stays quiet when a phrase is correct French or the
   word can take either gender. Try to find a correct sentence that gets
   flagged; if we find one, it's a rule to tighten.
6. **Search with a typo.** Open the phrasebook and search "bonjur" or
   "cafe". The right phrase still appears, because the search ranks phrases
   by letter-pair similarity with Quiver.

## What it checks

Here is the kind of thing we see in the editor:

```
Nous avons acheté une fromage et des pommes rouge.
                  ~~~~~~~~~~~            ~~~~~
                  un fromage             rouges
```

| Check | Example | Severity | Source |
|---|---|---|---|
| Spelling | gentile → gentille | Error | System spellchecker, guesses ranked by Quiver |
| Unknown words | Ahdourdui, with no fix offered | Warning | System spellchecker, no French guess |
| Run-together words | jesuis → je suis, jaime → j'aime, nemangepas → ne mange pas | Warning | System spellchecker, split by Lexique |
| Article gender | une fromage → un fromage, ce maison → cette maison, quel maison → quelle maison | Error | Lexique, known noun |
| Contractions | à le marché → au marché | Error | Contraction rule |
| Elision | je aime → j'aime, au école → à l'école, si il → s'il | Error | Elision rule |
| Possessives | mon mère → ma mère, ma amie → mon amie | Error | Lexique, known noun |
| Adjective agreement | des pommes rouge → rouges | Error | Lexique adjective forms |
| Look-alike words | comment cava → comment ça va | Error | Look-alike list |
| A or à | je vais a Paris → à, il à faim → a | Error | Accent rule, Lexique verb forms |
| Prepositions | à Canada → au Canada, je vais France → en France, en les montagnes → dans les montagnes, dépend sur → dépend de, en printemps → au printemps | Error | Country list, preposition list, place and en rules |
| Conjugation | je va → je vais, ils mange → ils mangent | Error | Conjugation rule, Lexique verb forms |
| Être or avoir | j'ai allé → je suis allé, il s'a trompé → il s'est trompé | Error | Auxiliary rule, Lexique participles |
| Participle agreement | il a mangée → mangé, elles sont allé → allées | Error | Participle rule, Lexique participles |
| Articles for things in general | j'aime fromage → j'aime le fromage | Error | Article rule, Lexique gender |
| Si clauses | si tu viendras → si tu viens, si j'avais le temps, je viendrai → je viendrais | Error | Si clause rule, Lexique verb forms |
| Future after quand | quand j'arrive demain, je t'appellerai → quand j'arriverai | Error | Future after quand rule, Lexique verb forms |
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
book button opens a phrasebook beside the editor: 676 complete phrases
in 17 situations, from greetings and the café to directions, travel
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

## Journal, Explain and postcards

Each entry is saved as an ordinary text file, so any text editor reads our
writing. **Back Up Journal…** in Settings writes every entry into one ZIP, plus a
small manifest of file names and dates; the format is the same on iPhone,
iPad and Mac. Restoring merges: it adds what's missing, skips what's
already there, and never changes or removes an entry, using **Restore from
Backup…**. If an entry of the
same name has different writing, the backup's version is kept beside it as
"(recovered)", and restoring the same backup twice adds nothing.

**Explain** reads a whole entry with Apple's on-device language model and
offers up to four phrases worth knowing, in the order they appear. It only
runs once the French has no errors, so it can't explain a mistake as if it
were right. Its notes are the model's, not the linter's rules.

**Share as Postcard** gathers an entry's painting, its French as written,
the English translation if there is one, and the date for the postmark.

## How it works

Every check reads the same text and reports issues, each with a severity
and a rule that names it. The part-of-speech layer runs first, because
several rules read its verdicts. The sections below follow the layers from
the first line of defence to the last: the system spellchecker, Quiver's
ranking, the tagged context, the phrase list and the gender model.

### Spelling and run-together words

The system spellchecker flags words it doesn't know and offers guesses.
Only guesses the Lexique lexicon knows are offered, because the Mac's French
spellchecker also returns English words ("fro" would otherwise become
"from"). A flagged word with no French guess is still underlined as a
warning, with no fix. Seeing the mistake comes first, and a name the system
doesn't know never blocks play.

The system never suggests a space, so "jesuis" comes back as "jésus". To
catch two or three words typed as one, we try every split point before the
guesses are ranked. A split qualifies when the first piece is a function
word (*je*, *me*, *ne*, *un*) or an elided letter before a vowel, and the
rest are lexicon words of three letters or more, or function words
themselves. When exactly one split qualifies we offer it, as a warning;
when several fit, we stay silent. Only if no two-word split exists do we
look for three words, as in "nemangepas" → "ne mange pas", "jemappelle" →
"je m'appelle" and "cestbon" → "c'est bon". There at least one of the later
pieces must be a function word, an elision or a common link such as *pas* or
*est*, which keeps two arbitrary lexicon words from qualifying.

The split steps aside when the system offers the same letters with accents
("demanger" for "démanger" is a missing accent, not "de manger"), and a
capitalized word in the middle of a sentence is read as a name and never
split.

### Quiver APIs used

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

### The part-of-speech layer

Nearly 30% of running French has more than one reading in Lexique,
and most of that is two-way. Before the rules run, each pass is tagged
once by small binary `LogisticRegression` deciders, and every rule reads
the verdicts instead of working out its neighbours by hand:

- article or pronoun, for le, la, les and l' ("je la porte");
- adjective or noun, for words Lexique lists as both (malade, jeune);
- helper or main verb, for avoir and être ("il a mangé", "il a faim");
- noun or verb, for words like demande and porte, so "la demande sur le
  site" never matches a pattern for the verb demander;
- *et* or *est*, which learners often swap, settled from the words around
  it rather than from which one was typed.

The first four share one recipe, `ContextDecider`: the five words around
the target and what Lexique says each can be. Each is one JSON file of
word lists and weights, trained in the Quiver Notebook
(`coquille-part-of-speech-model.swift`) on the Universal Dependencies
French treebanks. On held-out treebank text, at the 0.95 cutoff the
rules use, article or pronoun decides 97% of cases and is right on
99.8%; adjective or noun decides 54% and is right on 98.9%; helper or
main decides 73% and is right on 99.1%; noun or verb decides 67% and is
right on 98.8%. A word the decider isn't sure about gets no verdict, and the rules stay
silent. The *et* or *est* decider has its own model file,
`fr.et-est-model.json`, trained the same way.

### The phrase list

Every listed phrase lives in `fr.patterns.json`: look-alikes, word
choices, idioms, meaning questions and prepositions, one entry each. An
entry can name a verb instead of a form, so `@jouer le $sport` →
`@jouer au $sport` catches "nous jouons le foot" and "je jouais le
tennis" alike, and "@faire une décision" → "@prendre une décision" turns
"fait" into "prend", or "pris" after avoir.

Place names live in `fr.places.json`, nested country › region › city,
each with the article that settles its preposition (au Canada, en
France, aux États-Unis). Only the countries are judged for now; the
regions and cities wait for a French teacher's review.

The verb + preposition entries tagged `"origin": "UD treebanks"` are
generated by `swift Tools/BuildVerbPrepositions.swift ~/Projects/Resources
quiver-demo-coquille/LanguagePacks/French/fr.patterns.json`, which
counts which preposition each verb takes in the treebanks and keeps an
entry only when the flagged word pair never appears there. A rerun
replaces those entries and leaves the hand-written ones alone.

### The gender model

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

## How we know it's right

A narrow linter that's always right beats a broad one that cries wolf, so
we test the silences as hard as the catches. The test target holds more
than 450 XCTest cases: the false-positive traps above, correct French that
must pass clean, hostile `coquille://` links, calendar selection for the
daily prompt, and a check that every phrasebook phrase passes the whole
linter, platform spellchecker included, with no issues.

Each model is measured on text it never saw. The part-of-speech deciders
and the gender model report, at the cutoff the rules use, how often they
decide and how often they're right when they do. A word a model isn't sure
about gets no verdict, so the cost of an uncertain case is a missed
correction, never a wrong one. The scorecards for run-together words work
the same way: sentences written before the filter was built, run through
the real spellchecker, with traps for names and accent slips that must
not be split.

## Extend it

Most changes are data, not code. A new phrase is one entry in
`fr.phrases.json` with its situation, French, English, register and an
optional note. A new look-alike, word choice, idiom or preposition is one
entry in `fr.patterns.json`. A change to an explanation is a change to its
template in `fr.explanations.json`. The lexicon, the gender model and the
verb + preposition entries each rebuild with the commands in their
sections. A new two-way ambiguity is a new `ContextDecider` file trained in
the Quiver Notebook, with no code changes, and a model trained with a
different feature recipe is refused instead of mis-read. After any change,
run the tests: a rule that starts flagging correct French fails them.

## Widgets and exercise links

The `CoquilleWidgets` extension provides **Le tableau du jour**, a widget
that pairs each daily prompt with a painting, and one control, Écrire, on
iPhone, iPad and Mac. Add them through the system's widget gallery and
Control Center **+** flow.

The painting is always in full color. Small shows it with today's French
prompt; medium adds the English beneath the French; large adds the
painting's French title and **Cette semaine**, the week's paintings from
Monday to Sunday with today ringed. iPad and the Mac desktop add extra
large: the painting on the left, with the prompt and a two-row week beside
it. On iPhone and iPad the Lock Screen gets a rectangular prompt and a
circular pencil-and-scribble mark, and StandBy on iPhone shows the small
face full screen. Tapping anywhere opens today's prompt as an unsaved draft. The prompt
changes on the local calendar day, including across daylight-saving
changes, and everything works offline. Écrire, which can sit in Control
Center, on the Lock Screen or on the Action Button, carries on with the
writing already open, or starts today's entry with the keyboard up.

The 142 paintings are originals made for Coquille, grouped in 18 themes, and
they belong to the app. Each ships in `Prompts/Paintings.xcassets` as
`Tableau-<slug>`, pre-sized to 700 px, and there are 14 daily prompts to pair
them with. The full-size originals live outside the repo in
`~/Projects/Resources/coquille-paintings/`; a new or revised painting is
resized with `sips -Z 700` into its imageset.

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
- `PartOfSpeech/` — the five deciders and the tagger that runs before the rules.
- `Journal/` — saved entries, rename, and backup and restore as a ZIP.
- `Welcome/`, `Settings/`, `About/` — the first-run tour, Settings and the About dialog.
- `Paintings/` — the paintings' views and the postcard.
- `Phrasebook/` — the phrase model, the Quiver-backed search and the
  phrasebook view.
- `Speech/`, `Translation/`, `Stats/`, `Editor/` — playback, on-device
  translation, the learner's progress (stored only on the device) and
  the SwiftUI views.
- `Prompts/`, `Exercises/` — the daily catalog, strict custom-URL router,
  exercise confirmation, and optional hint presentation.
- `CoquilleWidgets/` — Le tableau du jour, its paintings and the Control
  Center controls, with shared prompt code but no Quiver dependency.
- `Fonts/` — IBM Plex Sans and Mono, registered at app launch and declared
  under `UIAppFonts` for the widget process.
- `Tools/BuildLexicon.swift` — rebuilds the lexicon from the full
  Lexique table, applying `Tools/fr.noun-gender-overrides.json` and
  `Tools/fr.adjective-overrides.json`.
- `quiver-demo-coquilleTests/` — more than 450 XCTest cases, including the
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

