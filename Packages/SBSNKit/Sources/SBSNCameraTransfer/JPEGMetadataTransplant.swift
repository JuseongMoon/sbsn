import Foundation

/// 원본 JPEG의 메타데이터 세그먼트를 새로 인코딩한 JPEG로 옮기고, 출력과 맞지 않는 값만 고친다(D037, 설계 문서 4.1절).
///
/// 고객 최종본은 작가가 올린 파일의 메타데이터를 전부 유지한다(GPS·일련번호·소유자·MakerNote·IPTC·XMP).
/// ImageIO의 메타데이터 복사(`AddImageFromSource`·`AddImageAndMetadata`)는 MakerNote를 버려서(실제 a7C II 원본으로 확인) 바이트로 옮긴다.
/// - 옮기는 것: Exif APP1(TIFF 블록 통째로), XMP APP1과 확장 XMP, APP13(IPTC 등 Photoshop 정보), COM. 바이트 그대로다.
/// - 고치는 것(TIFF는 같은 자리·같은 길이): IFD0 Orientation=1, Exif PixelXDimension·PixelYDimension=출력 크기, ColorSpace=1,
///   Interop 색 공간 표시 R03(Adobe RGB)→R98. 회전하거나 줄였으면 IFD1(썸네일) 연결을 끊는다. 원본에 없는 태그는 넣지 않는다.
///   MakerNote 안의 오프셋이 TIFF 머리 기준이라 블록 길이를 바꾸면 깨진다.
/// - XMP는 텍스트라 같은 값(tiff:Orientation, exif:PixelX·YDimension, tiff:ImageWidth·ImageLength, photoshop:ICCProfile)을 고치고,
///   출력에 없는 데이터를 가리키는 항목(hdrgm:*, GCamera:MotionPhoto*, Container:Directory)을 지운 뒤 길이를 다시 잰다. 확장 XMP는 그대로 둔다.
/// - 옮기지 않는 것: ICC·MPF(APP2), JFIF(APP0), Adobe(APP14), 그 밖의 APP 세그먼트, 주 이미지 EOI 뒤 트레일러.
///   소니 HiddenData도 트레일러라 빠지고, ExifTool은 `[minor] Error reading HiddenData` 경고를 하나 낸다(공통 명세상 정상).
///   인코더가 쓴 JFIF·ICC(sRGB)와 이미지 데이터는 그대로 둔다.
enum JPEGMetadataTransplant {
    struct Output: Equatable {
        let width: Int
        let height: Int
        /// 회전했거나 줄여서 원본 썸네일(IFD1)이 출력과 맞지 않는다.
        let dropsThumbnail: Bool
    }

    enum TransplantError: Error {
        case notJPEG
        case malformedSegment
        case malformedTIFF
    }

    struct Segment: Equatable {
        let marker: UInt8
        let payload: [UInt8]
    }

    static let xmpHeader = Array("http://ns.adobe.com/xap/1.0/\u{0}".utf8)
    static let extendedXMPHeader = Array("http://ns.adobe.com/xmp/extension/\u{0}".utf8)
    static let exifHeader: [UInt8] = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]
    /// 세그먼트 길이 칸(2바이트)에 들어갈 수 있는 최대 내용 길이
    static let maxPayload = 65_533

    static func transplant(from source: Data, into encoded: Data, output: Output) throws -> Data {
        let (sourceSegments, _) = try split([UInt8](source))
        let (encodedSegments, scan) = try split([UInt8](encoded))
        var moved: [Segment] = []
        for segment in sourceSegments {
            switch segment.marker {
            case 0xE1 where segment.payload.starts(with: exifHeader):
                moved.append(Segment(marker: 0xE1, payload: try patchedExif(segment.payload, output: output)))
            case 0xE1 where segment.payload.starts(with: xmpHeader):
                moved.append(Segment(marker: 0xE1, payload: patchedXMP(segment.payload, output: output)))
            case 0xE1 where segment.payload.starts(with: extendedXMPHeader), 0xED, 0xFE:
                moved.append(segment)
            default:
                break
            }
        }
        // 인코더가 쓴 Exif·XMP·APP13·COM은 버리고 원본 것으로 바꾼다. JFIF(APP0)는 맨 앞에 둔다.
        let kept = encodedSegments.filter { ![0xE1, 0xED, 0xFE].contains($0.marker) }
        let ordered = kept.filter { $0.marker == 0xE0 } + moved + kept.filter { $0.marker != 0xE0 }
        var out: [UInt8] = [0xFF, 0xD8]
        out.reserveCapacity(encoded.count + ordered.reduce(0) { $0 + $1.payload.count + 4 })
        for segment in ordered {
            let length = segment.payload.count + 2
            out += [0xFF, segment.marker, UInt8(length >> 8), UInt8(length & 0xFF)]
            out += segment.payload
        }
        out += scan
        return Data(out)
    }

    /// SOS 앞의 세그먼트들과 SOS부터 끝까지(이미지 데이터)를 나눈다.
    static func split(_ bytes: [UInt8]) throws -> (segments: [Segment], scan: [UInt8]) {
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw TransplantError.notJPEG }
        var index = 2
        var segments: [Segment] = []
        while index + 1 < bytes.count {
            guard bytes[index] == 0xFF else { throw TransplantError.malformedSegment }
            let marker = bytes[index + 1]
            if marker == 0xFF {
                index += 1 // 채움 바이트
                continue
            }
            if marker == 0xDA {
                return (segments, Array(bytes[index...]))
            }
            guard index + 4 <= bytes.count else { throw TransplantError.malformedSegment }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { throw TransplantError.malformedSegment }
            segments.append(Segment(marker: marker, payload: Array(bytes[(index + 4)..<(index + 2 + length)])))
            index += 2 + length
        }
        throw TransplantError.malformedSegment
    }

    // MARK: - Exif(TIFF)

    static func patchedExif(_ payload: [UInt8], output: Output) throws -> [UInt8] {
        var tiff = try TIFFBlock(payload: payload, base: exifHeader.count)
        let ifd0 = try tiff.ifd(at: tiff.firstIFDOffset)
        if let orientation = ifd0.entries[0x0112] {
            try tiff.setInteger(orientation, to: 1)
        }
        if output.dropsThumbnail {
            tiff.setUInt32(0, at: ifd0.nextIFDPointer)
        }
        if let exifPointer = ifd0.entries[0x8769] {
            let exif = try tiff.ifd(at: tiff.uint32(at: exifPointer.valueOffset))
            if let entry = exif.entries[0xA002] { try tiff.setInteger(entry, to: output.width) }
            if let entry = exif.entries[0xA003] { try tiff.setInteger(entry, to: output.height) }
            if let entry = exif.entries[0xA001] { try tiff.setInteger(entry, to: 1) }
            if let interopPointer = exif.entries[0xA005] {
                let interop = try tiff.ifd(at: tiff.uint32(at: interopPointer.valueOffset))
                if let index = interop.entries[0x0001], index.type == 2, index.count == 4,
                   tiff.bytes[index.valueOffset..<(index.valueOffset + 3)].elementsEqual(Array("R03".utf8)) {
                    tiff.replaceBytes(Array("R98".utf8), at: index.valueOffset)
                }
            }
        }
        precondition(tiff.bytes.count == payload.count, "TIFF 블록 길이는 바뀌면 안 된다")
        return tiff.bytes
    }

    /// Exif APP1 안의 TIFF 블록. 오프셋은 TIFF 머리(`base`) 기준이다.
    struct TIFFBlock {
        struct Entry {
            let tag: UInt16
            let type: UInt16
            let count: Int
            /// 값이 4바이트 안이면 항목 안의 값 칸, 아니면 값이 있는 곳(절대 위치)
            let valueOffset: Int
        }

        struct IFD {
            let entries: [UInt16: Entry]
            /// 다음 IFD 오프셋이 적힌 곳(절대 위치)
            let nextIFDPointer: Int
        }

        var bytes: [UInt8]
        let base: Int
        let littleEndian: Bool

        init(payload: [UInt8], base: Int) throws {
            guard payload.count >= base + 8 else { throw TransplantError.malformedTIFF }
            bytes = payload
            self.base = base
            switch (payload[base], payload[base + 1]) {
            case (0x49, 0x49): littleEndian = true
            case (0x4D, 0x4D): littleEndian = false
            default: throw TransplantError.malformedTIFF
            }
        }

        var firstIFDOffset: Int {
            get throws { try uint32(at: base + 4) }
        }

        func uint16(at index: Int) throws -> Int {
            guard index >= 0, index + 2 <= bytes.count else { throw TransplantError.malformedTIFF }
            return littleEndian ? Int(bytes[index]) | Int(bytes[index + 1]) << 8 : Int(bytes[index]) << 8 | Int(bytes[index + 1])
        }

        func uint32(at index: Int) throws -> Int {
            guard index >= 0, index + 4 <= bytes.count else { throw TransplantError.malformedTIFF }
            let b = bytes[index..<(index + 4)].map(Int.init)
            return littleEndian ? b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24 : b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
        }

        func ifd(at offset: Int) throws -> IFD {
            let start = base + offset
            let count = try uint16(at: start)
            var entries: [UInt16: Entry] = [:]
            for index in 0..<count {
                let position = start + 2 + index * 12
                let tag = UInt16(try uint16(at: position))
                let type = UInt16(try uint16(at: position + 2))
                let valueCount = try uint32(at: position + 4)
                let unit = [1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8][Int(type)] ?? 1
                let size = unit * valueCount
                let valueOffset = size <= 4 ? position + 8 : base + (try uint32(at: position + 8))
                guard valueOffset >= 0, valueOffset + size <= bytes.count else { throw TransplantError.malformedTIFF }
                entries[tag] = Entry(tag: tag, type: type, count: valueCount, valueOffset: valueOffset)
            }
            let next = start + 2 + count * 12
            guard next + 4 <= bytes.count else { throw TransplantError.malformedTIFF }
            return IFD(entries: entries, nextIFDPointer: next)
        }

        /// SHORT·LONG 값 하나를 같은 칸에 고쳐 쓴다. 칸에 들어가지 않는 값이면 고치지 않는다.
        mutating func setInteger(_ entry: Entry, to value: Int) throws {
            guard entry.count == 1 else { return }
            switch entry.type {
            case 3 where value <= 0xFFFF: setUInt16(value, at: entry.valueOffset)
            case 4: setUInt32(value, at: entry.valueOffset)
            default: return
            }
        }

        mutating func setUInt16(_ value: Int, at index: Int) {
            let b = [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]
            replaceBytes(littleEndian ? b : b.reversed(), at: index)
        }

        mutating func setUInt32(_ value: Int, at index: Int) {
            let b = [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF)]
            replaceBytes(littleEndian ? b : b.reversed(), at: index)
        }

        mutating func replaceBytes(_ new: [UInt8], at index: Int) {
            bytes.replaceSubrange(index..<(index + new.count), with: new)
        }
    }

    // MARK: - XMP

    /// XMP 텍스트의 고칠 값과 지울 항목을 처리한다. 고친 결과가 세그먼트에 들어가지 않으면 원본을 그대로 둔다.
    static func patchedXMP(_ payload: [UInt8], output: Output) -> [UInt8] {
        guard let text = String(bytes: payload.dropFirst(xmpHeader.count), encoding: .utf8) else { return payload }
        var xmp = text
        let values = [
            ("tiff:Orientation", "1"),
            ("exif:PixelXDimension", String(output.width)),
            ("exif:PixelYDimension", String(output.height)),
            ("tiff:ImageWidth", String(output.width)),
            ("tiff:ImageLength", String(output.height)),
            ("photoshop:ICCProfile", "sRGB IEC61966-2.1"),
        ]
        for (name, value) in values {
            let quoted = NSRegularExpression.escapedTemplate(for: value)
            xmp = replacing(#"(\b\#(name)\s*=\s*")[^"]*(")"#, in: xmp, with: "$1\(quoted)$2")
            xmp = replacing(#"(<\#(name)>)[^<]*(</\#(name)>)"#, in: xmp, with: "$1\(quoted)$2")
        }
        // 앞의 공백은 한 글자만 잡는다. 카메라 XMP는 끝에 수십 KB 공백 채움이 있어 `\s+`로 시작하면 되짚기가 폭증한다(실제 a7C II 원본).
        for name in [#"hdrgm:[A-Za-z0-9_]+"#, #"GCamera:MotionPhoto[A-Za-z0-9_]*"#, #"Container:Directory"#] {
            xmp = replacing(#"\s\#(name)\s*=\s*"[^"]*""#, in: xmp, with: "")
            xmp = replacing(#"<(\#(name))\b[^>]*?(/>|>.*?</\1>)"#, in: xmp, with: "")
        }
        let patched = xmpHeader + Array(xmp.utf8)
        return patched.count <= maxPayload ? patched : payload
    }

    private static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
