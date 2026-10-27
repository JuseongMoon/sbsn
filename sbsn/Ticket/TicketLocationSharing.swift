import CoreLocation
import Observation
import SBSNBackend
import SBSNCore
import SBSNUI

/// 매칭 뒤 만나는 동안의 위치 공유: 작가 위치를 듣고 내 위치를 올린다.
///
/// 내 위치는 10m 넘게 움직였거나 마지막 발행에서 15초가 지났을 때 올린다. 멈춰 있으면 위치 업데이트가 드물어
/// 15초 조건은 별도 heartbeat 루프가 맡는다. 두 루프는 뷰의 `.task`로 돌려 화면을 떠나면 함께 끝난다.
@Observable
@MainActor
final class TicketLocationSharing {
    static let publishDistanceMeters: CLLocationDistance = 10
    static let publishInterval: TimeInterval = 15

    let ticketId: String
    let myUid: String
    let authorization = CustomerLocationAuthorization()

    /// 나를 뺀 참여자 위치(= 작가)
    private(set) var others: [LocationSample] = []
    private(set) var myPoint: SBSNCore.GeoPoint?
    private(set) var listenError: String?
    private(set) var publishError: String?

    private var latestLocation: CLLocation?
    private var lastPublished: (location: CLLocation, at: Date)?
    private var isPublishing = false

    init(ticketId: String, myUid: String) {
        self.ticketId = ticketId
        self.myUid = myUid
    }

    func listenToOthers() async {
        listenError = nil
        do {
            for try await samples in TicketLocationService.locations(ticketId: ticketId) {
                others = samples.filter { $0.uid != myUid }
            }
        } catch {
            guard !Task.isCancelled else { return }
            listenError = "작가 위치를 받지 못했습니다: \(error.localizedDescription)"
        }
    }

    func shareMyLocation() async {
        authorization.requestWhenInUseIfNeeded()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.receiveLocationUpdates() }
            group.addTask { await self.heartbeat() }
        }
    }

    private func receiveLocationUpdates() async {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else { continue }
                latestLocation = location
                myPoint = SBSNCore.GeoPoint(location.coordinate)
                if let lastPublished,
                   location.distance(from: lastPublished.location) < Self.publishDistanceMeters,
                   Date().timeIntervalSince(lastPublished.at) < Self.publishInterval {
                    continue
                }
                await publish(location)
            }
        } catch {
            guard !Task.isCancelled else { return }
            publishError = "내 위치를 받지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func heartbeat() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.publishInterval))
            guard !Task.isCancelled, let latestLocation else { continue }
            if let lastPublished, Date().timeIntervalSince(lastPublished.at) < Self.publishInterval {
                continue
            }
            await publish(latestLocation)
        }
    }

    private func publish(_ location: CLLocation) async {
        guard !isPublishing else { return }
        isPublishing = true
        defer { isPublishing = false }
        do {
            try await TicketLocationService.publish(ticketId: ticketId, uid: myUid, point: SBSNCore.GeoPoint(location.coordinate))
            lastPublished = (location, Date())
            publishError = nil
        } catch {
            publishError = "내 위치를 보내지 못했습니다: \(error.localizedDescription)"
        }
    }
}
