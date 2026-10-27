import FirebaseFirestore
import FirebaseStorage
import Foundation
import SBSNCore

/// 촬영 티켓 단위로 사진을 서버에 올린다.
///
/// - Firestore `tickets/{ticketID}`: 고객이 작가를 확정할 때 만든다(`TicketService.confirm`). 작가 앱은 만들지 않는다.
/// - Firestore `tickets/{ticketID}/photos/{원본 파일명}`: 미리보기·고화질본·원본 경로와 업로드 시각.
///   찜(`favoritedAt`)·구매(`purchasedAt`)·전달(`deliveredAt`)은 고객 앱이 쓰고 작가 앱은 읽기만 한다(보안 규칙으로 막음).
/// - Storage `tickets/{ticketID}/previews/{원본 파일명}.jpg`: 고객에게 먼저 보여 줄 저화질·워터마크 미리보기
/// - Storage `tickets/{ticketID}/fullres/{원본 파일명}.heic`: 구매하면 넘기는 원해상도 고화질본
/// - Storage `tickets/{ticketID}/originals/{원본 파일명}`: 원본(구매한 사진만)
///
/// Storage 보안 규칙은 객체 메타데이터의 `customerUid`·`photographerUid`로 읽을 사람을 정하므로 모든 업로드에 참여자를 적는다.
/// 미리보기와 원본을 언제, 몇 장씩 동시에, 어떤 전송 방식으로 올릴지는 호출하는 쪽이 정한다.
public actor TicketPhotoUploader {
    public struct Upload: Sendable {
        public let storagePath: String
        public let byteCount: Int
        /// 로그인·티켓 확인·사진 문서 기록까지 포함한 전체 시간
        public let duration: TimeInterval
        /// Storage로 파일을 보내는 데 걸린 시간만
        public let transferDuration: TimeInterval
    }

    /// 파일을 Storage로 보내는 방식. 실증 단계에서 속도를 비교하려고 호출하는 쪽이 고른다.
    public enum Transport: String, Sendable, CaseIterable {
        /// `putFile`. 실기기에서는 iOS 백그라운드 전송(백그라운드 URLSession)으로 나가 앱이 멈춰도 이어지지만,
        /// 시스템이 전송 시점과 속도를 조절할 수 있다.
        case file
        /// `putData`. 앱 안의 일반 전송으로 10MB씩 나눠 보낸다. 앱이 백그라운드에서 멈추면 전송도 멈춘다.
        case data
    }

    public let ticketID: String
    /// 이 티켓의 고객. 객체 메타데이터에 적어 고객이 미리보기와 구매한 고화질본을 읽을 수 있게 한다.
    public let customerUID: String

    public init(ticketID: String, customerUID: String) {
        self.ticketID = ticketID
        self.customerUID = customerUID
    }

    /// 미리보기 JPEG를 올리고 사진 문서를 만든다. `originalFileName`이 사진 문서 ID가 된다.
    public func uploadPreview(fileAt url: URL, originalFileName: String, capturedAt: Date?, transport: Transport) async throws -> Upload {
        let startedAt = Date()
        let storagePath = "tickets/\(ticketID)/previews/\(originalFileName).jpg"
        let (byteCount, transferDuration) = try await put(url, at: storagePath, contentType: "image/jpeg", transport: transport)

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
        return Upload(storagePath: storagePath, byteCount: byteCount, duration: Date().timeIntervalSince(startedAt),
                      transferDuration: transferDuration)
    }

    /// 고객이 사진에 남긴 요청. 문서에 값이 있으면 그 시각에 찜·구매한 것이다.
    public struct PhotoDemand: Sendable, Equatable {
        public let favoritedAt: Date?
        public let purchasedAt: Date?
    }

    /// 원해상도 고화질본(HEIC)을 올리고 사진 문서에 고화질본 정보를 더한다.
    public func uploadFullResolution(fileAt url: URL, originalFileName: String, transport: Transport) async throws -> Upload {
        let startedAt = Date()
        let storagePath = "tickets/\(ticketID)/fullres/\(originalFileName).heic"
        let (byteCount, transferDuration) = try await put(url, at: storagePath, contentType: "image/heic", transport: transport)

        try await photoDocument(originalFileName).setData([
            "fileName": originalFileName,
            "fullresPath": storagePath,
            "fullresByteCount": byteCount,
            "fullresUploadedAt": FieldValue.serverTimestamp(),
        ], merge: true)
        return Upload(storagePath: storagePath, byteCount: byteCount, duration: Date().timeIntervalSince(startedAt),
                      transferDuration: transferDuration)
    }

    /// 티켓 사진들의 찜·구매 상태를 실시간으로 받는다. 키는 원본 파일명.
    public func photoDemands() -> AsyncThrowingStream<[String: PhotoDemand], Error> {
        Self.listenToPhotoDemands(ticketID: ticketID)
    }

    /// 찜·구매 상태를 서버에서 한 번 읽는다. 앱이 백그라운드에서 잠깐 깨어났을 때처럼 실시간 리스너가 다시 붙기를 기다릴 수 없을 때 쓴다.
    public func fetchPhotoDemands() async throws -> [String: PhotoDemand] {
        let snapshot = try await ticketDocument.collection("photos").getDocuments(source: .server)
        return Self.demands(in: snapshot)
    }

    /// 사진 문서 전부를 서버에서 한 번 읽는다. 앱을 다시 켰을 때 어떤 파일이 이미 올라갔는지 복원하는 데 쓴다. 키는 원본 파일명.
    public func fetchPhotoRecords() async throws -> [String: PhotoRecord] {
        let snapshot = try await ticketDocument.collection("photos").getDocuments(source: .server)
        var records: [String: PhotoRecord] = [:]
        for document in snapshot.documents {
            records[document.documentID] = FirestoreCodec.photo(id: document.documentID, data: document.data())
        }
        return records
    }

    /// 고화질본 객체가 이미 서버에 있는지. 업로드는 끝났는데 문서를 쓰기 전에 앱이 멈춘 경우를 복원할 때 확인한다.
    public func fullResolutionExists(originalFileName: String) async -> Bool {
        let reference = Storage.storage().reference(withPath: "tickets/\(ticketID)/fullres/\(originalFileName).heic")
        return (try? await reference.getMetadata()) != nil
    }

    /// 고화질본 객체는 있는데 문서가 없을 때, 문서만 채운다.
    public func recordFullResolution(originalFileName: String, byteCount: Int) async throws {
        try await photoDocument(originalFileName).setData([
            "fileName": originalFileName,
            "fullresPath": "tickets/\(ticketID)/fullres/\(originalFileName).heic",
            "fullresByteCount": byteCount,
            "fullresUploadedAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }

    // Firestore는 리스너를 메인 스레드에서 부른다. 액터에 묶인 클로저로 만들면 Swift 6 격리 검사에 걸리므로 격리 밖에서 만든다.
    private nonisolated static func listenToPhotoDemands(ticketID: String) -> AsyncThrowingStream<[String: PhotoDemand], Error> {
        AsyncThrowingStream { continuation in
            let registration = Firestore.firestore().collection("tickets").document(ticketID).collection("photos")
                .addSnapshotListener { snapshot, error in
                    guard let snapshot else {
                        continuation.finish(throwing: error)
                        return
                    }
                    continuation.yield(Self.demands(in: snapshot))
                }
            nonisolated(unsafe) let listener = registration
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    private nonisolated static func demands(in snapshot: QuerySnapshot) -> [String: PhotoDemand] {
        var demands: [String: PhotoDemand] = [:]
        for document in snapshot.documents {
            let data = document.data()
            demands[document.documentID] = PhotoDemand(
                favoritedAt: (data["favoritedAt"] as? Timestamp)?.dateValue(),
                purchasedAt: (data["purchasedAt"] as? Timestamp)?.dateValue()
            )
        }
        return demands
    }

    /// 원본을 올리고 사진 문서에 원본 정보를 더한다.
    public func uploadOriginal(fileAt url: URL, transport: Transport) async throws -> Upload {
        let startedAt = Date()
        let fileName = url.lastPathComponent
        let storagePath = "tickets/\(ticketID)/originals/\(fileName)"
        let (byteCount, transferDuration) = try await put(url, at: storagePath, contentType: Self.contentType(for: url),
                                                          transport: transport)

        try await photoDocument(fileName).setData([
            "fileName": fileName,
            "originalPath": storagePath,
            "originalByteCount": byteCount,
            "originalUploadedAt": FieldValue.serverTimestamp(),
        ], merge: true)
        return Upload(storagePath: storagePath, byteCount: byteCount, duration: Date().timeIntervalSince(startedAt),
                      transferDuration: transferDuration)
    }

    /// 올린 바이트 수와 Storage 전송 시간을 돌려준다.
    private func put(_ url: URL, at storagePath: String, contentType: String, transport: Transport) async throws -> (Int, TimeInterval) {
        let photographerUID = try await Backend.signedInUserID()
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        // 보안 규칙이 이 메타데이터로 읽을 사람을 정한다. 티켓의 고객과 다르면 업로드가 거부된다.
        metadata.customMetadata = ["ticketId": ticketID, "customerUid": customerUID, "photographerUid": photographerUID]
        let reference = Storage.storage().reference(withPath: storagePath)
        let startedAt = Date()
        let stored: StorageMetadata
        switch transport {
        case .file:
            stored = try await reference.putFileAsync(from: url, metadata: metadata)
        case .data:
            stored = try await reference.putDataAsync(try Data(contentsOf: url, options: .mappedIfSafe), metadata: metadata)
        }
        return (Int(stored.size), Date().timeIntervalSince(startedAt))
    }

    private func photoDocument(_ fileName: String) -> DocumentReference {
        ticketDocument.collection("photos").document(fileName)
    }

    private var ticketDocument: DocumentReference {
        Firestore.firestore().collection("tickets").document(ticketID)
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
