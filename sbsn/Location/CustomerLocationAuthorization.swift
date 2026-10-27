import CoreLocation
import Observation

/// 위치 권한(When In Use)을 요청하고 상태 변화를 화면에 알린다.
///
/// 위치 자체는 `CLLocationUpdate.liveUpdates()`로 받으므로 여기서는 권한만 다룬다. 고객은 백그라운드 위치가 필요 없다.
@Observable
@MainActor
final class CustomerLocationAuthorization: NSObject, CLLocationManagerDelegate {
    private(set) var status = CLAuthorizationStatus.notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    var isAuthorized: Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    func requestWhenInUseIfNeeded() {
        guard status == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    // CoreLocation이 부르는 콜백은 격리 밖이므로 값만 꺼내 메인으로 넘긴다.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}
