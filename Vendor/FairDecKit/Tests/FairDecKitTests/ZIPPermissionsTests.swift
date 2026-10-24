import Foundation
import XCTest
import ZIPFoundation
@testable import FairDecKit

final class ZIPPermissionsTests: XCTestCase {
    func testRawPermissionsIncludingUnspecifiedDOSAndZIP64() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.zip")
        let output = root.appendingPathComponent("output.zip")
        let names = ["unspecified", "dos-mode", "readonly", "executable", "folder/", "link"]
        for (url, paths) in [(source, names), (output, names.reversed().map { $0 })] {
            let archive = try Archive(url: url, accessMode: .create)
            for path in paths {
                let data = path == "link" ? Data("executable".utf8) : Data()
                let type: Entry.EntryType = path == "link" ? .symlink : (path.hasSuffix("/") ? .directory : .file)
                try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count), permissions: 0o755) { _, _ in data }
            }
        }
        let platforms: [UInt16] = [20, 20, 20, 789, 789, 789]
        let attributes: [UInt32] = [0, 0o600 << 16, 3, 0o100751 << 16, 0o41750 << 16, 0o120777 << 16]
        let records = try zipDirectory(at: source).records
        var raw = try Data(contentsOf: source)
        func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
            (0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
        for (i, record) in records.enumerated() {
            raw.replaceSubrange(record.offset + 4..<record.offset + 6, with: bytes(platforms[i]))
            raw.replaceSubrange(record.offset + 38..<record.offset + 42, with: bytes(attributes[i]))
        }
        try raw.write(to: source)
        for zip64 in [false, true] {
            if zip64 {
                let end = raw.count - 22
                let offset = try raw.uint32(end + 16)
                let size = try raw.uint32(end + 12)
                var record = Data()
                record.append(contentsOf: bytes(UInt32(0x06064b50)))
                record.append(contentsOf: bytes(UInt64(44)))
                record.append(contentsOf: bytes(UInt16(789)))
                record.append(contentsOf: bytes(UInt16(45)))
                record.append(contentsOf: bytes(UInt32(0)))
                record.append(contentsOf: bytes(UInt32(0)))
                record.append(contentsOf: bytes(UInt64(names.count)))
                record.append(contentsOf: bytes(UInt64(names.count)))
                record.append(contentsOf: bytes(UInt64(size)))
                record.append(contentsOf: bytes(UInt64(offset)))
                record.append(contentsOf: bytes(UInt32(0x07064b50)))
                record.append(contentsOf: bytes(UInt32(0)))
                record.append(contentsOf: bytes(UInt64(end)))
                record.append(contentsOf: bytes(UInt32(1)))
                raw.replaceSubrange(end + 8..<end + 12, with: [255, 255, 255, 255])
                raw.insert(contentsOf: record, at: end)
                try raw.write(to: source)
            }
            let rebuilt = root.appendingPathComponent("rebuilt-\(zip64).zip")
            try preserveZIP(from: source, replacing: output, to: rebuilt)
            XCTAssertEqual(try Data(contentsOf: rebuilt), try Data(contentsOf: source))
            let expected = Dictionary(uniqueKeysWithValues: zip(names, try zipDirectory(at: source).records))
            let actual = try zipDirectory(at: rebuilt).records
            for (name, record) in zip(names, actual) {
                XCTAssertEqual(record.platform, expected[name]?.platform)
                XCTAssertEqual(record.attributes, expected[name]?.attributes)
            }
            let archive = try Archive(url: rebuilt, accessMode: .read)
            XCTAssertEqual(archive["link"]?.type, .symlink)
            XCTAssertEqual(archive["folder/"]?.type, .directory)
        }
        for data in [Data(), Data(repeating: 0, count: 22), Data(raw.dropLast())] {
            try data.write(to: source)
            XCTAssertThrowsError(try zipDirectory(at: source).records)
        }
    }
}
