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

    @Test func quantizedPointStaysWithinHalfGridAndIsStable() {
        let grid = PhotographerPresence.publicGridMeters
        let snapped = gyeongbokgung.quantized(gridMeters: grid)
        let latitudeMeters = abs(snapped.latitude - gyeongbokgung.latitude) * GeoPoint.metersPerDegreeLatitude
        let longitudeMeters = abs(snapped.longitude - gyeongbokgung.longitude) * GeoPoint.metersPerDegreeLatitude * cos(gyeongbokgung.latitude * .pi / 180)
        #expect(latitudeMeters <= grid / 2 + 0.001)
        #expect(longitudeMeters <= grid / 2 + 0.001)
        // 같은 격자 안에서 조금 움직여도 공개 위치는 그대로다(격자 가운데에서 간격의 1/10만 움직인 점).
        let latitudeStep = grid / GeoPoint.metersPerDegreeLatitude
        let nearby = GeoPoint(latitude: snapped.latitude + latitudeStep / 10, longitude: snapped.longitude + latitudeStep / 10)
        #expect(nearby.quantized(gridMeters: grid) == snapped)
        #expect(snapped.quantized(gridMeters: grid) == snapped)
        // 다른 격자로 넘어가면 바뀐다.
        let farther = GeoPoint(latitude: snapped.latitude + latitudeStep, longitude: snapped.longitude)
        #expect(farther.quantized(gridMeters: grid) != snapped)
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

    @Test func displayNameIsTrimmedAndBounded() {
        #expect(PhotographerPresence.validDisplayName("  김작가 ") == "김작가")
        #expect(PhotographerPresence.validDisplayName("") == nil)
        #expect(PhotographerPresence.validDisplayName(String(repeating: "가", count: PhotographerPresence.displayNameLimit - 1)) != nil)
        #expect(PhotographerPresence.validDisplayName(String(repeating: "가", count: PhotographerPresence.displayNameLimit)) == nil)
    }
}
