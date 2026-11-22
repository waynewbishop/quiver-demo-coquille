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

import Compression
import Foundation

/// A small ZIP reader and writer, so a journal backup is a standard archive that the Finder,
/// the Files app and any unzip tool can open, without adding a dependency.
///
/// It writes every file uncompressed, which suits short text and keeps the format simple.
/// It reads uncompressed files and the deflate compression the Finder and most tools use.
/// Archives over 4 GB, with more than 65,535 files, or with passwords aren't supported.
nonisolated enum ZipArchive {

    /// One file in an archive: its path, when it was last changed, and its bytes.
    struct Member: Equatable {
        let name: String
        let modified: Date
        let data: Data
    }

    /// What reading an archive found: the files that came out whole, and the names of
    /// those that were damaged or use something this reader doesn't support.
    struct Contents {
        var members: [Member] = []
        var damaged: [String] = []
    }

    /// Why an archive couldn't be written or read at all.
    enum Failure: LocalizedError, Equatable {
        case notAnArchive
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .notAnArchive: "This isn't a ZIP archive, or it's damaged."
            case .tooLarge: "This is too large to handle."
            }
        }
    }

    /// The most one file may expand to, and the most the whole archive may, so a small
    /// crafted archive can't use all the device's memory.
    static let maximumFileSize = 64 * 1024 * 1024
    static let maximumTotalSize = 256 * 1024 * 1024
    /// The largest archive file: the most the files can hold plus room for the headers,
    /// which take about 700 bytes a file at the most, for at most 65,535 files. `write`
    /// refuses to go past it, so every archive it makes passes the same check on reading.
    static let maximumArchiveSize = maximumTotalSize + 0xFFFF * 700

    // MARK: - Writing

    /// Builds an archive holding `members`, in order.
    static func write(_ members: [Member]) throws -> Data {
        guard members.count <= 0xFFFF else { throw Failure.tooLarge }

        // Refuse anything `read` would refuse, so a saved archive can always be opened again.
        var totalSize = 0
        for member in members {
            totalSize += member.data.count
            guard member.data.count <= maximumFileSize, totalSize <= maximumTotalSize else { throw Failure.tooLarge }
        }

        var output = [UInt8]()
        var directory = [UInt8]()

        for member in members {
            let name = Array(member.name.utf8)
            let size = member.data.count
            guard name.count <= 0xFFFF, size < 0xFFFF_FFFF, output.count < 0xFFFF_FFFF else { throw Failure.tooLarge }
            let checksum = crc32(Array(member.data))
            let (time, date) = dosTimestamp(for: member.modified)
            let offset = output.count

            // The local header, then the file's bytes.
            output.appendLE32(0x0403_4B50)
            output.appendLE16(20)
            output.appendLE16(utf8NameFlag)
            output.appendLE16(0)
            output.appendLE16(time)
            output.appendLE16(date)
            output.appendLE32(checksum)
            output.appendLE32(UInt32(size))
            output.appendLE32(UInt32(size))
            output.appendLE16(UInt16(name.count))
            output.appendLE16(0)
            output.append(contentsOf: name)
            output.append(contentsOf: member.data)

            // The matching entry in the directory at the end.
            directory.appendLE32(0x0201_4B50)
            directory.appendLE16(unixMadeBy)
            directory.appendLE16(20)
            directory.appendLE16(utf8NameFlag)
            directory.appendLE16(0)
            directory.appendLE16(time)
            directory.appendLE16(date)
            directory.appendLE32(checksum)
            directory.appendLE32(UInt32(size))
            directory.appendLE32(UInt32(size))
            directory.appendLE16(UInt16(name.count))
            directory.appendLE16(0)
            directory.appendLE16(0)
            directory.appendLE16(0)
            directory.appendLE16(0)
            directory.appendLE32(regularFilePermissions)
            directory.appendLE32(UInt32(offset))
            directory.append(contentsOf: name)
        }

        guard output.count + directory.count < 0xFFFF_FFFF else { throw Failure.tooLarge }
        let directoryOffset = output.count
        output.append(contentsOf: directory)
        guard output.count + 22 <= maximumArchiveSize else { throw Failure.tooLarge }

        // The end record, which says where the directory is.
        output.appendLE32(0x0605_4B50)
        output.appendLE16(0)
        output.appendLE16(0)
        output.appendLE16(UInt16(members.count))
        output.appendLE16(UInt16(members.count))
        output.appendLE32(UInt32(directory.count))
        output.appendLE32(UInt32(directoryOffset))
        output.appendLE16(0)
        return Data(output)
    }

    // MARK: - Reading

    /// Reads every file in an archive.
    ///
    /// A file whose bytes don't match its checksum, or that can't be decompressed, is listed
    /// as damaged while the others still come out.
    ///
    /// - Throws: `Failure` when the archive's directory itself can't be read.
    static func read(_ archive: Data) throws -> Contents {
        let bytes = [UInt8](archive)
        guard let endRecord = findEndRecord(in: bytes),
              let count = bytes.le16(at: endRecord + 10),
              let directoryOffset = bytes.le32(at: endRecord + 16),
              directoryOffset != 0xFFFF_FFFF else { throw Failure.notAnArchive }

        var contents = Contents()
        var position = directoryOffset
        var totalSize = 0

        for _ in 0..<count {
            guard bytes.le32(at: position) == 0x0201_4B50,
                  let flags = bytes.le16(at: position + 8),
                  let method = bytes.le16(at: position + 10),
                  let time = bytes.le16(at: position + 12),
                  let dosDate = bytes.le16(at: position + 14),
                  let checksum = bytes.le32(at: position + 16),
                  let compressedSize = bytes.le32(at: position + 20),
                  let size = bytes.le32(at: position + 24),
                  let nameLength = bytes.le16(at: position + 28),
                  let extraLength = bytes.le16(at: position + 30),
                  let commentLength = bytes.le16(at: position + 32),
                  let localOffset = bytes.le32(at: position + 42),
                  position + 46 + nameLength <= bytes.count else { throw Failure.notAnArchive }

            let name = String(decoding: bytes[(position + 46)..<(position + 46 + nameLength)], as: UTF8.self)
            position += 46 + nameLength + extraLength + commentLength

            // A folder entry holds no file.
            if name.hasSuffix("/") { continue }

            totalSize += size
            guard size <= maximumFileSize, totalSize <= maximumTotalSize else { throw Failure.tooLarge }

            guard let data = fileBytes(in: bytes, localOffset: localOffset, flags: flags, method: method,
                                       compressedSize: compressedSize, size: size, checksum: checksum) else {
                contents.damaged.append(name)
                continue
            }
            contents.members.append(Member(name: name, modified: date(fromDOS: time, date: dosDate), data: data))
        }
        return contents
    }

    /// One file's bytes, checked against its recorded size and checksum, or `nil` when
    /// they can't be trusted.
    private static func fileBytes(in bytes: [UInt8], localOffset: Int, flags: Int, method: Int,
                                  compressedSize: Int, size: Int, checksum: Int) -> Data? {
        // A password-protected file can't be read.
        guard flags & 1 == 0,
              bytes.le32(at: localOffset) == 0x0403_4B50,
              let nameLength = bytes.le16(at: localOffset + 26),
              let extraLength = bytes.le16(at: localOffset + 28) else { return nil }
        let start = localOffset + 30 + nameLength + extraLength
        let end = start + compressedSize
        guard start <= end, end <= bytes.count else { return nil }
        let stored = Data(bytes[start..<end])

        let data: Data
        switch method {
        case 0:
            data = stored
        case 8:
            // Compression's zlib is the raw deflate stream a ZIP file holds.
            guard let inflated = inflate(stored, expecting: size) else { return nil }
            data = inflated
        default:
            return nil
        }
        guard data.count == size, Int(crc32(Array(data))) == checksum else { return nil }
        return data
    }

    /// Decompresses raw deflate bytes into at most `size` bytes, never allocating more, and
    /// returns `nil` unless they expand to exactly `size`.
    private static func inflate(_ stored: Data, expecting size: Int) -> Data? {
        guard size <= maximumFileSize else { return nil }
        // One spare byte, so output longer than declared shows up as a mismatch.
        let capacity = size + 1
        var output = [UInt8](repeating: 0, count: capacity)
        let written = stored.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return output.withUnsafeMutableBufferPointer { destination in
                guard let target = destination.baseAddress else { return 0 }
                return compression_decode_buffer(target, capacity, base, stored.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { return nil }
        return Data(output.prefix(size))
    }

    /// Where the end record starts, searching back from the end of the archive.
    private static func findEndRecord(in bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var position = bytes.count - 22
        while position >= lowest {
            if bytes.le32(at: position) == 0x0605_4B50 { return position }
            position -= 1
        }
        return nil
    }

    // MARK: - Details

    /// Marks a file name as UTF-8, so accents survive the trip.
    private static let utf8NameFlag: UInt16 = 0x0800
    /// "Made on Unix", so unzip tools read the permissions below.
    private static let unixMadeBy: UInt16 = (3 << 8) | 20
    /// A regular file readable by everyone and writable by its owner.
    private static let regularFilePermissions: UInt32 = 0o100644 << 16

    /// A date as the ZIP format's two 16-bit fields, clamped to the years it can hold.
    private static func dosTimestamp(for date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max((parts.year ?? 1980) - 1980, 0), 127)
        let time = ((parts.hour ?? 0) << 11) | ((parts.minute ?? 0) << 5) | ((parts.second ?? 0) / 2)
        let day = (year << 9) | ((parts.month ?? 1) << 5) | (parts.day ?? 1)
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: day))
    }

    /// The date held in the ZIP format's two 16-bit fields, or the epoch when they're blank.
    private static func date(fromDOS time: Int, date: Int) -> Date {
        let parts = DateComponents(year: 1980 + (date >> 9), month: (date >> 5) & 0xF, day: date & 0x1F,
                                   hour: time >> 11, minute: (time >> 5) & 0x3F, second: (time & 0x1F) * 2)
        return Calendar.current.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    /// The table the checksum uses, built once.
    private static let checksumTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? (value >> 1) ^ 0xEDB8_8320 : value >> 1
        }
        return value
    }

    /// The CRC-32 checksum of `bytes`, as ZIP files record it.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var value: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            value = checksumTable[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
        }
        return ~value
    }
}

private nonisolated extension Array where Element == UInt8 {

    /// Adds a 16-bit number, low byte first.
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    /// Adds a 32-bit number, low byte first.
    mutating func appendLE32(_ value: UInt32) {
        appendLE16(UInt16(truncatingIfNeeded: value))
        appendLE16(UInt16(truncatingIfNeeded: value >> 16))
    }

    /// The 16-bit number at `offset`, or `nil` past the end.
    func le16(at offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return Int(self[offset]) | Int(self[offset + 1]) << 8
    }

    /// The 32-bit number at `offset`, or `nil` past the end.
    func le32(at offset: Int) -> Int? {
        guard let low = le16(at: offset), let high = le16(at: offset + 2) else { return nil }
        return low | high << 16
    }
}
