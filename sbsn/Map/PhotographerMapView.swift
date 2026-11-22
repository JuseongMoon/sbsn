import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 촬영 가능한 작가를 지도에서 보는 화면("촬영" 탭, 활성 티켓이 없을 때).
///
/// 출시 1단계 지도(D059·D063): 지도가 멈출 때와 60초마다 `LaunchMapService`로 조회해 작가 표시점·묶음을 Google 지도에 그린다(D051·L30).
/// 작가를 골라 매칭하는 카드·확정은 2단계 매칭 때 다시 만든다(D063으로 MVP 핀·확정 UI를 지웠다).
/// 고객이 위치 권한을 거부해도 지도와 작가 핀은 보여야 하므로 처음 화면은 서울 시청 근처다.
struct PhotographerMapView: View {
    @Environment(CustomerSession.self) private var session
    @State private var authorization = CustomerLocationAuthorization()
    /// 누른 핀(강조만 한다)
    @State private var selectedUid: String?
    @State private var mapError: String?
    @State private var mode = Mode.map
    /// 출시 지도: 마지막으로 멈춘 화면과 조회 결과
    @State private var lastViewport: MapViewport?
    @State private var launchMap: LaunchMapState?

    /// 출시 지도 조회 결과를 묶은 것
    struct LaunchMapState: Equatable {
        let clusters: [PublicLocationGrid.MapCluster]
        /// 조회 영역 안 결과가 100명을 넘어 반환된 점만 셌다
        let truncated: Bool
        /// 화면이 100칸보다 넓어 가운데만 조회했다("확대하면 더 보입니다")
        let narrowed: Bool
    }

    enum Mode: Hashable {
        case map
        case list
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .map:
                    map
                        .safeAreaInset(edge: .bottom) {
                            if hasBottomPanel { bottomPanel }
                        }
                case .list:
                    // 지도 화면 안에 붙는 예시 목록이라 제목은 그대로 "작가 찾기"로 둔다.
                    SamplePhotographerList()
                        .accessibilityIdentifier("sample.\(CustomerFeatures.photographerList.id)")
                }
            }
            .safeAreaInset(edge: .top) { modePicker }
            .navigationTitle("작가 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { plannedMenus }
            .task { authorization.requestWhenInUseIfNeeded() }
            .task { await refreshLaunchMapPeriodically() }
        }
    }

    /// Google 지도(D051·L30, 맵 ID 없음). 출시 지도 조회 결과(표시점·묶음)를 그린다(Android 3057de3과 같은 기준).
    private var map: some View {
        GoogleMapView(pins: launchPins, selection: $selectedUid, showsMyLocation: true,
                      onIdle: { viewport in
                          lastViewport = viewport
                          Task { await queryLaunchMap(viewport) }
                      })
        .overlay(alignment: .top) {
            if launchMap?.narrowed == true {
                Text("확대하면 더 보입니다")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityIdentifier("launch.map.zoomIn")
            }
        }
    }

    /// 출시 지도 핀: 한 명은 그 작가의 표시점(marker.<닉네임>), 둘 이상은 합친 사각형 가운데의 인원수(cluster.<묶음 ID>, 잘렸으면 "n+")
    private var launchPins: [MapPin] {
        guard let launchMap else { return [] }
        return launchMap.clusters.map { cluster in
            let position = PublicLocationGrid.unproject(cluster.center)
            let point = GeoPoint(latitude: position.latitude, longitude: position.longitude)
            if let single = cluster.single {
                return MapPin(id: "launch.\(single.uid)", title: single.nickname, point: point, style: .photographer,
                              accessibilityIdentifier: "marker.\(single.nickname)")
            }
            let count = launchMap.truncated ? "\(cluster.count)+" : "\(cluster.count)"
            return MapPin(id: "cluster.\(cluster.id)", title: "작가 \(count)명", point: point, style: .cluster(count),
                          accessibilityIdentifier: "cluster.\(cluster.id)")
        }
    }

    /// 멈춘 화면으로 출시 지도를 조회한다(규격: 여덟 점 폭 → 묶음 수준, 100칸이 넘는 축은 가운데 100칸).
    private func queryLaunchMap(_ viewport: MapViewport) async {
        guard let box = PublicLocationGrid.projectedViewport(viewport.points.map { ($0.latitude, $0.longitude) }) else { return }
        let level = PublicLocationGrid.clusterLevel(screenWidthMm: box.east - box.west)
        let center = PublicLocationGrid.project(latitude: viewport.center.latitude, longitude: viewport.center.longitude)
        let rect = PublicLocationGrid.queryRect(west: box.west, south: box.south, east: box.east, north: box.north, center: center)
        guard rect.west <= rect.east, rect.south <= rect.north else {
            // 서비스 범위 밖: 조회하지 않고 "확대하면 더 보입니다"도 띄우지 않는다(규격: 조회가 있고 잘렸을 때만)
            launchMap = LaunchMapState(clusters: [], truncated: false, narrowed: false)
            return
        }
        do {
            let result = try await LaunchMapService.findPhotographers(west: rect.west, south: rect.south, east: rect.east, north: rect.north)
            guard viewport == lastViewport else { return }
            mapError = nil
            launchMap = LaunchMapState(clusters: PublicLocationGrid.clusters(result.photographers, level: level),
                                       truncated: result.truncated, narrowed: rect.narrowed)
        } catch {
            mapError = "작가 지도를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 지도가 멈춘 뒤에도 60초마다 다시 조회한다(표시 위치 유효 기간 120초, 작가 발행 60초).
    private func refreshLaunchMapPeriodically() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if let lastViewport { await queryLaunchMap(lastViewport) }
        }
    }

    private var modePicker: some View {
        Picker("보기", selection: $mode) {
            Text("지도").tag(Mode.map)
            Text("목록").tag(Mode.list)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityIdentifier("customer.findMode")
    }

    // MARK: - 하단 패널

    /// 조회 결과가 비었다(서비스 범위 밖 포함). 화면이 넓어 가운데만 조회했으면 다른 곳에 있을 수 있어 말하지 않는다.
    private var showsNoPhotographers: Bool {
        guard let launchMap else { return false }
        return launchMap.clusters.isEmpty && !launchMap.narrowed
    }

    private var hasBottomPanel: Bool {
        session.lockWarning != nil || mapError != nil || authorization.isDenied || showsNoPhotographers
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let warning = session.lockWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let mapError {
                HStack {
                    Text(mapError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("다시 시도") {
                        guard let lastViewport else { return }
                        Task { await queryLaunchMap(lastViewport) }
                    }
                    .font(.caption)
                }
            }
            if authorization.isDenied {
                Text("위치 권한이 없어 내 위치는 보이지 않습니다. 지도를 움직여 작가를 찾아 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if showsNoPhotographers {
                Label("주변에 촬영 가능한 작가가 없습니다", systemImage: "camera.metering.none")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }

    // MARK: - 준비 중 메뉴

    private var plannedMenus: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                CustomerSampleScreen(CustomerFeatures.conditions)
            } label: {
                Label(CustomerFeatures.conditions.title, systemImage: CustomerFeatures.conditions.systemImage)
            }
            .accessibilityIdentifier("planned.conditions")
            NavigationLink {
                CustomerSampleScreen(CustomerFeatures.events)
            } label: {
                Label(CustomerFeatures.events.title, systemImage: CustomerFeatures.events.systemImage)
            }
            .accessibilityIdentifier("planned.events")
        }
    }
}
