import Foundation
import Testing
@testable import SBSNCore

struct PresenceTests {
    let now = Date(timeIntervalSince1970: 3_000_000)
    let gyeongbokgung = GeoPoint(latitude: 37.579617, longitude: 126.977041)

    func presence(available: Bool = true, activeTicketId: String? = nil, age: TimeInterval = 0, location: GeoPoint? = nil) -> PhotographerPresence {
        PhotographerPresence(uid: "P", displayName: "작가", isAvailable: available,
                             location: location ?? gyeongbokgung, updatedAt: now.addingTimeInterval(-age), activeTicketId: activeTicketId)
    }

    @Test func shortDistancesAreInMeters() {
        let north = GeoPoint(latitude: gyeongbokgung.latitude + 25 / GeoPoint.metersPerDegreeLatitude, longitude: gyeongbokgung.longitude)
        #expect(abs(gyeongbokgung.distance(to: north) - 25) < 0.01)
        #expect(gyeongbokgung.distance(to: gyeongbokgung) == 0)
    }

    @Test func selectableOnlyWhenAvailableUnlockedAndFresh() {
        #expect(presence().isSelectable(at: now))
        #expect(presence(available: false).isSelectable(at: now) == false)
        #expect(presence(activeTicketId: "T1").isSelectable(at: now) == false)
        #expect(presence(age: PhotographerPresence.staleAfter - 1).isSelectable(at: now))
        #expect(presence(age: PhotographerPresence.staleAfter + 1).isSelectable(at: now) == false)
        var noLocation = presence()
        noLocation.location = nil
        #expect(noLocation.isSelectable(at: now) == false)
    }
}

/// 종료·취소 때 작가 잠금을 풀지: 공개 상태 문서가 있고 잠금이 이 티켓일 때만(공통 명세, 웹 규칙과 같은 조건).
@Test func photographerLockIsReleasedOnlyWhenHeldByThisTicket() {
    #expect(PhotographerPresence.releasesLock(presenceExists: true, activeTicketId: "T1", for: "T1"))
    #expect(!PhotographerPresence.releasesLock(presenceExists: false, activeTicketId: nil, for: "T1"), "문서 없음(24시간 보존으로 지워짐)")
    #expect(!PhotographerPresence.releasesLock(presenceExists: true, activeTicketId: "T2", for: "T1"), "다른 티켓으로 잠김")
    #expect(!PhotographerPresence.releasesLock(presenceExists: true, activeTicketId: nil, for: "T1"), "이미 풀림")
}
