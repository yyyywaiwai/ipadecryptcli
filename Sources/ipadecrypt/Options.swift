import Darwin
import Foundation
import FairDecKit

struct CLIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct Options {
    static let usage = """
    Usage: ipadecrypt <fairplayipa_path> [-c <credential.bin>] [--mode fast|lowmem]

    Output: <name>.decrypted.ipa next to the input (never overwritten).
    Without -c: use ~/.ipadecrypt/credential.bin.
    If missing, prompt for a credential file and save its 16-byte contents.
    --mode: fast (more memory) or lowmem (default, lower memory usage).
    """

    let input: URL
    let credentialPath: String?
    let mode: FairDecKit.Mode
    var output: URL {
        input.deletingPathExtension().appendingPathExtension("decrypted.ipa")
    }

    init(_ arguments: [String]) throws {
        var positional: String?
        var credential: String?
        var selectedMode: FairDecKit.Mode?
        var index = 0
        var optionsEnded = false
        while index < arguments.count {
            let argument = arguments[index]
            if !optionsEnded && argument == "--" {
                optionsEnded = true
            } else if !optionsEnded && argument == "--mode" {
                index += 1
                guard selectedMode == nil, index < arguments.count else {
                    throw CLIError("Specify --mode once, followed by fast or lowmem.")
                }
                switch arguments[index] {
                case "fast": selectedMode = .fast
                case "lowmem": selectedMode = .lowMemory
                default: throw CLIError("Invalid mode: \(arguments[index]). Use fast or lowmem.")
                }
            } else if !optionsEnded && argument == "-c" {
                index += 1
                guard credential == nil, index < arguments.count, !arguments[index].isEmpty,
                      !arguments[index].hasPrefix("-") else {
                    throw CLIError("Specify -c once, followed by a credential file path.")
                }
                credential = arguments[index]
            } else {
                guard optionsEnded || !argument.hasPrefix("-") else {
                    throw CLIError("Unknown option: \(argument)\n\(Self.usage)")
                }
                guard positional == nil, !argument.isEmpty else { throw CLIError(Self.usage) }
                positional = argument
            }
            index += 1
        }
        guard let positional else { throw CLIError(Self.usage) }
        input = Self.fileURL(positional)
        credentialPath = credential
        mode = selectedMode ?? .lowMemory
    }

    static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    static func readCredential(at url: URL) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: 17) ?? Data()
        guard data.count == 16 else { throw CLIError("Credential must contain exactly 16 bytes: \(url.path)") }
        return data
    }

    func credential(home: URL, prompt: () -> String?) throws -> Data {
        if let credentialPath { return try Self.readCredential(at: Self.fileURL(credentialPath)) }
        let directory = home.appendingPathComponent(".ipadecrypt", isDirectory: true)
        let saved = directory.appendingPathComponent("credential.bin")
        var status = stat()
        if lstat(saved.path, &status) == 0 {
            return try Self.readCredential(at: saved)
        }
        guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard let response = prompt()?.trimmingCharacters(in: .whitespacesAndNewlines), !response.isEmpty else {
            throw CLIError("No credential path entered. You can also specify it with -c.")
        }
        let data = try Self.readCredential(at: Self.fileURL(response))
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else {
            throw CLIError("The credential storage path must be a regular directory.")
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let descriptor = open(saved.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try file.write(contentsOf: data)
            try file.close()
        } catch {
            try? file.close()
            try? fm.removeItem(at: saved)
            throw error
        }
        return data
    }

    func run(home: URL, prompt: () -> String?) throws -> URL {
        let values = try input.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw CLIError("The input must be a regular IPA file.") }
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CLIError("Output file already exists: \(output.path)")
        }
        let data = try credential(home: home, prompt: prompt)
        return try FairDecKit.decryptIPA(at: input, to: output, credential: data, mode: mode)
    }
}
