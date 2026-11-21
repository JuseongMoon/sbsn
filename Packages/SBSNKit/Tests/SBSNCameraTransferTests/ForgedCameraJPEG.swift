import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SBSNCameraTransfer

/// 카메라 원본처럼 메타데이터를 붙인 시험용 JPEG(합성, 실제 사진·위치 아님).
///
/// ImageIO로는 MakerNote·임의 XMP를 쓸 수 없어 세그먼트를 직접 만든다. 구조는 설계 문서 4.2절 실험의 `forge.py`와 같다.
/// - Exif APP1: IFD0(기종·회전·Artist·Copyright) → Exif IFD(촬영 시각, MakerNote 1,036바이트, 색 공간, 크기, Interop,
///   소유자, 본체·렌즈 일련번호, 렌즈) → GPS IFD → Interop IFD → IFD1(썸네일)
/// - XMP APP1(회전·크기·라이트룸 `crs`·임의 이름공간·hdrgm·MotionPhoto·Container·ICCProfile), 확장 XMP APP1, APP13(IPTC),
///   COM, 알 수 없는 APP3, EOI 뒤 트레일러
struct ForgedCameraJPEG {
    static let makerNote: [UInt8] = Array("SONY DSC \u{0}\u{0}\u{0}".utf8) + (0..<4).flatMap { _ in (0...255).map(UInt8.init) }

    let url: URL
    let exifPayload: [UInt8]
    let extendedXMPPayload: [UInt8]
    let iptcPayload: [UInt8]
    let commentPayload: [UInt8]

    /// - Parameters:
    ///   - width·height: 저장된 픽셀 크기(회전 전)
    ///   - adobeRGB: Exif 색 공간 65535(미보정)와 Interop R03, XMP ICCProfile "Adobe RGB (1998)"로 표시한다(픽셀은 sRGB).
    ///   - includesSizeAndColorSpace: false면 Exif에 크기·색 공간 칸을 넣지 않는다.
    init(directory: URL, width: Int, height: Int, orientation: Int, adobeRGB: Bool = false, includesSizeAndColorSpace: Bool = true) throws {
        let plain = try Self.encode(width: width, height: height)
        let thumbnail = try Self.encode(width: 160, height: 107)
        let (plainSegments, scan) = try JPEGMetadataTransplant.split([UInt8](plain))

        var exifIFD: [(UInt16, Value)] = [
            (0x9003, .ascii("2026:11:21 14:05:00")),
            (0x927C, .undefined(Self.makerNote)),
            (0xA005, .pointer(3)),
            (0xA430, .ascii("Owner Name")),
            (0xA431, .ascii("5123456")),
            (0xA434, .ascii("FE 35mm F1.8")),
            (0xA435, .ascii("0012345")),
        ]
        if includesSizeAndColorSpace {
            exifIFD += [(0xA001, .short(adobeRGB ? 65535 : 1)), (0xA002, .long(width)), (0xA003, .long(height))]
        }
        let ifds: [IFD] = [
            IFD(entries: [
                (0x010F, .ascii("SONY")), (0x0110, .ascii("ILCE-7CM2")), (0x0112, .short(orientation)),
                (0x013B, .ascii("Test Photographer")), (0x8298, .ascii("(c) Test")), (0x8769, .pointer(1)), (0x8825, .pointer(2)),
            ], next: 4),
            IFD(entries: exifIFD, next: nil),
            IFD(entries: [
                (0x0001, .ascii("N")), (0x0002, .rationals([(37, 1), (34, 1), (4656, 100)])),
                (0x0003, .ascii("E")), (0x0004, .rationals([(126, 1), (58, 1), (1452, 100)])),
            ], next: nil),
            IFD(entries: [(0x0001, .ascii(adobeRGB ? "R03" : "R98"))], next: nil),
            IFD(entries: [(0x0103, .short(6)), (0x0201, .data([UInt8](thumbnail))), (0x0202, .long(thumbnail.count))], next: nil),
        ]
        exifPayload = JPEGMetadataTransplant.exifHeader + Self.tiff(ifds)

        let xmp = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?><x:xmpmeta xmlns:x="adobe:ns:meta/">\
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description rdf:about="" \
        xmlns:tiff="http://ns.adobe.com/tiff/1.0/" xmlns:exif="http://ns.adobe.com/exif/1.0/" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" \
        xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/" xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/" \
        xmlns:GCamera="http://ns.google.com/photos/1.0/camera/" xmlns:Container="http://ns.google.com/photos/1.0/container/" \
        xmlns:sbsnTest="http://example.com/sbsnTest/1.0/" \
        tiff:Orientation="\(orientation)" exif:PixelXDimension="\(width)" exif:PixelYDimension="\(height)" \
        crs:Exposure2012="+0.50" sbsnTest:Note="custom" photoshop:ICCProfile="\(adobeRGB ? "Adobe RGB (1998)" : "sRGB IEC61966-2.1")" \
        hdrgm:Version="1.0" GCamera:MotionPhoto="1" GCamera:MotionPhotoVersion="1">\
        <dc:creator><rdf:Seq><rdf:li>Test Photographer</rdf:li></rdf:Seq></dc:creator>\
        <Container:Directory><rdf:Seq><rdf:li rdf:parseType="Resource"><Container:Item/></rdf:li></rdf:Seq></Container:Directory>\
        </rdf:Description></rdf:RDF></x:xmpmeta><?xpacket end="w"?>
        """
        let xmpPayload = JPEGMetadataTransplant.xmpHeader + Array(xmp.utf8)
        extendedXMPPayload = JPEGMetadataTransplant.extendedXMPHeader + Array("0123456789ABCDEF0123456789ABCDEF".utf8)
            + [0, 0, 0, 16, 0, 0, 0, 0] + Array("<x:extended/>".utf8)
        let byline = Array("Test Photographer".utf8)
        let record: [UInt8] = [0x1C, 0x02, 0x50, 0x00, UInt8(byline.count)] + byline
        iptcPayload = Array("Photoshop 3.0\u{0}8BIM".utf8) + [0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, UInt8(record.count)] + record
            + (record.count % 2 == 1 ? [0] : [])
        commentPayload = Array("forged comment".utf8)

        var bytes: [UInt8] = [0xFF, 0xD8]
        let segments: [(UInt8, [UInt8])] = [(0xE1, exifPayload), (0xE1, xmpPayload), (0xE1, extendedXMPPayload), (0xED, iptcPayload),
                                            (0xFE, commentPayload), (0xE3, Array("SBSNTEST unknown app".utf8))]
            + plainSegments.filter { !(0xE0...0xEF).contains($0.marker) && $0.marker != 0xFE }.map { ($0.marker, $0.payload) }
        for (marker, payload) in segments {
            let length = payload.count + 2
            bytes += [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
        }
        bytes += scan
        bytes += Array("SONY HIDDEN DATA TRAILER".utf8)
        url = directory.appending(path: "forged-\(UUID().uuidString).jpg")
        try Data(bytes).write(to: url)
    }

    /// Exif APP1 안의 MakerNote 바이트
    static func makerNote(in exifPayload: [UInt8]) throws -> [UInt8] {
        let tiff = try JPEGMetadataTransplant.TIFFBlock(payload: exifPayload, base: JPEGMetadataTransplant.exifHeader.count)
        let ifd0 = try tiff.ifd(at: tiff.firstIFDOffset)
        let exif = try tiff.ifd(at: tiff.uint32(at: try #require(ifd0.entries[0x8769]).valueOffset))
        let entry = try #require(exif.entries[0x927C])
        return Array(tiff.bytes[entry.valueOffset..<(entry.valueOffset + entry.count)])
    }

    // MARK: - 만들기

    enum Value {
        case ascii(String)
        case short(Int)
        case long(Int)
        case undefined([UInt8])
        case rationals([(Int, Int)])
        /// 다른 IFD의 시작 위치(IFD 번호)
        case pointer(Int)
        /// 값 영역에 바이트를 두고 그 위치를 LONG으로 적는다(썸네일)
        case data([UInt8])
    }

    struct IFD {
        let entries: [(UInt16, Value)]
        let next: Int?
    }

    /// 리틀 엔디언 TIFF 블록. IFD들을 차례로 두고 4바이트를 넘는 값은 뒤의 값 영역에 둔다.
    static func tiff(_ ifds: [IFD]) -> [UInt8] {
        var starts: [Int] = []
        var position = 8
        for ifd in ifds {
            starts.append(position)
            position += 2 + ifd.entries.count * 12 + 4
        }
        let dataStart = position
        var data: [UInt8] = []
        var out: [UInt8] = [0x49, 0x49, 0x2A, 0x00] + le32(starts[0])
        for ifd in ifds {
            out += le16(ifd.entries.count)
            for (tag, value) in ifd.entries.sorted(by: { $0.0 < $1.0 }) {
                let type: Int
                let count: Int
                var bytes: [UInt8]
                switch value {
                case .ascii(let text): bytes = Array(text.utf8) + [0]; type = 2; count = bytes.count
                case .short(let number): bytes = le16(number); type = 3; count = 1
                case .long(let number): bytes = le32(number); type = 4; count = 1
                case .undefined(let raw): bytes = raw; type = 7; count = raw.count
                case .rationals(let pairs): bytes = pairs.flatMap { le32($0.0) + le32($0.1) }; type = 5; count = pairs.count
                case .pointer(let index): bytes = le32(starts[index]); type = 4; count = 1
                case .data(let raw):
                    bytes = le32(dataStart + data.count); type = 4; count = 1
                    data += raw + (raw.count % 2 == 1 ? [0] : [])
                }
                out += le16(Int(tag)) + le16(type) + le32(count)
                if bytes.count <= 4 {
                    out += bytes + [UInt8](repeating: 0, count: 4 - bytes.count)
                } else {
                    out += le32(dataStart + data.count)
                    data += bytes + (bytes.count % 2 == 1 ? [0] : [])
                }
            }
            out += le32(ifd.next.map { starts[$0] } ?? 0)
        }
        return out + data
    }

    private static func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)] }
    private static func le32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF)]
    }

    private static func encode(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for x in stride(from: 0, to: width, by: 40) {
            context.setFillColor(red: CGFloat(x) / CGFloat(width), green: 0.4, blue: 1 - CGFloat(x) / CGFloat(width), alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 40, height: height))
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
