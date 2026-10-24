import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
@testable import FairDecKit

final class FairDecKitTests: XCTestCase {
    private struct Reference: Decodable {
        struct Vector: Decodable {
            let source, work, block, finish, key: String
            let index: UInt32
            let sources: [String]
        }
        struct Binary: Decodable {
            let header, ciphertext, sinf, supf, clear: String
            let base: Int

            var source: Data {
                var thin = hex(header)
                thin.append(Data(repeating: 0, count: 4096 - thin.count))
                thin.append(hex(ciphertext))
                guard base > 0 else { return thin }
                var fat = Data()
                func word(_ value: UInt32) {
                    fat.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
                }
                word(base == 4096 ? 0xcafebabe : 0xcafebabf)
                word(1)
                word(0x0100000c)
                word(0)
                if base != 4096 { word(0) }
                word(UInt32(base))
                if base != 4096 { word(0) }
                word(UInt32(thin.count))
                word(12)
                if base != 4096 { word(0) }
                fat.append(Data(repeating: 0, count: base - fat.count))
                fat.append(thin)
                return fat
            }
        }
        let vectors: [Vector]
        let binaries: [Binary]
    }

    private var credential: Data { Data(0..<16) }

    private func reference() throws -> Reference {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reference", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
    }

    func testPythonAndCReferenceVectors() throws {
        let transform = try BlockTransform()
        for vector in try reference().vectors {
            let source = Array(hex(vector.source)), work = Array(hex(vector.work))
            XCTAssertEqual(Data(transform(source, work)), hex(vector.block))
            XCTAssertEqual(Data(finish(source)), hex(vector.finish))
            XCTAssertEqual(sourceBlocks(source, index: vector.index).map { Data($0) }, vector.sources.map(hex))
            XCTAssertEqual(Data(derivePageKey(wrapped: source, index: vector.index, work: work, transform: transform)), hex(vector.key))
        }
    }

    func testThinFAT32FAT64AndSINFAndSUPFVariants() throws {
        for fixture in try reference().binaries {
            // Also exercise Data whose startIndex is not zero.
            let source = (Data([0xaa]) + fixture.source).dropFirst()
            let result = try FairDecKit.decryptBinary(source, sinf: hex(fixture.sinf), supf: hex(fixture.supf), credential: credential)
            XCTAssertEqual(digest(result), fixture.clear)
            XCTAssertEqual(try result.uint32(fixture.base + 48), 0)
            XCTAssertEqual(try result.checkedBytes(fixture.base + 4096, 4096), Data((0..<4096).map { UInt8(truncatingIfNeeded: $0) }))
        }
    }

    func testInvalidInputsThrow() throws {
        let fixture = try reference().binaries[0]
        for size in [0, 15, 17] {
            XCTAssertThrowsError(try FairDecKit.decryptBinary(fixture.source, sinf: hex(fixture.sinf), supf: hex(fixture.supf), credential: Data(repeating: 0, count: size)))
        }
        for size in [0, 3, 7, 31, 55] {
            XCTAssertThrowsError(try FairDecKit.decryptBinary(fixture.source.prefix(size), sinf: hex(fixture.sinf), supf: hex(fixture.supf), credential: credential))
        }
        for (sinf, supf) in [(Data(), hex(fixture.supf)), (hex(fixture.sinf), Data()),
                             (hex(fixture.sinf), Data(hex(fixture.supf).dropLast()))] {
            XCTAssertThrowsError(try FairDecKit.decryptBinary(fixture.source, sinf: sinf, supf: supf, credential: credential))
        }
        var invalidFAT = try reference().binaries[2].source
        invalidFAT.replaceSubrange(16..<24, with: repeatElement(UInt8(255), count: 8))
        XCTAssertThrowsError(try FairDecKit.decryptBinary(invalidFAT, sinf: hex(fixture.sinf), supf: hex(fixture.supf), credential: credential))
    }

    func testIPAFallbacksPreservationAndFailureCleanup() throws {
        for mode in [FairDecKit.Mode.lowMemory, .fast] {
            try checkIPA(mode: mode)
        }
    }

    private func checkIPA(mode: FairDecKit.Mode) throws {
        let fixtures = try reference().binaries
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input.ipa"), output = root.appendingPathComponent("output.ipa")
        let app = "Payload/Fixture.app", plug = app + "/PlugIns/Plug.appex", framework = app + "/Frameworks/Library.framework"
        let paths = [app + "/Fixture", plug + "/Plug", framework + "/Library"]
        do {
            let archive = try Archive(url: input, accessMode: .create)
            for (path, fixture) in zip(paths, fixtures) { try add(archive, path, fixture.source) }
            try add(archive, app + "/SC_Info/Fixture.sinf", hex(fixtures[0].sinf))
            try add(archive, app + "/SC_Info/Fixture.supf", hex(fixtures[0].supf))
            try add(archive, plug + "/SC_Info/Plug.v5.supf", hex(fixtures[1].supf))
            try add(archive, framework + "/SC_Info/Library.v4.sinf", hex(fixtures[2].sinf))
            try add(archive, framework + "/SC_Info/Library.v5.supf", hex(fixtures[2].supf))
            try add(archive, framework + "/SC_Info/Library.supf", Data("ignored in favor of v5".utf8))
            let clear = try FairDecKit.decryptBinary(fixtures[0].source, sinf: hex(fixtures[0].sinf), supf: hex(fixtures[0].supf), credential: credential)
            try add(archive, app + "/Already", clear)
            try add(archive, app + "/SC_Info/Already.supf", Data())
            let chunk = Data(repeating: 0x5a, count: 64 * 1024)
            try archive.addEntry(with: app + "/large-resource", type: .file, uncompressedSize: Int64(8 * 1024 * 1024), compressionMethod: .deflate) { _, size in
                chunk.prefix(size)
            }
            let resource = Data("unchanged".utf8)
            try archive.addEntry(with: app + "/resource.txt", type: .file, uncompressedSize: Int64(resource.count)) { position, size in
                resource.subdata(in: Int(position)..<(Int(position) + size))
            }
            try archive.addEntry(with: app + "/empty/", type: .directory, uncompressedSize: Int64(0), permissions: 0o755) { _, _ in Data() }
            let link = Data("resource.txt".utf8)
            try archive.addEntry(with: app + "/link", type: .symlink, uncompressedSize: Int64(link.count)) { _, _ in link }
        }
        // Legal padding before the first local header must not corrupt central-directory offsets.
        var padded = Data(repeating: 0xab, count: 13) + (try Data(contentsOf: input))
        let end = padded.count - 22
        var directory = Int(try padded.uint32(end + 16)) + 13
        func store(_ value: UInt32, at offset: Int) {
            padded.replaceSubrange(offset..<(offset + 4), with: [0, 8, 16, 24].map { UInt8(truncatingIfNeeded: value >> $0) })
        }
        store(UInt32(directory), at: end + 16)
        for _ in 0..<(try padded.uint32(end + 8) & 0xffff) {
            let offset = try padded.uint32(directory + 42)
            store(offset + 13, at: directory + 42)
            let lengths = try padded.uint32(directory + 28)
            let comment = try padded.uint32(directory + 32) & 0xffff
            directory += 46 + Int(lengths & 0xffff) + Int(lengths >> 16) + Int(comment)
        }
        try padded.write(to: input)
        let inputHash = digest(try Data(contentsOf: input))
        let binaries = try FairDecKit.decryptBinaries(in: input, credential: credential, mode: mode)
        if mode == .lowMemory {
            XCTAssertEqual(binaries, try FairDecKit.decryptBinaries(in: input, credential: credential))
        }
        XCTAssertEqual(Set(binaries.keys), Set(paths))
        for (path, fixture) in zip(paths, fixtures) {
            XCTAssertEqual(digest(try XCTUnwrap(binaries[path])), fixture.clear)
        }
        XCTAssertThrowsError(try FairDecKit.decryptIPA(at: input, to: output, credential: Data(repeating: 0, count: 16), mode: mode))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), ["input.ipa"])
        var damaged = try Data(contentsOf: input)
        let resourceRange = try XCTUnwrap(damaged.range(of: Data("unchanged".utf8)))
        damaged[resourceRange.lowerBound] ^= 1
        let damagedURL = root.appendingPathComponent("damaged.ipa")
        try damaged.write(to: damagedURL)
        XCTAssertThrowsError(try FairDecKit.decryptIPA(at: damagedURL, to: output, credential: credential, mode: mode))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".fairdeckit-") })
        let badBinaryURL = root.appendingPathComponent("bad-binary.ipa")
        do {
            let archive = try Archive(url: badBinaryURL, accessMode: .create)
            let source = fixtures[0].source
            try archive.addEntry(with: paths[0], type: .file, uncompressedSize: Int64(source.count)) { position, size in
                source.subdata(in: Int(position)..<(Int(position) + size))
            }
            try add(archive, app + "/SC_Info/Fixture.sinf", hex(fixtures[0].sinf))
            try add(archive, app + "/SC_Info/Fixture.supf", hex(fixtures[0].supf))
        }
        var badBinary = try Data(contentsOf: badBinaryURL)
        let ciphertext = try XCTUnwrap(badBinary.range(of: hex(fixtures[0].ciphertext).prefix(16)))
        badBinary[ciphertext.lowerBound] ^= 1
        try badBinary.write(to: badBinaryURL)
        XCTAssertThrowsError(try FairDecKit.decryptIPA(at: badBinaryURL, to: output, credential: credential, mode: mode)) { error in
            XCTAssertTrue(error.localizedDescription.contains("ZIP checksum/size mismatch"), "\(error)")
        }
        XCTAssertThrowsError(try FairDecKit.decryptBinaries(in: badBinaryURL, credential: credential, mode: mode)) { error in
            XCTAssertTrue(error.localizedDescription.contains("ZIP checksum/size mismatch"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".fairdeckit-") })
        XCTAssertEqual(try FairDecKit.decryptIPA(at: input, to: output, credential: credential, mode: mode), output)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
        let original = try Archive(url: input, accessMode: .read)
        let result = try Archive(url: output, accessMode: .read)
        XCTAssertEqual(Set(original.map(\.path)), Set(result.map(\.path)))
        for entry in result {
            let before = try XCTUnwrap(original[entry.path])
            XCTAssertEqual(entry.type, before.type)
            XCTAssertEqual(entry.fileAttributes[.modificationDate] as? Date, before.fileAttributes[.modificationDate] as? Date)
            XCTAssertEqual(entry.fileAttributes[.posixPermissions] as? NSNumber, before.fileAttributes[.posixPermissions] as? NSNumber)
            if let i = paths.firstIndex(of: entry.path) {
                XCTAssertEqual(digest(try read(result, entry)), fixtures[i].clear)
            } else {
                XCTAssertEqual(try read(result, entry), try read(original, before))
            }
        }
        let outputHash = digest(try Data(contentsOf: output))
        XCTAssertThrowsError(try FairDecKit.decryptIPA(at: input, to: output, credential: credential, mode: mode))
        XCTAssertThrowsError(try FairDecKit.decryptIPA(at: input, to: input, credential: credential, mode: mode))
        XCTAssertEqual(digest(try Data(contentsOf: input)), inputHash)
        XCTAssertEqual(digest(try Data(contentsOf: output)), outputHash)
    }

    func testDownloadedIPAAgainstPython() throws {
        let env = ProcessInfo.processInfo.environment
        guard let input = env["FAIRDECKIT_IPA"], let credential = env["FAIRDECKIT_CREDENTIAL"],
              let expected = env["FAIRDECKIT_REFERENCE"], let output = env["FAIRDECKIT_OUTPUT"] else {
            throw XCTSkip("Set FAIRDECKIT_IPA, FAIRDECKIT_CREDENTIAL, FAIRDECKIT_REFERENCE and FAIRDECKIT_OUTPUT for the local integration check")
        }
        let key = try Data(contentsOf: URL(fileURLWithPath: credential))
        let inputURL = URL(fileURLWithPath: input), outputURL = URL(fileURLWithPath: output)
        let modes: [String: FairDecKit.Mode] = ["lowMemory": .lowMemory, "fast": .fast]
        let mode = try XCTUnwrap(modes[env["FAIRDECKIT_MODE"] ?? "lowMemory"])
        try FairDecKit.decryptIPA(at: inputURL, to: outputURL, credential: key, mode: mode)
        let result = try Archive(url: outputURL, accessMode: .read)
        let reference = try Archive(url: URL(fileURLWithPath: expected), accessMode: .read)
        let expectedEntries = Dictionary(uniqueKeysWithValues: reference.map { ($0.path, $0) })
        XCTAssertEqual(Set(result.map(\.path)), Set(expectedEntries.keys))
        var checked = 0
        for entry in result {
            let before = try XCTUnwrap(expectedEntries[entry.path])
            XCTAssertEqual(entry.uncompressedSize, before.uncompressedSize, entry.path)
            XCTAssertEqual(entry.fileAttributes[.posixPermissions] as? NSNumber, before.fileAttributes[.posixPermissions] as? NSNumber, entry.path)
            var hash = SHA256(), referenceHash = SHA256()
            let checksum = try result.extract(entry) { hash.update(data: $0) }
            let referenceChecksum = try reference.extract(before) { referenceHash.update(data: $0) }
            XCTAssertEqual(checksum, entry.checksum, entry.path)
            XCTAssertEqual(referenceChecksum, before.checksum, entry.path)
            XCTAssertEqual(hash.finalize(), referenceHash.finalize(), entry.path)
            checked += 1
        }
        print("Python/Swift IPA parity (\(mode)): \(checked) entries (SHA-256, CRC32, size, permissions)")
    }

    private func add(_ archive: Archive, _ path: String, _ data: Data) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             permissions: 0o755, compressionMethod: .deflate) { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
    }

    private func read(_ archive: Archive, _ entry: Entry) throws -> Data {
        var result = Data()
        let checksum = try archive.extract(entry) { result.append($0) }
        XCTAssertEqual(checksum, entry.checksum)
        return result
    }
}

private func hex(_ string: String) -> Data {
    let bytes = Array(string.utf8)
    precondition(bytes.count % 2 == 0)
    func nibble(_ c: UInt8) -> UInt8 { c >= 97 ? c - 87 : c - 48 }
    return Data(stride(from: 0, to: bytes.count, by: 2).map { nibble(bytes[$0]) << 4 | nibble(bytes[$0 + 1]) })
}

private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
