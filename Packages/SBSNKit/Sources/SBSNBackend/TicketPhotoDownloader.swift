import FirebaseStorage
import Foundation

/// 고객 앱이 티켓 사진 파일을 내려받는다.
///
/// - 미리보기(`previews/<파일명>.jpg`): 메모리·디스크 캐시에만 두고 사진 앱에는 저장하지 않는다(워터마크 저화질).
/// - 고화질본(`fullres/<파일명>.jpg`): 구매한 사진만 읽힌다(보안 규칙). 고객 최종본(JPEG)이라 받은 파일을 그대로 사진 앱에 넣는다.
/// 캐시는 `Caches/Tickets/<티켓 ID>/` 아래라 저장 공간이 부족하면 시스템이 지울 수 있다.
public actor TicketPhotoDownloader {
    public static let previewMaxBytes: Int64 = 1024 * 1024
    public static let fullResolutionMaxBytes: Int64 = 50 * 1024 * 1024

    public let ticketID: String
    private let directory: URL
    private var previews: [String: Data] = [:]
    private var previewTasks: [String: Task<Data, Error>] = [:]

    public init(ticketID: String) {
        self.ticketID = ticketID
        directory = URL.cachesDirectory
            .appending(path: "Tickets", directoryHint: .isDirectory)
            .appending(path: ticketID, directoryHint: .isDirectory)
    }

    /// 미리보기 JPEG. 같은 파일을 동시에 여러 번 요청해도 한 번만 받는다.
    public func preview(fileName: String) async throws -> Data {
        if let data = previews[fileName] {
            return data
        }
        if let task = previewTasks[fileName] {
            return try await task.value
        }
        let fileURL = directory.appending(path: "previews", directoryHint: .isDirectory).appending(path: fileName + ".jpg")
        let storagePath = "tickets/\(ticketID)/previews/\(fileName).jpg"
        let task = Task {
            if let cached = try? Data(contentsOf: fileURL) {
                return cached
            }
            let data = try await Storage.storage().reference(withPath: storagePath).data(maxSize: Self.previewMaxBytes)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
            return data
        }
        previewTasks[fileName] = task
        defer { previewTasks[fileName] = nil }
        let data = try await task.value
        previews[fileName] = data
        return data
    }

    /// 고화질본 JPEG를 파일로 받는다. 사진 앱은 확장자로 형식을 알아보므로 `.jpg`로 저장한다.
    public func downloadFullResolution(fileName: String) async throws -> URL {
        let fileURL = directory.appending(path: "fullres", directoryHint: .isDirectory).appending(path: fileName + ".jpg")
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            return fileURL
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let reference = Storage.storage().reference(withPath: TicketPhotoUploader.fullResolutionPath(ticketID: ticketID, originalFileName: fileName))
        return try await reference.writeAsync(toFile: fileURL)
    }

    /// 고화질본 객체가 서버에 있는지. 작가 앱이 업로드는 끝냈는데 문서를 쓰기 전에 멈춘 경우를 잡는다(구매한 사진만 읽힌다).
    public func fullResolutionExists(fileName: String) async -> Bool {
        let reference = Storage.storage().reference(withPath: TicketPhotoUploader.fullResolutionPath(ticketID: ticketID, originalFileName: fileName))
        return (try? await reference.getMetadata()) != nil
    }
}
