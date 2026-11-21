import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SBSNCameraTransfer

/// 위치가 지워진 사진 판별(I008). 사례는 Android `PhotoLocationTests`와 같다(Galaxy·에뮬레이터 사진 선택 창 실측 모양).
/// HEIC는 맥 ImageIO로 만든 실제 파일의 Exif 아이템을 읽고, 값을 0으로 지운 파일도 본다. 좌표는 모두 가짜다.
struct PhotoLocationTests {
    /// 서울 근처 가짜 좌표(37°34'46.56" N, 126°58'14.52" E)
    static let latitude: [UInt32] = [37, 1, 34, 1, 4656, 100]
    static let longitude: [UInt32] = [126, 1, 58, 1, 1452, 100]

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "PhotoLocationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func realCoordinatesArePresent() {
        #expect(PhotoLocation.of(exifPayload: Self.exif(gps: GPS())) == .present)
        #expect(PhotoLocation.of(exifPayload: Self.exif(gps: GPS(), littleEndian: false)) == .present)
    }

    /// 사진 선택 창이 위치 공유를 허락받지 않았을 때(Android 실측): 태그는 남고 Ref와 유리수 값이 모두 0(0/0)
    @Test func zeroedValuesAreRemoved() {
        let zeroed = GPS(latitudeRef: 0, longitudeRef: 0, latitude: Array(repeating: 0, count: 6), longitude: Array(repeating: 0, count: 6))
        #expect(PhotoLocation.of(exifPayload: Self.exif(gps: zeroed)) == .removed)
        #expect(PhotoLocation.of(exifPayload: Self.exif(gps: zeroed, littleEndian: false)) == .removed)
    }

    @Test func noGPSIsAbsent() {
        #expect(PhotoLocation.of(exifPayload: Self.exif(gps: nil)) == .absent)
        // GPS IFD는 있지만 위도·경도 항목이 없다(카메라가 위치를 못 잡았을 때 버전만 쓰는 경우)
        #expect(PhotoLocation.of(exifPayload: Self.exif(gps: GPS(coordinates: false))) == .absent)
        #expect(PhotoLocation.of(exifPayload: nil) == .absent)
        #expect(PhotoLocation.of(exifPayload: Array("Exif\u{0}\u{0}XX".utf8)) == .absent)
    }

    /// Exif 앞에 COM이 있어 지우는 자리가 밀린 경우(Android 실측): 위도 항목의 형식 칸이 0이 되고, 경도는 도만 0/0이고 분·초는 남는다.
    /// JPEG 파일에서 Exif를 꺼내는 길까지 함께 본다.
    @Test func shiftedRedactionWithCommentFirstIsRemoved() throws {
        let broken = GPS(latitudeType: 0, latitude: Array(repeating: 0, count: 6), longitude: [0, 0, 58, 1, 1452, 100])
        let payload = Self.exif(gps: broken)
        let jpeg = try writeJPEG([(0xFE, Array("sbsn test comment".utf8)), (0xE1, payload),
                                  (0xE1, JPEGMetadataTransplant.xmpHeader + Array("<x/>".utf8))])
        let extracted = PhotoLocation.exifPayload(ofJPEG: jpeg)
        #expect(extracted == payload)
        #expect(PhotoLocation.of(exifPayload: extracted) == .removed)
        // 경도만 도가 0/0이어도 지워진 것이다
        #expect(PhotoLocation.of(exifPayload: Self.exif(gps: GPS(longitude: [0, 0, 58, 1, 1452, 100]))) == .removed)
    }

    @Test func jpegWithoutExifHasNoPayload() throws {
        #expect(PhotoLocation.exifPayload(ofJPEG: try writeJPEG([(0xFE, Array("comment".utf8))])) == nil)
        let text = directory.appending(path: "not-jpeg.jpg")
        try Data("not a jpeg".utf8).write(to: text)
        #expect(PhotoLocation.exifPayload(ofJPEG: text) == nil)
        #expect(PhotoLocation.exifPayload(ofHEIF: text) == nil)
    }

    /// 입력 검사가 형식에 맞춰 판별 결과를 담는다(JPEG).
    @Test func inspectionCarriesJPEGLocation() throws {
        let present = try writeImage(type: .jpeg, gps: true)
        let none = try writeImage(type: .jpeg, gps: false)
        #expect(PhotoInspection.of(present)?.location == .present)
        #expect(PhotoInspection.of(none)?.location == .absent)

        let removed = try zeroingCoordinates(of: present, payload: try #require(PhotoLocation.exifPayload(ofJPEG: present)))
        #expect(PhotoInspection.of(removed)?.location == .removed)
    }

    /// HEIC: ImageIO가 만든 실제 파일에서 Exif 아이템을 찾는다. 값을 0으로 지우면 지워짐으로 본다.
    @Test func heicExifItemIsRead() throws {
        let present = try writeImage(type: .heic, gps: true)
        let none = try writeImage(type: .heic, gps: false)
        let payload = try #require(PhotoLocation.exifPayload(ofHEIF: present))
        #expect(payload.starts(with: JPEGMetadataTransplant.exifHeader))
        #expect(PhotoLocation.of(exifPayload: payload) == .present)
        #expect(PhotoInspection.of(present)?.location == .present)
        #expect(PhotoInspection.of(none)?.location == .absent)

        let removed = try zeroingCoordinates(of: present, payload: payload)
        #expect(PhotoInspection.of(removed)?.format == .heif)
        #expect(PhotoInspection.of(removed)?.location == .removed)
    }

    // MARK: - 시험 파일

    struct GPS {
        var coordinates = true
        var latitudeRef: UInt8 = UInt8(ascii: "N")
        var longitudeRef: UInt8 = UInt8(ascii: "E")
        var latitudeType: UInt16 = 5
        var latitude: [UInt32]?
        var longitude: [UInt32]?
    }

    /// IFD0(GPS 포인터 하나) → GPS IFD(Ref·위도·Ref·경도) → 값 영역. Android 시험의 `exif()`와 같은 배치다.
    static func exif(gps: GPS?, littleEndian: Bool = true) -> [UInt8] {
        var tiff = [UInt8](repeating: 0, count: 256)
        func put16(_ index: Int, _ value: Int) {
            let b = [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]
            tiff.replaceSubrange(index..<(index + 2), with: littleEndian ? b : b.reversed())
        }
        func put32(_ index: Int, _ value: Int) {
            let b = [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24 & 0xFF)]
            tiff.replaceSubrange(index..<(index + 4), with: littleEndian ? b : b.reversed())
        }
        let mark: UInt8 = littleEndian ? 0x49 : 0x4D
        tiff[0] = mark
        tiff[1] = mark
        put16(2, 42)
        put32(4, 8)
        let ifd0 = 8
        guard let gps else {
            // IFD0에 Orientation 하나만
            put16(ifd0, 1); put16(ifd0 + 2, 0x0112); put16(ifd0 + 4, 3); put32(ifd0 + 6, 1); put16(ifd0 + 10, 1); put32(ifd0 + 14, 0)
            return JPEGMetadataTransplant.exifHeader + tiff[0..<(ifd0 + 18)]
        }
        let gpsIFD = ifd0 + 18
        put16(ifd0, 1); put16(ifd0 + 2, 0x8825); put16(ifd0 + 4, 4); put32(ifd0 + 6, 1); put32(ifd0 + 10, gpsIFD); put32(ifd0 + 14, 0)
        let entries = gps.coordinates ? 4 : 1
        let values = gpsIFD + 2 + entries * 12 + 4
        put16(gpsIFD, entries)
        func entry(_ index: Int, tag: Int, type: Int, count: Int, fill: (Int) -> Void) {
            let position = gpsIFD + 2 + index * 12
            put16(position, tag); put16(position + 2, type); put32(position + 4, count)
            fill(position + 8)
        }
        if gps.coordinates {
            entry(0, tag: 0x0001, type: 2, count: 2) { tiff[$0] = gps.latitudeRef }
            entry(1, tag: 0x0002, type: Int(gps.latitudeType), count: 3) { put32($0, values) }
            entry(2, tag: 0x0003, type: 2, count: 2) { tiff[$0] = gps.longitudeRef }
            entry(3, tag: 0x0004, type: 5, count: 3) { put32($0, values + 24) }
            for (i, v) in (gps.latitude ?? latitude).enumerated() { put32(values + i * 4, Int(v)) }
            for (i, v) in (gps.longitude ?? longitude).enumerated() { put32(values + 24 + i * 4, Int(v)) }
        } else {
            entry(0, tag: 0x0000, type: 1, count: 4) { tiff[$0] = 2; tiff[$0 + 1] = 3 }
        }
        put32(gpsIFD + 2 + entries * 12, 0)
        return JPEGMetadataTransplant.exifHeader + tiff[0..<(values + 48)]
    }

    /// SOI + 세그먼트 + 이미지 데이터 자리(SOS·EOI). 판별은 SOS 앞에서 멈추므로 이미지 데이터는 없어도 된다.
    private func writeJPEG(_ segments: [(UInt8, [UInt8])]) throws -> URL {
        var bytes: [UInt8] = [0xFF, 0xD8]
        for (marker, payload) in segments {
            let length = payload.count + 2
            bytes += [0xFF, marker, UInt8(length >> 8), UInt8(length & 0xFF)] + payload
        }
        bytes += [0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9]
        let url = directory.appending(path: "segments-\(UUID().uuidString).jpg")
        try Data(bytes).write(to: url)
        return url
    }

    /// ImageIO로 만든 작은 사진(가짜 좌표 선택).
    private func writeImage(type: UTType, gps: Bool) throws -> URL {
        let context = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let image = try #require(context.makeImage())
        let url = directory.appending(path: "image-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        var properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:22 10:00:00"],
        ]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 126.9707, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// 파일 안의 Exif에서 위도·경도 유리수 값을 0으로 지운 사본(사진 선택 창이 값만 지우는 모양).
    private func zeroingCoordinates(of url: URL, payload: [UInt8]) throws -> URL {
        let header = JPEGMetadataTransplant.exifHeader
        let tiff = try JPEGMetadataTransplant.TIFFBlock(payload: payload, base: header.count)
        let pointer = try #require(try tiff.ifd(at: tiff.firstIFDOffset).entries[PhotoLocation.gpsIFDTag])
        let gps = try tiff.ifd(at: tiff.uint32(at: pointer.valueOffset))
        var bytes = [UInt8](try Data(contentsOf: url))
        // 파일에서 TIFF 블록이 시작하는 곳(HEIC는 Exif 아이템 안, JPEG는 APP1 안)
        let body = Array(payload[header.count...])
        let start = try #require(Data(bytes).range(of: Data(body))?.lowerBound)
        for tag in [PhotoLocation.latitudeTag, PhotoLocation.longitudeTag] {
            let entry = try #require(gps.entries[tag])
            let at = start + entry.valueOffset - header.count
            bytes.replaceSubrange(at..<(at + 24), with: [UInt8](repeating: 0, count: 24))
        }
        let copy = directory.appending(path: "zeroed-\(UUID().uuidString).\(url.pathExtension)")
        try Data(bytes).write(to: copy)
        return copy
    }
}
