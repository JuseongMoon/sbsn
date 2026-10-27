import CoreLocation
import Foundation
import Observation
import SBSNCore

/// 작가 위치. "촬영 가능"을 켠 동안 앱이 뒤에 있어도 계속 받는다.
///
/// 권한은 When In Use로 충분하다. `Info.plist`의 백그라운드 모드 `location`과 `allowsBackgroundLocationUpdates`가 있으면
/// 앞에서 시작한 위치 수신이 백그라운드에서도 이어지고(상태 표시줄에 위치 표시가 뜬다), 앱이 멈추지 않아 매칭·구매 리스너도 살아 있다.
/// 작가가 폰을 잠그고 주머니에 넣어도 고객 지도에서 사라지지 않게 하려는 것이다.
/// 자동 일시 정지는 끈다. When In Use 앱은 한번 멈추면 앱을 다시 열 때까지 위치를 받지 못한다(작가는 한자리에 오래 서 있다).
@Observable
@MainActor
final class PhotographerLocationTracker: NSObject {
    enum Status: Equatable {
        case idle
        case waitingForAuthorization
        case denied
        case tracking
        case failed(String)
    }

    private(set) var status = Status.idle
    private(set) var latest: GeoPoint?
    /// 새 위치가 올 때마다 부른다. 호출하는 쪽이 발행 간격을 정한다.
    @ObservationIgnored var onLocation: ((GeoPoint) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private(set) var isTracking = false

    override init() {
        super.init()
        manager.delegate = self
        // 고객 지도는 100m 격자, 만나는 지도는 수십 m면 충분하다. 정확도를 낮춰 배터리를 아낀다.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .otherNavigation
    }

    /// 위치 수신을 시작한다. 권한이 없으면 묻는다. 백그라운드 수신은 앞에 있을 때 시작해야 뒤에서도 이어진다.
    func start() {
        guard !isTracking else { return }
        isTracking = true
        switch manager.authorizationStatus {
        case .notDetermined:
            status = .waitingForAuthorization
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = .denied
        default:
            beginUpdates()
        }
    }

    func stop() {
        isTracking = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        if status == .tracking || status == .waitingForAuthorization {
            status = .idle
        }
    }

    private func beginUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    private func authorizationChanged() {
        guard isTracking else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        case .denied, .restricted:
            status = .denied
        default:
            status = .waitingForAuthorization
        }
    }

    private func received(_ location: CLLocation) {
        guard isTracking else { return }
        let point = GeoPoint(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        latest = point
        status = .tracking
        onLocation?(point)
    }
}

// Core Location은 관리자를 만든 스레드(메인)에서 델리게이트를 부른다.
extension PhotographerLocationTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated { received(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // 위치를 잠깐 못 잡는 오류(kCLErrorLocationUnknown)는 다음 위치를 기다리면 된다.
        guard (error as? CLError)?.code != .locationUnknown else { return }
        let message = error.localizedDescription
        MainActor.assumeIsolated { status = .failed(message) }
    }
}
