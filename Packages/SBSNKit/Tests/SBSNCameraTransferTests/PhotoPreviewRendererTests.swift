import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SBSNCameraTransfer

struct PhotoPreviewRendererTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "PhotoPreviewRendererTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @Test func shrinksToMaxPixelSizeAndAppliesOrientation() throws {
        // 가로 4000x3000 원본에 "시계 방향 90도 회전"(EXIF 6)이 붙은 사진은 세로 사진으로 보여야 한다.
        let source = try makeJPEG(width: 4000, height: 3000, properties: [kCGImagePropertyOrientation: 6])
        let preview = directory.appending(path: "preview.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)

        let size = try pixelSize(of: preview)
        #expect(size.width == 768)
        #expect(size.height == 1024)
        #expect(try fileSize(preview) < fileSize(source))
    }

    @Test func dropsLocationAndCameraMetadata() throws {
        let source = try makeJPEG(width: 3000, height: 2000, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLongitude: 126.977],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "ILCE-7CM2"],
        ])
        let preview = directory.appending(path: "preview.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)

        let imageSource = try #require(CGImageSourceCreateWithURL(preview as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFModel] == nil)
    }

    @Test func keepsSmallImagesAtOriginalSize() throws {
        let source = try makeJPEG(width: 800, height: 600, properties: [:])
        let preview = directory.appending(path: "preview.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: preview)

        let size = try pixelSize(of: preview)
        #expect(size.width == 800)
        #expect(size.height == 600)
    }

    @Test func burnsWatermarkIntoPreviewPixels() throws {
        let source = try makeJPEG(width: 2000, height: 1500, properties: [:])
        let plain = directory.appending(path: "plain.jpg")
        let marked = directory.appending(path: "marked.jpg")

        try PhotoPreviewRenderer.renderJPEG(from: source, to: plain, quality: 1, watermark: nil)
        try PhotoPreviewRenderer.renderJPEG(from: source, to: marked, quality: 1)

        // 워터마크 글자가 사진 전체에 반복되므로, 바뀐 픽셀이 한쪽에 몰리지 않고 넓게 퍼져 있어야 한다.
        let difference = try changedPixelShare(between: plain, and: marked)
        #expect(difference.total > 0.05)
        #expect(difference.leftHalf > 0.02)
        #expect(difference.rightHalf > 0.02)
    }

    @Test func fullResolutionJPEGBakesRotationAndKeepsAllMetadata() throws {
        // 세로로 찍은 사진(EXIF 6)은 회전을 픽셀에 반영해 어느 뷰어에서나 세로로 보이게 한다. 메타데이터는 전부 남는다(D037).
        let source = try makeJPEG(width: 3000, height: 2000, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLongitude: 126.977],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:22 14:00:00",
                kCGImagePropertyExifBodySerialNumber: "5012345",
                kCGImagePropertyExifCameraOwnerName: "Photographer",
            ],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "ILCE-7CM2", kCGImagePropertyTIFFArtist: "작가 실명"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCByline: ["작가 실명"]],
        ])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 2000 && info.height == 3000)
        #expect(info.exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:22 14:00:00")
        #expect(info.tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7CM2")
        #expect(info.tiff[kCGImagePropertyTIFFArtist] as? String == "작가 실명")
        #expect(info.properties[kCGImagePropertyGPSDictionary] != nil)
        #expect(info.properties[kCGImagePropertyIPTCDictionary] != nil)
        #expect(info.exif[kCGImagePropertyExifBodySerialNumber] as? String == "5012345")
        #expect(info.exif[kCGImagePropertyExifCameraOwnerName] as? String == "Photographer")
        #expect(info.exif[kCGImagePropertyExifPixelXDimension] as? Int == 2000)
        #expect(info.exif[kCGImagePropertyExifPixelYDimension] as? Int == 3000)
    }

    /// 가장 흔한 입력(가로 sRGB JPEG)은 그리지 않고 다시 인코딩만 하는 경로를 탄다. 이 경로에서도 메타데이터는 전부 남는다.
    @Test func plainSRGBJPEGKeepsOriginalResolutionAndAllMetadata() throws {
        let source = try makeJPEG(width: 3000, height: 2000, properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLongitude: 126.977],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:10:22 14:00:00",
                kCGImagePropertyExifBodySerialNumber: "5012345",
                kCGImagePropertyExifLensSerialNumber: "0001234",
            ],
        ])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 3000 && info.height == 2000)
        #expect(info.exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2026:10:22 14:00:00")
        #expect(info.properties[kCGImagePropertyGPSDictionary] != nil)
        #expect(info.exif[kCGImagePropertyExifBodySerialNumber] as? String == "5012345")
        #expect(info.exif[kCGImagePropertyExifLensSerialNumber] as? String == "0001234")
    }

    /// 카메라를 Adobe RGB로 두면 색 관리 안 하는 뷰어(메신저 등)에서 색이 바래 보이므로 sRGB 픽셀로 바꾼다.
    @Test func adobeRGBIsConvertedToSRGB() throws {
        let source = try makeJPEG(width: 1200, height: 800, properties: [:], colorSpace: CGColorSpace(name: CGColorSpace.adobeRGB1998)!)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        #expect(try deliverable(output).width == 1200)
    }

    /// 10비트 HEIF(Display P3)로 찍는 카메라도 8비트 sRGB JPEG로 넘긴다.
    @Test func tenBitHEIFIsConvertedToEightBitJPEG() throws {
        let source = try makeImage(width: 1600, height: 1200, type: .heic, bitsPerComponent: 16,
                                   colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 1600 && info.height == 1200)
    }

    /// 입력 검사: 형식과 회전을 반영한 크기, 촬영 시각을 디코드 없이 읽는다(D040 ③).
    @Test func inspectionReadsFormatOrientedSizeAndCaptureTime() throws {
        let portrait = try makeJPEG(width: 6000, height: 4000, properties: [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:11:21 14:05:00",
                kCGImagePropertyExifOffsetTimeOriginal: "+09:00",
            ],
        ])
        let heic = try makeImage(width: 640, height: 480, type: .heic, bitsPerComponent: 16,
                                 colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!)
        let png = try makeImage(width: 640, height: 480, type: .png, bitsPerComponent: 8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let text = directory.appending(path: "not-image.jpg")
        try Data("not an image".utf8).write(to: text)

        let info = try #require(PhotoInspection.of(portrait))
        #expect(info.format == .jpeg)
        #expect(info.width == 4000 && info.height == 6000 && info.longSide == 6000)
        #expect(info.capturedAt == ISO8601DateFormatter().date(from: "2026-11-21T14:05:00+09:00"))
        #expect(PhotoInspection.of(heic)?.format == .heif)
        #expect(PhotoInspection.of(png)?.format == .other(UTType.png.identifier))
        #expect(PhotoInspection.of(text) == nil)
        #expect(PhotoInspection.format(of: UTType.rawImage.identifier) == .raw)
        #expect(PhotoInspection.format(of: "com.sony.arw-raw-image") == .raw)
    }

    @Test func capsLongSideWhenAsked() throws {
        let source = try makeJPEG(width: 4000, height: 3000, properties: [:])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output, maxPixelSize: 2000)

        let info = try deliverable(output)
        #expect(info.width == 2000 && info.height == 1500)
    }

    /// 6,000만 화소를 "넘는" 원본만 줄인다(안드로이드 `automaticMaxPixelSize`와 같은 경계).
    @Test func automaticCapAppliesOnlyAboveSixtyMegapixels() {
        #expect(PhotoPreviewRenderer.automaticMaxPixelSize(width: 10000, height: 6000) == nil)
        #expect(PhotoPreviewRenderer.automaticMaxPixelSize(width: 10000, height: 6001) == 8192)
        #expect(PhotoPreviewRenderer.automaticMaxPixelSize(width: 7008, height: 4672) == nil)
        #expect(PhotoPreviewRenderer.automaticMaxPixelSize(width: 11648, height: 8736) == 8192)
    }

    /// 안드로이드 비교 입력과 같은 크기(약 69.9MP). 긴 변 8192, 짧은 변은 5460.8을 반올림한 5461이어야 한다.
    @Test func capsSourcesAboveSixtyMegapixelsToLongSide8192() throws {
        let source = try makeJPEG(width: 10240, height: 6826, properties: [:])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 8192 && info.height == 5461)
        #expect(info.exif[kCGImagePropertyExifPixelXDimension] as? Int == 8192)
        #expect(info.exif[kCGImagePropertyExifPixelYDimension] as? Int == 5461)
    }

    /// 원본 메타데이터 세그먼트(Exif·XMP·확장 XMP·APP13·COM)가 바이트 그대로 옮겨진다. MakerNote도 같다(D037).
    /// 원본의 다른 APP 세그먼트와 EOI 뒤 트레일러는 옮기지 않는다.
    @Test func fullResolutionKeepsEveryMetadataSegmentByteForByte() throws {
        let forged = try ForgedCameraJPEG(directory: directory, width: 1200, height: 800, orientation: 1)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: forged.url, to: output)

        let info = try deliverable(output)
        #expect(info.width == 1200 && info.height == 800)
        let segments = try JPEGMetadataTransplant.split([UInt8](try Data(contentsOf: output))).segments
        let exif = try #require(segments.first { $0.marker == 0xE1 && $0.payload.starts(with: JPEGMetadataTransplant.exifHeader) })
        #expect(exif.payload == forged.exifPayload, "가로·원본 크기면 Exif 블록이 한 바이트도 바뀌지 않는다")
        #expect(try ForgedCameraJPEG.makerNote(in: exif.payload) == ForgedCameraJPEG.makerNote)
        let xmp = try #require(segments.first { $0.marker == 0xE1 && $0.payload.starts(with: JPEGMetadataTransplant.xmpHeader) })
        let xmpText = String(decoding: xmp.payload, as: UTF8.self)
        #expect(xmpText.contains("crs:Exposure2012=\"+0.50\"") && xmpText.contains("sbsnTest:Note=\"custom\""))
        #expect(segments.contains { $0.marker == 0xE1 && $0.payload == forged.extendedXMPPayload })
        #expect(segments.contains { $0.marker == 0xED && $0.payload == forged.iptcPayload })
        #expect(segments.contains { $0.marker == 0xFE && $0.payload == forged.commentPayload })
        #expect(!segments.contains { $0.marker == 0xE3 }, "알 수 없는 APP 세그먼트는 옮기지 않는다")
        let bytes = try Data(contentsOf: output)
        #expect(bytes.suffix(2) == Data([0xFF, 0xD9]), "EOI 뒤 트레일러는 옮기지 않는다")
        #expect(info.properties[kCGImagePropertyGPSDictionary] != nil)
        #expect(info.exif[kCGImagePropertyExifBodySerialNumber] as? String == "5123456")
        #expect(info.exif[kCGImagePropertyExifLensSerialNumber] as? String == "0012345")
        #expect(info.exif[kCGImagePropertyExifCameraOwnerName] as? String == "Owner Name")
        #expect(info.tiff[kCGImagePropertyTIFFArtist] as? String == "Test Photographer")
    }

    /// 세로 원본: 회전을 픽셀에 반영하고 Exif·XMP의 회전·크기만 고친다. 원본 방향 썸네일(IFD1)은 연결을 끊는다.
    /// 출력에 없는 데이터를 가리키는 XMP 항목(hdrgm·MotionPhoto·Container)은 지운다. MakerNote는 그대로다.
    @Test func rotatedSourceFixesOnlyOrientationAndSize() throws {
        let forged = try ForgedCameraJPEG(directory: directory, width: 1200, height: 800, orientation: 6)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: forged.url, to: output)

        let info = try deliverable(output)
        #expect(info.width == 800 && info.height == 1200)
        #expect(info.exif[kCGImagePropertyExifPixelXDimension] as? Int == 800)
        #expect(info.exif[kCGImagePropertyExifPixelYDimension] as? Int == 1200)
        let segments = try JPEGMetadataTransplant.split([UInt8](try Data(contentsOf: output))).segments
        let exif = try #require(segments.first { $0.marker == 0xE1 && $0.payload.starts(with: JPEGMetadataTransplant.exifHeader) })
        #expect(exif.payload.count == forged.exifPayload.count, "TIFF 블록 길이는 그대로다")
        #expect(try ForgedCameraJPEG.makerNote(in: exif.payload) == ForgedCameraJPEG.makerNote)
        let tiff = try JPEGMetadataTransplant.TIFFBlock(payload: exif.payload, base: JPEGMetadataTransplant.exifHeader.count)
        let ifd0 = try tiff.ifd(at: tiff.firstIFDOffset)
        #expect(try tiff.uint32(at: ifd0.nextIFDPointer) == 0, "썸네일 IFD1 연결이 끊긴다")
        let xmp = try #require(segments.first { $0.marker == 0xE1 && $0.payload.starts(with: JPEGMetadataTransplant.xmpHeader) })
        let xmpText = String(decoding: xmp.payload, as: UTF8.self)
        #expect(xmpText.contains("tiff:Orientation=\"1\""))
        #expect(xmpText.contains("exif:PixelXDimension=\"800\"") && xmpText.contains("exif:PixelYDimension=\"1200\""))
        #expect(!xmpText.contains("hdrgm:Version") && !xmpText.contains("GCamera:MotionPhoto") && !xmpText.contains("<Container:Directory"))
        #expect(xmpText.contains("crs:Exposure2012"), "다른 XMP 항목은 그대로다")
    }

    /// Adobe RGB 원본: 픽셀은 sRGB로 바꾸고, 색 공간 표시(Exif ColorSpace, Interop R03, XMP ICCProfile)도 출력에 맞춘다.
    @Test func adobeRGBMarkersFollowSRGBOutput() throws {
        let forged = try ForgedCameraJPEG(directory: directory, width: 1200, height: 800, orientation: 1, adobeRGB: true)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: forged.url, to: output)

        let info = try deliverable(output)
        #expect(info.exif[kCGImagePropertyExifColorSpace] as? Int == 1)
        let segments = try JPEGMetadataTransplant.split([UInt8](try Data(contentsOf: output))).segments
        let exif = try #require(segments.first { $0.marker == 0xE1 && $0.payload.starts(with: JPEGMetadataTransplant.exifHeader) })
        #expect(exif.payload.count == forged.exifPayload.count)
        #expect(String(decoding: exif.payload, as: UTF8.self).contains("R98"))
        #expect(!String(decoding: exif.payload, as: UTF8.self).contains("R03"))
        let xmp = try #require(segments.first { $0.marker == 0xE1 && $0.payload.starts(with: JPEGMetadataTransplant.xmpHeader) })
        #expect(String(decoding: xmp.payload, as: UTF8.self).contains("photoshop:ICCProfile=\"sRGB IEC61966-2.1\""))
    }

    /// 카메라 XMP 끝의 공백 채움(a7C II는 약 54KB)에서 지울 항목 찾기가 느려지지 않는다(되짚기 폭증 회귀 방지).
    @Test func xmpPatchStaysFastWithLargeWhitespacePadding() {
        let xmp = #"<x:xmpmeta><rdf:RDF><rdf:Description tiff:Orientation="6" hdrgm:Version="1.0"/></rdf:RDF></x:xmpmeta>"#
            + String(repeating: " ", count: 60_000) + "<?xpacket end=\"w\"?>"
        let payload = JPEGMetadataTransplant.xmpHeader + Array(xmp.utf8)
        let started = Date()

        let patched = JPEGMetadataTransplant.patchedXMP(payload, output: .init(width: 4672, height: 7008, dropsThumbnail: true))

        #expect(Date().timeIntervalSince(started) < 1)
        let text = String(decoding: patched, as: UTF8.self)
        #expect(text.contains("tiff:Orientation=\"1\"") && !text.contains("hdrgm:Version"))
    }

    /// 원본에 없는 태그는 새로 넣지 않는다(공통 명세): 크기·색 공간 칸이 없는 원본은 출력에도 없다.
    @Test func absentTagsAreNotAdded() throws {
        let forged = try ForgedCameraJPEG(directory: directory, width: 1200, height: 800, orientation: 6, includesSizeAndColorSpace: false)
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: forged.url, to: output)

        let segments = try JPEGMetadataTransplant.split([UInt8](try Data(contentsOf: output))).segments
        let exif = try #require(segments.first { $0.marker == 0xE1 && $0.payload.starts(with: JPEGMetadataTransplant.exifHeader) })
        let tiff = try JPEGMetadataTransplant.TIFFBlock(payload: exif.payload, base: JPEGMetadataTransplant.exifHeader.count)
        let ifd0 = try tiff.ifd(at: tiff.firstIFDOffset)
        let exifIFD = try tiff.ifd(at: tiff.uint32(at: try #require(ifd0.entries[0x8769]).valueOffset))
        #expect(exifIFD.entries[0xA002] == nil && exifIFD.entries[0xA003] == nil && exifIFD.entries[0xA001] == nil)
        #expect(try tiff.uint16(at: try #require(ifd0.entries[0x0112]).valueOffset) == 1)
    }

    /// HEIF 원본은 ImageIO 메타데이터 트리로 옮긴다. 위치·일련번호·기종은 남고 회전은 1이 된다(MakerNote는 빠질 수 있다).
    @Test func heifSourceKeepsMetadataThroughMetadataTree() throws {
        let source = try makeImage(width: 1600, height: 1200, type: .heic, bitsPerComponent: 8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   properties: [
                                       kCGImagePropertyOrientation: 6,
                                       kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5796, kCGImagePropertyGPSLongitude: 126.977],
                                       kCGImagePropertyExifDictionary: [kCGImagePropertyExifBodySerialNumber: "5012345"],
                                       kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "ILCE-7CM2"],
                                   ])
        let output = directory.appending(path: "full.jpg")

        try PhotoPreviewRenderer.renderFullResolutionJPEG(from: source, to: output)

        let info = try deliverable(output)
        #expect(info.width == 1200 && info.height == 1600)
        #expect(info.properties[kCGImagePropertyGPSDictionary] != nil)
        #expect(info.exif[kCGImagePropertyExifBodySerialNumber] as? String == "5012345")
        #expect(info.tiff[kCGImagePropertyTIFFModel] as? String == "ILCE-7CM2")
    }

    @Test func rejectsFilesThatAreNotImages() throws {
        let source = directory.appending(path: "not-image.jpg")
        try Data("not an image".utf8).write(to: source)

        #expect(throws: PhotoPreviewRenderer.RenderError.self) {
            try PhotoPreviewRenderer.renderJPEG(from: source, to: directory.appending(path: "preview.jpg"))
        }
    }

    private func makeJPEG(width: Int, height: Int, properties: [CFString: Any],
                          colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws -> URL {
        try makeImage(width: width, height: height, type: .jpeg, bitsPerComponent: 8, colorSpace: colorSpace, properties: properties)
    }

    private func makeImage(width: Int, height: Int, type: UTType, bitsPerComponent: Int, colorSpace: CGColorSpace,
                           properties: [CFString: Any] = [:]) throws -> URL {
        let bitmapInfo = bitsPerComponent == 16
            ? CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ))
        // 압축이 되도록 단색이 아닌 그라데이션을 그린다.
        for x in stride(from: 0, to: width, by: 50) {
            context.setFillColor(red: CGFloat(x) / CGFloat(width), green: 0.5, blue: 1 - CGFloat(x) / CGFloat(width), alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 50, height: height))
        }
        let url = directory.appending(path: "source-\(UUID().uuidString).\(type.preferredFilenameExtension ?? "img")")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// 고객 최종본이 지켜야 할 모양(JPEG, 회전 정보 1, 8비트, sRGB)을 확인하고 크기와 메타데이터를 돌려준다.
    private func deliverable(_ url: URL) throws -> (width: Int, height: Int, properties: [CFString: Any],
                                                    exif: [CFString: Any], tiff: [CFString: Any]) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyOrientation] as? Int ?? 1 == 1)
        #expect(properties[kCGImagePropertyDepth] as? Int == 8)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.colorSpace?.name == CGColorSpace.sRGB, "색 공간: \(String(describing: image.colorSpace?.name))")
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int), try #require(properties[kCGImagePropertyPixelHeight] as? Int),
                properties, properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:],
                properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:])
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        #expect(orientation == 1, "미리보기에는 회전 정보가 픽셀에 반영돼 있어야 한다")
        return (try #require(properties[kCGImagePropertyPixelWidth] as? Int), try #require(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    /// 두 사진에서 눈에 띄게(채널 차이 24 이상) 바뀐 픽셀의 비율. 전체, 왼쪽 절반, 오른쪽 절반.
    private func changedPixelShare(between a: URL, and b: URL) throws -> (total: Double, leftHalf: Double, rightHalf: Double) {
        let first = try rgba(a)
        let second = try rgba(b)
        #expect(first.width == second.width && first.height == second.height)
        var changed = (total: 0, left: 0, right: 0)
        for y in 0..<first.height {
            for x in 0..<first.width {
                let i = (y * first.width + x) * 4
                let isChanged = (0..<3).contains { abs(Int(first.pixels[i + $0]) - Int(second.pixels[i + $0])) >= 24 }
                guard isChanged else { continue }
                changed.total += 1
                if x < first.width / 2 { changed.left += 1 } else { changed.right += 1 }
            }
        }
        let count = Double(first.width * first.height)
        return (Double(changed.total) / count, Double(changed.left) / (count / 2), Double(changed.right) / (count / 2))
    }

    private func rgba(_ url: URL) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (pixels, image.width, image.height)
    }

    private func fileSize(_ url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int)
    }
}
