import CoreLocation
import Observation
import SBSNBackend
import SBSNCore
import SBSNUI
import UIKit

/// 매칭 뒤 만나는 동안의 위치 공유: 작가 위치를 듣고 내 위치를 올린다.
///
/// 내 위치는 10m 넘게 움직였거나 마지막 발행에서 10초가 지났을 때 올린다(L14). 멈춰 있으면 위치 업데이트가 드물어
/// 10초 조건은 별도 heartbeat 루프가 맡는다. 고객 앱은 앞에 있을 때만 보낸다(백그라운드 위치 없음, L13). 두 루프는 `TicketBackgroundWork`가 만나는 단계 동안 돌린다:
/// 탭을 옮겨도 이어지고, 둘 다 시작하거나 티켓이 바뀌면 함께 끝난다.
@Observable
@MainActor
final class TicketLocationSharing {
    static let publishDistanceMeters: CLLocationDistance = 10
    static let publishInterval: TimeInterval = LocationSample.meetupPublishInterval

    let ticketId: String
    let myUid: String
    /// 출시 2단계 티켓(`launchTickets`)이면 true
    let launch: Bool
    let authorization = CustomerLocationAuthorization()

    /// 나를 뺀 참여자 위치(= 작가)
    private(set) var others: [LocationSample] = []
    private(set) var myPoint: SBSNCore.GeoPoint?
    private(set) var listenError: String?
    private(set) var publishError: String?

    private var latestLocation: CLLocation?
    private var lastPublished: (location: CLLocation, at: Date)?
    private var isPublishing = false

    init(ticketId: String, myUid: String, launch: Bool = false) {
        self.ticketId = ticketId
        self.myUid = myUid
        self.launch = launch
    }

    func listenToOthers() async {
        listenError = nil
        do {
            for try await samples in TicketLocationService.locations(ticketId: ticketId, launch: launch) {
                others = samples.filter { $0.uid != myUid }
            }
        } catch {
            guard !Task.isCancelled else { return }
            listenError = "작가 위치를 받지 못했습니다: \(error.localizedDescription)"
        }
    }

    func shareMyLocation() async {
        // 앞으로 돌아와 다시 시작할 때 뒤로 가기 전 위치를 올리지 않는다(새 위치가 올 때까지 기다린다).
        latestLocation = nil
        lastPublished = nil
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
                if UIApplication.shared.applicationState != .active { CustomerLocationReader.backgroundUpdates += 1 }
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
            try await TicketLocationService.publish(ticketId: ticketId, uid: myUid, point: SBSNCore.GeoPoint(location.coordinate), launch: launch)
            lastPublished = (location, Date())
            publishError = nil
        } catch {
            publishError = "내 위치를 보내지 못했습니다: \(error.localizedDescription)"
        }
    }
}
