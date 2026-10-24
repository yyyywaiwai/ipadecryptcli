import Foundation
import XCTest
import ZIPFoundation
@testable import FairDecKit

final class ZIPPreservationTests: XCTestCase {
    func testCommentsExtrasTimestampsDescriptorsAndUntouchedCompressedBytes() throws {
        for mode in [FairDecKit.Mode.fast, .lowMemory] {
            for width in [32, 64] {
                let input = try XCTUnwrap(Bundle.module.url(forResource: "metadata-\(width)", withExtension: "zip", subdirectory: "Fixtures"))
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }
                let output = root.appendingPathComponent("output.ipa")
                try FairDecKit.decryptIPA(at: input, to: output, credential: Data(0..<16), mode: mode)
                let before = try Data(contentsOf: input), after = try Data(contentsOf: output)
                let original = try zipDirectory(at: input), result = try zipDirectory(at: output)
                XCTAssertEqual(original.records.count, result.records.count)
                let prefixLength = Int(try original.records[0].field(42).value)
                XCTAssertEqual(before.prefix(prefixLength), after.prefix(prefixLength))
                let paths = try Archive(url: input, accessMode: .read).map(\.path)
                XCTAssertEqual(paths, try Archive(url: output, accessMode: .read).map(\.path))
                for (index, records) in zip(original.records, result.records).enumerated() {
                    let (a, b) = records
                    var expected = a.header
                    expected.replaceSubrange(16..<20, with: b.header[16..<20])
                    for offset in [20, 42] {
                        let field = try a.field(offset)
                        let position = field.offset - a.offset
                        expected.replaceSubrange(position..<(position + field.width), with: b.header[position..<(position + field.width)])
                    }
                    XCTAssertEqual(expected, b.header, "Central header metadata: \(paths[index])")
                    let oldOffset = Int(try a.field(42).value), newOffset = Int(try b.field(42).value)
                    let length = try 30 + Int(zipInteger(before, oldOffset + 26, 2)) + Int(zipInteger(before, oldOffset + 28, 2))
                    // The non-seeking fixture uses zero CRC/size placeholders, including ZIP64 extras.
                    XCTAssertEqual(try before.checkedBytes(oldOffset, length), try after.checkedBytes(newOffset, length))
                    if !paths[index].hasSuffix("/Fixture") {
                        let oldEnd = index + 1 < original.records.count ? Int(try original.records[index + 1].field(42).value) : original.offset
                        let newEnd = index + 1 < result.records.count ? Int(try result.records[index + 1].field(42).value) : result.offset
                        XCTAssertEqual(try before.checkedBytes(oldOffset, oldEnd - oldOffset),
                                       try after.checkedBytes(newOffset, newEnd - newOffset), "Untouched entry: \(paths[index])")
                    }
                }
                XCTAssertEqual(try before.checkedBytes(original.end + 22, before.count - original.end - 22),
                               try after.checkedBytes(result.end + 22, after.count - result.end - 22))
            }
        }
    }

    func testGrowingCompressedEntryRelocatesFollowingEntries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("source.zip"), replacement = root.appendingPathComponent("replacement.zip")
        let output = root.appendingPathComponent("output.zip")
        let newData = Data((0..<8192).map { UInt8(truncatingIfNeeded: ($0 * 73) ^ ($0 >> 5)) })
        for (url, content) in [(input, Data(repeating: 0, count: 8192)), (replacement, newData)] {
            let archive = try Archive(url: url, accessMode: .create)
            try archive.addEntry(with: "first", type: .file, uncompressedSize: Int64(8192), compressionMethod: .deflate) { p, n in
                content.subdata(in: Int(p)..<(Int(p) + n))
            }
            if url == input {
                try archive.addEntry(with: "second", type: .file, uncompressedSize: Int64(1)) { _, _ in Data([42]) }
            }
        }
        try preserveZIP(from: input, replacing: replacement, to: output)
        XCTAssertGreaterThan(try Data(contentsOf: output).count, try Data(contentsOf: input).count)
        let archive = try Archive(url: output, accessMode: .read)
        var data = Data()
        _ = try archive.extract(XCTUnwrap(archive["first"])) { data.append($0) }
        XCTAssertEqual(data, newData)
        data.removeAll()
        _ = try archive.extract(XCTUnwrap(archive["second"])) { data.append($0) }
        XCTAssertEqual(data, Data([42]))
    }
}
