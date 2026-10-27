import SBSNBackend

/// 티켓 하나를 보는 동안 화면들이 같이 쓰는 객체 묶음. 티켓 화면이 만들고 티켓이 바뀌면 통째로 새로 만든다.
@MainActor
final class TicketWorkspace {
    let ticketId: String
    let myUid: String
    let downloader: TicketPhotoDownloader
    let previews: PhotoPreviewLoader
    let delivery: PhotoDeliveryManager
    let favorites: FavoriteToggler
    let locationSharing: TicketLocationSharing

    init(ticketId: String, myUid: String) {
        self.ticketId = ticketId
        self.myUid = myUid
        downloader = TicketPhotoDownloader(ticketID: ticketId)
        previews = PhotoPreviewLoader(downloader: downloader)
        delivery = PhotoDeliveryManager(ticketId: ticketId, downloader: downloader)
        favorites = FavoriteToggler(ticketId: ticketId)
        locationSharing = TicketLocationSharing(ticketId: ticketId, myUid: myUid)
    }
}
