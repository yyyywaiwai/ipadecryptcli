import Foundation

public enum FairDecKitError: Error, LocalizedError, Sendable {
    case invalidCredential
    case invalidData(String)
    case notEncrypted
    case noEncryptedBinaries

    public var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Credential must contain exactly 16 bytes"
        case .invalidData(let reason): return reason
        case .notEncrypted: return "Mach-O cryptid is already zero"
        case .noEncryptedBinaries: return "No encrypted arm64 binaries with supported SINF/SUPF"
        }
    }
}

public enum FairDecKit {
    public enum Mode: Sendable, Equatable {
        /// Processes ZIP entries through temporary files with bounded page buffers.
        case lowMemory
        /// Processes each complete ZIP entry in memory, avoiding temporary-entry I/O.
        case fast
    }

    /// Returns each decrypted binary keyed by its path within the IPA, without writing an output IPA.
    /// Unlike decryptIPA, this retains all decrypted binaries in memory.
    public static func decryptBinaries(
        in input: URL, credential: Data, mode: Mode = .lowMemory
    ) throws -> [String: Data] {
        guard credential.count == 16 else { throw FairDecKitError.invalidCredential }
        guard input.isFileURL else { throw FairDecKitError.invalidData("Input must be a file URL") }
        return try readDecryptedBinaries(at: input, credential: credential, mode: mode)
    }

    /// Decrypts the arm64 slice and clears cryptid. Other slices and bytes remain unchanged.
    /// SINF and SUPF are the binary's SC_Info records, not paths to files.
    public static func decryptBinary(
        _ source: Data, sinf: Data, supf: Data, credential: Data
    ) throws -> Data {
        guard credential.count == 16 else { throw FairDecKitError.invalidCredential }
        return try decryptMachO(source, sinf: sinf, supf: supf, credential: credential,
                                 transform: BlockTransform())
    }

    /// Writes a new IPA, preserving the input. The output path must not exist.
    /// Synchronous and CPU intensive: call off the main actor in an app.
    @discardableResult
    public static func decryptIPA(
        at input: URL, to output: URL, credential: Data, mode: Mode = .lowMemory
    ) throws -> URL {
        guard credential.count == 16 else { throw FairDecKitError.invalidCredential }
        let fm = FileManager.default
        guard input.isFileURL, output.isFileURL else {
            throw FairDecKitError.invalidData("Input and output must be file URLs")
        }
        guard input.standardizedFileURL.resolvingSymlinksInPath()
                != output.standardizedFileURL.resolvingSymlinksInPath() else {
            throw FairDecKitError.invalidData("Input and output must differ")
        }
        guard !fm.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let parent = output.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let temporary = try makeTemporaryDirectory(in: parent)
        defer { try? fm.removeItem(at: temporary) }
        let provisional = temporary.appendingPathComponent("output.ipa")
        try writeIPA(from: input, to: provisional, credential: credential, mode: mode)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: provisional.path)
        // shortcut: local hard-link-capable volumes only; add File Provider export if needed.
        try fm.linkItem(at: provisional, to: output)
        return output
    }
}

func makeTemporaryDirectory(in parent: URL) throws -> URL {
    let url = parent.appendingPathComponent(".fairdeckit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                           attributes: [.posixPermissions: 0o700])
    return url
}

func readExactly(_ file: FileHandle, at offset: Int, count: Int) throws -> Data {
    try file.seek(toOffset: UInt64(offset))
    var data = try file.read(upToCount: count) ?? Data()
    while data.count < count {
        guard let chunk = try file.read(upToCount: count - data.count), !chunk.isEmpty else {
            throw FairDecKitError.invalidData("Truncated file at offset \(offset)")
        }
        data.append(chunk)
    }
    return data
}

extension Data {
    func checkedBytes(_ offset: Int, _ length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset <= count, length <= count - offset else {
            throw FairDecKitError.invalidData("Truncated data at offset \(offset)")
        }
        return subdata(in: (startIndex + offset)..<(startIndex + offset + length))
    }

    func uint32(_ offset: Int, bigEndian: Bool = false) throws -> UInt32 {
        guard offset >= 0, offset <= count, count - offset >= 4 else {
            throw FairDecKitError.invalidData("Truncated word at offset \(offset)")
        }
        let i = startIndex + offset
        if bigEndian {
            return UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16
                | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
        }
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8
            | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }

    func uint64BE(_ offset: Int) throws -> UInt64 {
        try UInt64(uint32(offset, bigEndian: true)) << 32
            | UInt64(uint32(offset + 4, bigEndian: true))
    }
}

struct MachOInfo {
    let base: Int
    let cryptOffset: Int
    let cryptSize: Int
    let cryptIDOffset: Int
}

func arm64EncryptionInfo(_ data: Data) throws -> MachOInfo {
    let arm64: UInt32 = 0x0100000c
    let magic = try data.uint32(0, bigEndian: true)
    var slices: [(Int, Int)] = []
    if magic == 0xcafebabe || magic == 0xcafebabf {
        let count = Int(try data.uint32(4, bigEndian: true))
        let stride = magic == 0xcafebabe ? 20 : 32
        guard (1...16).contains(count), data.count >= 8 + count * stride else {
            throw FairDecKitError.invalidData("Invalid FAT architecture table")
        }
        for i in 0..<count {
            let position = 8 + i * stride
            guard try data.uint32(position, bigEndian: true) == arm64 else { continue }
            let offset: UInt64
            let size: UInt64
            if stride == 20 {
                offset = UInt64(try data.uint32(position + 8, bigEndian: true))
                size = UInt64(try data.uint32(position + 12, bigEndian: true))
            } else {
                offset = try data.uint64BE(position + 8)
                size = try data.uint64BE(position + 16)
            }
            guard offset <= UInt64(data.count), size <= UInt64(data.count) - offset else {
                throw FairDecKitError.invalidData("arm64 slice exceeds file")
            }
            slices.append((Int(offset), Int(size)))
        }
    } else if magic == 0xcffaedfe {
        slices = [(0, data.count)]
    } else {
        throw FairDecKitError.invalidData("Not a supported arm64 Mach-O")
    }
    guard slices.count == 1 else {
        throw FairDecKitError.invalidData("Expected one arm64 slice, found \(slices.count)")
    }
    let (base, sliceSize) = slices[0]
    guard sliceSize >= 32, base <= data.count, sliceSize <= data.count - base,
          try data.uint32(base) == 0xfeedfacf, try data.uint32(base + 4) == arm64 else {
        throw FairDecKitError.invalidData("Invalid arm64 Mach-O header")
    }
    let commandCount = Int(try data.uint32(base + 16))
    let commandSize = Int(try data.uint32(base + 20))
    guard commandCount <= 1000, commandSize <= sliceSize - 32 else {
        throw FairDecKitError.invalidData("Load commands exceed arm64 slice")
    }
    var position = base + 32
    let end = position + commandSize
    var found: [(Int, Int, UInt32, Int)] = []
    for _ in 0..<commandCount {
        guard end - position >= 8 else { throw FairDecKitError.invalidData("Truncated load command") }
        let command = try data.uint32(position)
        let size = Int(try data.uint32(position + 4))
        guard size >= 8, size <= end - position else {
            throw FairDecKitError.invalidData("Invalid load command size")
        }
        if command == 0x2c {
            guard size >= 24 else { throw FairDecKitError.invalidData("Short encryption info command") }
            found.append((Int(try data.uint32(position + 8)), Int(try data.uint32(position + 12)),
                          try data.uint32(position + 16), position + 16))
        }
        position += size
    }
    guard found.count == 1 else { throw FairDecKitError.invalidData("Expected one encryption command") }
    let (offset, size, cryptID, idOffset) = found[0]
    if cryptID == 0 { throw FairDecKitError.notEncrypted }
    guard cryptID == 1, size > 0, size % 4096 == 0 else {
        throw FairDecKitError.invalidData("Unsupported cryptid/size: \(cryptID), \(size)")
    }
    guard offset <= sliceSize, size <= sliceSize - offset, idOffset + 4 <= base + offset else {
        throw FairDecKitError.invalidData("Invalid encrypted region bounds")
    }
    return MachOInfo(base: base, cryptOffset: offset, cryptSize: size, cryptIDOffset: idOffset)
}

func arm64SUPFRecordOffset(_ supf: Data, requiredPages: Int) throws -> Int {
    let prefix = [UInt8](try supf.checkedBytes(0, 4))
    guard [3, 5].contains(prefix[0]), ["507", "510", "612"].contains(String(bytes: prefix[1...3], encoding: .ascii)) else {
        throw FairDecKitError.invalidData("Unsupported SUPF format")
    }
    let headerSize = prefix[0] == 3 ? 32 : 12
    let count = Int(try supf.uint32(8, bigEndian: true))
    guard (1...16).contains(count) else { throw FairDecKitError.invalidData("Invalid SUPF architecture count") }
    var position = 12
    for _ in 0..<count {
        guard position <= supf.count, supf.count - position >= 4 + headerSize else {
            throw FairDecKitError.invalidData("Truncated SUPF architecture header")
        }
        let length = Int(try supf.uint32(position, bigEndian: true))
        let cpu = try supf.uint32(position + 4, bigEndian: true)
        let subtype = try supf.uint32(position + 8, bigEndian: true)
        guard length >= headerSize, length <= supf.count - position - 4 else {
            throw FairDecKitError.invalidData("Invalid SUPF architecture length")
        }
        let pages = Int(try supf.uint32(position + headerSize, bigEndian: true))
        if cpu == 0x0100000c && subtype == 0 {
            guard pages >= requiredPages, pages <= (length - headerSize) / 32 else {
                throw FairDecKitError.invalidData("Incomplete SUPF arm64 page records")
            }
            return position + 4 + headerSize
        }
        position += length + 4
    }
    throw FairDecKitError.invalidData("arm64 SUPF record missing")
}

func decryptMachO(
    _ source: Data, sinf: Data, supf: Data, credential: Data, transform: BlockTransform
) throws -> Data {
    let info = try arm64EncryptionInfo(source)
    var result = Data(source)
    try decryptPages(info, sinf: sinf, supf: supf, credential: credential, transform: transform,
                     read: { try source.checkedBytes($0, $1) },
                     write: { result.replaceSubrange($0..<($0 + $1.count), with: $1) })
    return result
}

func arm64EncryptionInfo(at url: URL) throws -> MachOInfo {
    try autoreleasepool {
        try arm64EncryptionInfo(Data(contentsOf: url, options: .alwaysMapped))
    }
}

func decryptMachO(at url: URL, sinf: Data, supf: Data, credential: Data, transform: BlockTransform) throws {
    // Mapping reads only the Mach-O headers; encrypted pages are read/written through a 4 KB buffer.
    let info = try arm64EncryptionInfo(at: url)
    let file = try FileHandle(forUpdating: url)
    defer { try? file.close() }
    try decryptPages(info, sinf: sinf, supf: supf, credential: credential, transform: transform,
                     read: { try readExactly(file, at: $0, count: $1) },
                     write: { offset, data in
        try file.seek(toOffset: UInt64(offset))
        try file.write(contentsOf: data)
    })
    try file.close()
}

private func decryptPages(
    _ info: MachOInfo, sinf: Data, supf: Data, credential: Data, transform: BlockTransform,
    read: (Int, Int) throws -> Data, write: (Int, Data) throws -> Void
) throws {
    let pageCount = info.cryptSize / 4096
    let recordStart = try arm64SUPFRecordOffset(supf, requiredPages: pageCount)
    let work = try deriveWork16(credential: credential, sinf: sinf)
    for page in 0..<pageCount {
        try autoreleasepool {
            let record = [UInt8](try supf.checkedBytes(recordStart + 32 * page, 32))
            let absoluteIndex = (info.base + info.cryptOffset) / 4096 + page
            guard let index = UInt32(exactly: absoluteIndex) else {
                throw FairDecKitError.invalidData("Page index exceeds UInt32")
            }
            let key = derivePageKey(wrapped: Array(record[0..<16]), index: index, work: work, transform: transform)
            let start = info.base + info.cryptOffset + 4096 * page
            let clear = try aesCBC(try read(start, 4096), key: key, iv: Array(record[16..<32]))
            try write(start, clear)
        }
    }
    try write(info.cryptIDOffset, Data([0, 0, 0, 0]))
}
