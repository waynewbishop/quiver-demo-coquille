// Builds the noun list the gender model trains on, from the full Lexique 3.83 table.
//
// Usage:
//   swift Tools/BuildGenderNouns.swift /path/to/Lexique383.tsv Tools/fr.gender-nouns.csv
//
// Each row is one singular noun and whether it is feminine (1) or masculine (0).
// Nouns Lexique lists with both genders (le livre, la livre) are left out, since
// their ending can't decide them. The gender is a 1/0 number rather than "f"/"m",
// because the Notebook's CSV loader numbers text labels alphabetically, which would
// make feminine 0 instead of the 1 the app expects. The output is derived from
// Lexique and so carries Lexique's CC BY-SA 4.0 license.

import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: swift BuildGenderNouns.swift <Lexique383.tsv> <output.csv>\n".utf8))
    exit(1)
}

let table = try String(contentsOf: URL(fileURLWithPath: arguments[1]), encoding: .utf8)
// Lexique uses CRLF line endings, so split on any newline rather than on "\n" alone.
var lines = table.split(whereSeparator: \.isNewline)
let header = lines.removeFirst().split(separator: "\t", omittingEmptySubsequences: false).map(String.init)

/// Returns the position of a named Lexique column, stopping if the table layout changed.
func column(_ name: String) -> Int {
    guard let index = header.firstIndex(of: name) else {
        FileHandle.standardError.write(Data("missing column \(name)\n".utf8))
        exit(1)
    }
    return index
}

let orthoColumn = column("ortho")
let categoryColumn = column("cgram")
let genderColumn = column("genre")
let numberColumn = column("nombre")

// Every gender Lexique gives each singular noun spelling.
var genders: [String: Set<String>] = [:]

for line in lines {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard fields.count == header.count, fields[categoryColumn] == "NOM" else { continue }
    let noun = fields[orthoColumn]
    // Plurals would teach the model that -s means nothing; the app only checks singular articles.
    guard fields[numberColumn] != "p", noun.allSatisfy(\.isLetter) else { continue }
    let gender = fields[genderColumn]
    genders[noun, default: []].insert(gender.isEmpty ? "x" : gender)
}

var csv = "noun,feminine\n"
var feminineCount = 0
var masculineCount = 0
for noun in genders.keys.sorted() {
    guard let only = genders[noun], only.count == 1, let gender = only.first, gender != "x" else { continue }
    let feminine = gender == "f" ? 1 : 0
    csv += "\(noun),\(feminine)\n"
    if feminine == 1 { feminineCount += 1 } else { masculineCount += 1 }
}

try csv.write(to: URL(fileURLWithPath: arguments[2]), atomically: true, encoding: .utf8)
print("nouns \(feminineCount + masculineCount) · feminine \(feminineCount) · masculine \(masculineCount)")
