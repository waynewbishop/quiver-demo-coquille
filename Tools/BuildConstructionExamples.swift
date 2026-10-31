// Builds the Phase 1 French construction dataset without app dependencies.
//
// Usage (from the repository root):
//   swift Tools/BuildConstructionExamples.swift
//
// Reads fr.phrases.json, fr.lexicon.json and Tools/fr.construction-seed.json,
// then writes Tools/fr.construction-examples.csv. The seed adds clean examples
// from FrenchGrammarTests, its explanation strings, and targeted hard negatives.
// Labels are inferred from lexicon entries and surface cues. Each deterministic
// corruption inherits its clean source's labels and stable text-derived group ID.

import Foundation

struct Phrase: Decodable {
    let french: String
}

struct Seed: Decodable {
    let text: String
    let source: String
}

struct Lexicon: Decodable {
    let participles: [String: [[String]]]
    let conjugations: [String: [[String]]]
}

struct Token {
    let text: String
    let folded: String
    let range: Range<String.Index>
}

struct Labels {
    var pastTense = 0
    var planWithAller = 0
    var negation = 0
    var question = 0

    var values: [Int] { [pastTense, planWithAller, negation, question] }
}

struct Compound {
    let auxiliaryIndex: Int
    let participleIndex: Int
    let auxiliaryLemma: String
    let participleLemma: String
}

struct Row {
    let text: String
    let group: String
    let labels: Labels
    let kind: String
}

func load<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: URL(fileURLWithPath: path)))
}

func tokens(in text: String) -> [Token] {
    var result: [Token] = []
    var index = text.startIndex
    while index < text.endIndex {
        guard text[index].isLetter else {
            index = text.index(after: index)
            continue
        }
        let start = index
        repeat { index = text.index(after: index) } while index < text.endIndex && text[index].isLetter
        let word = String(text[start..<index])
        result.append(Token(text: word, folded: word.lowercased(), range: start..<index))
    }
    return result
}

func entries(_ word: String, in table: [String: [[String]]]) -> [[String]] {
    table[word] ?? []
}

func isFiniteForm(_ word: String, _ lemma: String, in lexicon: Lexicon) -> Bool {
    entries(word, in: lexicon.conjugations).contains { $0.count >= 2 && $0[0] == lemma }
}

let etreAuxiliaryVerbs: Set<String> = [
    "aller", "apparaître", "arriver", "descendre", "devenir", "entrer", "monter",
    "mourir", "naître", "partir", "passer", "rentrer", "rester", "retourner",
    "revenir", "sortir", "tomber", "venir"
]

let compoundAdverbs: Set<String> = [
    "bien", "déjà", "encore", "jamais", "mieux", "pas", "plus", "souvent", "tout", "trop"
]

func hasClauseBreak(_ text: String, _ left: Token, _ right: Token) -> Bool {
    text[left.range.upperBound..<right.range.lowerBound].contains { ",;:.!?".contains($0) }
}

func findCompound(in text: String, _ words: [Token], lexicon: Lexicon) -> Compound? {
    for i in words.indices {
        let auxiliary = words[i].folded
        let auxiliaryLemma = ["avoir", "être"].first {
            isFiniteForm(auxiliary, $0, in: lexicon)
        }
        guard let auxiliaryLemma else { continue }

        for j in (i + 1)..<min(i + 7, words.count) {
            let candidate = words[j]
            if hasClauseBreak(text, words[j - 1], candidate) { break }
            if ["tu", "plus"].contains(candidate.folded) { continue }
            if candidate.folded == "vue", j + 1 < words.count, words[j + 1].folded == "sur" { break }
            if let participle = entries(candidate.folded, in: lexicon.participles).first,
               participle.count >= 2 {
                return Compound(
                    auxiliaryIndex: i,
                    participleIndex: j,
                    auxiliaryLemma: auxiliaryLemma,
                    participleLemma: participle[0]
                )
            }
            if entries(candidate.folded, in: lexicon.conjugations).isEmpty == false,
               compoundAdverbs.contains(candidate.folded) == false {
                break
            }
        }
    }
    return nil
}

func isReflexiveCompound(_ words: [Token], auxiliaryIndex: Int) -> Bool {
    guard auxiliaryIndex > 0 else { return false }
    let previous = words[auxiliaryIndex - 1].folded
    if ["me", "m", "se", "s"].contains(previous) { return true }
    guard ["nous", "vous"].contains(previous), auxiliaryIndex > 1 else { return false }
    return words[auxiliaryIndex - 2].folded == previous
}

func isCompoundPast(_ compound: Compound, _ words: [Token]) -> Bool {
    compound.auxiliaryLemma == "avoir"
        || etreAuxiliaryVerbs.contains(compound.participleLemma)
        || isReflexiveCompound(words, auxiliaryIndex: compound.auxiliaryIndex)
}

func infinitives(in lexicon: Lexicon) -> Set<String> {
    var result = Set<String>()
    for table in [lexicon.participles, lexicon.conjugations] {
        for values in table.values {
            for entry in values where entry.isEmpty == false {
                result.insert(entry[0])
            }
        }
    }
    return result
}

func hasAllerPlan(_ words: [Token], infinitives: Set<String>, lexicon: Lexicon) -> Bool {
    let allowedBetween: Set<String> = [
        "en", "la", "le", "les", "leur", "lui", "me", "m", "ne", "n", "nous",
        "pas", "se", "s", "te", "tu", "vous", "y"
    ]
    for i in words.indices where isFiniteForm(words[i].folded, "aller", in: lexicon) {
        guard entries(words[i].folded, in: lexicon.conjugations).contains(where: {
            $0.count >= 2 && $0[0] == "aller" && $0[1].split(separator: " ").contains { $0.hasPrefix("ip") }
        }) else { continue }
        for j in (i + 1)..<min(i + 5, words.count) {
            let word = words[j].folded
            if infinitives.contains(word) { return true }
            if allowedBetween.contains(word) == false { break }
        }
    }
    return false
}

func labels(for text: String, lexicon: Lexicon, infinitives: Set<String>) -> Labels {
    let words = tokens(in: text)
    let compound = findCompound(in: text, words, lexicon: lexicon)
    let compoundIsPast = compound.map { isCompoundPast($0, words) } ?? false
    return Labels(
        pastTense: compoundIsPast ? 1 : 0,
        planWithAller: hasAllerPlan(words, infinitives: infinitives, lexicon: lexicon) ? 1 : 0,
        negation: words.contains { ["ne", "n", "pas", "jamais", "rien"].contains($0.folded) } ? 1 : 0,
        question: text.contains("?") ? 1 : 0
    )
}

func wrongAuxiliary(in text: String, _ words: [Token], _ compound: Compound) -> String? {
    guard compound.auxiliaryLemma == "être",
          etreAuxiliaryVerbs.contains(compound.participleLemma),
          compound.auxiliaryIndex > 0 else { return nil }
    let subject = words[compound.auxiliaryIndex - 1]
    let auxiliary = words[compound.auxiliaryIndex].folded
    let replacement: String
    switch (subject.folded, auxiliary) {
    case ("je", "suis"):
        replacement = subject.text.first == "J" ? "J'ai" : "j'ai"
    case ("tu", "es"):
        replacement = "\(subject.text) as"
    case ("il", "est"), ("elle", "est"), ("on", "est"):
        replacement = "\(subject.text) a"
    case ("nous", "sommes"):
        replacement = "\(subject.text) avons"
    case ("vous", "êtes"):
        replacement = "\(subject.text) avez"
    case ("ils", "sont"), ("elles", "sont"):
        replacement = "\(subject.text) ont"
    default:
        return nil
    }
    var result = text
    result.replaceSubrange(subject.range.lowerBound..<words[compound.auxiliaryIndex].range.upperBound, with: replacement)
    return result
}

func infinitiveForParticiple(in text: String, _ words: [Token], _ compound: Compound) -> String {
    var result = text
    result.replaceSubrange(words[compound.participleIndex].range, with: compound.participleLemma)
    return result
}

func missingEtreAfterAller(in text: String, _ words: [Token], _ compound: Compound) -> String? {
    guard compound.auxiliaryLemma == "être", compound.participleLemma == "aller",
          compound.auxiliaryIndex > 0 else { return nil }
    let subject = words[compound.auxiliaryIndex - 1].folded
    guard ["je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles"].contains(subject) else {
        return nil
    }
    var result = text
    result.replaceSubrange(words[compound.auxiliaryIndex].range, with: "")
    return result.replacingOccurrences(of: "  ", with: " ")
}

func missingPlanEtre(in text: String, _ words: [Token], lexicon: Lexicon) -> String? {
    let allowedBetween: Set<String> = ["ne", "n", "pas", "tu", "y"]
    for i in words.indices where isFiniteForm(words[i].folded, "aller", in: lexicon) {
        for j in (i + 1)..<min(i + 5, words.count) {
            let word = words[j]
            if word.folded == "être" {
                var result = text
                result.replaceSubrange(word.range, with: "")
                return result.replacingOccurrences(of: "  ", with: " ")
            }
            if !allowedBetween.contains(word.folded) { break }
        }
    }
    return nil
}

func missingNegationMarker(in text: String, _ words: [Token]) -> String? {
    guard let i = words.firstIndex(where: { $0.folded == "ne" || $0.folded == "n" }) else { return nil }
    let marker = words[i]
    var result = text
    if marker.folded == "ne" {
        let end = i + 1 < words.count ? words[i + 1].range.lowerBound : marker.range.upperBound
        result.replaceSubrange(marker.range.lowerBound..<end, with: "")
    } else {
        guard i + 1 < words.count else { return nil }
        let next = words[i + 1]
        if i > 0, ["je", "ce"].contains(words[i - 1].folded) {
            let previous = words[i - 1]
            let initial = previous.text.prefix(1)
            result.replaceSubrange(previous.range.lowerBound..<next.range.lowerBound, with: initial + "'")
        } else {
            result.replaceSubrange(marker.range.lowerBound..<next.range.lowerBound, with: "")
        }
    }
    return result
}

let accentReplacements: [Character: Character] = [
    "à": "a", "â": "a", "ä": "a", "ç": "c", "é": "e", "è": "e", "ê": "e", "ë": "e",
    "î": "i", "ï": "i", "ô": "o", "ö": "o", "ù": "u", "û": "u", "ü": "u", "ÿ": "y",
    "À": "A", "Â": "A", "Ä": "A", "Ç": "C", "É": "E", "È": "E", "Ê": "E", "Ë": "E",
    "Î": "I", "Ï": "I", "Ô": "O", "Ö": "O", "Ù": "U", "Û": "U", "Ü": "U", "Ÿ": "Y"
]

func droppedAccent(in text: String) -> String? {
    guard let index = text.firstIndex(where: { accentReplacements[$0] != nil }),
          let replacement = accentReplacements[text[index]] else { return nil }
    var result = text
    result.replaceSubrange(index...index, with: String(replacement))
    return result
}

func groupID(for text: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1099511628211
    }
    return String(format: "g%016llx", hash)
}

func csvField(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

let phrasePath = "quiver-demo-coquille/LanguagePacks/French/fr.phrases.json"
let lexiconPath = "quiver-demo-coquille/LanguagePacks/French/fr.lexicon.json"
let seedPath = "Tools/fr.construction-seed.json"
let outputPath = "Tools/fr.construction-examples.csv"

let phrases = try load([Phrase].self, phrasePath)
let seeds = try load([Seed].self, seedPath)
let lexicon = try load(Lexicon.self, lexiconPath)
let allInfinitives = infinitives(in: lexicon)
let cleanTexts = Set(phrases.map(\.french) + seeds.map(\.text)).sorted()

var rows: [Row] = []
var groupOwners: [String: String] = [:]
var corruptionCounts: [String: Int] = [:]

for clean in cleanTexts {
    let group = groupID(for: clean)
    if let owner = groupOwners[group], owner != clean {
        FileHandle.standardError.write(Data("group ID collision: \(owner) / \(clean)\n".utf8))
        exit(1)
    }
    groupOwners[group] = clean

    let cleanLabels = labels(for: clean, lexicon: lexicon, infinitives: allInfinitives)
    rows.append(Row(text: clean, group: group, labels: cleanLabels, kind: "clean"))
    let words = tokens(in: clean)
    let compound = findCompound(in: clean, words, lexicon: lexicon)
    let compoundIsPast = compound.map { isCompoundPast($0, words) } ?? false

    var variants: [(String, String)] = []
    if let compound, compoundIsPast {
        if let corrupted = wrongAuxiliary(in: clean, words, compound) {
            variants.append((corrupted, "wrongAuxiliary"))
        }
        variants.append((infinitiveForParticiple(in: clean, words, compound), "infinitiveForParticiple"))
        if let corrupted = missingEtreAfterAller(in: clean, words, compound) {
            variants.append((corrupted, "missingEtreAfterAller"))
        }
    }
    if let corrupted = missingPlanEtre(in: clean, words, lexicon: lexicon) {
        variants.append((corrupted, "missingPlanEtre"))
    }
    if let corrupted = missingNegationMarker(in: clean, words) {
        variants.append((corrupted, "missingNe"))
    }
    if let corrupted = droppedAccent(in: clean) {
        variants.append((corrupted, "droppedAccent"))
    }

    var seen = Set<String>([clean])
    for (text, kind) in variants where text != clean && seen.insert(text).inserted {
        rows.append(Row(text: text, group: group, labels: cleanLabels, kind: kind))
        corruptionCounts[kind, default: 0] += 1
    }
}

var csv = "text,group,kind,pastTense,planWithAller,negation,question\n"
for row in rows {
    let fields = [csvField(row.text), csvField(row.group), csvField(row.kind)] + row.labels.values.map(String.init)
    csv += fields.joined(separator: ",") + "\n"
}
try csv.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)

let labelNames = ["pastTense", "planWithAller", "negation", "question"]
let classCounts = (0..<4).map { label in rows.reduce(0) { $0 + $1.labels.values[label] } }
let allZero = rows.filter { $0.labels.values.allSatisfy { $0 == 0 } }.count
let multiLabel = rows.filter { $0.labels.values.reduce(0, +) > 1 }.count
let cleanCount = rows.filter { $0.kind == "clean" }.count

print("rows \(rows.count) · clean \(cleanCount) · corrupted \(rows.count - cleanCount) · groups \(groupOwners.count)")
print("classes " + labelNames.enumerated().map { "\($1)=\(classCounts[$0])" }.joined(separator: " · "))
print("label shapes allZero=\(allZero) · multiLabel=\(multiLabel)")
print("corruptions " + ["wrongAuxiliary", "infinitiveForParticiple", "droppedAccent", "missingNe", "missingEtreAfterAller", "missingPlanEtre"].map {
    "\($0)=\(corruptionCounts[$0, default: 0])"
}.joined(separator: " · "))
print("wrote \(outputPath)")
