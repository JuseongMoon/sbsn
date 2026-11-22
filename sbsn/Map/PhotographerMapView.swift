import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 촬영 가능한 작가를 지도에서 고르고 확정하는 화면("촬영" 탭, 활성 티켓이 없을 때).
///
/// 작가 카드의 "이 작가와 촬영하기"가 가격·조건 확인 자리 화면을 띄우고, 그 화면의 확정 버튼이 확정 트랜잭션을 부른다.
/// 작가 목록 리스너는 이 화면이 떠 있는 동안만 붙고, 마커는 Google 지도(`GoogleMapView`)의 핀을 눌러 고른다(D051·L30).
/// 고객이 위치 권한을 거부해도 지도와 작가 마커는 보여야 하므로 처음 화면은 서울 시청 근처이고 작가가 보이면 작가들에게 맞춘다.
struct PhotographerMapView: View {
    let myUid: String

    @Environment(CustomerSession.self) private var session
    @State private var authorization = CustomerLocationAuthorization()
    @State private var photographers: [PhotographerPresence] = []
    @State private var selectedUid: String?
    /// 값을 올리면 지도가 보이는 작가를 모두 담게 맞춘다(Google 지도).
    @State private var framing = 0
    /// 사용자가 지도를 직접 움직인 뒤에는 작가 목록이 바뀌어도 자동으로 맞추지 않는다.
    @State private var userMovedMap = false
    @State private var hasFramedPhotographers = false
    /// `isSelectable`은 시각에 따라 달라지므로 주기적으로 갱신해 오래된 작가를 지도에서 뺀다.
    @State private var now = Date()
    @State private var listenError: String?
    @State private var listenerGeneration = 0
    @State private var isConfirming = false
    @State private var confirmFailure: ConfirmFailure?
    /// 확정이 거부된 작가. 리스너가 갱신되기 전이라도 바로 지도에서 뺀다.
    @State private var rejectedUids: Set<String> = []
    /// 가격·조건 확인 시트에 띄운 작가. 시트를 연 동안 지도에서 빠져도 그 작가로 확정한다.
    @State private var reviewingPhotographer: PhotographerPresence?
    @State private var mode = Mode.map
    /// 출시 1단계 지도(D059): 에뮬레이터를 쓸 때만 조회한다. 마지막으로 멈춘 화면과 조회 결과
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

    struct ConfirmFailure {
        let message: String
        /// `alreadyMatched`일 때 서버가 알려 준 진행 중인 티켓
        let existingTicketId: String?
    }

    private struct Marker: Identifiable {
        let presence: PhotographerPresence
        let point: GeoPoint

        var id: String { presence.uid }
    }

    private var markers: [Marker] {
        photographers.compactMap { presence in
            guard presence.isSelectable(at: now), !rejectedUids.contains(presence.uid), let location = presence.location else { return nil }
            return Marker(presence: presence, point: location)
        }
    }

    private var selectedPhotographer: PhotographerPresence? {
        markers.first { $0.id == selectedUid }?.presence
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .map:
                    map
                        .safeAreaInset(edge: .bottom) { bottomPanel }
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
            .task(id: listenerGeneration) { await listen() }
            .task { await tickClock() }
            .task { await refreshLaunchMapPeriodically() }
            .onChange(of: markers.map(\.id)) { _, ids in
                if let selectedUid, !ids.contains(selectedUid) {
                    self.selectedUid = nil
                }
                // 작가가 처음 보일 때, 그리고 사용자가 지도를 움직이기 전까지는 보이는 작가가 바뀔 때마다 작가들이 모두 보이게 맞춘다.
                // 기본 위치(서울 시청)에 두면 멀리 있는 작가 마커가 화면 밖에 남는다. 앱을 다시 열면 첫 목록이 기기 캐시에서 와서
                // 이미 떠난 작가에게 맞춰진 뒤 서버 목록의 작가가 화면 밖에 남기도 한다(둘 다 실기기에서 확인).
                // 첫 맞춤은 따로 기억한다(사용자가 움직이기 전에 맞춘 것인지).
                if !ids.isEmpty, !hasFramedPhotographers || !userMovedMap {
                    hasFramedPhotographers = true
                    framing += 1
                }
            }
            .sheet(item: $reviewingPhotographer) { photographer in
                PriceReviewSheet(photographer: photographer, isConfirming: isConfirming,
                                 onConfirm: { confirm(photographer) },
                                 onClose: { reviewingPhotographer = nil })
            }
        }
    }

    /// Google 지도(D051·L30, 맵 ID 없음). 핀 제목이 작가 이름이고 UI 시험은 `marker.<이름>`으로 찾는다.
    /// 에뮬레이터에서는 출시 지도 조회 결과(표시점·묶음)도 함께 그린다(Android 3057de3과 같은 기준).
    private var map: some View {
        GoogleMapView(pins: markers.map {
            MapPin(id: $0.id, title: $0.presence.displayName, point: $0.point, style: .photographer,
                   accessibilityIdentifier: "marker.\($0.presence.displayName)")
        } + launchPins, selection: $selectedUid, framing: framing, showsMyLocation: true,
                      onUserMove: { userMovedMap = true },
                      onIdle: Backend.usesLaunchFeatures ? { viewport in
                          lastViewport = viewport
                          Task { await queryLaunchMap(viewport) }
                      } : nil)
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
        guard Backend.usesLaunchFeatures,
              let box = PublicLocationGrid.projectedViewport(viewport.points.map { ($0.latitude, $0.longitude) })
        else { return }
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
            launchMap = LaunchMapState(clusters: PublicLocationGrid.clusters(result.photographers, level: level),
                                       truncated: result.truncated, narrowed: rect.narrowed)
        } catch {
            listenError = "작가 지도를 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 지도가 멈춘 뒤에도 60초마다 다시 조회한다(표시 위치 유효 기간 120초, 작가 발행 60초).
    private func refreshLaunchMapPeriodically() async {
        guard Backend.usesLaunchFeatures else { return }
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

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let warning = session.lockWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let listenError {
                HStack {
                    Text(listenError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("다시 시도") { listenerGeneration += 1 }
                        .font(.caption)
                }
            }
            if authorization.isDenied {
                Text("위치 권한이 없어 내 위치는 보이지 않습니다. 지도를 움직여 작가를 찾아 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let photographer = selectedPhotographer {
                photographerCard(photographer)
            } else if markers.isEmpty {
                Label("주변에 촬영 가능한 작가가 없습니다", systemImage: "camera.metering.none")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("지도에서 작가를 골라 주세요")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let confirmFailure {
                VStack(alignment: .leading, spacing: 6) {
                    Text(confirmFailure.message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                    if let existing = confirmFailure.existingTicketId {
                        Button("진행 중인 촬영 열기") { session.rememberTicket(existing) }
                            .font(.footnote)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
    }

    private func photographerCard(_ photographer: PhotographerPresence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(photographer.displayName)
                .font(.headline)
            if let updatedAt = photographer.updatedAt {
                Text("\(Self.relativeFormatter.localizedString(for: updatedAt, relativeTo: now)) 갱신")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                CustomerSampleScreen(CustomerFeatures.photographerProfile)
            } label: {
                Text(CustomerFeatures.photographerProfile.title)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("planned.photographerProfile")
            Button {
                confirmFailure = nil
                reviewingPhotographer = photographer
            } label: {
                Text("이 작가와 촬영하기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("customer.review")
            .disabled(isConfirming)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

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

    // MARK: - 동작

    private func listen() async {
        listenError = nil
        do {
            for try await update in PhotographerDirectory.availablePhotographers() {
                photographers = update
            }
        } catch {
            guard !Task.isCancelled else { return }
            listenError = "작가 목록을 불러오지 못했습니다: \(error.localizedDescription)"
        }
    }

    private func tickClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            now = Date()
        }
    }

    /// 확정 트랜잭션(가격·조건 확인 시트의 확정 버튼). 성공하면 세션이 티켓 화면으로 넘긴다.
    /// 거부되면 시트를 닫고 지도에 안내를 남긴다.
    private func confirm(_ photographer: PhotographerPresence) {
        guard !isConfirming else { return }
        guard session.isOnline else {
            reviewingPhotographer = nil
            confirmFailure = ConfirmFailure(message: "인터넷 연결을 확인해 주세요.", existingTicketId: nil)
            return
        }
        isConfirming = true
        confirmFailure = nil
        Task {
            defer { isConfirming = false }
            do {
                let ticketId = try await TicketService.confirm(photographer: photographer, customerUid: myUid)
                reviewingPhotographer = nil
                session.rememberTicket(ticketId)
            } catch let error as TicketService.ConfirmError {
                reviewingPhotographer = nil
                rejectedUids.insert(photographer.uid)
                selectedUid = nil
                if case .alreadyMatched(let existing) = error {
                    confirmFailure = ConfirmFailure(message: error.localizedDescription, existingTicketId: existing)
                } else {
                    confirmFailure = ConfirmFailure(message: error.localizedDescription, existingTicketId: nil)
                }
            } catch {
                reviewingPhotographer = nil
                confirmFailure = ConfirmFailure(message: "확정하지 못했습니다: \(error.localizedDescription)", existingTicketId: nil)
            }
        }
    }
}
