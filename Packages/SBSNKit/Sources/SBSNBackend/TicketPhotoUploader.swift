import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation

/// 촬영 티켓 단위로 사진 원본을 서버에 올린다(실증 단계).
///
/// - Firestore `tickets/{ticketID}`: `photographerUid`, `createdAt`
/// - Firestore `tickets/{ticketID}/photos/{fileName}`: 파일 정보와 업로드 시각
/// - Storage `tickets/{ticketID}/originals/{fileName}`: 원본
///
/// 보안 규칙이 티켓 문서의 `photographerUid`로 업로드 권한을 확인하므로, 티켓 문서를 먼저 만든 뒤 원본을 올린다.
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

    public func upload(fileAt url: URL, capturedAt: Date?) async throws -> Upload {
        let startedAt = Date()
        let photographerUID = try await signedInUserID()
        try await createTicketIfNeeded(photographerUID: photographerUID)

        let fileName = url.lastPathComponent
        let storagePath = "tickets/\(ticketID)/originals/\(fileName)"
        let contentType = Self.contentType(for: url)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        let stored = try await Storage.storage().reference(withPath: storagePath).putFileAsync(from: url, metadata: metadata)
        let byteCount = Int(stored.size)

        var photo: [String: Any] = [
            "fileName": fileName,
            "storagePath": storagePath,
            "byteCount": byteCount,
            "contentType": contentType,
            "uploadedAt": FieldValue.serverTimestamp(),
        ]
        if let capturedAt {
            photo["capturedAt"] = Timestamp(date: capturedAt)
        }
        try await ticketDocument.collection("photos").document(fileName).setData(photo)

        return Upload(storagePath: storagePath, byteCount: byteCount, duration: Date().timeIntervalSince(startedAt))
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
