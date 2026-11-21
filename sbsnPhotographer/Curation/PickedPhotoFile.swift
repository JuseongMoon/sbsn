import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// 사진 선택기가 넘긴 파일을 받자마자 앱 임시 폴더로 복사한다(넘겨받은 파일은 곧 지워진다).
///
/// 선택기는 `.current`(변환 없이 현재 표현)로 연다. 시뮬레이터에서 원본과 바이트까지 같았다(2026-11-21, 설계 문서 4.3절).
/// 형식은 JPEG → HEIC → HEIF 순으로 요청해 RAW+JPEG 묶음이면 JPEG가 온다. 그 밖의 형식(RAW 단독 등)은 받은 뒤 검사에서 막는다.
nonisolated struct PickedPhotoFile: Transferable {
    let url: URL
    /// 선택기가 알려 준 원래 파일 이름(확장자는 `.jpeg`로 바뀔 수 있다)
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .jpeg) { try PickedPhotoFile(copying: $0.file) }
        FileRepresentation(importedContentType: .heic) { try PickedPhotoFile(copying: $0.file) }
        FileRepresentation(importedContentType: .heif) { try PickedPhotoFile(copying: $0.file) }
        FileRepresentation(importedContentType: .image) { try PickedPhotoFile(copying: $0.file) }
    }

    init(copying source: URL) throws {
        url = try Self.copyToInbox(source)
        fileName = source.lastPathComponent
    }

    /// 파일 앱(`fileImporter`)에서 고른 파일. 보안 범위 접근 안에서 복사한다.
    static func fromFileImporter(_ source: URL) throws -> PickedPhotoFile {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        return try PickedPhotoFile(copying: source)
    }

    private static func copyToInbox(_ source: URL) throws -> URL {
        let directory = URL.cachesDirectory.appending(path: "PickedPhotos", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
