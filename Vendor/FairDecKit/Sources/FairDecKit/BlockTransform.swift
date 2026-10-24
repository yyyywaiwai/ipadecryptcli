import Foundation

// Direct UInt32 wrapping-arithmetic port of transform.c; table offsets are unchanged.
struct BlockTransform: Sendable {
    private let tables: [UInt32]

    init() throws {
        guard let url = Bundle.module.url(forResource: "transform_const_data", withExtension: "bin") else {
            throw FairDecKitError.invalidData("Missing transform constant resource")
        }
        let data = try Data(contentsOf: url)
        guard data.count == 0x36750 else {
            throw FairDecKitError.invalidData("Invalid transform constant resource size")
        }
        tables = data.map(UInt32.init)
    }

    private func tableWord(_ offset: Int, _ index: UInt32) -> UInt32 {
        let i = offset + Int(index) * 4
        return tables[i] | tables[i + 1] << 8 | tables[i + 2] << 16 | tables[i + 3] << 24
    }

    private func decodeFirstStageByte(_ value: UInt32) -> UInt32 {
        ((value & 0xff) &+ 0x123) ^ 0x19b3092a
    }

    private func mixTableWordA(_ value: UInt32) -> UInt32 { (value &+ 0xce853eba) ^ 0x4eb7d448 }
    private func mixTableWordB(_ value: UInt32) -> UInt32 { (value &+ 0x4e853eba) ^ 0x8e4b91e3 }
    private func mixTableWordC(_ value: UInt32) -> UInt32 { (value &+ 0xf8570001) ^ 0x59ca32d7 }

    private func decodeOutputByte0(_ value: UInt32, _ tableMask: UInt32, _ valueMask: UInt32, _ outputMask: UInt32) -> UInt32 {
        (tables[196656 + Int(value ^ tableMask)] &- (value ^ valueMask) &- 3) ^ outputMask
    }

    private func decodeOutputByte1(_ value: UInt32, _ tableMask: UInt32, _ valueMask: UInt32, _ outputMask: UInt32) -> UInt32 {
        ((value ^ valueMask) &+ 0x78) ^ tables[144848 + Int(value ^ tableMask)] ^ outputMask
    }

    private func decodeOutputByte2(_ value: UInt32, _ tableMask: UInt32, _ outputMask: UInt32) -> UInt32 {
        tables[144592 + Int(value ^ tableMask)] ^ outputMask
    }

    private func decodeOutputByte3(_ value: UInt32, _ tableMask: UInt32, _ valueMask: UInt32, _ outputMask: UInt32) -> UInt32 {
        ((value ^ valueMask) &+ tables[118912 + Int(value ^ tableMask)] &+ 0xa5) ^ outputMask
    }

    func callAsFunction(_ source: [UInt8], _ work: [UInt8]) -> [UInt8] {
        let constant: [UInt8] = [0xb4, 0xf2, 0x7c, 0xb8, 0x4e, 0xaa, 0xff, 0x3c, 0x13, 0x09, 0xbe, 0x40, 0x89, 0xf0, 0x29, 0x72]
        var output = [UInt8](repeating: 0, count: 16)
        var uVar3: UInt32
        var uVar4: UInt32
        var uVar5: UInt32
        var uVar6: UInt32
        var uVar7: UInt32
        var uVar8: UInt32
        var uVar9: UInt32
        var uVar10: UInt32
        var uVar11: UInt32
        var uVar12: UInt32
        var uVar13: UInt32
        var uVar14: UInt32
        var uVar15: UInt32
        var uVar16: UInt32
        var uVar17: UInt32
        var uVar18: UInt32
        var uVar19: UInt32
        var uVar20: UInt32
        var uVar21: UInt32
        var uVar22: UInt32
        var uVar23: UInt32
        var uVar24: UInt32
        var uVar25: UInt32
        var uVar26: UInt32
        var uVar27: UInt32
        var uVar28: UInt32
        var uVar29: UInt32
        var uVar30: UInt32
        var uVar31: UInt32
        var uVar32: UInt32
        var uVar33: UInt32
        var uVar34: UInt32
        var uVar35: UInt32
        var uVar36: UInt32
        var uVar37: UInt32
        var uVar38: UInt32
        var uVar39: UInt32
        var uVar40: UInt32
        var uVar41: UInt32
        var uVar42: UInt32
        var uVar43: UInt32
        var uVar44: UInt32
        var uVar45: UInt32
        var uVar46: UInt32
        var uVar47: UInt32
        var uVar48: UInt32
        var uVar49: UInt32
        var uVar50: UInt32
        var uVar52: UInt32
        var uVar53: UInt32
        var uVar54: UInt32
        let input_byte1_table = 123824
        let input_byte0_table = 177360
        uVar10 = ((tables[input_byte0_table + Int((UInt32(work[12]) ^ 0x76))] &+ 0x4b) ^ 0x7b)
        uVar5 = (uVar10 & 0xff)
        let input_byte3_table = 209440
        let input_byte2_table = 180784
        uVar4 = (((((tables[input_byte0_table + Int((UInt32(work[0]) ^ 0x9c))] << 0x18) | (tables[input_byte3_table + Int((UInt32(work[3]) ^ 0x47))] ^ 0xd6)) | ((tables[input_byte2_table + Int((UInt32(work[2]) ^ 0xac))] ^ 0xec) << 0x8)) | ((tables[input_byte1_table + Int((UInt32(work[1]) ^ 0x4a))] ^ 0xa6) << 0x10)) &+ 0x4b000000)
        uVar3 = (((((tables[input_byte1_table + Int((UInt32(work[9]) ^ 0xe6))] ^ 0x72) << 0x10) | ((tables[input_byte2_table + Int((UInt32(work[10]) ^ 0xa7))] ^ 0x6) << 0x8)) | (tables[input_byte3_table + Int((UInt32(work[11]) ^ 0xfb))] ^ 0x75)) | (((tables[input_byte0_table + Int((UInt32(work[8]) ^ 0xa8))] &+ 0x4b) ^ 0x28) << 0x18))
        uVar52 = (uVar3 ^ 0x786633df)
        uVar6 = ((((uVar10 << 0x18) | ((tables[input_byte1_table + Int((UInt32(work[13]) ^ 0x84))] ^ 0xbd) << 0x10)) | (tables[input_byte3_table + Int((UInt32(work[15]) ^ 0x8))] ^ 0x40)) | ((tables[input_byte2_table + Int((UInt32(work[14]) ^ 0xe3))] ^ 0xe8) << 0x8))
        uVar3 = (((((tables[input_byte1_table + Int((UInt32(work[5]) ^ 0xd1))] ^ 0x65) << 0x10) | ((tables[input_byte2_table + Int((UInt32(work[6]) ^ 0x40))] ^ 0x79) << 0x8)) | (((tables[input_byte0_table + Int((UInt32(work[4]) ^ 0xe0))] &+ 0x4b) ^ 0xe8) << 0x18)) | (tables[input_byte3_table + Int((UInt32(work[7]) ^ 0x3f))] ^ 0x28))
        uVar10 = (uVar3 ^ 0x697720c)
        uVar3 = ((((uVar6 ^ 0x5b80b964) & 0xff) ^ 0xa7) &+ 0x1f264300)
        uVar11 = (uVar3 ^ 0xdbbaed5b)
        let first_low_table = 152848
        uVar12 = (((uVar11 ^ 0x576) &+ 0xd4e8000) ^ tableWord(first_low_table, (uVar3 ^ 0x1f2643b6)))
        uVar11 = (uVar4 ^ 0x3cfbe2e1)
        let first_high_table = 191936
        uVar3 = (uVar5 ^ 0x78)
        uVar3 = (((uVar4 ^ decodeFirstStageByte(uVar3)) ^ tableWord(first_high_table, (uVar5 ^ 0xc4))) ^ uVar12)
        let first_byte2_table = 181040
        let first_byte1_table = 153872
        uVar13 = (((tableWord(first_byte1_table, (tables[input_byte2_table + Int((UInt32(work[14]) ^ 0xe3))] ^ 0xe4)) &+ 0x82923b6f) ^ tableWord(first_byte2_table, (tables[input_byte1_table + Int((UInt32(work[13]) ^ 0x84))] ^ 0xa4))) ^ (uVar3 ^ 0x7eab6905))
        uVar14 = (((uVar10 ^ uVar13) ^ 0x654f64ea) ^ 0x33a1f418)
        uVar15 = ((uVar52 ^ uVar14) ^ 0x72c8bd2a)
        uVar16 = (uVar6 ^ uVar15)
        uVar17 = (uVar16 ^ 0x134f22c8)
        uVar3 = ((uVar17 & 0xff) ^ 0xc49cae69)
        uVar3 = (((uVar3 ^ 0x76) &+ 0xd4e7d00) ^ tableWord(first_low_table, ((uVar17 & 0xff) ^ 0x84)))
        uVar3 = ((uVar3 ^ 0x7eab6905) ^ tableWord(first_byte2_table, (((uVar17 >> 0x10) & 0xff) ^ 0xe5)))
        uVar5 = ((uVar17 >> 0x18) ^ 0x85)
        uVar18 = (((((tableWord(first_byte1_table, (((uVar17 >> 0x8) & 0xff) ^ 0x21)) &+ 0x82923b6f) ^ tableWord(first_high_table, ((uVar17 >> 0x18) ^ 0x39))) ^ uVar13) ^ decodeFirstStageByte(uVar5)) ^ uVar3)
        uVar19 = (uVar18 ^ 0x3f98d223)
        uVar20 = (uVar52 ^ uVar19)
        uVar21 = ((uVar20 ^ uVar17) ^ 0x94592e63)
        uVar3 = ((uVar21 >> 0x18) ^ 0x77)
        uVar3 = (((((tableWord(first_byte1_table, (((uVar21 >> 0x8) & 0xff) ^ 0xdc)) &+ 0x3e921d40) ^ 0xf398f012) ^ tableWord(first_high_table, ((uVar21 >> 0x18) ^ 0xcb))) ^ uVar19) ^ decodeFirstStageByte(uVar3))
        uVar5 = ((uVar21 & 0xff) ^ 0xc49cae02)
        uVar22 = (((tableWord(first_low_table, ((uVar21 & 0xff) ^ 0xef)) ^ tableWord(first_byte2_table, (((uVar21 >> 0x10) & 0xff) ^ 0xfe))) ^ ((uVar5 ^ 0x76) &+ 0xd4e7d00)) ^ (uVar3 ^ 0x7eab6905))
        uVar23 = (((uVar14 ^ uVar19) ^ uVar22) ^ 0x258d9763)
        uVar24 = ((uVar23 ^ uVar20) ^ 0x4601c465)
        uVar21 = (uVar24 ^ uVar21)
        uVar3 = ((uVar21 >> 0x18) ^ 0x19)
        uVar5 = ((uVar21 & 0xff) ^ 0xc49cae48)
        uVar25 = ((((((tableWord(first_byte2_table, (((uVar21 >> 0x10) & 0xff) ^ 0x8f)) ^ (tableWord(first_byte1_table, (((uVar21 >> 0x8) & 0xff) ^ 0x93)) &+ 0x82923b6f)) ^ tableWord(first_high_table, ((uVar21 >> 0x18) ^ 0xa5))) ^ tableWord(first_low_table, ((uVar21 & 0xff) ^ 0xa5))) ^ uVar22) ^ ((uVar5 ^ 0x76) &+ 0xd4e7d00)) ^ decodeFirstStageByte(uVar3))
        uVar26 = (uVar25 ^ 0x7eab6905)
        uVar27 = ((uVar26 ^ uVar20) ^ 0x4601c465)
        uVar28 = ((uVar27 ^ uVar21) ^ 0xcbb1f184)
        uVar3 = (uVar28 & 0xff)
        uVar4 = ((uVar3 ^ 0xc49caefb) ^ (tableWord(first_low_table, (uVar3 ^ 0x16)) ^ 0x15778576))
        uVar3 = (((tableWord(first_byte1_table, (((uVar28 >> 0x8) & 0xff) ^ 0xc2)) &+ 0x82923b6f) ^ uVar26) ^ uVar4)
        uVar5 = ((uVar28 >> 0x18) ^ 0xe9)
        uVar29 = (((tableWord(first_high_table, ((uVar28 >> 0x18) ^ 0x55)) ^ tableWord(first_byte2_table, (((uVar28 >> 0x10) & 0xff) ^ 0xb2))) ^ decodeFirstStageByte(uVar5)) ^ (uVar3 ^ 0x7eab6905))
        uVar30 = ((uVar29 ^ uVar26) ^ uVar23)
        uVar31 = ((uVar27 ^ uVar30) ^ 0x35055031)
        uVar32 = (uVar31 ^ uVar28)
        uVar3 = (uVar32 & 0xff)
        uVar3 = (((uVar3 ^ 0x68) &+ 0x15778500) ^ tableWord(first_low_table, (uVar3 ^ 0x32)))
        uVar3 = (((tableWord(first_byte1_table, (((uVar32 >> 0x8) & 0xff) ^ 0x73)) &+ 0x82923b6f) ^ uVar29) ^ (uVar3 ^ 0x4fd1f582))
        uVar5 = (uVar3 ^ 0xde575bdd)
        uVar12 = (tableWord(first_byte2_table, (((uVar32 >> 0x10) & 0xff) ^ 0x40)) ^ 0x7eab6905)
        uVar4 = (uVar12 &- ((tableWord(first_byte2_table, (((uVar32 >> 0x10) & 0xff) ^ 0x40)) ^ uVar5) ^ 0xba37c7c4))
        uVar33 = ((uVar32 >> 0x18) ^ 0x36)
        uVar34 = ((decodeFirstStageByte(uVar33) ^ tableWord(first_high_table, ((uVar32 >> 0x18) ^ 0x8a))) ^ ((((uVar5 ^ (0 &- (uVar3 ^ 0x1acbf51c))) ^ (uVar4 ^ 0x47dd682a)) ^ 0x8341c6eb) &+ uVar12))
        uVar3 = (uVar34 ^ 0x5e2bc04c)
        uVar35 = (uVar30 ^ uVar3)
        uVar36 = (uVar35 ^ 0x8d84a556)
        uVar28 = (uVar36 ^ uVar28)
        uVar5 = ((uVar28 & 0xff) ^ 0xc49caec6)
        uVar5 = (((uVar5 ^ 0x76) &+ 0xd4e7d00) ^ tableWord(first_low_table, ((uVar28 & 0xff) ^ 0x2b)))
        uVar12 = ((uVar28 >> 0x18) ^ 0x4c)
        uVar37 = (((((tableWord(first_high_table, ((uVar28 >> 0x18) ^ 0xf0)) ^ tableWord(first_byte2_table, (((uVar28 >> 0x10) & 0xff) ^ 0x2f))) ^ (tableWord(first_byte1_table, (((uVar28 >> 0x8) ^ 0xffffffff) & 0xff)) &+ 0x82923b6f)) ^ uVar3) ^ decodeFirstStageByte(uVar12)) ^ (uVar5 ^ 0x5e2bc04c))
        uVar31 = (uVar36 ^ uVar31)
        uVar5 = (uVar37 ^ 0xa8938483)
        uVar36 = (uVar36 ^ uVar5)
        uVar38 = (uVar36 ^ 0x5c685d36)
        uVar39 = (uVar38 ^ uVar31)
        uVar40 = (uVar39 ^ uVar28)
        uVar3 = ((uVar40 >> 0x18) ^ 0xf4)
        uVar3 = (decodeFirstStageByte(uVar3) ^ tableWord(first_high_table, ((uVar40 >> 0x18) ^ 0x48)))
        uVar5 = ((uVar3 ^ 0x3b38ed86) ^ uVar5)
        uVar3 = ((((uVar40 ^ 0xef68065b) & 0xff) ^ 0x36) &+ 0x3a312300)
        uVar33 = tableWord(first_low_table, ((uVar40 & 0xff) ^ 0xbf))
        uVar12 = (uVar3 ^ 0xfead8d3f)
        uVar3 = ((uVar12 &- ((uVar33 ^ uVar3) ^ 0xebda0849)) ^ (0 &- (uVar33 ^ 0x15778576)))
        uVar41 = ((((tableWord(first_byte1_table, (((uVar40 >> 0x8) & 0xff) ^ 0xfe)) &+ 0x82923b6f) ^ tableWord(first_byte2_table, (((uVar40 >> 0x10) & 0xff) ^ 0x8d))) ^ (((uVar3 ^ 0x15778576) ^ uVar33) &+ uVar12)) ^ (uVar5 ^ 0x7eab6905))
        uVar42 = (uVar41 ^ uVar31)
        uVar43 = ((uVar42 ^ uVar40) ^ 0x6e5ac8d9)
        uVar3 = ((uVar43 & 0xff) ^ 0xc49cae97)
        uVar3 = ((((tableWord(first_low_table, ((uVar43 & 0xff) ^ 0x7a)) ^ (tableWord(first_byte1_table, (((uVar43 >> 0x8) & 0xff) ^ 0xa3)) &+ 0x82923b6f)) ^ uVar41) ^ ((uVar3 ^ 0x76) &+ 0xd4e7d00)) ^ 0xde782d98)
        uVar5 = ((uVar43 >> 0x18) ^ 0xb0)
        uVar44 = (((tableWord(first_high_table, ((uVar43 >> 0x18) ^ 0xc)) ^ tableWord(first_byte2_table, (((uVar43 >> 0x10) & 0xff) ^ 0xf1))) ^ decodeFirstStageByte(uVar5)) ^ (uVar3 ^ 0x7eab6905))
        uVar38 = (uVar41 ^ uVar38)
        uVar45 = ((uVar38 ^ uVar44) ^ 0xfacd8d8d)
        uVar46 = ((uVar45 ^ uVar40) ^ 0x6e5ac8d9)
        uVar3 = ((uVar46 >> 0x18) ^ 0xac)
        uVar3 = (decodeFirstStageByte(uVar3) ^ tableWord(first_high_table, ((uVar46 >> 0x18) ^ 0x10)))
        uVar5 = (((tableWord(first_byte1_table, (((uVar46 >> 0x8) & 0xff) ^ 0x2)) &+ 0x82923b6f) ^ uVar44) ^ uVar3)
        uVar3 = ((((uVar46 ^ 0xc1bfc8d8) & 0xff) ^ 0xf3) &+ 0x44c83100)
        uVar5 = ((uVar5 ^ 0x7eab6905) ^ tableWord(first_byte2_table, (((uVar46 >> 0x10) & 0xff) ^ 0xe6)))
        uVar47 = ((uVar3 ^ tableWord(first_low_table, (uVar3 ^ 0x44c831d0))) ^ (uVar5 ^ 0x15778576))
        uVar48 = (((uVar46 ^ uVar47) ^ uVar42) ^ 0x3cccedab)
        uVar49 = ((uVar47 ^ uVar42) ^ 0xd59b4d21)
        uVar4 = ((uVar24 ^ 0x2a09be64) &- (uVar13 ^ 0x4f54299))
        uVar3 = (uVar4 ^ 0x58fa2e52)
        uVar4 = ((uVar46 ^ 0x2849af33) &+ (uVar16 ^ 0x487fb4cc))
        uVar54 = ((uVar4 &+ 0x33b086f2) ^ 0x3a846044)
        uVar5 = (((((tables[input_byte1_table + Int((UInt32(constant[13]) ^ 0xc))] ^ 0x7) << 0x10) | ((tables[input_byte2_table + Int((UInt32(constant[14]) ^ 0x9c))] ^ 0x95) << 0x8)) | (tables[input_byte3_table + Int((UInt32(constant[15]) ^ 0x20))] ^ 0x71)) | (((tables[input_byte0_table + Int((UInt32(constant[12]) ^ 0x54))] &+ 0x4b) ^ 0xca) << 0x18))
        uVar12 = (((((tables[input_byte2_table + Int((UInt32(constant[2]) ^ 0x4c))] ^ 0xa1) << 0x8) | ((tables[input_byte1_table + Int((UInt32(constant[1]) ^ 0x1f))] ^ 0x25) << 0x10)) | (tables[input_byte3_table + Int((UInt32(constant[3]) ^ 0x9f))] ^ 0x73)) | (((tables[input_byte0_table + Int((UInt32(constant[0]) ^ 0x52))] &+ 0x4b) ^ 0xe5) << 0x18))
        uVar33 = ((((((tables[input_byte0_table + Int((UInt32(constant[4]) ^ 0x71))] &+ 0x4b) ^ 0x51) << 0x18) | ((tables[input_byte2_table + Int((UInt32(constant[6]) ^ 0xc7))] ^ 0xd0) << 0x8)) | (tables[input_byte3_table + Int((UInt32(constant[7]) ^ 0x89))] ^ 0x79)) | ((tables[input_byte1_table + Int((UInt32(constant[5]) ^ 0xf))] ^ 0xfb) << 0x10))
        uVar50 = (uVar3 ^ 0xeab3aab1)
        let source_byte0_table = 202112
        let source_byte2_table = 126160
        let source_byte1_table = 156256
        let source_byte3_table = 172224
        uVar7 = (((((tables[source_byte0_table + Int((UInt32(source[8]) ^ 0x53))] ^ 0xc6) << 0x18) | ((tables[source_byte1_table + Int((UInt32(source[9]) ^ 0x5d))] ^ 0xc6) << 0x10)) | (tables[source_byte3_table + Int((UInt32(source[11]) ^ 0x41))] ^ 0x5f)) | ((tables[source_byte2_table + Int((UInt32(source[10]) ^ 0x37))] ^ 0xf2) << 0x8))
        uVar8 = (((((tables[source_byte0_table + Int((UInt32(source[12]) ^ 0x32))] ^ 0x78) << 0x18) | ((tables[source_byte2_table + Int((UInt32(source[14]) ^ 0x95))] ^ 0xd5) << 0x8)) | (tables[source_byte3_table + Int((UInt32(source[15]) ^ 0xcd))] ^ 0x30)) | ((tables[source_byte1_table + Int((UInt32(source[13]) ^ 0x71))] ^ 0x1f) << 0x10))
        uVar9 = (((((tables[source_byte1_table + Int((UInt32(source[5]) ^ 0xe4))] ^ 0xbf) << 0x10) | ((tables[source_byte0_table + Int((UInt32(source[4]) ^ 0x5c))] ^ 0xb3) << 0x18)) | (tables[source_byte3_table + Int((UInt32(source[7]) ^ 0xe6))] ^ 0xaa)) | ((tables[source_byte2_table + Int((UInt32(source[6]) ^ 0xc5))] ^ 0x4c) << 0x8))
        uVar53 = (((((tables[source_byte0_table + Int((UInt32(source[0]) ^ 0x22))] ^ 0x2b) << 0x18) | ((tables[source_byte2_table + Int((UInt32(source[2]) ^ 0xae))] ^ 0x6a) << 0x8)) | ((tables[source_byte1_table + Int((UInt32(source[1]) ^ 0x97))] ^ 0xf6) << 0x10)) | (tables[source_byte3_table + Int((UInt32(source[3]) ^ 0x9d))] ^ 0xd5))
        uVar52 = (((uVar52 ^ uVar7) ^ 0xba60a927) ^ ((((((tables[input_byte0_table + Int((UInt32(constant[8]) ^ 0x76))] &+ 0x4b) ^ 0xa7) << 0x18) | (tables[input_byte3_table + Int((UInt32(constant[11]) ^ 0x7b))] ^ 0xd2)) | ((tables[input_byte2_table + Int((UInt32(constant[10]) ^ 0x61))] ^ 0x9e) << 0x8)) | ((tables[input_byte1_table + Int((UInt32(constant[9]) ^ 0xf9))] ^ 0xad) << 0x10)))
        uVar5 = (((uVar6 ^ uVar5) ^ uVar8) ^ 0x64effffb)
        uVar11 = (((uVar3 ^ uVar11) ^ uVar12) ^ uVar53)
        uVar10 = ((((uVar10 ^ uVar3) ^ uVar33) ^ uVar9) ^ 0x67ee5dfb)
        uVar7 = ((uVar11 ^ uVar3) ^ 0x59ba3917)
        uVar10 = ((uVar10 ^ 0x56031cbe) ^ uVar50)
        let middle_high_table = 178736
        let middle_low_table = 206048
        uVar11 = (((tableWord(middle_low_table, ((uVar5 & 0xff) ^ 0xc7)) &+ 0xce853eba) ^ tableWord(middle_high_table, ((uVar7 >> 0x18) ^ 0x2c))) ^ (((uVar7 >> 0x18) ^ 0x33c08cbd) &+ 0xd0fd5400))
        let middle_byte1_table = 200544
        uVar12 = (((tableWord(middle_low_table, ((uVar7 & 0xff) ^ 0xd8)) &+ 0xce853eba) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0x68))) ^ (((uVar10 >> 0x18) ^ 0x33c08cf9) &+ 0xd0fd5400))
        uVar12 = ((uVar12 ^ 0x4eb7d448) ^ tableWord(middle_byte1_table, (((uVar5 >> 0x8) & 0xff) ^ 0xa5)))
        let middle_byte2_table = 199504
        uVar11 = ((uVar11 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0x55)))
        uVar6 = (mixTableWordA(tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0xa5))) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0xb4)))
        uVar33 = ((uVar52 >> 0x18) ^ 0x33c08c9c)
        uVar33 = (tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0x8c)) ^ ((uVar33 ^ 0x81) &+ 0xd0fd5400))
        uVar6 = ((((((uVar5 >> 0x18) ^ 0x33c08ccb) &+ 0xd0fd5400) ^ tableWord(middle_byte2_table, (((uVar7 >> 0x10) & 0xff) ^ 0x26))) ^ tableWord(middle_high_table, ((uVar5 >> 0x18) ^ 0x5a))) ^ (uVar6 ^ 0xe4b91e3))
        uVar10 = (((uVar33 ^ 0x4eb7d448) ^ tableWord(middle_byte1_table, (((uVar7 >> 0x8) & 0xff) ^ 0x98))) ^ (tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0x9a)) &+ 0xce853eba))
        uVar11 = ((uVar11 ^ 0x4eb7d448) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x3e)))
        uVar10 = (((uVar15 ^ 0xb7acceb3) ^ tableWord(middle_byte2_table, (((uVar5 >> 0x10) & 0xff) ^ 0xea))) ^ uVar10)
        uVar5 = ((uVar16 ^ 0x6bff3f42) ^ (uVar6 ^ 0x23808b8e))
        uVar52 = (((uVar14 ^ 0xcea7dbc5) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x59))) ^ uVar12)
        uVar12 = (mixTableWordB(tableWord(middle_low_table, ((uVar5 & 0xff) ^ 0xa7))) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x34)))
        uVar6 = ((uVar10 >> 0x18) ^ 0x33c08c17)
        uVar6 = (((uVar6 ^ 0x81) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0x7)))
        uVar11 = ((uVar13 ^ 0x5116330) ^ (uVar11 ^ 0x1e421a9))
        uVar33 = (((tableWord(middle_low_table, ((uVar11 & 0xff) ^ 0x19)) &+ 0xce853eba) ^ tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0x4a))) ^ (((uVar52 >> 0x18) ^ 0x33c08cdb) &+ 0xd0fd5400))
        uVar33 = ((uVar33 ^ 0x4eb7d448) ^ tableWord(middle_byte1_table, (((uVar5 >> 0x8) & 0xff) ^ 0x68)))
        uVar7 = ((uVar5 >> 0x18) ^ 0x33c08cf4)
        uVar7 = (((uVar7 ^ 0x81) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar5 >> 0x18) ^ 0xe4)))
        uVar5 = ((uVar6 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar5 >> 0x10) & 0xff) ^ 0x6e)))
        uVar6 = (((tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0xb6)) &+ 0xce853eba) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x94))) ^ (uVar7 ^ 0x4eb7d448))
        uVar7 = ((uVar11 >> 0x18) ^ 0x33c08c89)
        uVar12 = (((((uVar18 ^ 0x964f96f7) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0x8a))) ^ (uVar12 ^ 0x4eb7d448)) ^ ((uVar7 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_high_table, ((uVar11 >> 0x18) ^ 0x99)))
        uVar10 = ((((uVar14 ^ uVar19) ^ 0xf30b7afb) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0xe2))) ^ (uVar33 ^ 0xe4b91e3))
        uVar52 = ((((uVar20 ^ 0x1adb87e7) ^ tableWord(middle_byte1_table, (((uVar11 >> 0x8) & 0xff) ^ 0x36))) ^ (tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0x9b)) &+ 0xce853eba)) ^ (uVar5 ^ 0x4eb7d448))
        uVar11 = ((((uVar20 ^ uVar17) ^ 0x318b8018) ^ tableWord(middle_byte2_table, (((uVar11 >> 0x10) & 0xff) ^ 0xc5))) ^ (uVar6 ^ 0xe4b91e3))
        uVar5 = (mixTableWordA(tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0x3f))) ^ tableWord(middle_byte1_table, (((uVar12 >> 0x8) & 0xff) ^ 0xfb)))
        uVar5 = ((((tableWord(middle_byte2_table, (((uVar11 >> 0x10) & 0xff) ^ 0x97)) ^ 0x377d6cee) ^ tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0x2c))) ^ (uVar52 >> 0x18)) ^ (uVar5 ^ 0xe4b91e3))
        uVar6 = (((uVar10 >> 0x18) ^ 0x377d6c9b) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0x59)))
        uVar6 = ((uVar6 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x2f)))
        uVar33 = (mixTableWordB(tableWord(middle_low_table, ((uVar11 & 0xff) ^ 0xb3))) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0x84)))
        uVar7 = ((uVar11 >> 0x18) ^ 0x33c08cf8)
        uVar8 = ((uVar12 >> 0x18) ^ 0x33c08cc9)
        uVar10 = ((((((uVar21 ^ 0x90ae848f) ^ tableWord(middle_byte2_table, (((uVar12 >> 0x10) & 0xff) ^ 0x36))) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0xc1))) ^ ((uVar7 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_high_table, ((uVar11 >> 0x18) ^ 0xe8))) ^ (tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0x30)) &+ 0xce853eba))
        uVar5 = ((uVar24 ^ 0x626932c5) ^ (uVar5 ^ 0x48608ca1))
        uVar11 = (((tableWord(middle_byte1_table, (((uVar11 >> 0x8) & 0xff) ^ 0xad)) ^ uVar23) ^ (tableWord(middle_low_table, ((uVar12 & 0xff) ^ 0x72)) &+ 0xce853eba)) ^ (uVar6 ^ 0x4eb7d448))
        uVar52 = (((((uVar22 ^ 0x45c73e3d) ^ ((uVar8 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x8e))) ^ tableWord(middle_high_table, ((uVar12 >> 0x18) ^ 0xd9))) ^ (uVar33 ^ 0x4eb7d448))
        uVar12 = (mixTableWordB(tableWord(middle_low_table, ((uVar11 & 0xff) ^ 0xab))) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0x66)))
        uVar6 = ((uVar11 >> 0x18) ^ 0x33c08c3d)
        uVar6 = (((tableWord(middle_high_table, ((uVar11 >> 0x18) ^ 0x2d)) ^ tableWord(middle_byte2_table, (((uVar5 >> 0x10) & 0xff) ^ 0xe))) ^ mixTableWordB(tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0xbd)))) ^ ((uVar6 ^ 0x81) &+ 0xd0fd5400))
        uVar33 = (((uVar52 >> 0x18) ^ 0xe4b9124) ^ tableWord(middle_byte2_table, (((uVar11 >> 0x10) & 0xff) ^ 0x44)))
        uVar33 = ((uVar33 ^ 0x377d6c81) ^ tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0x84)))
        uVar7 = ((uVar10 >> 0x18) ^ 0x33c08ce3)
        uVar7 = ((((uVar7 ^ 0x81) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0xf3))) ^ (tableWord(middle_low_table, ((uVar5 & 0xff) ^ 0xa2)) &+ 0xce853eba))
        uVar11 = ((uVar7 ^ 0x4eb7d448) ^ tableWord(middle_byte1_table, (((uVar11 >> 0x8) & 0xff) ^ 0xe)))
        uVar7 = ((uVar5 >> 0x18) ^ 0x33c08c37)
        uVar12 = (((((uVar27 ^ 0xdacebdbd) ^ ((uVar7 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x4a))) ^ (uVar12 ^ 0x4eb7d448)) ^ tableWord(middle_high_table, ((uVar5 >> 0x18) ^ 0x27)))
        uVar5 = ((((uVar25 ^ 0x348b8bca) ^ tableWord(middle_byte1_table, (((uVar5 >> 0x8) & 0xff) ^ 0xa7))) ^ (tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0xa6)) &+ 0xce853eba)) ^ (uVar33 ^ 0x4eb7d448))
        uVar52 = ((((uVar27 ^ uVar21) ^ 0x249841) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0xf7))) ^ (uVar11 ^ 0xe4b91e3))
        uVar10 = ((((uVar26 ^ uVar23) ^ 0x3d1e55f7) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0x8d))) ^ (uVar6 ^ 0x4eb7d448))
        uVar11 = (mixTableWordA(tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0x55))) ^ tableWord(middle_byte1_table, (((uVar5 >> 0x8) & 0xff) ^ 0x3)))
        uVar6 = (((((uVar10 >> 0x18) ^ 0x33c08ca9) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0x38))) ^ (tableWord(middle_low_table, ((uVar5 & 0xff) ^ 0x19)) &+ 0xce853eba))
        uVar6 = ((uVar6 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar12 >> 0x10) & 0xff) ^ 0xf4)))
        uVar33 = (((mixTableWordA(tableWord(middle_low_table, ((uVar12 & 0xff) ^ 0x55))) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0x60))) ^ tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0x18))) ^ (((uVar52 >> 0x18) ^ 0x33c08c89) &+ 0xd0fd5400))
        uVar10 = (((tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0x55)) ^ (((uVar5 >> 0x18) ^ 0x33c08ca3) &+ 0xd0fd5400)) ^ mixTableWordB(tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0xf4)))) ^ tableWord(middle_high_table, ((uVar5 >> 0x18) ^ 0x32)))
        uVar13 = (uVar10 ^ 0x4eb7d448)
        uVar10 = (tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x9c)) ^ (uVar11 ^ 0xe4b91e3))
        uVar11 = (((uVar32 ^ 0x6717c8f5) ^ tableWord(middle_byte2_table, (((uVar5 >> 0x10) & 0xff) ^ 0x99))) ^ (uVar33 ^ 0xe4b91e3))
        uVar10 = (((((uVar27 ^ uVar30) ^ 0x20c9a3b4) ^ (uVar12 >> 0x18)) ^ tableWord(middle_high_table, ((uVar12 >> 0x18) ^ 0xb1))) ^ (uVar10 ^ 0x377d6c81))
        uVar52 = (((uVar30 ^ 0x3eea361e) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x74))) ^ (uVar6 ^ 0x4eb7d448))
        uVar5 = ((uVar29 ^ 0x87746b7f) ^ tableWord(middle_byte1_table, (((uVar12 >> 0x8) & 0xff) ^ 0xc7)))
        uVar12 = (uVar5 ^ uVar13)
        uVar6 = ((uVar10 >> 0x18) ^ 0x33c08cb9)
        uVar6 = (((uVar6 ^ 0x81) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0xa9)))
        uVar33 = ((uVar52 >> 0x18) ^ 0x33c08caf)
        uVar33 = (((uVar33 ^ 0x81) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0xbf)))
        uVar33 = ((uVar33 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0x48)))
        uVar7 = ((uVar12 >> 0x18) ^ 0x33c08c43)
        uVar6 = (((tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0xe3)) &+ 0xce853eba) ^ tableWord(middle_byte1_table, (((uVar12 >> 0x8) & 0xff) ^ 0x1f))) ^ (uVar6 ^ 0x4eb7d448))
        uVar6 = (((uVar31 ^ 0x50321738) ^ tableWord(middle_byte2_table, (((uVar11 >> 0x10) & 0xff) ^ 0xec))) ^ (uVar6 ^ 0xe4b91e3))
        uVar8 = (((uVar28 ^ 0x13e1fc0c) ^ mixTableWordA(tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0xdf)))) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0xad)))
        uVar9 = ((uVar11 >> 0x18) ^ 0x33c08c7b)
        uVar52 = ((((((uVar34 ^ 0x8252f3da) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0x14))) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x27))) ^ tableWord(middle_high_table, ((uVar12 >> 0x18) ^ 0x53))) ^ ((uVar7 ^ 0x81) &+ 0xd0fd5400)) ^ (tableWord(middle_low_table, ((uVar11 & 0xff) ^ 0xe0)) &+ 0xce853eba))
        uVar10 = ((((uVar8 ^ 0xe4b91e3) ^ ((uVar9 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_high_table, ((uVar11 >> 0x18) ^ 0x6b))) ^ tableWord(middle_byte2_table, (((uVar12 >> 0x10) & 0xff) ^ 0x44)))
        uVar11 = ((((uVar35 ^ 0xf300959b) ^ tableWord(middle_byte1_table, (((uVar11 >> 0x8) & 0xff) ^ 0x64))) ^ (tableWord(middle_low_table, (((uVar5 ^ uVar13) ^ 0xffffffff) & 0xff)) &+ 0xce853eba)) ^ (uVar33 ^ 0x4eb7d448))
        uVar5 = ((uVar11 >> 0x18) ^ 0x33c08c9b)
        uVar5 = (((uVar5 ^ 0x81) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar11 >> 0x18) ^ 0x8b)))
        uVar12 = (mixTableWordA(tableWord(middle_low_table, (uVar10 & 0xff))) ^ tableWord(middle_byte1_table, (((uVar6 >> 0x8) & 0xff) ^ 0x41)))
        uVar33 = (((uVar6 >> 0x18) ^ 0x377d6cb8) ^ tableWord(middle_high_table, ((uVar6 >> 0x18) ^ 0x7a)))
        uVar33 = ((uVar33 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0x75)))
        uVar5 = ((uVar5 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar6 >> 0x10) & 0xff) ^ 0xeb)))
        uVar7 = ((uVar52 >> 0x18) ^ 0x33c08c25)
        uVar8 = ((uVar10 >> 0x18) ^ 0x33c08c75)
        uVar5 = ((((uVar36 ^ 0x215e2ccb) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0xdc))) ^ (uVar5 ^ 0x4eb7d448)) ^ (tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0xab)) &+ 0xce853eba))
        uVar10 = ((((((uVar40 ^ 0x1f432ca8) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x51))) ^ tableWord(middle_byte1_table, (((uVar11 >> 0x8) & 0xff) ^ 0xd7))) ^ ((uVar8 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0x65))) ^ (tableWord(middle_low_table, ((uVar6 & 0xff) ^ 0xfe)) &+ 0xce853eba))
        uVar6 = ((((uVar39 ^ 0x7a337c23) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x75))) ^ (uVar33 ^ 0x4eb7d448)) ^ (tableWord(middle_low_table, ((uVar11 & 0xff) ^ 0x2f)) &+ 0xce853eba))
        uVar52 = (((((uVar37 ^ 0xd81f3004) ^ tableWord(middle_byte2_table, (((uVar11 >> 0x10) & 0xff) ^ 0xaf))) ^ ((uVar7 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0x35))) ^ (uVar12 ^ 0xe4b91e3))
        uVar11 = ((((uVar10 >> 0x18) ^ 0x33c08c00) &+ 0xd0fd5400) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0x91)))
        uVar11 = ((uVar11 ^ 0x4eb7d448) ^ tableWord(middle_byte1_table, (((uVar5 >> 0x8) & 0xff) ^ 0x26)))
        uVar12 = ((uVar52 >> 0x18) ^ 0x33c08c0b)
        uVar12 = (((tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0x9b)) &+ 0xce853eba) ^ ((uVar12 ^ 0x81) &+ 0xd0fd5400)) ^ tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0x1b)))
        uVar12 = ((uVar12 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar5 >> 0x10) & 0xff) ^ 0x4d)))
        uVar33 = (((((uVar6 >> 0x18) ^ 0x377d6c63) ^ mixTableWordA(tableWord(middle_low_table, ((uVar5 & 0xff) ^ 0xaf)))) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x83))) ^ tableWord(middle_high_table, ((uVar6 >> 0x18) ^ 0xa1)))
        uVar7 = ((uVar5 >> 0x18) ^ 0x33c08cff)
        uVar5 = (((((uVar7 ^ 0x81) &+ 0xd0fd5400) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0x48))) ^ mixTableWordA(tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0xde)))) ^ tableWord(middle_high_table, ((uVar5 >> 0x18) ^ 0xef)))
        uVar10 = (((uVar42 ^ 0x5aa762b4) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0x89))) ^ (uVar33 ^ 0xe4b91e3))
        uVar52 = ((((uVar43 ^ 0x8780aca1) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x2))) ^ (uVar11 ^ 0xe4b91e3)) ^ (tableWord(middle_low_table, ((uVar6 & 0xff) ^ 0x3b)) &+ 0xce853eba))
        uVar11 = (((uVar41 ^ 0x9a463139) ^ (uVar12 ^ 0x4eb7d448)) ^ tableWord(middle_byte1_table, (((uVar6 >> 0x8) & 0xff) ^ 0x2b)))
        uVar5 = (((uVar38 ^ 0x8fa0bf20) ^ tableWord(middle_byte2_table, (((uVar6 >> 0x10) & 0xff) ^ 0xe7))) ^ (uVar5 ^ 0xe4b91e3))
        uVar12 = (mixTableWordB(tableWord(middle_low_table, ((uVar5 & 0xff) ^ 0x77))) ^ tableWord(middle_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0xca)))
        uVar6 = ((uVar11 >> 0x18) ^ 0x33c08c8a)
        uVar6 = (((tableWord(middle_high_table, ((uVar11 >> 0x18) ^ 0x9a)) ^ tableWord(middle_byte2_table, (((uVar5 >> 0x10) & 0xff) ^ 0x92))) ^ mixTableWordB(tableWord(middle_low_table, ((uVar52 & 0xff) ^ 0xfc)))) ^ ((uVar6 ^ 0x81) &+ 0xd0fd5400))
        uVar33 = ((uVar52 >> 0x18) ^ 0x33c08c1d)
        uVar33 = (tableWord(middle_high_table, ((uVar52 >> 0x18) ^ 0xd)) ^ ((uVar33 ^ 0x81) &+ 0xd0fd5400))
        uVar12 = ((((uVar10 >> 0x18) ^ 0x33c08c03) ^ tableWord(middle_high_table, ((uVar10 >> 0x18) ^ 0x13))) ^ (uVar12 ^ 0x377d6c81))
        uVar7 = ((uVar5 >> 0x18) ^ 0x33c08c5d)
        uVar7 = (tableWord(middle_high_table, ((uVar5 >> 0x18) ^ 0x4d)) ^ ((uVar7 ^ 0x81) &+ 0xd0fd5400))
        uVar33 = (((uVar33 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar11 >> 0x10) & 0xff) ^ 0xb9))) ^ (tableWord(middle_low_table, ((uVar10 & 0xff) ^ 0x24)) &+ 0xce853eba))
        uVar12 = (((((uVar42 ^ uVar45) ^ uVar54) ^ tableWord(middle_byte1_table, (((uVar11 >> 0x8) & 0xff) ^ 0xf2))) ^ (uVar12 ^ 0x4eb7d448)) ^ 0x86e37f37)
        uVar5 = ((uVar33 ^ 0x4eb7d448) ^ tableWord(middle_byte1_table, (((uVar5 >> 0x8) & 0xff) ^ 0xf1)))
        uVar11 = (((uVar7 ^ 0xe4b91e3) ^ tableWord(middle_byte2_table, (((uVar10 >> 0x10) & 0xff) ^ 0xf7))) ^ (tableWord(middle_low_table, ((uVar11 & 0xff) ^ 0xe3)) &+ 0xce853eba))
        uVar52 = ((((uVar3 ^ uVar45) ^ tableWord(middle_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0xd0))) ^ (uVar11 ^ 0x4eb7d448)) ^ 0x4fd66f27)
        uVar52 = ((uVar52 ^ 0x56031cbe) ^ uVar50)
        uVar11 = ((uVar46 ^ 0x525cd2bd) ^ (uVar5 ^ 0x7a157d8e))
        uVar3 = ((((uVar3 ^ uVar44) ^ 0x4f5c5bdc) ^ tableWord(middle_byte1_table, (((uVar10 >> 0x8) & 0xff) ^ 0xa1))) ^ (uVar6 ^ 0x4eb7d448))
        uVar50 = ((uVar3 ^ 0x56031cbe) ^ uVar50)
        uVar54 = ((uVar12 ^ 0x457b9fbb) ^ uVar54)
        let final_byte1_table = 148192
        let final_high_table = 183344
        let final_low_table = 185392
        uVar3 = ((tableWord(final_high_table, ((uVar52 >> 0x18) ^ 0xf)) ^ 0x6e4f6830) ^ tableWord(final_low_table, ((uVar50 & 0xff) ^ 0x7a)))
        let final_byte2_table = 136112
        uVar10 = (mixTableWordC(tableWord(final_byte2_table, (((uVar11 >> 0x10) & 0xff) ^ 0xee))) ^ tableWord(final_byte1_table, (((uVar50 >> 0x8) & 0xff) ^ 0x4c)))
        uVar10 = ((uVar10 ^ 0x1f226eb6) ^ tableWord(final_low_table, ((uVar52 & 0xff) ^ 0x84)))
        uVar5 = (mixTableWordC(tableWord(final_byte2_table, (((uVar52 >> 0x10) & 0xff) ^ 0x1b))) ^ tableWord(final_byte1_table, (((uVar54 >> 0x8) & 0xff) ^ 0xcd)))
        uVar5 = ((uVar5 ^ 0x1f226eb6) ^ tableWord(final_low_table, ((uVar11 & 0xff) ^ 0x1)))
        uVar12 = (((tableWord(final_low_table, ((uVar54 & 0xff) ^ 0x3c)) ^ 0x6e4f6830) ^ tableWord(final_high_table, ((uVar11 >> 0x18) ^ 0x24))) ^ (tableWord(final_byte2_table, (((uVar50 >> 0x10) & 0xff) ^ 0xd8)) &+ 0x2156722c))
        uVar5 = (((uVar47 ^ 0x95821f3f) ^ tableWord(final_high_table, ((uVar50 >> 0x18) ^ 0x67))) ^ (uVar5 ^ 0x716d0686))
        uVar10 = ((((uVar49 ^ 0x56031cbe) ^ 0xe8b64565) ^ tableWord(final_high_table, ((uVar54 >> 0x18) ^ 0x15))) ^ (uVar10 ^ 0x716d0686))
        uVar3 = (((((uVar45 ^ uVar47) ^ 0xc0df89ef) ^ (uVar3 ^ 0x70caa0b8)) ^ tableWord(final_byte1_table, (((uVar11 >> 0x8) & 0xff) ^ 0x24))) ^ (tableWord(final_byte2_table, (((uVar54 >> 0x10) & 0xff) ^ 0xc3)) &+ 0x2156722c))
        uVar52 = ((((uVar48 ^ 0x56031cbe) ^ 0x4b867b29) ^ tableWord(final_byte1_table, (((uVar52 >> 0x8) & 0xff) ^ 0x61))) ^ (uVar12 ^ 0x70caa0b8))
        output[0] = UInt8(truncatingIfNeeded: decodeOutputByte3(((uVar5 >> 0x18) & 0xff), 0x77, 0x41, 0x7a))
        output[1] = UInt8(truncatingIfNeeded: decodeOutputByte2(((uVar5 >> 0x10) & 0xff), 0xc2, 0xb5))
        output[2] = UInt8(truncatingIfNeeded: decodeOutputByte1(((uVar5 >> 0x8) & 0xff), 0xf8, 0x6d, 0x80))
        output[3] = UInt8(truncatingIfNeeded: decodeOutputByte0((uVar5 & 0xff), 0xef, 0x64, 0xf5))
        output[4] = UInt8(truncatingIfNeeded: decodeOutputByte3(((uVar3 >> 0x18) & 0xff), 0x1e, 0x28, 0xa6))
        output[5] = UInt8(truncatingIfNeeded: decodeOutputByte2(((uVar3 >> 0x10) & 0xff), 0x2c, 0xc8))
        output[6] = UInt8(truncatingIfNeeded: decodeOutputByte1(((uVar3 >> 0x8) & 0xff), 0x80, 0x15, 0x3))
        output[7] = UInt8(truncatingIfNeeded: decodeOutputByte0((uVar3 & 0xff), 0xee, 0x65, 0x3b))
        output[8] = UInt8(truncatingIfNeeded: decodeOutputByte3(((uVar10 >> 0x18) & 0xff), 0xe8, 0xde, 0x7d))
        output[9] = UInt8(truncatingIfNeeded: decodeOutputByte2(((uVar10 >> 0x10) & 0xff), 0x2e, 0xb1))
        output[10] = UInt8(truncatingIfNeeded: decodeOutputByte1(((uVar10 >> 0x8) & 0xff), 0xcb, 0x5e, 0x2b))
        output[11] = UInt8(truncatingIfNeeded: decodeOutputByte0((uVar10 & 0xff), 0x6a, 0xe1, 0xbe))
        output[12] = UInt8(truncatingIfNeeded: decodeOutputByte3(((uVar52 >> 0x18) & 0xff), 0x6c, 0x5a, 0xb8))
        output[13] = UInt8(truncatingIfNeeded: decodeOutputByte2(((uVar52 >> 0x10) & 0xff), 0x1d, 0x90))
        output[14] = UInt8(truncatingIfNeeded: decodeOutputByte1(((uVar52 >> 0x8) & 0xff), 0xa, 0x9f, 0xdd))
        output[15] = UInt8(truncatingIfNeeded: decodeOutputByte0((uVar52 & 0xff), 0xf8, 0x73, 0x74))
        return output
    }
}
