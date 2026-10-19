import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

/// 촬영 티켓 단위로 사진을 서버에 올린다(실증 단계).
///
/// - Firestore `tickets/{ticketID}`: `photographerUid`, `createdAt`
/// - Firestore `tickets/{ticketID}/photos/{원본 파일명}`: 미리보기·원본 경로와 업로드 시각
/// - Storage `tickets/{ticketID}/previews/{원본 파일명}.jpg`: 고객에게 먼저 보여 줄 미리보기
/// - Storage `tickets/{ticketID}/originals/{원본 파일명}`: 원본
///
/// 보안 규칙이 티켓 문서의 `photographerUid`로 업로드 권한을 확인하므로, 티켓 문서를 먼저 만든 뒤 파일을 올린다.
/// 미리보기와 원본을 언제 올릴지(미리보기 먼저, 원본은 한 장씩)는 호출하는 쪽이 정한다.
public actor TicketPhotoUploader {
    public struct Upload: Sendable {
        public let storagePath: String
        public let byteCount: Int
        public let duration: TimeInterval
    }

    public let ticketID: String
    // 여러 사진이 동시에 올라올 때 익명 로그인과 티켓 생성이 한 번만 일어나도록, 진행 중인 작업을 함께 기다린다.
    // (실기기에서 동시 업로드가 익명 사용자를 둘 만들어 티켓 소유자와 업로더가 달라지는 문제가 있었다.)
    private var signInTask: Task<String, Error>?
    private var ticketTask: Task<Void, Error>?

    public init(ticketID: String) {
        self.ticketID = ticketID
    }

    /// 미리보기 JPEG를 올리고 사진 문서를 만든다. `originalFileName`이 사진 문서 ID가 된다.
    public func uploadPreview(fileAt url: URL, originalFileName: String, capturedAt: Date?) async throws -> Upload {
        let startedAt = Date()
        let storagePath = "tickets/\(ticketID)/previews/\(originalFileName).jpg"
        let byteCount = try await put(url, at: storagePath, contentType: "image/jpeg")

        var photo: [String: Any] = [
            "fileName": originalFileName,
            "previewPath": storagePath,
            "previewByteCount": byteCount,
            "previewUploadedAt": FieldValue.serverTimestamp(),
        ]
        if let capturedAt {
            photo["capturedAt"] = Timestamp(date: capturedAt)
        }
        try await photoDocument(originalFileName).setData(photo, merge: true)
        return Upload(storagePath: storagePath, byteCount: byteCount, duration: Date().timeIntervalSince(startedAt))
    }

    /// 원본을 올리고 사진 문서에 원본 정보를 더한다.
    public func uploadOriginal(fileAt url: URL) async throws -> Upload {
        let startedAt = Date()
        let fileName = url.lastPathComponent
        let storagePath = "tickets/\(ticketID)/originals/\(fileName)"
        let byteCount = try await put(url, at: storagePath, contentType: Self.contentType(for: url))

        try await photoDocument(fileName).setData([
            "fileName": fileName,
            "originalPath": storagePath,
            "originalByteCount": byteCount,
            "originalUploadedAt": FieldValue.serverTimestamp(),
        ], merge: true)
        return Upload(storagePath: storagePath, byteCount: byteCount, duration: Date().timeIntervalSince(startedAt))
    }

    private func put(_ url: URL, at storagePath: String, contentType: String) async throws -> Int {
        let photographerUID = try await signedInUserID()
        try await createTicketIfNeeded(photographerUID: photographerUID)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        let stored = try await Storage.storage().reference(withPath: storagePath).putFileAsync(from: url, metadata: metadata)
        return Int(stored.size)
    }

    private func photoDocument(_ fileName: String) -> DocumentReference {
        ticketDocument.collection("photos").document(fileName)
    }

    private var ticketDocument: DocumentReference {
        Firestore.firestore().collection("tickets").document(ticketID)
    }

    private func signedInUserID() async throws -> String {
        if let user = Auth.auth().currentUser {
            return user.uid
        }
        if let signInTask {
            return try await signInTask.value
        }
        let task = Task { try await Auth.auth().signInAnonymously().user.uid }
        signInTask = task
        do {
            return try await task.value
        } catch {
            signInTask = nil
            throw error
        }
    }

    private func createTicketIfNeeded(photographerUID: String) async throws {
        if let ticketTask {
            return try await ticketTask.value
        }
        let document = ticketDocument
        let task = Task {
            try await document.setData([
                "photographerUid": photographerUID,
                "createdAt": FieldValue.serverTimestamp(),
            ], merge: true)
        }
        ticketTask = task
        do {
            try await task.value
        } catch {
            ticketTask = nil
            throw error
        }
    }

    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "heic", "heif", "hif": "image/heif"
        case "arw": "image/x-sony-arw"
        default: "application/octet-stream"
        }
    }
}
