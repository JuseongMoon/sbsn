import Foundation
import Observation
import SBSNBackend
import SBSNCore

/// 출시 1단계 공개 위치 발행(D059, L07·L08, 웹 격자 규격 "기기 세션"). 개발용 에뮬레이터를 쓸 때만 돈다.
/// sbsn-dev의 MVP presence 흐름은 그대로 두고 이 루프는 켜지 않는다. Android `LaunchPresencePublisher`(bfe54c7·fbba4b9)와 같은 동작이다.
///
/// - 촬영 가능을 **직접 켜면**(`turnOn`) 새 공개 세션(세션 키·deviceSessionId)을 만들고 `setLaunchAvailabilityV1(true)` 뒤 60초마다 표시점을 발행한다.
/// - **앱 재시작으로 이어 갈 때**(`resume`)는 저장한 세션으로 발행만 한다. 켜기를 다시 보내 다른 기기의 소유권을 가져오지 않는다(격자 규격).
///   세션이 없으면 이어 가지 않는다(키를 잃으면 작가가 다시 켜야 새 세션이 된다).
/// - 서버가 1분에 한 번만 받으므로 칸이 바뀌어도 다음 주기에 보낸다. RESOURCE_EXHAUSTED면 다음 주기까지 기다린다. 위치가 없으면 5초마다 다시 본다.
/// - 다른 기기가 켜면 이 기기의 발행이 FAILED_PRECONDITION이 된다. 되풀이하지 않고 멈춘 뒤 세션을 지우고 `onReplacedByOtherDevice`로 알린다
///   (서버에 끄기를 보내지 않는다. 이미 다른 기기 것이다).
/// - 승인 전 작가·삭제 요청 중이면 서버가 거부한다. 멈추고 `onRejected`로 서버 문구를 넘긴다.
/// - 끄면(`turnOff`) `setLaunchAvailabilityV1(false)`를 보내고 세션을 지운다. 네트워크로 실패하면 deviceSessionId만 남겨 다음에 다시 보낸다.
@Observable
@MainActor
final class LaunchPresencePublisher {
    static let publishInterval: Duration = .seconds(60)
    static let waitForLocation: Duration = .seconds(5)
    static let retryTurnOn: Duration = .seconds(10)

    /// 개발 메뉴에 보이는 마지막 상태(좌표·키는 넣지 않는다)
    private(set) var status: String?
    /// 발행 루프가 돌고 있다
    private(set) var isRunning = false

    @ObservationIgnored var latestLocation: () -> GeoPoint? = { nil }
    @ObservationIgnored var onReplacedByOtherDevice: (() -> Void)?
    @ObservationIgnored var onRejected: ((String) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    var isEnabled: Bool { Backend.usesLaunchFeatures }

    /// 촬영 가능을 직접 켰을 때. 새 세션을 만들고 소유권을 가져온다.
    func turnOn(uid: String) {
        guard isEnabled else { return }
        let session = LaunchPublicSession.start(uid: uid)
        LaunchPublicSession.Store.save(session)
        run(session, sendTurnOn: true)
    }

    /// 앱이 다시 켜져 촬영 가능을 이어 갈 때. 저장한 세션이 없으면 false(작가가 다시 켜야 한다).
    func resume(uid: String) -> Bool {
        guard isEnabled else { return true }
        guard let session = LaunchPublicSession.Store.load(uid: uid) else { return false }
        if !isRunning {
            run(session, sendTurnOn: false)
        }
        return true
    }

    /// 촬영 가능을 껐을 때·로그아웃·계정 삭제 전. 서버에 끄기를 보내고 세션을 지운다(다음에 켜면 새 키·새 표시점).
    func turnOff(uid: String?) async {
        stopLoop()
        guard isEnabled, let uid else { return }
        guard let session = LaunchPublicSession.Store.load(uid: uid) else {
            LaunchPublicSession.Store.clear()
            return
        }
        LaunchPublicSession.Store.clear()
        await sendTurnOff(.init(uid: uid, deviceSessionId: session.deviceSessionId))
    }

    /// 지난번에 실패한 끄기를 다시 보낸다(같은 계정일 때만. 다른 계정 것은 120초 뒤 지도에서 저절로 사라진다).
    func flushPendingTurnOff(uid: String) async {
        guard isEnabled, let pending = LaunchPublicSession.Store.pendingOff else { return }
        guard pending.uid == uid else {
            LaunchPublicSession.Store.setPendingOff(nil)
            return
        }
        await sendTurnOff(pending)
    }

    // MARK: - 내부

    private func stopLoop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func sendTurnOff(_ pending: LaunchPublicSession.PendingOff) async {
        do {
            try await LaunchArtistService.setAvailability(false, deviceSessionId: pending.deviceSessionId)
            LaunchPublicSession.Store.setPendingOff(nil)
            status = "촬영 가능 끔"
        } catch LaunchArtistService.Failure.other(let message) {
            LaunchPublicSession.Store.setPendingOff(pending)
            status = "끄기 실패(다음에 다시 보냄) · \(message)"
        } catch {
            // 이미 다른 기기가 켰거나(소유권 없음) 서버가 거부했다. 다시 보낼 것이 없다.
            LaunchPublicSession.Store.setPendingOff(nil)
            status = "끄기 생략 · \(error.localizedDescription)"
        }
    }

    private enum Outcome {
        case published
        case waitingForLocation
        case stop
    }

    private func run(_ session: LaunchPublicSession, sendTurnOn: Bool) {
        stopLoop()
        isRunning = true
        task = Task { [weak self] in
            if sendTurnOn {
                await self?.flushPendingTurnOff(uid: session.uid)
                while !Task.isCancelled {
                    guard let self else { return }
                    do {
                        try await LaunchArtistService.setAvailability(true, deviceSessionId: session.deviceSessionId)
                        break
                    } catch LaunchArtistService.Failure.other(let message) {
                        status = "촬영 가능 켜기 실패(다시 시도) · \(message)"
                        try? await Task.sleep(for: Self.retryTurnOn)
                    } catch {
                        finish(rejected: error.localizedDescription)
                        return
                    }
                }
            }
            while !Task.isCancelled {
                guard let self else { return }
                switch await publishOnce(session) {
                case .stop:
                    return
                case .waitingForLocation:
                    try? await Task.sleep(for: Self.waitForLocation)
                case .published:
                    try? await Task.sleep(for: Self.publishInterval)
                }
            }
        }
    }

    private func publishOnce(_ session: LaunchPublicSession) async -> Outcome {
        guard let point = latestLocation() else {
            status = "위치를 기다리는 중"
            return .waitingForLocation
        }
        guard let publication = PublicLocationGrid.publication(latitude: point.latitude, longitude: point.longitude,
                                                               uid: session.uid, key: session.key)
        else {
            status = "서비스 범위 밖이라 발행하지 않음"
            return .published
        }
        do {
            try await LaunchArtistService.publish(publication, deviceSessionId: session.deviceSessionId)
            status = "발행 \(publication.cellId) · \(Date().formatted(date: .omitted, time: .standard))"
        } catch LaunchArtistService.Failure.replacedByOtherDevice {
            guard !Task.isCancelled else { return .stop }
            LaunchPublicSession.Store.clear()
            stopLoop()
            status = "다른 기기에서 촬영 가능을 켜서 멈춤"
            onReplacedByOtherDevice?()
            return .stop
        } catch LaunchArtistService.Failure.rateLimited {
            status = "1분 제한: 다음 주기에 보냄"
        } catch LaunchArtistService.Failure.rejected(let message) {
            guard !Task.isCancelled else { return .stop }
            finish(rejected: message)
            return .stop
        } catch {
            status = "발행 실패 · \(error.localizedDescription)"
        }
        return .published
    }

    private func finish(rejected message: String) {
        LaunchPublicSession.Store.clear()
        stopLoop()
        status = "서버가 거부함 · \(message)"
        onRejected?(message)
    }
}
