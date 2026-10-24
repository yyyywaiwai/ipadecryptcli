import Foundation

func zipBytes(_ value: UInt64, width: Int) -> Data {
    Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
}

// Rebuild only ZIP64's own extra field; keep every other TLV and the entry comment byte-for-byte.
func zipHeader(_ original: Data, central: Bool, values: [Int: UInt64], forceVersion45: Bool = false) throws -> Data {
    var header = original
    let fixedSize = central ? 46 : 30
    let nameField = central ? 28 : 26
    let extraField = central ? 30 : 28
    let nameSize = Int(try zipInteger(header, nameField, 2))
    let extraSize = Int(try zipInteger(header, extraField, 2))
    let fields = central ? [(24, 4, 8), (20, 4, 8), (42, 4, 8), (34, 2, 4)] : [(22, 4, 8), (18, 4, 8)]
    var needsZIP64 = false
    for (offset, width, _) in fields {
        let sentinel = width == 2 ? UInt64(UInt16.max) : UInt64(UInt32.max)
        if try zipInteger(original, offset, width) == sentinel || (values[offset] ?? 0) >= sentinel { needsZIP64 = true }
    }
    // Do not parse or normalize unrelated extras when fixed-width updates are sufficient.
    if !needsZIP64 {
        for (offset, width, _) in fields {
            if let value = values[offset] { header.replaceSubrange(offset..<(offset + width), with: zipBytes(value, width: width)) }
        }
        if forceVersion45 {
            let field = central ? 6 : 4
            header.replaceSubrange(field..<(field + 2), with: zipBytes(max(try zipInteger(original, field, 2), 45), width: 2))
        }
        return header
    }
    let start = fixedSize + nameSize
    let extras = try header.checkedBytes(start, extraSize)
    var zip64Range: Range<Int>?
    var payload = Data()
    var position = 0
    while position < extras.count {
        let tag = try zipInteger(extras, position, 2)
        let size = Int(try zipInteger(extras, position + 2, 2))
        guard size <= extras.count - position - 4 else { throw FairDecKitError.invalidData("Truncated ZIP extra field") }
        if tag == 1 {
            guard zip64Range == nil else { throw FairDecKitError.invalidData("Duplicate ZIP64 extra field") }
            zip64Range = position..<(position + 4 + size)
            payload = try extras.checkedBytes(position + 4, size)
        }
        position += 4 + size
    }
    let localPromotion = !central && (values[18] ?? 0) >= UInt32.max
    var updatedPayload = Data()
    var consumed = 0
    var wide = false
    var promoted = false
    for (offset, width, wideWidth) in fields {
        let sentinel = width == 2 ? UInt64(UInt16.max) : UInt64(UInt32.max)
        let fixed = try zipInteger(original, offset, width)
        let wasWide = fixed == sentinel
        let old: UInt64
        if wasWide {
            old = try zipInteger(payload, consumed, wideWidth)
            consumed += wideWidth
        } else {
            old = fixed
        }
        let value = values[offset] ?? old
        let needsWide = wasWide || value >= sentinel || localPromotion
        if needsWide {
            wide = true
            promoted = promoted || !wasWide
            updatedPayload.append(zipBytes(value, width: wideWidth))
            header.replaceSubrange(offset..<(offset + width), with: zipBytes(sentinel, width: width))
        } else if values[offset] != nil {
            header.replaceSubrange(offset..<(offset + width), with: zipBytes(value, width: width))
        }
    }
    // Preserve any existing ZIP64 payload suffix that is not one of the declared sentinel fields.
    updatedPayload.append(try payload.checkedBytes(consumed, payload.count - consumed))
    var updatedExtras = extras
    if wide || zip64Range != nil {
        guard updatedPayload.count <= Int(UInt16.max) else { throw FairDecKitError.invalidData("ZIP64 extra field is too large") }
        let field = zipBytes(1, width: 2) + zipBytes(UInt64(updatedPayload.count), width: 2) + updatedPayload
        if let range = zip64Range { updatedExtras.replaceSubrange(range, with: field) }
        else { updatedExtras.append(field) }
    }
    guard updatedExtras.count <= Int(UInt16.max) else {
        throw FairDecKitError.invalidData("No room for ZIP64 without discarding existing extra fields")
    }
    header.replaceSubrange(extraField..<(extraField + 2), with: zipBytes(UInt64(updatedExtras.count), width: 2))
    if promoted || forceVersion45 {
        let versionField = central ? 6 : 4
        let version = try zipInteger(header, versionField, 2)
        header.replaceSubrange(versionField..<(versionField + 2), with: zipBytes(max(version, 45), width: 2))
    }
    header.replaceSubrange(start..<(start + extraSize), with: updatedExtras)
    return header
}

// The classic EOCD comment is copied separately and is never decoded or regenerated.
func zipEndRecords(_ original: Data, count: Int, directorySize: UInt64, directoryOffset: UInt64,
                   zip64Offset: UInt64?, existingZIP64: Bool) throws -> Data {
    var end = try original.checkedBytes(0, 22)
    let oldSize = try end.uint32(12), oldOffset = try end.uint32(16)
    let needsZIP64 = existingZIP64 || count >= Int(UInt16.max)
        || directorySize >= UInt32.max || directoryOffset >= UInt32.max
    let size = oldSize == UInt32.max || directorySize >= UInt32.max ? UInt64(UInt32.max) : directorySize
    let offset = oldOffset == UInt32.max || directoryOffset >= UInt32.max ? UInt64(UInt32.max) : directoryOffset
    end.replaceSubrange(12..<16, with: zipBytes(size, width: 4))
    end.replaceSubrange(16..<20, with: zipBytes(offset, width: 4))
    if count >= Int(UInt16.max) {
        end.replaceSubrange(8..<12, with: zipBytes(UInt64(UInt16.max), width: 2) + zipBytes(UInt64(UInt16.max), width: 2))
    }
    guard needsZIP64 && !existingZIP64 else { return end }
    guard let zip64Offset else { throw FairDecKitError.invalidData("Missing new ZIP64 directory position") }
    var record = zipBytes(0x06064b50, width: 4) + zipBytes(44, width: 8)
    record.append(zipBytes(45, width: 2) + zipBytes(45, width: 2))
    record.append(Data(repeating: 0, count: 8))
    record.append(zipBytes(UInt64(count), width: 8) + zipBytes(UInt64(count), width: 8))
    record.append(zipBytes(directorySize, width: 8) + zipBytes(directoryOffset, width: 8))
    record.append(zipBytes(0x07064b50, width: 4) + zipBytes(0, width: 4))
    record.append(zipBytes(zip64Offset, width: 8) + zipBytes(1, width: 4))
    record.append(end)
    return record
}
