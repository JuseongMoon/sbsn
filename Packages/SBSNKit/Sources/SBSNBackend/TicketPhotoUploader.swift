import FirebaseFirestore
import FirebaseStorage
import Foundation
import SBSNCore

/// 작가가 고른 사진을 서버에 올린다(선별 전달, D036·D038).
///
/// - Storage `tickets/{티켓}/previews/{사진 ID}.jpg`: 고객에게 먼저 보일 저화질·워터마크 미리보기(1MB 미만)
/// - Storage `tickets/{티켓}/fullres/{사진 ID}.jpg`: 구매하면 넘기는 고객 최종본(50MiB 미만, 메타데이터 전부 유지)
/// - Firestore `tickets/{티켓}/photos/{사진 ID}`: 초안 필드(`fileName`·`capturedAt`, 갈래별 경로·바이트 수·업로드 시각).
///   찜·구매·전달은 고객 앱이 쓰고 작가 앱은 읽기만 한다.
///
/// 보안 규칙: 촬영이 끝난 뒤·공개 전에만 쓸 수 있다. 객체는 만들기만 되고(덮어쓰기·삭제 불가), 문서 필드는 더하기만 된다
/// (이미 쓴 값은 바꿀 수 없다). 그래서 다시 올릴 때는 먼저 서버에 있는지 본다: 문서에 그 갈래가 있으면 끝이고,
/// 객체만 있으면(올린 뒤 문서를 쓰기 전에 멈춘 경우) 그 크기로 문서만 채운다. 객체 메타데이터는 참여자 uid 두 개만 적는다.
public actor TicketPhotoUploader {
    /// 사진 하나에 올리는 두 파일
    public enum Variant: String, Sendable, CaseIterable {
        case preview
        case fullres

        var folder: String {
            switch self {
            case .preview: "previews"
            case .fullres: "fullres"
            }
        }
    }

    /// 파일을 Storage로 보내는 방식.
    public enum Transport: String, Sendable, CaseIterable {
        /// `putFile`. 실기기에서는 iOS 백그라운드 전송(백그라운드 URLSession)으로 나가 앱이 멈춰도 이어지지만,
        /// 시스템이 전송 시점과 속도를 조절할 수 있다.
        case file
        /// `putData`. 앱 안의 일반 전송이다. 앱이 백그라운드에서 멈추면 전송도 멈춘다.
        case data
    }

    public struct Upload: Sendable {
        public let storagePath: String
        public let byteCount: Int
        /// 확인·전송·문서 기록까지 포함한 전체 시간
        public let duration: TimeInterval
        /// Storage로 파일을 보내는 데 걸린 시간만(이미 있어서 보내지 않았으면 0)
        public let transferDuration: TimeInterval
        /// 서버에 이미 있어서 다시 보내지 않았다.
        public let reusedExisting: Bool
    }

    public let ticketID: String
    /// 이 티켓의 고객. 객체 메타데이터에 적어 규칙이 업로드를 확인한다.
    public let customerUID: String

    public init(ticketID: String, customerUID: String) {
        self.ticketID = ticketID
        self.customerUID = customerUID
    }

    public nonisolated static func storagePath(ticketID: String, photoID: String, variant: Variant) -> String {
        "tickets/\(ticketID)/\(variant.folder)/\(photoID).jpg"
    }

    /// 사진 하나의 한 갈래를 서버에 둔다. 이미 있으면 다시 보내지 않는다.
    /// - Parameters:
    ///   - fileName: 원래 파일 이름(표시용). 없으면 문서에 적지 않는다.
    ///   - capturedAt: EXIF 촬영 시각. 미리보기 갈래에서만 적는다.
    public func deliver(_ variant: Variant, photoID: String, fileAt url: URL, fileName: String?, capturedAt: Date?,
                        transport: Transport) async throws -> Upload {
        let startedAt = Date()
        let path = Self.storagePath(ticketID: ticketID, photoID: photoID, variant: variant)
        let document = photoDocument(photoID)
        if let existing = try? await recordedByteCount(variant, in: document) {
            return Upload(storagePath: path, byteCount: existing, duration: Date().timeIntervalSince(startedAt), transferDuration: 0,
                          reusedExisting: true)
        }
        var byteCount: Int
        var transferDuration: TimeInterval = 0
        var reused = false
        if let size = await objectSize(at: path) {
            byteCount = size
            reused = true
        } else {
            do {
                (byteCount, transferDuration) = try await put(url, at: path, transport: transport)
            } catch {
                // 응답만 못 받고 만들어졌을 수 있다(만들기만 되는 규칙이라 다시 보내면 거부된다).
                guard let size = await objectSize(at: path) else { throw error }
                byteCount = size
                reused = true
            }
        }
        var fields: [String: Any] = [
            "\(variant.rawValue)Path": path,
            "\(variant.rawValue)ByteCount": byteCount,
            "\(variant.rawValue)UploadedAt": FieldValue.serverTimestamp(),
        ]
        if let fileName, !fileName.isEmpty {
            fields["fileName"] = String(fileName.prefix(255))
        }
        if variant == .preview, let capturedAt {
            fields["capturedAt"] = Timestamp(date: capturedAt)
        }
        do {
            try await document.setData(fields, merge: true)
        } catch {
            // 앞선 시도가 이미 썼으면 같은 필드를 다시 쓰는 것은 거부된다. 서버에 있으면 끝난 것이다.
            guard let existing = try? await recordedByteCount(variant, in: document) else { throw error }
            byteCount = existing
            reused = true
        }
        return Upload(storagePath: path, byteCount: byteCount, duration: Date().timeIntervalSince(startedAt),
                      transferDuration: transferDuration, reusedExisting: reused)
    }

    /// 작가가 본 사진 문서들(초안과 공개 뒤 찜·구매·전달)을 실시간으로 받는다. 키는 사진 ID.
    public nonisolated func photoRecords() -> AsyncThrowingStream<[String: PhotoRecord], Error> {
        FirestoreListeners.documents(of: Self.photosCollection(ticketID)) { snapshot in
            Self.records(in: snapshot)
        }
    }

    /// 사진 문서 전부를 서버에서 한 번 읽는다. 앱을 다시 켰을 때 어떤 파일이 이미 올라갔는지 복원하는 데 쓴다.
    public func fetchPhotoRecords() async throws -> [String: PhotoRecord] {
        Self.records(in: try await Self.photosCollection(ticketID).getDocuments(source: .server))
    }

    // MARK: - 내부

    /// 문서에 그 갈래가 기록돼 있으면 바이트 수, 없으면 nil
    private func recordedByteCount(_ variant: Variant, in document: DocumentReference) async throws -> Int? {
        let data = try await document.getDocument(source: .server).data()
        guard data?["\(variant.rawValue)UploadedAt"] != nil else { return nil }
        return data?["\(variant.rawValue)ByteCount"] as? Int
    }

    private func objectSize(at path: String) async -> Int? {
        guard let metadata = try? await Storage.storage().reference(withPath: path).getMetadata() else { return nil }
        return Int(metadata.size)
    }

    /// 올린 바이트 수와 Storage 전송 시간을 돌려준다.
    private func put(_ url: URL, at storagePath: String, transport: Transport) async throws -> (Int, TimeInterval) {
        let photographerUID = try await Backend.signedInUserID()
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        // 규칙이 이 두 키만 허용하고, 티켓의 참여자와 같은지 본다.
        metadata.customMetadata = ["customerUid": customerUID, "photographerUid": photographerUID]
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

    private func photoDocument(_ photoID: String) -> DocumentReference {
        Self.photosCollection(ticketID).document(photoID)
    }

    private nonisolated static func photosCollection(_ ticketID: String) -> CollectionReference {
        Firestore.firestore().collection("tickets").document(ticketID).collection("photos")
    }

    private nonisolated static func records(in snapshot: QuerySnapshot) -> [String: PhotoRecord] {
        var records: [String: PhotoRecord] = [:]
        for document in snapshot.documents {
            records[document.documentID] = FirestoreCodec.photo(id: document.documentID, data: document.data(with: .estimate))
        }
        return records
    }
}
