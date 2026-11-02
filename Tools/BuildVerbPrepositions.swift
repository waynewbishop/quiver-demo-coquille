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

// Generates the verb + preposition entries in fr.patterns.json from correct French.
// Usage:
//   swift Tools/BuildVerbPrepositions.swift ~/Projects/Resources quiver-demo-coquille/LanguagePacks/French/fr.patterns.json
//
// Which preposition a verb takes is a fact about the verb: dépendre takes de, téléphoner
// takes à, essayer takes de before an infinitive. The Universal Dependencies French
// treebanks (GSD, Rhapsodie, ParisStories; CC BY-SA 4.0) record it: each argument the
// verb governs (obl:arg, iobj) or infinitive it introduces (xcomp with a mark) names its
// preposition. The script counts those per verb and writes three kinds of entry:
//
//   wrong preposition before an infinitive   "essaie à faire" → "essaie de faire"
//   wrong preposition before a noun          "dépend sur" → "dépend de"
//   missing preposition before a possessive  "téléphone ma mère" → "téléphone à ma mère"
//
// An entry is written only when the verb is frequent enough, one preposition dominates,
// and the flagged word pair never appears anywhere in the treebanks, so no correct
// sentence in them would be flagged. Entries are tagged "origin": "UD treebanks"; a rerun
// replaces those and leaves every hand-written entry alone.

import Foundation

// MARK: - Settings

/// The fewest times a verb must show the construction before its counts are trusted.
let minimumSupport = 8
/// The share one preposition must have among the verb's arguments.
let minimumShare = 0.9
/// The preposition English speakers put where French wants another: "on" (depend on, count on).
/// À, de, dans, avec and pour also open ordinary phrases after almost any verb ("participer avec
/// ses amis", "parvenu dans la soirée"), so they would flag correct French.
let substitutes = ["sur"]
let possessives = ["mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "votre", "nos", "vos", "leur", "leurs"]

// MARK: - Read the treebanks

struct Word {
    let id: Int
    let text: String
    let lemma: String
    let tag: String
    let features: String
    let head: Int
    let relation: String
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("Usage: swift Tools/BuildVerbPrepositions.swift <Resources folder> <fr.patterns.json>")
    exit(1)
}
let resources = NSString(string: arguments[1]).expandingTildeInPath
let patternsPath = arguments[2]
let treebanks = [
    "UD_French-GSD/fr_gsd", "UD_French-Rhapsodie/fr_rhapsodie", "UD_French-ParisStories/fr_parisstories"
].flatMap { base in ["train", "dev", "test"].map { "\(resources)/\(base)-ud-\($0).conllu" } }

/// Reads one CoNLL-U file into sentences. Contractions keep their parts ("au" is à + le),
/// because the dependencies name the parts; `surface` keeps what a learner would see.
func sentences(in path: String) -> [(words: [Word], surface: [String])] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("Couldn't read \(path). Download it from Universal Dependencies.")
        exit(1)
    }
    var result: [(words: [Word], surface: [String])] = []
    var words: [Word] = []
    var surface: [String] = []
    var skipThrough = 0
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.isEmpty {
            if !words.isEmpty { result.append((words, surface)) }
            words = []
            surface = []
            skipThrough = 0
            continue
        }
        if line.hasPrefix("#") { continue }
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count > 7 else { continue }
        if columns[0].contains(".") { continue }
        if columns[0].contains("-") {
            skipThrough = Int(columns[0].split(separator: "-")[1]) ?? 0
            surface.append(columns[1].lowercased())
            continue
        }
        guard let id = Int(columns[0]) else { continue }
        if id > skipThrough { surface.append(columns[1].lowercased()) }
        words.append(Word(
            id: id, text: columns[1].lowercased(), lemma: columns[2].lowercased(), tag: columns[3],
            features: columns[5], head: Int(columns[6]) ?? -1, relation: columns[7]
        ))
    }
    return result
}

let corpus = treebanks.flatMap(sentences(in:))
print(corpus.count, "sentences")

// MARK: - Count each verb's constructions

var directObjects: [String: Int] = [:]
var nounPrepositions: [String: [String: Int]] = [:]
var infinitivePrepositions: [String: [String: Int]] = [:]
var forms: [String: Set<String>] = [:]
var occurrences: [String: Int] = [:]
/// How often each verb appears with a reflexive se, as in "il s'agit de".
var reflexive: [String: Int] = [:]
/// Every adjacent pair of surface words, to veto any entry that would fire on correct French.
var pairs = Set<String>()

for (words, surface) in corpus {
    for index in surface.indices.dropLast() {
        pairs.insert(surface[index] + " " + surface[index + 1])
    }
    var children: [Int: [Word]] = [:]
    for word in words { children[word.head, default: []].append(word) }
    for verb in words where verb.tag == "VERB" {
        forms[verb.lemma, default: []].insert(verb.text)
        occurrences[verb.lemma, default: 0] += 1
        if (children[verb.id] ?? []).contains(where: { $0.relation.hasPrefix("expl") }) {
            reflexive[verb.lemma, default: 0] += 1
        }
        for child in children[verb.id] ?? [] {
            let grandchildren = children[child.id] ?? []
            switch child.relation {
            case "obj":
                // A clitic object ("je le vois") counts too: the verb takes one directly.
                directObjects[verb.lemma, default: 0] += 1
            case "iobj":
                // "je lui téléphone": an indirect clitic stands for à + a person.
                nounPrepositions[verb.lemma, default: [:]]["à", default: 0] += 1
            case "obl:arg":
                if let preposition = grandchildren.first(where: { $0.relation == "case" })?.lemma {
                    nounPrepositions[verb.lemma, default: [:]][preposition, default: 0] += 1
                }
            case "xcomp" where child.features.contains("VerbForm=Inf"):
                let mark = grandchildren.first { $0.relation == "mark" }?.lemma ?? "∅"
                infinitivePrepositions[verb.lemma, default: [:]][mark, default: 0] += 1
            default:
                break
            }
        }
    }
}

/// The preposition with at least `minimumShare` of `counts`, if any, and how often it appears.
func dominant(_ counts: [String: Int]?) -> (preposition: String, count: Int, total: Int)? {
    guard let counts, let top = counts.max(by: { $0.value < $1.value }) else { return nil }
    let total = counts.values.reduce(0, +)
    guard total >= minimumSupport, Double(top.value) / Double(total) >= minimumShare else { return nil }
    return (top.key, top.value, total)
}

/// Whether the verb is mostly reflexive ("s'agir de", "s'emparer de"), so its counts describe
/// the reflexive verb, which a pattern on the bare verb would misread.
func isMostlyReflexive(_ verb: String) -> Bool {
    Double(reflexive[verb] ?? 0) > 0.5 * Double(occurrences[verb] ?? 1)
}

/// Whether any form of `verb` is followed by `next` anywhere in the treebanks.
func appears(_ verb: String, before next: String) -> Bool {
    (forms[verb] ?? []).contains { pairs.contains($0 + " " + next) }
}

// MARK: - Write entries

var entries: [[String: Any]] = []
var report: [String] = []

for verb in infinitivePrepositions.keys.sorted() {
    guard !isMostlyReflexive(verb),
          let top = dominant(infinitivePrepositions[verb]), ["à", "de"].contains(top.preposition) else { continue }
    let wrong = top.preposition == "à" ? "de" : "à"
    guard !appears(verb, before: wrong) else { continue }
    entries.append([
        "kind": "preposition", "match": "@\(verb) \(wrong)", "fix": "@\(verb) \(top.preposition)",
        "onlyBeforeInfinitive": true, "origin": "UD treebanks",
        "note": "Before an infinitive, \(verb) takes \(top.preposition): \(top.count) of \(top.total) times in the treebanks."
    ])
    report.append("\(verb) + \(top.preposition) + infinitive (\(top.count)/\(top.total)); flags \(wrong)")
}

for verb in nounPrepositions.keys.sorted() {
    guard !isMostlyReflexive(verb), let top = dominant(nounPrepositions[verb]) else { continue }
    let objects = directObjects[verb] ?? 0
    // A verb that also takes a direct object often ("parler français") isn't settled by its preposition.
    guard Double(objects) <= 0.1 * Double(top.total) else { continue }
    for wrong in substitutes where wrong != top.preposition && !appears(verb, before: wrong) {
        entries.append([
            "kind": "preposition", "match": "@\(verb) \(wrong)", "fix": "@\(verb) \(top.preposition)",
            "unlessBeforeInfinitive": true, "origin": "UD treebanks",
            "note": "\(verb.capitalized) takes \(top.preposition) before what it's about: \(top.count) of \(top.total) times in the treebanks."
        ])
        report.append("\(verb) + \(top.preposition) (\(top.count)/\(top.total)); flags \(wrong)")
    }
    // "téléphoner ma mère": a verb that never takes a direct object needs its preposition.
    if objects == 0, ["à", "de"].contains(top.preposition), !possessives.contains(where: { appears(verb, before: $0) }) {
        entries.append([
            "kind": "preposition", "match": "@\(verb) $possessive", "fix": "@\(verb) \(top.preposition) $possessive",
            "origin": "UD treebanks",
            "note": "\(verb.capitalized) takes \(top.preposition) before a person or thing: \(top.count) of \(top.total) times in the treebanks, never a direct object."
        ])
        report.append("\(verb) + \(top.preposition), no direct object (\(top.total)); flags a missing \(top.preposition)")
    }
}

// The verbs learners use most, and what the treebanks say about them, so the hand-written
// entries can cover what the counts can't settle.
for verb in ["téléphoner", "dépendre", "essayer", "commencer", "décider", "oublier", "répondre", "ressembler",
             "écouter", "attendre", "chercher", "demander", "obéir", "jouer", "rêver", "souvenir", "intéresser"] {
    print("  check \(verb): \(occurrences[verb] ?? 0) uses, objects \(directObjects[verb] ?? 0),",
          "nouns \(nounPrepositions[verb] ?? [:]), infinitives \(infinitivePrepositions[verb] ?? [:])")
}
print(entries.count, "entries")
for line in report { print("  " + line) }

// MARK: - Merge into fr.patterns.json

guard let data = FileManager.default.contents(atPath: patternsPath),
      var file = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let existing = file["entries"] as? [[String: Any]] else {
    print("Couldn't read \(patternsPath)")
    exit(1)
}
let handWritten = existing.filter { ($0["origin"] as? String) != "UD treebanks" }
file["entries"] = handWritten + entries
var classes = file["classes"] as? [String: Any] ?? [:]
classes["possessive"] = possessives
file["classes"] = classes
let output = try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try output.write(to: URL(fileURLWithPath: patternsPath))
print("Wrote \(handWritten.count) hand-written and \(entries.count) generated entries to \(patternsPath)")
