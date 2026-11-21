import Foundation
import Observation
import SBSNBackend
import SBSNCore

/// 끝난 선별 촬영들의 갤러리(D040 ①, 설계 문서 3절). 내 사진 탭이 진행 중 티켓과 따로 들고 있어, 고객이 공개 전에 새 촬영을 시작해도 남는다.
///
/// 티켓 ID 목록은 기기에 저장하고(`SBSNGalleryTicketIDs`, 최근 것부터), 앱을 켤 때 서버에서도 찾는다
/// (고객 uid + `curatedV1` 티켓을 종료 시각 내림차순으로, 공통 명세). 목록의 티켓은 문서를 듣고 있어 공개되면 바로 바뀐다.
@Observable
@MainActor
final class GalleryStore {
    static let storageKey = "SBSNGalleryTicketIDs"
    /// 구매 기한(7일)이 지나고도 서버 보관(30일) 동안은 산 사진을 다시 받을 수 있게 목록에 남긴다.
    static let keepAfterPublish: TimeInterval = 30 * 24 * 60 * 60

    private(set) var ticketIDs: [String]
    private(set) var tickets: [String: TicketRecord] = [:]
    @ObservationIgnored private var workspaces: [String: GalleryWorkspace] = [:]
    @ObservationIgnored private var listeners: [String: Task<Void, Never>] = [:]

    init() {
        ticketIDs = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
    }

    /// 목록 화면용: 최근 종료 순, 오래된 것은 뺀다.
    var galleries: [TicketRecord] {
        ticketIDs.compactMap { tickets[$0] }
            .filter { ticket in
                guard let publishedAt = ticket.galleryPublishedAt else { return ticket.cancelledAt == nil }
                return publishedAt.addingTimeInterval(Self.keepAfterPublish) > Date()
            }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }

    /// 앱을 켤 때 한 번: 저장한 목록을 듣고, 서버에서 지난 촬영을 찾아 더한다.
    func start(uid: String) async {
        for ticketID in ticketIDs { listen(ticketID) }
        if let found = try? await TicketService.customerGalleryTickets(uid: uid) {
            for ticket in found where ticket.endedAt != nil {
                tickets[ticket.id] = ticket
                remember(ticket.id)
            }
        }
    }

    /// 선별 촬영이 끝났을 때(`TicketBackgroundWork`) 목록에 더한다.
    func remember(_ ticketID: String) {
        if !ticketIDs.contains(ticketID) {
            ticketIDs.insert(ticketID, at: 0)
            UserDefaults.standard.set(Array(ticketIDs.prefix(50)), forKey: Self.storageKey)
        }
        listen(ticketID)
    }

    func ticket(_ ticketID: String) -> TicketRecord? {
        tickets[ticketID]
    }

    /// 갤러리 한 곳의 미리보기·찜·구매·전달 묶음. 화면을 닫아도 내려받기·저장이 이어지게 여기서 들고 있는다.
    func workspace(for ticketID: String) -> GalleryWorkspace {
        if let workspace = workspaces[ticketID] { return workspace }
        let workspace = GalleryWorkspace(ticketID: ticketID)
        workspaces[ticketID] = workspace
        if let ticket = tickets[ticketID] { workspace.update(ticket) }
        return workspace
    }

    private func listen(_ ticketID: String) {
        guard listeners[ticketID] == nil else { return }
        listeners[ticketID] = Task { [weak self] in
            do {
                for try await update in TicketService.ticket(ticketID) {
                    guard let self else { return }
                    if let update {
                        tickets[ticketID] = update
                        workspaces[ticketID]?.update(update)
                    }
                }
            } catch {}
            self?.listeners[ticketID] = nil
        }
    }
}

/// 공개된 갤러리 하나를 보는 동안 화면들이 같이 쓰는 객체 묶음.
@Observable
@MainActor
final class GalleryWorkspace {
    let ticketID: String
    let downloader: TicketPhotoDownloader
    let previews: PhotoPreviewLoader
    let delivery: PhotoDeliveryManager
    let favorites: FavoriteToggler
    private(set) var ticket: TicketRecord?

    init(ticketID: String) {
        self.ticketID = ticketID
        downloader = TicketPhotoDownloader(ticketID: ticketID)
        previews = PhotoPreviewLoader(downloader: downloader)
        delivery = PhotoDeliveryManager(ticketId: ticketID, downloader: downloader)
        favorites = FavoriteToggler(ticketId: ticketID)
    }

    /// 공개되면 공개 목록의 사진 문서를 듣기 시작한다(한 번만).
    func update(_ ticket: TicketRecord) {
        self.ticket = ticket
        if ticket.isGalleryPublished {
            delivery.startListening(photoIds: ticket.galleryPhotoIds)
        }
    }
}
