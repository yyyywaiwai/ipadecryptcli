import CommonCrypto
import CryptoKit
import Foundation
import XCTest
import ZIPFoundation
@testable import FairDecKit

final class LargeEncryptedIPATests: XCTestCase {
    private let binaryPath = "Payload/Large.app/Large"
    private let credential = Data(0..<16)

    private struct Fixture {
        let input: URL
        let credentialFile: URL
        let size: Int
        let encryptedSize: Int
        let plainSHA256: String
        let cipherSHA256: String
    }

    private func hex(_ string: String) -> Data {
        let chars = Array(string)
        return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! })
    }

    private func hashString(_ hash: SHA256.Digest) -> String {
        hash.map { String(format: "%02x", $0) }.joined()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func encrypt(_ plain: Data, key: [UInt8], iv: [UInt8]) throws -> Data {
        var result = Data(count: plain.count + 16)
        let capacity = result.count
        var written = 0
        let status = result.withUnsafeMutableBytes { destination in
            plain.withUnsafeBytes { source in
                key.withUnsafeBytes { key in
                    iv.withUnsafeBytes { iv in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                                key.baseAddress, 16, iv.baseAddress, source.baseAddress, plain.count,
                                destination.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess, written == plain.count else { throw FairDecKitError.invalidData("Fixture encryption failed") }
        result.count = written
        return result
    }

    private func generate(in root: URL, pages: Int) throws -> Fixture {
        let referenceURL = try XCTUnwrap(Bundle.module.url(forResource: "reference", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: referenceURL)) as? [String: Any])
        let binary = try XCTUnwrap((reference["binaries"] as? [[String: Any]])?.first)
        let sinf = hex(try XCTUnwrap(binary["sinf"] as? String))
        var header = hex(try XCTUnwrap(binary["header"] as? String))
        let encryptedSize = pages * 4096
        guard encryptedSize <= UInt32.max else { throw FairDecKitError.invalidData("Mach-O cryptsize is a 32-bit field") }
        header.replaceSubrange(44..<48, with: zipBytes(UInt64(encryptedSize), width: 4))
        header.append(Data(repeating: 0, count: 4096 - header.count))
        var clearHeader = header
        clearHeader.replaceSubrange(48..<52, with: Data(repeating: 0, count: 4))
        let tail = Data(repeating: 0x5a, count: 8192)
        let size = 4096 + encryptedSize + tail.count
        var supf = hex(try XCTUnwrap(binary["supf"] as? String)).prefix(48)
        // SUPF integers are big-endian, unlike Mach-O and ZIP fields.
        func bigWord(_ value: Int) -> Data {
            Data([24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
        }
        supf.replaceSubrange(12..<16, with: bigWord(32 + pages * 32))
        supf.replaceSubrange(44..<48, with: bigWord(pages))
        let wrapped = Array(UInt8(0x30)...UInt8(0x3f))
        let iv = Array(UInt8(0x40)...UInt8(0x4f))
        let record = Data(wrapped + iv)
        supf.reserveCapacity(48 + pages * 32)
        for _ in 0..<pages { supf.append(record) }
        let transform = try BlockTransform()
        let work = try deriveWork16(credential: credential, sinf: sinf)
        let input = root.appendingPathComponent("encrypted.ipa")
        let credentialFile = root.appendingPathComponent("credential.bin")
        guard !FileManager.default.fileExists(atPath: input.path) else { throw CocoaError(.fileWriteFileExists) }
        try credential.write(to: credentialFile, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialFile.path)
        var plainHash = SHA256(), cipherHash = SHA256()
        var consumed = 0
        let pattern = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0) })
        do {
            let archive = try Archive(url: input, accessMode: .create)
            try archive.addEntry(with: binaryPath, type: .file, uncompressedSize: Int64(size),
                                 permissions: 0o751, compressionMethod: .none, bufferSize: 64 * 1024) { position, count in
                guard position == Int64(consumed), count % 4096 == 0 else {
                    throw FairDecKitError.invalidData("Non-sequential fixture provider")
                }
                var output = Data()
                output.reserveCapacity(count)
                for offset in stride(from: consumed, to: consumed + count, by: 4096) {
                    try autoreleasepool {
                        let plain: Data
                        let encrypted: Data
                        if offset == 0 {
                            plain = clearHeader
                            encrypted = header
                        } else if offset < 4096 + encryptedSize {
                            let page = (offset - 4096) / 4096
                            var data = pattern
                            data.replaceSubrange(0..<8, with: zipBytes(UInt64(page), width: 8))
                            plain = data
                            let key = derivePageKey(wrapped: wrapped, index: UInt32(page + 1), work: work, transform: transform)
                            encrypted = try self.encrypt(plain, key: key, iv: iv)
                            if page > 0 && page % 65536 == 0 { self.log("Generated encrypted pages: \(page)/\(pages)") }
                        } else {
                            let start = offset - 4096 - encryptedSize
                            plain = tail.subdata(in: start..<(start + 4096))
                            encrypted = plain
                        }
                        plainHash.update(data: plain)
                        cipherHash.update(data: encrypted)
                        output.append(encrypted)
                    }
                }
                consumed += count
                return output
            }
            for (path, data) in [("Payload/Large.app/SC_Info/Large.sinf", sinf),
                                 ("Payload/Large.app/SC_Info/Large.supf", Data(supf)),
                                 ("Payload/Large.app/resource.txt", Data("resource preserved".utf8))] {
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { p, n in
                    data.subdata(in: Int(p)..<(Int(p) + n))
                }
            }
        }
        guard consumed == size else { throw FairDecKitError.invalidData("Incomplete generated binary") }
        return Fixture(input: input, credentialFile: credentialFile, size: size, encryptedSize: encryptedSize,
                       plainSHA256: hashString(plainHash.finalize()), cipherSHA256: hashString(cipherHash.finalize()))
    }

    private func verify(_ url: URL, fixture: Fixture, decrypted: Bool) throws -> String {
        let archive = try Archive(url: url, accessMode: .read)
        let entry = try XCTUnwrap(archive[binaryPath])
        XCTAssertEqual(entry.uncompressedSize, UInt64(fixture.size))
        var hash = SHA256(), count = 0
        var prefix = Data(), tail = Data()
        let crc = try archive.extract(entry, bufferSize: 1024 * 1024) { chunk in
            if prefix.count < 56 { prefix.append(chunk.prefix(56 - prefix.count)) }
            tail = Data(chunk.suffix(8192))
            hash.update(data: chunk)
            count += chunk.count
        }
        let digest = hashString(hash.finalize())
        guard digest == (decrypted ? fixture.plainSHA256 : fixture.cipherSHA256),
              crc == entry.checksum, count == fixture.size,
              try prefix.uint32(48) == (decrypted ? 0 : 1),
              try prefix.uint32(44) == UInt32(fixture.encryptedSize),
              tail == Data(repeating: 0x5a, count: 8192) else {
            throw FairDecKitError.invalidData("Binary SHA-256, CRC, length, cryptid or tail verification failed: \(url.path)")
        }
        let resource = try XCTUnwrap(archive["Payload/Large.app/resource.txt"])
        var data = Data()
        _ = try archive.extract(resource) { data.append($0) }
        guard data == Data("resource preserved".utf8) else { throw FairDecKitError.invalidData("Resource changed") }
        return digest
    }

    func testSmallEncryptedGeneratorRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try generate(in: root, pages: 2)
        _ = try verify(fixture.input, fixture: fixture, decrypted: false)
        for (name, mode) in [("lowmem", FairDecKit.Mode.lowMemory), ("fast", .fast)] {
            let output = root.appendingPathComponent("\(name).ipa")
            try FairDecKit.decryptIPA(at: fixture.input, to: output, credential: credential, mode: mode)
            _ = try verify(output, fixture: fixture, decrypted: true)
        }
    }

    #if os(macOS)
    func testOver4GiBEncryptedBinaryWithInstalledCLI() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["FAIRDECKIT_LARGE_ENCRYPTED_DIR"], let binary = env["FAIRDECKIT_IPADECRYPT_BIN"] else {
            throw XCTSkip("Set FAIRDECKIT_LARGE_ENCRYPTED_DIR and FAIRDECKIT_IPADECRYPT_BIN for the >4GiB encrypted test")
        }
        executionTimeAllowance = 3600
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var report: [String: Any] = ["status": "generating", "cli": binary]
        let reportURL = root.appendingPathComponent("report.json")
        func save() throws {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
        }
        try save()
        do {
            let generated = Date()
            let fixture = try generate(in: root, pages: Int(UInt32.max) / 4096)
            let generationSeconds = Date().timeIntervalSince(generated)
            guard fixture.size > Int(UInt32.max) + 1, try zipDirectory(at: fixture.input).zip64End != nil else {
                throw FairDecKitError.invalidData("Fixture is not a >4GiB ZIP64 binary")
            }
            report.merge(["input": fixture.input.path, "binary_size": fixture.size,
                          "encrypted_size": fixture.encryptedSize, "encrypted_pages": fixture.encryptedSize / 4096,
                          "expected_plaintext_sha256": fixture.plainSHA256, "expected_ciphertext_sha256": fixture.cipherSHA256,
                          "generation_seconds": generationSeconds, "status": "decrypting"], uniquingKeysWith: { _, new in new })
            try save()
            log("Fixture generated: \(fixture.size) bytes, encrypted=\(fixture.encryptedSize), seconds=\(generationSeconds)")
            var results: [[String: Any]] = []
            for mode in ["lowmem", "fast"] {
                let input = root.appendingPathComponent("\(mode).ipa")
                try FileManager.default.linkItem(at: fixture.input, to: input)
                let timeLog = root.appendingPathComponent("\(mode).time.log")
                let stdout = root.appendingPathComponent("\(mode).stdout.log")
                let stderr = root.appendingPathComponent("\(mode).stderr.log")
                XCTAssertTrue(FileManager.default.createFile(atPath: stdout.path, contents: nil))
                XCTAssertTrue(FileManager.default.createFile(atPath: stderr.path, contents: nil))
                let out = try FileHandle(forWritingTo: stdout), err = try FileHandle(forWritingTo: stderr)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/time")
                process.arguments = ["-l", "-o", timeLog.path, binary, input.path, "-c", fixture.credentialFile.path, "--mode", mode]
                process.standardOutput = out
                process.standardError = err
                let start = Date()
                log("Starting installed CLI: --mode \(mode)")
                try process.run()
                process.waitUntilExit()
                try out.close()
                try err.close()
                let seconds = Date().timeIntervalSince(start)
                guard process.terminationStatus == 0 else {
                    throw FairDecKitError.invalidData("CLI \(mode) failed (\(process.terminationStatus)): \(try String(contentsOf: stderr))")
                }
                let output = input.deletingPathExtension().appendingPathExtension("decrypted.ipa")
                let digest = try verify(output, fixture: fixture, decrypted: true)
                guard try zipDirectory(at: output).zip64End != nil else { throw FairDecKitError.invalidData("Output lost ZIP64") }
                let before = try zipDirectory(at: fixture.input), after = try zipDirectory(at: output)
                guard before.records.count == after.records.count else { throw FairDecKitError.invalidData("ZIP entries changed") }
                for (a, b) in zip(before.records, after.records) {
                    var expected = a.header
                    expected.replaceSubrange(16..<20, with: b.header[16..<20])
                    guard expected == b.header else { throw FairDecKitError.invalidData("ZIP metadata changed") }
                }
                results.append(["mode": mode, "exit_code": process.terminationStatus, "seconds": seconds,
                                "output": output.path, "binary_sha256": digest, "all_bytes_verified": true,
                                "zip64_preserved": true, "metadata_preserved": true, "resource_preserved": true,
                                "time_log": timeLog.path])
                report["modes"] = results
                try save()
                try FileManager.default.removeItem(at: input)
                log("Verified --mode \(mode): \(seconds) seconds; SHA256=\(digest)")
            }
            _ = try verify(fixture.input, fixture: fixture, decrypted: false)
            guard try Data(contentsOf: fixture.credentialFile) == credential else { throw FairDecKitError.invalidData("Credential changed") }
            report["status"] = "passed"
            report["input_binary_unchanged"] = true
            report["credential_unchanged"] = true
            try save()
        } catch {
            report["status"] = "failed"
            report["error"] = error.localizedDescription
            try? save()
            throw error
        }
    }
    #endif
}
