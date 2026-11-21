import Foundation

/// 고른 사진의 촬영 위치(GPS)가 지워진 채 들어왔는지 본다(I008, Android `PhotoLocation`과 같은 판별).
///
/// 사진 선택 창이 위치를 빼면서 GPS 태그는 두고 값 바이트만 0으로 지우는 경우가 있다(Android 실측: 위도·경도 유리수가 0/0,
/// Exif 앞에 COM이 있으면 지우는 자리가 밀려 위도 항목의 형식 칸이 0). 실제 좌표는 분모가 0일 수 없으므로
/// "GPS IFD가 있는데 위도·경도가 0/0이거나 형식이 잘못됨"이면 지워진 것으로 본다. GPS IFD가 없거나 위도·경도 항목이 없으면
/// 카메라가 위치를 남기지 않은 것이라 `absent`다. 고화질본 이식(D037)은 이 결과와 상관없이 받은 그대로 옮긴다.
///
/// ImageIO의 GPS 사전은 형식이 깨진 항목을 버리거나 0/0을 0으로 읽어 "없음"과 "지워짐"을 가릴 수 없어 Exif 바이트를 직접 본다.
/// JPEG는 이미지 데이터 앞까지만 읽고, HEIF는 Exif 아이템만 읽는다.
public enum PhotoLocation: String, Sendable, Equatable {
    /// 위치 정보가 없다(카메라가 남기지 않음, 읽을 수 없음)
    case absent
    /// 위도·경도가 온전하다
    case present
    /// GPS 태그는 있는데 값이 지워졌다(0/0 또는 잘못된 형식)
    case removed

    static let gpsIFDTag: UInt16 = 0x8825
    static let latitudeTag: UInt16 = 0x0002
    static let longitudeTag: UInt16 = 0x0004
    static let rationalType: UInt16 = 5
    /// HEIF `meta` 상자와 Exif 아이템을 읽는 상한(정상 파일은 수십 KB)
    static let maxMetaBoxSize = 8 << 20
    static let maxExifItemSize = 1 << 20

    /// 형식에 맞춰 파일에서 Exif를 꺼내 판별한다. JPEG·HEIF가 아니면 `absent`.
    public static func of(_ url: URL, format: PhotoInspection.Format) -> PhotoLocation {
        switch format {
        case .jpeg: of(exifPayload: exifPayload(ofJPEG: url))
        case .heif: of(exifPayload: exifPayload(ofHEIF: url))
        case .raw, .other: .absent
        }
    }

    /// Exif APP1 내용(`Exif\0\0` 머리 + TIFF 블록)으로 판별한다. 읽을 수 없으면 `absent`.
    static func of(exifPayload payload: [UInt8]?) -> PhotoLocation {
        let header = JPEGMetadataTransplant.exifHeader
        guard let payload, payload.count >= header.count + 8, payload.starts(with: header) else { return .absent }
        do {
            let tiff = try JPEGMetadataTransplant.TIFFBlock(payload: payload, base: header.count)
            guard let pointer = try tiff.ifd(at: tiff.firstIFDOffset).entries[gpsIFDTag] else { return .absent }
            let gps = try tiff.ifd(at: tiff.uint32(at: pointer.valueOffset))
            let coordinates = [gps.entries[latitudeTag], gps.entries[longitudeTag]].compactMap { $0 }
            if coordinates.isEmpty { return .absent }
            return try coordinates.allSatisfy { try isIntact($0, in: tiff) } ? .present : .removed
        } catch {
            return .absent
        }
    }

    /// 도·분·초 유리수 3개이고 분모가 모두 0이 아니어야 온전하다.
    private static func isIntact(_ entry: JPEGMetadataTransplant.TIFFBlock.Entry, in tiff: JPEGMetadataTransplant.TIFFBlock) throws -> Bool {
        guard entry.type == rationalType, entry.count == 3 else { return false }
        return try (0..<3).allSatisfy { try tiff.uint32(at: entry.valueOffset + $0 * 8 + 4) != 0 }
    }

    // MARK: - JPEG

    /// JPEG에서 Exif APP1 내용만 꺼낸다(이미지 데이터 앞에서 멈추고 다른 세그먼트는 건너뛴다). 없거나 JPEG가 아니면 nil.
    static func exifPayload(ofJPEG url: URL) -> [UInt8]? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        guard file.readBytes(2) == [0xFF, 0xD8] else { return nil }
        while true {
            guard file.readBytes(1) == [0xFF] else { return nil }
            var marker = file.readBytes(1)?.first
            while marker == 0xFF { marker = file.readBytes(1)?.first } // 채움 바이트
            guard let marker, marker != 0xDA, marker != 0xD9, let lengthBytes = file.readBytes(2) else { return nil }
            let length = Int(lengthBytes[0]) << 8 | Int(lengthBytes[1])
            guard length >= 2 else { return nil }
            if marker == 0xE1 {
                guard let payload = file.readBytes(length - 2) else { return nil }
                if payload.starts(with: JPEGMetadataTransplant.exifHeader) { return payload }
            } else {
                guard let offset = try? file.offset(), (try? file.seek(toOffset: offset + UInt64(length - 2))) != nil else { return nil }
            }
        }
    }

    // MARK: - HEIF

    /// HEIF(ISOBMFF)에서 Exif 아이템을 꺼내 JPEG Exif APP1 모양(`Exif\0\0` + TIFF)으로 돌려준다. 없으면 nil.
    ///
    /// `meta` → `iinf`에서 종류가 `Exif`인 아이템 ID → `iloc`에서 그 아이템의 파일 위치(`construction_method` 0)를 읽는다.
    /// 아이템 내용은 4바이트 "TIFF 머리까지 거리" + 내용이다(ISO/IEC 23008-12 부록 A, 애플 HEIC는 거리 6 + `Exif\0\0`).
    static func exifPayload(ofHEIF url: URL) -> [UInt8]? {
        guard let file = try? FileHandle(forReadingFrom: url), let fileSize = try? file.seekToEnd() else { return nil }
        defer { try? file.close() }
        guard let meta = topLevelBox("meta", in: file, fileSize: fileSize), meta.count > 4 else { return nil }
        var children: [String: [UInt8]] = [:]
        var reader = ByteReader(meta, at: 4) // FullBox: 판 1바이트 + 플래그 3바이트
        while let (type, body) = try? reader.box() {
            if children[type] == nil { children[type] = body }
        }
        guard let iinf = children["iinf"], let iloc = children["iloc"],
              let itemID = try? exifItemID(in: iinf), let extents = try? extents(of: itemID, in: iloc)
        else { return nil }
        var data: [UInt8] = []
        for (offset, length) in extents {
            guard length > 0, offset + UInt64(length) <= fileSize, data.count + length <= maxExifItemSize,
                  (try? file.seek(toOffset: offset)) != nil, let bytes = file.readBytes(length)
            else { return nil }
            data += bytes
        }
        guard data.count >= 4 else { return nil }
        let tiffStart = 4 + (Int(data[0]) << 24 | Int(data[1]) << 16 | Int(data[2]) << 8 | Int(data[3]))
        guard tiffStart + 8 <= data.count else { return nil }
        return JPEGMetadataTransplant.exifHeader + data[tiffStart...]
    }

    /// 맨 위 상자 중 `type`의 내용(머리 뺀 것). 다른 상자는 머리만 읽고 건너뛴다.
    private static func topLevelBox(_ type: String, in file: FileHandle, fileSize: UInt64) -> [UInt8]? {
        var position: UInt64 = 0
        while position + 8 <= fileSize {
            guard (try? file.seek(toOffset: position)) != nil, let header = file.readBytes(8) else { return nil }
            var size = UInt64(header[0]) << 24 | UInt64(header[1]) << 16 | UInt64(header[2]) << 8 | UInt64(header[3])
            var headerSize: UInt64 = 8
            if size == 1 {
                guard let large = file.readBytes(8) else { return nil }
                size = large.reduce(0) { $0 << 8 | UInt64($1) }
                headerSize = 16
            } else if size == 0 {
                size = fileSize - position
            }
            guard size >= headerSize, size <= fileSize - position else { return nil }
            if String(decoding: header[4..<8], as: UTF8.self) == type {
                let bodySize = size - headerSize
                guard bodySize <= UInt64(maxMetaBoxSize) else { return nil }
                return file.readBytes(Int(bodySize))
            }
            position += size
        }
        return nil
    }

    /// `iinf`에서 종류가 `Exif`인 첫 아이템 ID. `infe` 판 2·3만 종류 칸이 있다.
    private static func exifItemID(in iinf: [UInt8]) throws -> Int? {
        var reader = ByteReader(iinf)
        let version = try reader.uint(1)
        try reader.skip(3)
        let count = try reader.uint(version == 0 ? 2 : 4)
        for _ in 0..<count {
            let (type, body) = try reader.box()
            guard type == "infe" else { continue }
            var entry = ByteReader(body)
            let entryVersion = try entry.uint(1)
            try entry.skip(3)
            guard entryVersion >= 2 else { continue }
            let id = try entry.uint(entryVersion == 2 ? 2 : 4)
            try entry.skip(2) // item_protection_index
            if try entry.fourCC() == "Exif" { return id }
        }
        return nil
    }

    /// `iloc`에서 그 아이템의 파일 기준 구간들. 파일 오프셋이 아닌 방식(`idat`·다른 아이템)이면 nil.
    private static func extents(of itemID: Int, in iloc: [UInt8]) throws -> [(offset: UInt64, length: Int)]? {
        var reader = ByteReader(iloc)
        let version = try reader.uint(1)
        try reader.skip(3)
        let sizes = try reader.uint(1)
        let sizes2 = try reader.uint(1)
        let offsetSize = sizes >> 4, lengthSize = sizes & 0xF, baseOffsetSize = sizes2 >> 4
        let indexSize = version == 1 || version == 2 ? sizes2 & 0xF : 0
        let count = try reader.uint(version < 2 ? 2 : 4)
        for _ in 0..<count {
            let id = try reader.uint(version < 2 ? 2 : 4)
            let method = version == 1 || version == 2 ? try reader.uint(2) & 0xF : 0
            let dataReference = try reader.uint(2)
            let base = try reader.uint(baseOffsetSize)
            let extentCount = try reader.uint(2)
            var extents: [(offset: UInt64, length: Int)] = []
            for _ in 0..<extentCount {
                try reader.skip(indexSize)
                let offset = try reader.uint(offsetSize)
                let length = try reader.uint(lengthSize)
                // 깨진 파일의 큰 값끼리 더해 넘치지 않게 한다(넘치면 앱이 죽는다).
                let (start, overflow) = base.addingReportingOverflow(offset)
                guard !overflow else { throw ByteReader.OutOfRange() }
                extents.append((UInt64(start), length))
            }
            if id == itemID {
                return method == 0 && dataReference == 0 && !extents.isEmpty ? extents : nil
            }
        }
        return nil
    }

    /// 빅 엔디언 바이트 읽기. 범위를 넘으면 던진다.
    private struct ByteReader {
        struct OutOfRange: Error {}

        let bytes: [UInt8]
        var index: Int

        init(_ bytes: [UInt8], at index: Int = 0) {
            self.bytes = bytes
            self.index = index
        }

        mutating func skip(_ count: Int) throws {
            guard count >= 0, index + count <= bytes.count else { throw OutOfRange() }
            index += count
        }

        /// 0·1·2·4·8바이트 부호 없는 정수(0바이트는 0)
        mutating func uint(_ size: Int) throws -> Int {
            guard [0, 1, 2, 4, 8].contains(size), index + size <= bytes.count else { throw OutOfRange() }
            let value = bytes[index..<(index + size)].reduce(0) { $0 << 8 | Int($1) }
            index += size
            guard value >= 0 else { throw OutOfRange() }
            return value
        }

        mutating func fourCC() throws -> String {
            guard index + 4 <= bytes.count else { throw OutOfRange() }
            defer { index += 4 }
            return String(decoding: bytes[index..<(index + 4)], as: UTF8.self)
        }

        /// 상자 하나(종류, 머리 뺀 내용). 크기 0(끝까지)·1(64비트)도 읽는다.
        mutating func box() throws -> (type: String, body: [UInt8]) {
            let start = index
            var size = try uint(4)
            let type = try fourCC()
            if size == 1 {
                size = try uint(8)
            } else if size == 0 {
                size = bytes.count - start
            }
            let headerSize = index - start
            guard size >= headerSize, start + size <= bytes.count else { throw OutOfRange() }
            let body = Array(bytes[index..<(start + size)])
            index = start + size
            return (type, body)
        }
    }
}

private extension FileHandle {
    /// 정확히 `count`바이트를 읽는다. 모자라면 nil.
    func readBytes(_ count: Int) -> [UInt8]? {
        guard count >= 0 else { return nil }
        if count == 0 { return [] }
        guard let data = try? read(upToCount: count), data.count == count else { return nil }
        return [UInt8](data)
    }
}
