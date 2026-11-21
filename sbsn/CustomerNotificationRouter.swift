import Foundation
import Observation

/// 알림을 눌렀을 때 열 화면. 앱 델리게이트가 값을 넣고 뿌리 화면(`ContentView`)이 가져간다.
///
/// 서버는 같은 이벤트를 두 번 보낼 수 있다(공통 명세). 고객 앱은 알림을 받을 때 일을 하지 않고, 누를 때 화면만 옮긴다.
/// 화면 이동은 몇 번 해도 같고 공개 여부는 언제나 티켓 문서로 다시 확인하므로, 같은 `eventId`가 두 번 와도 결과가 같다.
@Observable
@MainActor
final class CustomerNotificationRouter {
    static let shared = CustomerNotificationRouter()

    var pendingGalleryTicketID: String?

    func openGallery(_ ticketID: String) {
        pendingGalleryTicketID = ticketID
    }
}
