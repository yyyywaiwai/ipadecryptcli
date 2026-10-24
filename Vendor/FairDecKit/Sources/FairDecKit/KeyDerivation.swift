import CommonCrypto
import CryptoKit
import Foundation

func aesCBC(_ data: Data, key: [UInt8], iv: [UInt8]) throws -> Data {
    guard key.count == 16, iv.count == 16, !data.isEmpty, data.count % 16 == 0 else {
        throw FairDecKitError.invalidData("Invalid AES-CBC dimensions")
    }
    var output = Data(count: data.count + kCCBlockSizeAES128)
    let capacity = output.count
    var written = 0
    let status = output.withUnsafeMutableBytes { destination in
        data.withUnsafeBytes { source in
            key.withUnsafeBytes { keyBytes in
                iv.withUnsafeBytes { ivBytes in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                            source.baseAddress, data.count, destination.baseAddress, capacity, &written)
                }
            }
        }
    }
    guard status == kCCSuccess, written == data.count else {
        throw FairDecKitError.invalidData("AES-CBC failed: \(status)")
    }
    output.count = written
    return output
}

private func atoms(_ data: Data, in range: Range<Int>) throws -> [(String, Range<Int>)] {
    var position = range.lowerBound
    var result: [(String, Range<Int>)] = []
    while position < range.upperBound {
        guard range.upperBound - position >= 8 else {
            throw FairDecKitError.invalidData("Truncated SINF atom")
        }
        let size = Int(try data.uint32(position, bigEndian: true))
        guard size >= 8, size <= range.upperBound - position else {
            throw FairDecKitError.invalidData("Invalid SINF atom size")
        }
        let type = String(decoding: try data.checkedBytes(position + 4, 4), as: UTF8.self)
        result.append((type, (position + 8)..<(position + size)))
        position += size
    }
    return result
}

private func sinfField(_ data: Data, _ wanted: String) throws -> Data {
    let roots = try atoms(data, in: 0..<data.count)
    guard roots.count == 1, roots[0].0 == "sinf" else {
        throw FairDecKitError.invalidData("Expected outer sinf atom")
    }
    let containers = try atoms(data, in: roots[0].1).filter { $0.0 == "schi" }
    guard containers.count == 1 else { throw FairDecKitError.invalidData("Expected one schi container") }
    let fields = try atoms(data, in: containers[0].1).filter { $0.0 == wanted }
    guard fields.count == 1 else { throw FairDecKitError.invalidData("Expected one \(wanted) field") }
    return try data.checkedBytes(fields[0].1.lowerBound, fields[0].1.count)
}

func deriveWork16(credential: Data, sinf: Data) throws -> [UInt8] {
    let name = try sinfField(sinf, "name").prefix { $0 != 0 }
    let iviv = try sinfField(sinf, "iviv")
    var record = try sinfField(sinf, "priv")
    guard record.count == 440 || record.count == 448 else {
        throw FairDecKitError.invalidData("Unsupported SINF priv-record length")
    }
    if record.count == 440 {
        guard record.suffix(8).allSatisfy({ $0 == 0 }) else {
            throw FairDecKitError.invalidData("Invalid SINF priv-record trailer")
        }
        record.removeLast(8)
    }
    guard credential.count == 16, iviv.count == 16 else {
        throw FairDecKitError.invalidData("Invalid SINF priv-record dimensions")
    }
    let iv = Array(Insecure.MD5.hash(data: Data(name) + iviv))
    let clear = try aesCBC(record, key: credential.map { $0 ^ 0x30 }, iv: iv)
    guard try clear.checkedBytes(0, 4) == Data("itun".utf8),
          try clear.checkedBytes(20, 4) == Data("key ".utf8),
          try clear.checkedBytes(44, 4) == Data("iviv".utf8) else {
        throw FairDecKitError.invalidData("Credential does not decode this SINF priv record")
    }
    let mask: [UInt8] = [0xc7, 0x62, 0x61, 0x10, 0xce, 0xcd, 0x15, 0x96, 0x3d, 0x85, 0x0f, 0x66, 0x05, 0xf1, 0x1c, 0x4b]
    return zip(try clear.checkedBytes(24, 16), mask).map { $0 ^ $1 }
}

private func high8(_ word: UInt64) -> [UInt8] {
    let b = (0..<8).map { Int((word >> ($0 * 8)) & 255) }
    func fold(_ value: Int, _ mask: Int) -> Int {
        let mixed = value ^ mask
        return (mixed - (0x5a & (mixed << 1)) + 0x2d) & 255
    }
    let q = b[1] ^ 0xa1
    let seventh = (q - 2 * ((b[1] & 0x52) ^ q) + 0x2d) & 255
    return [fold(b[7], 0x3e) ^ 0x3e, fold(b[6], 0x4a) ^ 0x24,
            fold(b[5], 0x45) ^ 0x93, fold(b[4], 0xb6) ^ 0x6d,
            fold(b[3], 0x64) ^ 0xa4, fold(b[2], 0xeb) ^ 0xdd,
            seventh ^ 0x04, (b[0] ^ 0x6c) ^ 0x5f].map { UInt8($0) }
}

func sourceBlocks(_ wrapped: [UInt8], index: UInt32) -> [[UInt8]] {
    let constant: [UInt8] = [0xb4, 0xf2, 0x7c, 0xb8, 0x4e, 0xaa, 0xff, 0x3c, 0x13, 0x09, 0xbe, 0x40, 0x89, 0xf0, 0x29, 0x72]
    let shifted = UInt64(index) << 12
    let first = zip(wrapped[8..<16], constant[0..<8]).map { $0 ^ $1 }
        + high8(0x3e4a45b664eba141 ^ shifted)
    let second = zip(wrapped, constant).map { $0 ^ $1 }
    let word = UInt64(0xb4f27cb84eaaff3c) ^ shifted
    let third = (0..<8).map { UInt8(truncatingIfNeeded: word >> ((7 - $0) * 8)) }
        + zip(wrapped[0..<8], constant[8..<16]).map { $0 ^ $1 }
    return [first, second, third]
}

func finish(_ state: [UInt8]) -> [UInt8] {
    let initial = stride(from: 0, to: 16, by: 2).map {
        (UInt64(state[$0]) << 8 | UInt64(state[$0 + 1])) ^ 0x18fb
    }
    let selectors = [[0, 1, 2, 3, 4, 5, 6, 7], [2, 1, 0, 3, 4, 7, 6, 5],
                     [2, 0, 4, 1, 6, 3, 7, 5], [1, 2, 4, 0, 7, 3, 5, 6]]
    let roundConstants: [UInt64] = [0x6ee6b74f, 0x78b72abf, 0xd227c8ea, 0x0c0081bc]
    var row = initial
    for selector in selectors {
        var next: [UInt64] = []
        for pair in 0..<4 {
            let a = row[selector[pair * 2]] ^ 0x18fb
            let b = row[selector[pair * 2 + 1]] ^ 0x18fb
            let mixed = a + b
            let square = (mixed * mixed ^ roundConstants[pair]) & 0xffffffff
            let high = (mixed >> 16) & 0xffff
            let low = ((0xcb61 &- high * high) ^ square) & 0xffff
            let top = (square >> 16) & 0xffff
            let coded = top ^ 0x6b2
            next.append(low ^ 0x18fb)
            next.append((coded &- 2 * ((coded & 0x58ff) ^ (top & 0x4004)) &+ 0x18fb) & 0xffff)
        }
        row = next
    }
    let finalSelectors = [[0, 1, 2, 3], [0, 2, 4, 6], [0, 3, 5, 7], [4, 5, 6, 7]]
    let finalWords: [UInt64] = [0x85fe4668, 0x15ea8fcd, 0x3a17569b, 0x216e68e0]
    var final: [UInt64] = []
    for (j, selector) in finalSelectors.enumerated() {
        let decoded = selector.map { row[$0] ^ 0x18fb }
        let left = decoded[0] | decoded[1] << 16
        let right = decoded[2] | decoded[3] << 16
        var x9 = left + right
        var x19 = (x9 & 0xffffffff) ^ 0x9cfd58b3de3fd77f
        x9 = ((x9 << 1) & 0x1bc7faefe) &+ x19 &+ 0x6302a74c21c02881
        x9 = x9 &* x9
        x19 = (x9 << 1) & 0x9e7b583f108f031c
        x9 = x9 &+ 0x4f3dac1f8847818e &- x19
        x19 = (finalWords[j] + 0xd573525f) & 0xffffffff
        let x22 = (x19 << 1) & 0x00000001108f031c
        x19 = x19 &+ 0x4f3dac1f8847818e &- x22
        x19 ^= x9
        x9 = x19 ^ (x9 >> 32)
        let low = (x9 ^ 0xb4e4) & 0xffff
        var high = ((x9 >> 16) ^ 0x4f3d) & 0xffffffff
        high = (high &- ((high << 1) & 0x31f6) &+ 0x18fb) & 0xffff
        final.append(contentsOf: [low, high])
    }
    return zip(initial, final).flatMap { a, b -> [UInt8] in
        let word = a ^ b
        return [UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word)]
    }
}

func derivePageKey(wrapped: [UInt8], index: UInt32, work: [UInt8], transform: BlockTransform) -> [UInt8] {
    let blocks = sourceBlocks(wrapped, index: index).map { transform($0, work) }
    let first = finish(blocks[0])
    let second = finish(zip(first, blocks[1]).map { $0 ^ $1 })
    return finish(zip(second, blocks[2]).map { $0 ^ $1 })
}
