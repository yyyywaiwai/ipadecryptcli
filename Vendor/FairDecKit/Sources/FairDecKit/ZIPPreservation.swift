import Foundation
import ZIPFoundation

// Keep raw headers so unknown extra fields, comments and platform attributes survive unchanged.
struct ZIPRecord {
    let offset: Int
    let header: Data
    var platform: Data { header.subdata(in: 4..<6) }
    var attributes: Data { header.subdata(in: 38..<42) }

    func field(_ offset: Int) throws -> ZIPField {
        let preceding = offset == 42 ? [24, 20] : (offset == 20 ? [24] : [])
        return try zipField(header, base: self.offset, fixed: offset,
                            extraStart: 46 + Int(zipInteger(header, 28, 2)),
                            extraSize: Int(zipInteger(header, 30, 2)), preceding: preceding)
    }
}

struct ZIPDirectory {
    let records: [ZIPRecord]
    let offset: Int
    let end: Int
    let zip64End: Int?
    let size: Int
    let directorySize: Int
}

func zipDirectory(at url: URL) throws -> ZIPDirectory {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let length = try file.seekToEnd()
    guard let size = Int(exactly: length), size >= 22 else {
        throw FairDecKitError.invalidData("Truncated ZIP directory")
    }
    let tailStart = max(0, size - 22 - 65535)
    let tail = try readExactly(file, at: tailStart, count: size - tailStart)
    func short(_ data: Data, _ offset: Int) throws -> Int {
        let bytes = try data.checkedBytes(offset, 2)
        return Int(bytes[0]) | Int(bytes[1]) << 8
    }
    var end: Int?
    for position in stride(from: tail.count - 22, through: 0, by: -1) {
        if try tail.uint32(position) == 0x06054b50,
           try position + 22 + short(tail, position + 20) == tail.count {
            end = position
            break
        }
    }
    guard let end, try short(tail, end + 4) == 0, try short(tail, end + 6) == 0 else {
        throw FairDecKitError.invalidData("Missing or multi-disk ZIP directory")
    }
    var count = try short(tail, end + 10)
    var directorySize = UInt64(try tail.uint32(end + 12))
    var directoryOffset = UInt64(try tail.uint32(end + 16))
    var zip64End: Int?
    var hasLocator = false
    let locatorPosition = tailStart + end - 20
    if locatorPosition >= 56 {
        let candidate = try readExactly(file, at: locatorPosition, count: 20)
        let position = try zipInteger(candidate, 8, 8)
        if try candidate.uint32(0) == 0x07064b50, try candidate.uint32(4) == 0,
           try candidate.uint32(16) == 1, position <= UInt64(locatorPosition - 56) {
            let record = try readExactly(file, at: Int(position), count: 12)
            let size = try zipInteger(record, 4, 8)
            hasLocator = try record.uint32(0) == 0x06064b50 && size >= 44
                && size == UInt64(locatorPosition) - position - 12
        }
    }
    if hasLocator || count == 65535 || directorySize == UInt32.max || directoryOffset == UInt32.max {
        guard tailStart + end >= 20 else { throw FairDecKitError.invalidData("Missing ZIP64 locator") }
        let locator = try readExactly(file, at: tailStart + end - 20, count: 20)
        guard try locator.uint32(0) == 0x07064b50, try locator.uint32(4) == 0,
              try locator.uint32(16) == 1 else {
            throw FairDecKitError.invalidData("Invalid ZIP64 locator")
        }
        func wide(_ data: Data, _ offset: Int) throws -> UInt64 {
            try UInt64(data.uint32(offset)) | UInt64(data.uint32(offset + 4)) << 32
        }
        let offset = try wide(locator, 8)
        guard offset <= length, length - offset >= 56, let position = Int(exactly: offset) else {
            throw FairDecKitError.invalidData("Invalid ZIP64 directory offset")
        }
        zip64End = position
        let record = try readExactly(file, at: position, count: 56)
        guard try record.uint32(0) == 0x06064b50, try record.uint32(16) == 0,
              try record.uint32(20) == 0, let entries = Int(exactly: try wide(record, 32)) else {
            throw FairDecKitError.invalidData("Invalid ZIP64 directory")
        }
        count = entries
        directorySize = try wide(record, 40)
        directoryOffset = try wide(record, 48)
    }
    guard directoryOffset <= length, directorySize <= length - directoryOffset,
          UInt64(count) <= directorySize / 46, let start = Int(exactly: directoryOffset),
          let bytes = Int(exactly: directorySize) else {
        throw FairDecKitError.invalidData("ZIP directory exceeds file")
    }
    var position = start
    let limit = start + bytes
    var result: [ZIPRecord] = []
    for _ in 0..<count {
        guard position <= limit, limit - position >= 46 else {
            throw FairDecKitError.invalidData("Truncated ZIP directory entry")
        }
        let header = try readExactly(file, at: position, count: 46)
        let entrySize = try 46 + short(header, 28) + short(header, 30) + short(header, 32)
        guard try header.uint32(0) == 0x02014b50, entrySize <= limit - position else {
            throw FairDecKitError.invalidData("Invalid ZIP directory entry")
        }
        result.append(ZIPRecord(offset: position, header: try readExactly(file, at: position, count: entrySize)))
        position += entrySize
    }
    return ZIPDirectory(records: result, offset: start, end: tailStart + end, zip64End: zip64End, size: size, directorySize: bytes)
}

func zipInteger(_ data: Data, _ offset: Int, _ width: Int) throws -> UInt64 {
    let bytes = try data.checkedBytes(offset, width)
    return bytes.enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
}

struct ZIPField {
    let offset: Int
    let width: Int
    let value: UInt64
}

private func zipField(_ header: Data, base: Int, fixed: Int, extraStart: Int,
                      extraSize: Int, preceding: [Int]) throws -> ZIPField {
    let value = try zipInteger(header, fixed, 4)
    if value != UInt32.max { return ZIPField(offset: base + fixed, width: 4, value: value) }
    let extras = try header.checkedBytes(extraStart, extraSize)
    var position = 0
    while position < extras.count {
        let tag = try zipInteger(extras, position, 2)
        let size = Int(try zipInteger(extras, position + 2, 2))
        guard size <= extras.count - position - 4 else { throw FairDecKitError.invalidData("Truncated ZIP extra field") }
        if tag == 1 {
            var skip = 0
            for field in preceding where try zipInteger(header, field, 4) == UInt32.max { skip += 8 }
            guard skip + 8 <= size else { throw FairDecKitError.invalidData("Missing ZIP64 field") }
            return ZIPField(offset: base + extraStart + position + 4 + skip, width: 8,
                            value: try zipInteger(extras, position + 4 + skip, 8))
        }
        position += 4 + size
    }
    throw FairDecKitError.invalidData("Missing ZIP64 extra field")
}

private enum ZIPReplacement {
    case bytes(Data)
    case file(offset: Int, count: Int)
}

private struct ZIPChange {
    let offset: Int
    let count: Int
    let replacement: ZIPReplacement
}

private func zipAdd(_ left: Int, _ right: Int) throws -> Int {
    let (value, overflow) = left.addingReportingOverflow(right)
    guard !overflow else { throw FairDecKitError.invalidData("ZIP offset overflow") }
    return value
}

private func shifted(_ offset: Int, by delta: Int) throws -> Int {
    let value = try zipAdd(offset, delta)
    guard value >= 0 else { throw FairDecKitError.invalidData("ZIP offset overflow") }
    return value
}

private func localDataOffset(_ file: FileHandle, at offset: Int, limit: Int) throws -> (Data, Int) {
    guard offset >= 0, offset <= limit, limit - offset >= 30 else { throw FairDecKitError.invalidData("Invalid ZIP local offset") }
    let header = try readExactly(file, at: offset, count: 30)
    let length = try 30 + Int(zipInteger(header, 26, 2)) + Int(zipInteger(header, 28, 2))
    guard try header.uint32(0) == 0x04034b50, length <= limit - offset else {
        throw FairDecKitError.invalidData("Invalid ZIP local header")
    }
    return (try readExactly(file, at: offset, count: length), offset + length)
}

// Only replace compressed binary bytes and dependent CRC/size/offset fields; copy everything else verbatim.
func preserveZIP(from input: URL, replacing replacements: URL, to output: URL) throws {
    let original = try zipDirectory(at: input)
    let changed = try zipDirectory(at: replacements)
    let sourcePaths = try Archive(url: input, accessMode: .read).map(\.path)
    let replacementPaths = try Archive(url: replacements, accessMode: .read).map(\.path)
    guard sourcePaths.count == original.records.count, replacementPaths.count == changed.records.count,
          Set(sourcePaths).count == sourcePaths.count, Set(replacementPaths).count == replacementPaths.count,
          Set(replacementPaths).isSubset(of: Set(sourcePaths)) else {
        throw FairDecKitError.invalidData("Invalid ZIP replacement entries")
    }
    let newRecords = Dictionary(uniqueKeysWithValues: zip(replacementPaths, changed.records))
    let source = try FileHandle(forReadingFrom: input)
    defer { try? source.close() }
    let replacementFile = try FileHandle(forReadingFrom: replacements)
    defer { try? replacementFile.close() }
    var changes: [ZIPChange] = []
    func replace(at offset: Int, old: Data, new: Data) {
        if old != new { changes.append(ZIPChange(offset: offset, count: old.count, replacement: .bytes(new))) }
    }
    var entries: [(String, ZIPRecord, Int)] = []
    for (path, entry) in zip(sourcePaths, original.records) {
        guard let offset = Int(exactly: try entry.field(42).value) else { throw FairDecKitError.invalidData("ZIP offset overflow") }
        entries.append((path, entry, offset))
    }
    entries.sort { $0.2 < $1.2 }
    var delta = 0
    var centralDelta = 0
    for (index, item) in entries.enumerated() {
        let (path, entry, offset) = item
        let limit = index + 1 < entries.count ? entries[index + 1].2 : original.offset
        guard offset < limit, limit <= original.offset else { throw FairDecKitError.invalidData("Overlapping ZIP entries") }
        let newOffset = try shifted(offset, by: delta)
        let replacement = newRecords[path]
        let oldSize = try entry.field(20).value
        let newSize = try replacement?.field(20).value ?? oldSize
        let uncompressed = try entry.field(24).value
        let oldCRC = try entry.header.uint32(16)
        let crc = try replacement?.header.uint32(16) ?? oldCRC
        var central = try zipHeader(entry.header, central: true, values: [20: newSize, 42: UInt64(newOffset)])
        central.replaceSubrange(16..<20, with: zipBytes(UInt64(crc), width: 4))
        replace(at: entry.offset, old: entry.header, new: central)
        centralDelta = try shifted(centralDelta, by: central.count - entry.header.count)
        let offsetPromoted = try entry.field(42).width == 4 && UInt64(newOffset) >= UInt32.max
        guard replacement != nil || offsetPromoted else { continue }
        guard let oldCount = Int(exactly: oldSize), let newCount = Int(exactly: newSize) else {
            throw FairDecKitError.invalidData("ZIP size overflow")
        }
        let (local, dataOffset) = try localDataOffset(source, at: offset, limit: limit)
        guard oldCount <= limit - dataOffset,
              try zipInteger(local, 8, 2) == zipInteger(entry.header, 10, 2) else {
            throw FairDecKitError.invalidData("Compressed ZIP data exceeds entry")
        }
        if let replacement {
            guard try uncompressed == replacement.field(24).value,
                  let replacementOffset = Int(exactly: try replacement.field(42).value),
                  try zipInteger(entry.header, 10, 2) == zipInteger(replacement.header, 10, 2) else {
                throw FairDecKitError.invalidData("Replacement changes ZIP entry size or compression method")
            }
            let (_, newDataOffset) = try localDataOffset(replacementFile, at: replacementOffset, limit: changed.offset)
            guard newCount <= changed.offset - newDataOffset else { throw FairDecKitError.invalidData("Invalid replacement data") }
            changes.append(ZIPChange(offset: dataOffset, count: oldCount,
                                     replacement: .file(offset: newDataOffset, count: newCount)))
        }
        let descriptor = try zipInteger(local, 6, 2) & 8 != 0
        var promoteDescriptor = false
        var descriptorGrowth = 0
        if descriptor {
            let start = dataOffset + oldCount
            let bytes = try readExactly(source, at: start, count: min(24, limit - start))
            var matched = false
            for signature in [4, 0] where !matched {
                if signature == 4 {
                    guard bytes.count >= 4 else { continue }
                    if try bytes.uint32(0) != 0x08074b50 { continue }
                }
                for width in [8, 4] where !matched {
                    let length = signature + 4 + width * 2
                    guard length <= bytes.count else { continue }
                    if try bytes.uint32(signature) == oldCRC,
                       try zipInteger(bytes, signature + 4, width) == oldSize,
                       try zipInteger(bytes, signature + 4 + width, width) == uncompressed {
                        let needsWide = try zipInteger(central, 6, 2) >= 45 || newSize >= UInt32.max
                        let newWidth = needsWide ? 8 : width
                        promoteDescriptor = newWidth > width
                        let updated = try bytes.checkedBytes(0, signature) + zipBytes(UInt64(crc), width: 4)
                            + zipBytes(newSize, width: newWidth) + zipBytes(uncompressed, width: newWidth)
                        replace(at: start, old: try bytes.checkedBytes(0, length), new: updated)
                        descriptorGrowth = updated.count - length
                        matched = true
                    }
                }
            }
            guard matched else { throw FairDecKitError.invalidData("Invalid ZIP data descriptor") }
        }
        var localValues: [Int: UInt64] = [:]
        let localSize = try zipField(local, base: offset, fixed: 18,
                                     extraStart: 30 + Int(zipInteger(local, 26, 2)),
                                     extraSize: Int(zipInteger(local, 28, 2)), preceding: [22])
        if !descriptor || localSize.value != 0 { localValues[18] = newSize }
        if newSize >= UInt32.max { localValues[18] = newSize; localValues[22] = uncompressed }
        var localHeader = try zipHeader(local, central: false, values: localValues, forceVersion45: promoteDescriptor)
        if try !descriptor || local.uint32(14) != 0 {
            localHeader.replaceSubrange(14..<18, with: zipBytes(UInt64(crc), width: 4))
        }
        replace(at: offset, old: local, new: localHeader)
        let growth = try zipAdd(zipAdd(newCount - oldCount, localHeader.count - local.count), descriptorGrowth)
        delta = try zipAdd(delta, growth)
    }
    let directoryOffset = try shifted(original.offset, by: delta)
    let directorySize = try shifted(original.directorySize, by: centralDelta)
    let endDelta = try zipAdd(delta, centralDelta)
    let end = try readExactly(source, at: original.end, count: 22)
    let updatedEnd = try zipEndRecords(end, count: entries.count, directorySize: UInt64(directorySize),
                                      directoryOffset: UInt64(directoryOffset),
                                      zip64Offset: UInt64(shifted(original.end, by: endDelta)),
                                      existingZIP64: original.zip64End != nil)
    replace(at: original.end, old: end, new: updatedEnd)
    if let zip64 = original.zip64End {
        let sizes = try readExactly(source, at: zip64 + 40, count: 16)
        replace(at: zip64 + 40, old: sizes,
                new: zipBytes(UInt64(directorySize), width: 8) + zipBytes(UInt64(directoryOffset), width: 8))
        let locator = try readExactly(source, at: original.end - 12, count: 8)
        replace(at: original.end - 12, old: locator, new: zipBytes(UInt64(try shifted(zip64, by: endDelta)), width: 8))
    }
    _ = try shifted(original.size, by: zipAdd(endDelta, updatedEnd.count - end.count))
    guard !FileManager.default.fileExists(atPath: output.path),
          FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
        throw CocoaError(.fileWriteFileExists)
    }
    let destination = try FileHandle(forWritingTo: output)
    defer { try? destination.close() }
    func copy(_ file: FileHandle, offset: Int, count: Int) throws {
        var position = offset
        var remaining = count
        while remaining > 0 {
            let size = min(64 * 1024, remaining)
            try autoreleasepool { try destination.write(contentsOf: readExactly(file, at: position, count: size)) }
            position += size
            remaining -= size
        }
    }
    var position = 0
    for change in changes.sorted(by: { $0.offset < $1.offset }) {
        guard change.offset >= position, change.offset <= original.size,
              change.count <= original.size - change.offset else { throw FairDecKitError.invalidData("Overlapping ZIP edits") }
        try copy(source, offset: position, count: change.offset - position)
        switch change.replacement {
        case .bytes(let bytes): try destination.write(contentsOf: bytes)
        case .file(let offset, let count): try copy(replacementFile, offset: offset, count: count)
        }
        position = change.offset + change.count
    }
    try copy(source, offset: position, count: original.size - position)
    try destination.close()
}
