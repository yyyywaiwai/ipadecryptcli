import CryptoKit
import Foundation
import XCTest
@testable import ipadecrypt

final class OptionsTests: XCTestCase {
    var root: URL!
    let bytes = Data(0..<16)
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func source(_ data: Data? = nil) throws -> URL {
        let url = root.appendingPathComponent("credential source.bin")
        try (data ?? bytes).write(to: url)
        return url
    }
    var saved: URL { root.appendingPathComponent(".ipadecrypt/credential.bin") }

    func testArgumentsAndOutput() throws {
        for args in [["some app.ipa", "-c", "key.bin"], ["-c", "key.bin", "some app.ipa"]] {
            let options = try Options(args)
            XCTAssertEqual(options.input.lastPathComponent, "some app.ipa")
            XCTAssertEqual(options.output.lastPathComponent, "some app.decrypted.ipa")
            XCTAssertEqual(options.credentialPath, "key.bin")
        }
        XCTAssertEqual(try Options(["--", "-app.ipa"]).input.lastPathComponent, "-app.ipa")
        XCTAssertEqual(Options.fileURL("~/credential.bin").path,
                       FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("credential.bin").path)
    }

    func testModeSelection() throws {
        XCTAssertEqual(try Options(["app.ipa"]).mode, .lowMemory)
        XCTAssertEqual(try Options(["app.ipa", "--mode", "lowmem"]).mode, .lowMemory)
        XCTAssertEqual(try Options(["--mode", "fast", "app.ipa", "-c", "key.bin"]).mode, .fast)
        for args in [["app.ipa", "--mode"], ["app.ipa", "--mode", "slow"],
                     ["app.ipa", "--mode", ""], ["app.ipa", "--mode", "-c", "key.bin"],
                     ["app.ipa", "--mode", "fast", "--mode", "lowmem"]] {
            XCTAssertThrowsError(try Options(args), "\(args)")
        }
    }

    func testInvalidArguments() {
        for args in [[], ["-c"], ["app.ipa", "-c"], ["app.ipa", "extra"], ["app.ipa", "--unknown"],
                     ["app.ipa", "-c", "a", "-c", "b"], ["app.ipa", "-c", ""], ["app.ipa", "-c", "-x"]] {
            XCTAssertThrowsError(try Options(args), "\(args)")
        }
    }

    func testExplicitCredentialDoesNotSaveOrPrompt() throws {
        let options = try Options(["app.ipa", "-c", source().path])
        XCTAssertEqual(try options.credential(home: root) { XCTFail("Unexpected prompt"); return nil }, bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
    }

    func testPromptImportsPrivateCopyAndReusesIt() throws {
        let url = try source()
        let options = try Options(["app.ipa"])
        XCTAssertEqual(try options.credential(home: root) { "  \(url.path)  " }, bytes)
        XCTAssertEqual(try Data(contentsOf: saved), bytes)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        for (url, permissions) in [(saved, 0o600), (saved.deletingLastPathComponent(), 0o700)] {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, permissions)
        }
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(try options.credential(home: root) { XCTFail("Unexpected prompt"); return nil }, bytes)
    }

    func testInvalidCredentialIsNotSaved() throws {
        for length in [0, 15, 17, 100] {
            let url = try source(Data(repeating: 0, count: length))
            XCTAssertThrowsError(try Options(["app.ipa"]).credential(home: root) { url.path })
            XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        }
    }

    func testMissingExplicitFileDoesNotFallBack() throws {
        XCTAssertThrowsError(try Options(["app.ipa", "-c", root.appendingPathComponent("missing").path])
            .credential(home: root) { XCTFail("Unexpected prompt"); return nil })
    }

    func testEmptyPromptOrEOFDoesNotSave() throws {
        for response: String? in [nil, "", "  "] {
            XCTAssertThrowsError(try Options(["app.ipa"]).credential(home: root) { response })
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
    }

    func testInvalidCacheDoesNotPromptOrOverwrite() throws {
        try FileManager.default.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: saved)
        XCTAssertThrowsError(try Options(["app.ipa"]).credential(home: root) { XCTFail("Unexpected prompt"); return nil })
        XCTAssertEqual(try Data(contentsOf: saved), Data([1]))
    }

    func testSymlinkDirectoryIsNotUsedForImport() throws {
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: saved.deletingLastPathComponent(), withDestinationURL: elsewhere)
        let url = try source()
        XCTAssertThrowsError(try Options(["app.ipa"]).credential(home: root) { url.path })
        XCTAssertFalse(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("credential.bin").path))
    }

    func testMissingInputAndExistingOutputDoNotPrompt() throws {
        let input = root.appendingPathComponent("app.ipa")
        let options = try Options([input.path])
        XCTAssertThrowsError(try options.run(home: root) { XCTFail("Unexpected prompt"); return nil })
        try Data([1, 2]).write(to: input)
        try Data([3, 4]).write(to: options.output)
        XCTAssertThrowsError(try options.run(home: root) { XCTFail("Unexpected prompt"); return nil })
        XCTAssertEqual(try Data(contentsOf: input), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: options.output), Data([3, 4]))
    }

    func testDecryptSyntheticIPAAndPreserveInput() throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "encrypted", withExtension: "zip", subdirectory: "Fixtures"))
        for mode in ["fast", "lowmem"] {
            let input = root.appendingPathComponent("sample-\(mode).ipa")
            try FileManager.default.copyItem(at: fixture, to: input)
            let original = try Data(contentsOf: input)
            let options = try Options([input.path, "-c", source().path, "--mode", mode])
            let output = try options.run(home: root) { XCTFail("Unexpected prompt"); return nil }
            XCTAssertEqual(try Data(contentsOf: input), original)
            let extracted = root.appendingPathComponent("extracted-\(mode)")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", output.path, extracted.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let binary = try Data(contentsOf: extracted.appendingPathComponent("Payload/Sample.app/Sample"))
            XCTAssertEqual(SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined(),
                           "fe99157964b099981db8b68e7277c1d65dde7967ce6e45786b3f32e60410bc3d")
            XCTAssertEqual(try String(contentsOf: extracted.appendingPathComponent("Payload/Sample.app/resource.txt")),
                           "resource preserved")
            XCTAssertThrowsError(try options.run(home: root) { XCTFail("Unexpected prompt"); return nil })
        }
    }

    func testBrokenIPADoesNotPublishOutput() throws {
        let input = root.appendingPathComponent("broken.ipa")
        try Data("not a zip".utf8).write(to: input)
        let options = try Options([input.path, "-c", source().path])
        XCTAssertThrowsError(try options.run(home: root) { XCTFail("Unexpected prompt"); return nil })
        XCTAssertFalse(FileManager.default.fileExists(atPath: options.output.path))
        XCTAssertEqual(try Data(contentsOf: input), Data("not a zip".utf8))
    }
}
