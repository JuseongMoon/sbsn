#if os(iOS) && canImport(GoogleMaps)
import GoogleMaps
import SBSNCore
import SwiftUI
import UIKit

/// Google Maps SDK 설정(D051·L30: 맵 ID 없이 쓴다 = 무료 "Maps SDK" SKU).
///
/// 키는 앱 번들의 `SBSNSecrets.plist`(`GoogleMapsAPIKey`)에서 읽는다. 이 파일은 공개 저장소에 올리지 않는다(.gitignore).
/// 키는 번들 ID와 Maps SDK for iOS로 제한돼 있다(sbsn-dev "sbsn iOS 고객/작가 앱 Maps(개발)").
public enum GoogleMapsSetup {
    /// 앱 시작 때 한 번 부른다. 키가 없으면 false(지도는 회색으로 보인다).
    @MainActor
    @discardableResult
    public static func configure() -> Bool {
        guard let url = Bundle.main.url(forResource: "SBSNSecrets", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let key = values["GoogleMapsAPIKey"] as? String, !key.isEmpty
        else { return false }
        return GMSServices.provideAPIKey(key)
    }
}

/// 지도 위 한 점
public struct MapPin: Identifiable, Equatable {
    public enum Style: Equatable {
        case me
        case photographer
        /// 여러 작가를 묶은 원(인원수 글자, 잘린 조회면 "n+")
        case cluster(String)
    }

    public let id: String
    public let title: String
    public let point: GeoPoint
    public let style: Style
    /// UI 시험 식별자(예: "marker.작가1")
    public let accessibilityIdentifier: String?

    public init(id: String, title: String, point: GeoPoint, style: Style, accessibilityIdentifier: String? = nil) {
        self.id = id
        self.title = title
        self.point = point
        self.style = style
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// 지도가 멈췄을 때 보이는 화면: 네 모서리와 네 변 가운데(끝값의 산술평균) 여덟 점과 카메라 중심(격자 규격 5항)
public struct MapViewport: Equatable, Sendable {
    public let points: [GeoPoint]
    public let center: GeoPoint
}

/// SwiftUI용 Google 지도. MapKit과 한 화면에 섞지 않는다(Google 약관 3.2.3(e)).
///
/// - `selection`: 누른 핀의 ID(지도 빈 곳을 누르면 nil)
/// - `framing`: 값이 바뀔 때마다 모든 핀이 보이게 카메라를 맞춘다
/// - `onUserMove`: 사용자가 지도를 직접 움직였을 때(자동 맞춤을 멈출지 정하는 데 쓴다)
/// - `bottomPadding`: 아래 카드가 Google 로고를 가리지 않게 지도 여백을 준다(약관 3.2.2(b))
public struct GoogleMapView: UIViewRepresentable {
    let pins: [MapPin]
    @Binding var selection: String?
    let framing: Int
    let showsMyLocation: Bool
    let bottomPadding: CGFloat
    let onUserMove: (() -> Void)?
    let onIdle: ((MapViewport) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    public init(pins: [MapPin], selection: Binding<String?> = .constant(nil), framing: Int = 0, showsMyLocation: Bool = false,
                bottomPadding: CGFloat = 0, onUserMove: (() -> Void)? = nil, onIdle: ((MapViewport) -> Void)? = nil) {
        self.pins = pins
        _selection = selection
        self.framing = framing
        self.showsMyLocation = showsMyLocation
        self.bottomPadding = bottomPadding
        self.onUserMove = onUserMove
        self.onIdle = onIdle
    }

    /// 핀이 없을 때의 처음 화면(서울 시청 근처)
    static let defaultCamera = GMSCameraPosition(latitude: 37.5665, longitude: 126.9780, zoom: 14)

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = Self.defaultCamera
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        // 핀을 VoiceOver·UI 시험이 찾을 수 있게 한다(핀 제목이 이름이 된다).
        mapView.accessibilityElementsHidden = false
        mapView.settings.compassButton = true
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        return mapView
    }

    public func updateUIView(_ mapView: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        mapView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        mapView.isMyLocationEnabled = showsMyLocation
        mapView.settings.myLocationButton = showsMyLocation
        mapView.padding = UIEdgeInsets(top: 0, left: 0, bottom: bottomPadding, right: 0)
        coordinator.sync(pins: pins, selection: selection, on: mapView)
        if coordinator.lastFraming != framing {
            coordinator.lastFraming = framing
            coordinator.frame(pins: pins, on: mapView)
        }
    }

    @MainActor
    public final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        var markers: [String: GMSMarker] = [:]
        var lastFraming: Int?
        private var lastStyles: [String: MapPin.Style] = [:]
        private var lastSelection: String?

        init(_ parent: GoogleMapView) {
            self.parent = parent
        }

        func sync(pins: [MapPin], selection: String?, on mapView: GMSMapView) {
            let ids = Set(pins.map(\.id))
            for (id, marker) in markers where !ids.contains(id) {
                marker.map = nil
                markers[id] = nil
                lastStyles[id] = nil
            }
            for pin in pins {
                let marker = markers[pin.id] ?? {
                    let marker = GMSMarker()
                    marker.userData = pin.id
                    marker.map = mapView
                    markers[pin.id] = marker
                    return marker
                }()
                marker.position = CLLocationCoordinate2D(latitude: pin.point.latitude, longitude: pin.point.longitude)
                marker.title = pin.title
                marker.accessibilityLabel = pin.accessibilityIdentifier ?? pin.title
                let isSelected = pin.id == selection
                if lastStyles[pin.id] != pin.style || (isSelected != (lastSelection == pin.id)) || marker.iconView == nil && marker.icon == nil {
                    apply(pin.style, selected: isSelected, to: marker)
                    lastStyles[pin.id] = pin.style
                }
                marker.zIndex = isSelected ? 10 : (pin.style == .me ? 5 : 1)
            }
            lastSelection = selection
        }

        private func apply(_ style: MapPin.Style, selected: Bool, to marker: GMSMarker) {
            switch style {
            case .me:
                marker.iconView = nil
                marker.icon = GMSMarker.markerImage(with: .systemBlue)
            case .photographer:
                marker.iconView = nil
                marker.icon = GMSMarker.markerImage(with: selected ? .systemRed : .systemOrange)
            case .cluster(let text):
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
                label.text = text
                label.textAlignment = .center
                label.font = .preferredFont(forTextStyle: .headline)
                label.textColor = .white
                label.backgroundColor = .systemOrange
                label.layer.cornerRadius = 22
                label.layer.masksToBounds = true
                label.layer.borderColor = UIColor.white.cgColor
                label.layer.borderWidth = 2
                marker.icon = nil
                marker.iconView = label
                marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            }
        }

        func frame(pins: [MapPin], on mapView: GMSMapView) {
            guard let first = pins.first else { return }
            if pins.count == 1 {
                mapView.animate(to: GMSCameraPosition(latitude: first.point.latitude, longitude: first.point.longitude, zoom: 15))
                return
            }
            var bounds = GMSCoordinateBounds()
            for pin in pins {
                bounds = bounds.includingCoordinate(CLLocationCoordinate2D(latitude: pin.point.latitude, longitude: pin.point.longitude))
            }
            mapView.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 60))
        }

        public nonisolated func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            let id = marker.userData as? String
            MainActor.assumeIsolated { parent.selection = id }
            return false
        }

        public nonisolated func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            MainActor.assumeIsolated { parent.selection = nil }
        }

        public nonisolated func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            let target = position.target
            MainActor.assumeIsolated {
                guard let onIdle = parent.onIdle else { return }
                let region = mapView.projection.visibleRegion()
                func point(_ c: CLLocationCoordinate2D) -> GeoPoint { GeoPoint(latitude: c.latitude, longitude: c.longitude) }
                func middle(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> GeoPoint {
                    GeoPoint(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
                }
                let points = [point(region.farLeft), point(region.farRight), point(region.nearLeft), point(region.nearRight),
                              middle(region.farLeft, region.farRight), middle(region.nearLeft, region.nearRight),
                              middle(region.farLeft, region.nearLeft), middle(region.farRight, region.nearRight)]
                onIdle(MapViewport(points: points, center: point(target)))
            }
        }

        public nonisolated func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            guard gesture else { return }
            MainActor.assumeIsolated { parent.onUserMove?() }
        }
    }
}
#endif
