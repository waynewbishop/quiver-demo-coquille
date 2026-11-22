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

@MainActor
final class ZipArchiveTests: XCTestCase {

    /// A whole-second date, since ZIP files keep time to two seconds.
    private let modified = Date(timeIntervalSince1970: 1_790_000_000)

    // The checksum matches the standard value for "123456789".
    func testChecksumMatchesTheStandardValue() {
        XCTAssertEqual(ZipArchive.crc32(Array("123456789".utf8)), 0xCBF4_3926)
    }

    // Files come back with their names, text and times, accents included.
    func testRoundTrip() throws {
        let members = [
            ZipArchive.Member(name: "entries/2026-11-14 Au café.txt", modified: modified, data: Data("Il pleut à Paris.".utf8)),
            ZipArchive.Member(name: "manifest.json", modified: modified, data: Data("{}".utf8)),
            ZipArchive.Member(name: "entries/vide.txt", modified: modified, data: Data())
        ]
        let contents = try ZipArchive.read(try ZipArchive.write(members))
        XCTAssertEqual(contents.damaged, [])
        XCTAssertEqual(contents.members.map(\.name), members.map(\.name))
        XCTAssertEqual(contents.members.map(\.data), members.map(\.data))
        for member in contents.members {
            XCTAssertEqual(member.modified.timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 2)
        }
    }

    // An archive with no files is valid.
    func testEmptyArchive() throws {
        let contents = try ZipArchive.read(try ZipArchive.write([]))
        XCTAssertTrue(contents.members.isEmpty)
        XCTAssertTrue(contents.damaged.isEmpty)
    }

    // A file whose bytes changed is reported by name, and the others still come out.
    func testDamagedFileIsReportedAndOthersRead() throws {
        let archive = try ZipArchive.write([
            ZipArchive.Member(name: "a.txt", modified: modified, data: Data("Il pleut.".utf8)),
            ZipArchive.Member(name: "b.txt", modified: modified, data: Data("Il neige.".utf8))
        ])
        let range = try XCTUnwrap(archive.range(of: Data("Il pleut.".utf8)))
        var tampered = archive
        tampered[range.lowerBound] ^= 0xFF

        let contents = try ZipArchive.read(tampered)
        XCTAssertEqual(contents.damaged, ["a.txt"])
        XCTAssertEqual(contents.members.map(\.name), ["b.txt"])
    }

    // Things that aren't archives are refused, not guessed at.
    func testNotAnArchive() {
        for data in [Data(), Data("hello".utf8), Data(repeating: 0x50, count: 100)] {
            XCTAssertThrowsError(try ZipArchive.read(data)) { error in
                XCTAssertEqual(error as? ZipArchive.Failure, .notAnArchive)
            }
        }
    }

    // An archive cut short loses its directory and is refused.
    func testTruncatedArchive() throws {
        let archive = try ZipArchive.write([ZipArchive.Member(name: "a.txt", modified: modified, data: Data("Il pleut.".utf8))])
        XCTAssertThrowsError(try ZipArchive.read(archive.prefix(archive.count / 2)))
    }

    // Compressed files, as the Finder and other tools write them, are read too.
    func testReadsDeflateCompressedFiles() throws {
        let text = String(repeating: "Il pleut à Paris. ", count: 40)
        let raw = Data(text.utf8)
        let packed = try (raw as NSData).compressed(using: .zlib) as Data
        let name = Array("compressed.txt".utf8)
        let checksum = ZipArchive.crc32(Array(raw))

        func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
        func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16((value >> 16) & 0xFFFF) }

        var archive = le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(8) + le16(0) + le16(0x21)
        archive += le32(Int(checksum)) + le32(packed.count) + le32(raw.count) + le16(name.count) + le16(0) + name
        archive += [UInt8](packed)
        let directoryOffset = archive.count
        var directory = le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(8) + le16(0) + le16(0x21)
        directory += le32(Int(checksum)) + le32(packed.count) + le32(raw.count) + le16(name.count)
        directory += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + name
        archive += directory
        archive += le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1) + le32(directory.count) + le32(directoryOffset) + le16(0)

        let contents = try ZipArchive.read(Data(archive))
        XCTAssertEqual(contents.damaged, [])
        XCTAssertEqual(contents.members.map(\.name), ["compressed.txt"])
        XCTAssertEqual(contents.members.first?.data, raw)
    }

    // The writer refuses a total the reader would refuse.
    func testWriterRefusesMoreThanTheReaderAllows() {
        let chunk = Data(count: ZipArchive.maximumFileSize)
        let members = (0..<5).map { ZipArchive.Member(name: "\($0).txt", modified: modified, data: chunk) }
        XCTAssertThrowsError(try ZipArchive.write(members)) { error in
            XCTAssertEqual(error as? ZipArchive.Failure, .tooLarge)
        }
    }

    // Compressed output longer than its declared size is damaged, not read in full.
    func testDeflateLongerThanDeclaredIsDamaged() throws {
        let raw = Data(String(repeating: "Il pleut. ", count: 200).utf8)
        let packed = try (raw as NSData).compressed(using: .zlib) as Data
        let name = Array("lie.txt".utf8)
        let checksum = ZipArchive.crc32(Array(raw))
        let declared = 10

        func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
        func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16((value >> 16) & 0xFFFF) }

        var archive = le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(8) + le16(0) + le16(0x21)
        archive += le32(Int(checksum)) + le32(packed.count) + le32(declared) + le16(name.count) + le16(0) + name
        archive += [UInt8](packed)
        let directoryOffset = archive.count
        var directory = le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(8) + le16(0) + le16(0x21)
        directory += le32(Int(checksum)) + le32(packed.count) + le32(declared) + le16(name.count)
        directory += le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + name
        archive += directory
        archive += le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1) + le32(directory.count) + le32(directoryOffset) + le16(0)

        let contents = try ZipArchive.read(Data(archive))
        XCTAssertEqual(contents.damaged, ["lie.txt"])
        XCTAssertTrue(contents.members.isEmpty)
    }
}
