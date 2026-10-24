import Foundation
import ZIPFoundation

func supfPaths(_ names: Set<String>) -> [String] {
    var binaries: [String: String] = [:]
    for name in names.sorted() {
        if name.hasSuffix(".v5.supf") {
            binaries[String(name.dropLast(8))] = name
        } else if name.hasSuffix(".supf") {
            let binary = String(name.dropLast(5))
            if binaries[binary] == nil { binaries[binary] = name }
        }
    }
    return binaries.values.sorted()
}

func enclosingAppSINF(_ names: Set<String>, bundle: String) -> String? {
    var parts = bundle.split(separator: "/").map(String.init)
    while !parts.isEmpty {
        let prefix = parts.joined(separator: "/")
        parts.removeLast()
        guard prefix.hasSuffix(".app") else { continue }
        let scInfo = prefix + "/SC_Info/"
        let sinfs = names.filter {
            $0.hasPrefix(scInfo) && $0.hasSuffix(".sinf")
                && $0.filter({ $0 == "/" }).count == scInfo.filter({ $0 == "/" }).count
        }.sorted()
        guard !sinfs.isEmpty else { continue }
        let stem = String(prefix.split(separator: "/").last!.dropLast(4))
        for suffix in [".sinf", ".v4.sinf"] {
            let preferred = scInfo + stem + suffix
            if sinfs.contains(preferred) { return preferred }
        }
        return sinfs.first(where: { !$0.hasSuffix(".v4.sinf") }) ?? sinfs.first
    }
    return nil
}

private let zipBufferSize = 64 * 1024

private func extract(_ archive: Archive, _ entry: Entry, consume: (Data) throws -> Void) throws {
    // ZIPFoundation reads symlink payloads in one allocation, unlike regular files.
    guard entry.type != .symlink || (entry.compressedSize <= zipBufferSize && entry.uncompressedSize <= zipBufferSize) else {
        throw FairDecKitError.invalidData("Symlink target exceeds ZIP buffer: \(entry.path)")
    }
    var size: UInt64 = 0
    let checksum = try archive.extract(entry, bufferSize: zipBufferSize) { chunk in
        guard size <= entry.uncompressedSize, UInt64(chunk.count) <= entry.uncompressedSize - size else {
            throw FairDecKitError.invalidData("ZIP entry exceeds declared size: \(entry.path)")
        }
        size += UInt64(chunk.count)
        try autoreleasepool { try consume(chunk) }
    }
    guard checksum == entry.checksum, size == entry.uncompressedSize else {
        throw FairDecKitError.invalidData("ZIP checksum/size mismatch: \(entry.path)")
    }
}

private func read(_ archive: Archive, _ path: String) throws -> Data {
    guard let entry = archive[path], entry.type == .file else {
        throw FairDecKitError.invalidData("Missing ZIP file: \(path)")
    }
    return try read(archive, entry)
}

private func read(_ archive: Archive, _ entry: Entry) throws -> Data {
    var data = Data()
    try extract(archive, entry) { data.append($0) }
    return data
}

private func withEntryFile(
    _ archive: Archive, _ entry: Entry, in directory: URL, body: (URL) throws -> Void
) throws {
    try autoreleasepool {
        let url = directory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try extract(archive, entry) { try file.write(contentsOf: $0) }
        try file.close()
        try body(url)
    }
}

private enum EntryContent {
    case data(Data)
    case file(URL)
}

private func withEntry(
    _ archive: Archive, _ entry: Entry, mode: FairDecKit.Mode, temporary: URL,
    body: (EntryContent) throws -> Void
) throws {
    switch mode {
    case .lowMemory:
        try withEntryFile(archive, entry, in: temporary) { try body(.file($0)) }
    case .fast:
        try autoreleasepool { try body(.data(read(archive, entry))) }
    }
}

func readDecryptedBinaries(at url: URL, credential: Data, mode: FairDecKit.Mode) throws -> [String: Data] {
    let temporary = mode == .lowMemory ? try makeTemporaryDirectory(in: FileManager.default.temporaryDirectory) : nil
    defer { if let temporary { try? FileManager.default.removeItem(at: temporary) } }
    let archive = try Archive(url: url, accessMode: .read)
    var result: [String: Data] = [:]
    try processBinaries(in: archive, credential: credential, mode: mode,
                        temporary: temporary ?? FileManager.default.temporaryDirectory) { path, content in
        switch content {
        case .data(let data): result[path] = data
        case .file(let file): result[path] = try Data(contentsOf: file)
        }
    }
    return result
}

func writeIPA(from input: URL, to output: URL, credential: Data, mode: FairDecKit.Mode) throws {
    let archive = try Archive(url: input, accessMode: .read)
    let temporary = output.deletingLastPathComponent()
    let replacements = temporary.appendingPathComponent(UUID().uuidString + ".zip")
    defer { try? FileManager.default.removeItem(at: replacements) }
    var replaced: Set<String> = []
    do {
        let destination = try Archive(url: replacements, accessMode: .create)
        try processBinaries(in: archive, credential: credential, mode: mode, temporary: temporary) { binaryPath, content in
            guard let entry = archive[binaryPath] else {
                throw FairDecKitError.invalidData("Missing binary: \(binaryPath)")
            }
            try write(destination, entry: entry, content: content)
            replaced.insert(binaryPath)
        }
    }
    // Validate even unchanged entries before copying their original compressed bytes.
    for entry in archive where !replaced.contains(entry.path) { try extract(archive, entry) { _ in } }
    try preserveZIP(from: input, replacing: replacements, to: output)
}

private func write(_ archive: Archive, entry: Entry, content: EntryContent) throws {
    switch content {
    case .data(let data):
        try write(archive, entry: entry) { position, size in
            data.subdata(in: Int(position)..<(Int(position) + size))
        }
    case .file(let url):
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try write(archive, entry: entry) { position, size in
            try autoreleasepool { try readExactly(file, at: Int(position), count: size) }
        }
    }
}

private func write(_ archive: Archive, entry: Entry, provider: Provider) throws {
    guard let size = Int64(exactly: entry.uncompressedSize) else {
        throw FairDecKitError.invalidData("ZIP entry is too large: \(entry.path)")
    }
    let compression: CompressionMethod = entry.isCompressed ? .deflate : .none
    try archive.addEntry(with: entry.path, type: entry.type, uncompressedSize: size,
                         compressionMethod: compression,
                         bufferSize: zipBufferSize, provider: provider)
}

private func processBinaries(
    in archive: Archive, credential: Data, mode: FairDecKit.Mode, temporary: URL,
    consume: (String, EntryContent) throws -> Void
) throws {
    let members = archive.map(\.path)
    let names = Set(members)
    guard names.count == members.count else {
        throw FairDecKitError.invalidData("Input ZIP has duplicate member names")
    }
    let transform = try BlockTransform()
    var decrypted = 0
    for supfPath in supfPaths(names) {
        guard let separator = supfPath.range(of: "/SC_Info/", options: .backwards) else {
            throw FairDecKitError.invalidData("SUPF outside SC_Info: \(supfPath)")
        }
        let bundle = String(supfPath[..<separator.lowerBound])
        let filename = String(supfPath[separator.upperBound...])
        let v5 = filename.hasSuffix(".v5.supf")
        let stem = String(filename.dropLast(v5 ? 8 : 5))
        let binaryPath = bundle + "/" + stem
        guard let entry = archive[binaryPath], entry.type == .file else {
            throw FairDecKitError.invalidData("Missing ZIP file: \(binaryPath)")
        }
        try withEntry(archive, entry, mode: mode, temporary: temporary) { source in
            do {
                switch source {
                case .data(let data): _ = try arm64EncryptionInfo(data)
                case .file(let file): _ = try arm64EncryptionInfo(at: file)
                }
            } catch FairDecKitError.notEncrypted {
                return
            }
            var sinfPath = bundle + "/SC_Info/" + stem + (v5 ? ".v4.sinf" : ".sinf")
            if !names.contains(sinfPath), v5 { sinfPath = bundle + "/SC_Info/" + stem + ".sinf" }
            if !names.contains(sinfPath) {
                guard let fallback = enclosingAppSINF(names, bundle: bundle) else {
                    throw FairDecKitError.invalidData("SUPF lacks SINF: \(supfPath)")
                }
                sinfPath = fallback
            }
            let sinf = try read(archive, sinfPath), supf = try read(archive, supfPath)
            switch source {
            case .data(let data):
                let clear = try decryptMachO(data, sinf: sinf, supf: supf, credential: credential, transform: transform)
                try consume(binaryPath, .data(clear))
            case .file(let file):
                try decryptMachO(at: file, sinf: sinf, supf: supf, credential: credential, transform: transform)
                try consume(binaryPath, source)
            }
            decrypted += 1
        }
    }
    guard decrypted > 0 else { throw FairDecKitError.noEncryptedBinaries }
}
