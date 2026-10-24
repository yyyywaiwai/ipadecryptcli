import Foundation
import XCTest
import ZIPFoundation
@testable import FairDecKit

final class ZIP64PromotionTests: XCTestCase {
    private func fixture() throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: "metadata-32", withExtension: "zip", subdirectory: "Fixtures"))
    }

    private func extras(_ header: Data, central: Bool, excludingZIP64: Bool = false) throws -> Data {
        let start = try (central ? 46 : 30) + Int(zipInteger(header, central ? 28 : 26, 2))
        let length = Int(try zipInteger(header, central ? 30 : 28, 2))
        let data = try header.checkedBytes(start, length)
        var output = Data(), position = 0
        while position < data.count {
            let tag = try zipInteger(data, position, 2)
            let count = Int(try zipInteger(data, position + 2, 2)) + 4
            if !excludingZIP64 || tag != 1 { output.append(try data.checkedBytes(position, count)) }
            position += count
        }
        return output
    }

    func testOnlyOverflowingCentralFieldsBecomeZIP64AndOtherMetadataSurvives() throws {
        let header = try zipDirectory(at: fixture()).records[0].header
        for offset in [20, 24, 42] {
            for value in [UInt64(UInt32.max) - 1, UInt64(UInt32.max), UInt64(UInt32.max) + 1] {
                let promoted = try zipHeader(header, central: true, values: [offset: value])
                let field = try ZIPRecord(offset: 0, header: promoted).field(offset)
                XCTAssertEqual(field.value, value)
                XCTAssertEqual(field.width, value >= UInt32.max ? 8 : 4)
                for other in [20, 24, 42] where other != offset {
                    XCTAssertEqual(try zipInteger(promoted, other, 4), try zipInteger(header, other, 4))
                }
                XCTAssertEqual(try extras(header, central: true), try extras(promoted, central: true, excludingZIP64: true))
                let commentSize = Int(try zipInteger(header, 32, 2))
                XCTAssertEqual(header.suffix(commentSize), promoted.suffix(commentSize))
                XCTAssertEqual(header[8..<16], promoted[8..<16])
                XCTAssertEqual(header[34..<42], promoted[34..<42])
                XCTAssertEqual(try zipInteger(promoted, 6, 2), value >= UInt32.max ? 45 : try zipInteger(header, 6, 2))
            }
        }
        let offsetOnly = try zipHeader(header, central: true, values: [42: UInt64(UInt32.max)])
        let expanded = try zipHeader(offsetOnly, central: true, values: [20: UInt64(UInt32.max) + 2])
        XCTAssertEqual(try ZIPRecord(offset: 0, header: expanded).field(42).value, UInt64(UInt32.max))
        XCTAssertEqual(try ZIPRecord(offset: 0, header: expanded).field(20).value, UInt64(UInt32.max) + 2)
        XCTAssertEqual(try extras(expanded, central: true, excludingZIP64: true), try extras(header, central: true))
        // Existing ZIP64 fields are not demoted when an entry shrinks again.
        let shrunk = try zipHeader(expanded, central: true, values: [20: 7, 42: 11])
        XCTAssertEqual(try ZIPRecord(offset: 0, header: shrunk).field(20).value, 7)
        XCTAssertEqual(try ZIPRecord(offset: 0, header: shrunk).field(20).width, 8)
    }

    func testFixedWidthChangesDoNotInterpretOpaqueExtraPadding() throws {
        let original = try zipDirectory(at: fixture()).records[0].header
        var header = original
        let start = 46 + Int(try zipInteger(header, 28, 2))
        let size = Int(try zipInteger(header, 30, 2))
        header.replaceSubrange(30..<32, with: zipBytes(UInt64(size + 1), width: 2))
        header.insert(0xff, at: start + size)
        let changed = try zipHeader(header, central: true, values: [42: 123])
        var expected = header
        expected.replaceSubrange(42..<46, with: zipBytes(123, width: 4))
        XCTAssertEqual(changed, expected)
    }

    func testLocatorSignatureInsideEntryCommentDoesNotCreateZIP64() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input.zip"), replacement = root.appendingPathComponent("replacement.zip")
        let output = root.appendingPathComponent("output.zip")
        let directory = try zipDirectory(at: fixture())
        let last = try XCTUnwrap(directory.records.last)
        var raw = try Data(contentsOf: fixture())
        let commentSize = try zipInteger(last.header, 32, 2)
        raw.replaceSubrange(last.offset + 32..<last.offset + 34, with: zipBytes(commentSize + 20, width: 2))
        raw.replaceSubrange(directory.end + 12..<directory.end + 16, with: zipBytes(UInt64(directory.directorySize + 20), width: 4))
        raw.insert(contentsOf: zipBytes(0x07064b50, width: 4) + Data(repeating: 0xff, count: 16), at: directory.end)
        try raw.write(to: input)
        XCTAssertNil(try zipDirectory(at: input).zip64End)
        do { _ = try Archive(url: replacement, accessMode: .create) }
        try preserveZIP(from: input, replacing: replacement, to: output)
        XCTAssertEqual(try Data(contentsOf: output), raw)
    }

    func testLocalSizePromotionAndFooterBoundaries() throws {
        let raw = try Data(contentsOf: fixture())
        let headerSize = try 30 + Int(zipInteger(raw, 26, 2)) + Int(zipInteger(raw, 28, 2))
        let local = try raw.checkedBytes(0, headerSize)
        let promoted = try zipHeader(local, central: false, values: [18: UInt64(UInt32.max), 22: 8192])
        XCTAssertEqual(try zipInteger(promoted, 18, 4), UInt64(UInt32.max))
        XCTAssertEqual(try zipInteger(promoted, 22, 4), UInt64(UInt32.max))
        XCTAssertEqual(try zipInteger(promoted, 4, 2), 45)
        XCTAssertEqual(try extras(promoted, central: false, excludingZIP64: true), try extras(local, central: false))
        let directory = try zipDirectory(at: fixture())
        let end = try raw.checkedBytes(directory.end, 22)
        for size in [UInt64(UInt32.max) - 1, UInt64(UInt32.max), UInt64(UInt32.max) + 1] {
            for offset in [UInt64(100), UInt64(UInt32.max)] {
                let updated = try zipEndRecords(end, count: 4, directorySize: size, directoryOffset: offset,
                                                zip64Offset: offset + size, existingZIP64: false)
                let wide = size >= UInt32.max || offset >= UInt32.max
                XCTAssertEqual(updated.count, wide ? 98 : 22)
                let classic = updated.suffix(22)
                XCTAssertEqual(try zipInteger(Data(classic), 12, 4), min(size, UInt64(UInt32.max)))
                XCTAssertEqual(try zipInteger(Data(classic), 16, 4), min(offset, UInt64(UInt32.max)))
                XCTAssertEqual(classic.suffix(2), end.suffix(2))
                if wide {
                    XCTAssertEqual(try zipInteger(updated, 40, 8), size)
                    XCTAssertEqual(try zipInteger(updated, 48, 8), offset)
                    XCTAssertEqual(try zipInteger(updated, 64, 8), size + offset)
                }
            }
        }
        var full = local
        let nameSize = Int(try zipInteger(full, 26, 2))
        let hugeExtra = zipBytes(0xcafe, width: 2) + zipBytes(65531, width: 2) + Data(repeating: 42, count: 65531)
        full.replaceSubrange(28..<30, with: zipBytes(65535, width: 2))
        full.replaceSubrange((30 + nameSize)..<full.count, with: hugeExtra)
        XCTAssertThrowsError(try zipHeader(full, central: false, values: [18: UInt64(UInt32.max), 22: 8192]))
    }

    func testSparseArchiveActuallyCrosses4GiBAndRemainsReadable() throws {
        guard ProcessInfo.processInfo.environment["FAIRDECKIT_LARGE_ZIP_TEST"] == "1" else {
            throw XCTSkip("Set FAIRDECKIT_LARGE_ZIP_TEST=1 for the 4GiB streaming/promotion check")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("large.zip"), replacement = root.appendingPathComponent("replacement.zip")
        let output = root.appendingPathComponent("output.zip")
        let original = try zipDirectory(at: fixture())
        var raw = try Data(contentsOf: fixture())
        let prefix = UInt64(UInt32.max) - UInt64(raw.count) - 1024
        for record in original.records {
            let offset = try record.field(42).value + prefix
            raw.replaceSubrange(record.offset + 42..<record.offset + 46, with: zipBytes(offset, width: 4))
        }
        raw.replaceSubrange(original.end + 16..<original.end + 20, with: zipBytes(UInt64(original.offset) + prefix, width: 4))
        XCTAssertTrue(FileManager.default.createFile(atPath: input.path, contents: nil))
        let file = try FileHandle(forWritingTo: input)
        try file.seek(toOffset: prefix)
        try file.write(contentsOf: raw)
        try file.close()
        let path = "Payload/Fixture.app/Fixture"
        var state: UInt32 = 0x12345678
        let content = Data((0..<8192).map { _ -> UInt8 in
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return UInt8(truncatingIfNeeded: state)
        })
        do {
            let archive = try Archive(url: replacement, accessMode: .create)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(content.count), compressionMethod: .deflate) { p, n in
                content.subdata(in: Int(p)..<(Int(p) + n))
            }
        }
        try preserveZIP(from: input, replacing: replacement, to: output)
        let result = try zipDirectory(at: output)
        XCTAssertNotNil(result.zip64End)
        XCTAssertGreaterThanOrEqual(UInt64(result.offset), UInt64(UInt32.max))
        XCTAssertEqual(try result.records[0].field(42).width, 4)
        XCTAssertEqual(try result.records[1].field(42).width, 8)
        for (before, after) in zip(original.records, result.records) {
            XCTAssertEqual(try extras(before.header, central: true), try extras(after.header, central: true, excludingZIP64: true))
            let size = Int(try zipInteger(before.header, 32, 2))
            XCTAssertEqual(before.header.suffix(size), after.header.suffix(size))
        }
        let commentSize = Int(try zipInteger(raw, original.end + 20, 2))
        let outputFile = try FileHandle(forReadingFrom: output)
        defer { try? outputFile.close() }
        XCTAssertEqual(try readExactly(outputFile, at: result.end + 22, count: commentSize), raw.suffix(commentSize))
        #if os(macOS)
        let validator = Process()
        validator.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        validator.arguments = ["-t", output.path]
        let log = Pipe()
        validator.standardOutput = log
        validator.standardError = log
        try validator.run()
        validator.waitUntilExit()
        let validation = String(decoding: log.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(validator.terminationStatus, 0, validation)
        #endif
        let archive = try Archive(url: output, accessMode: .read)
        var actual = Data()
        _ = try archive.extract(XCTUnwrap(archive[path])) { actual.append($0) }
        XCTAssertEqual(actual, content)
        for entry in archive where entry.path != path {
            var checksumData = Data()
            let checksum = try archive.extract(entry) { checksumData.append($0) }
            XCTAssertEqual(checksum, entry.checksum)
        }
        print("ZIP64 crossing verified: directory=\(result.offset), second local offset=\(try result.records[1].field(42).value)")
    }
}
