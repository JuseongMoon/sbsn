import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 촬영 가능한 작가를 지도에서 보는 화면("촬영" 탭, 활성 티켓이 없을 때).
///
/// 출시 1단계 지도(D059·D063): 지도가 멈출 때와 60초마다 `LaunchMapService`로 조회해 작가 표시점·묶음을 Google 지도에 그린다(D051·L30).
/// 2단계(설계 2.2): 작가 핀을 누르면 아래 카드(상태·휴게·활동 범위 밖·추천 시간)와 [채팅하기]. 신청은 대화방에서 한다.
/// 반경 판정은 고객 위치로 기기에서 한다(D065, 위치는 서버로 보내지 않는다).
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
    @State private var location = CustomerLocationReader.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var openRoomId: String?
    @State private var profileArtist: PublicLocationGrid.MapPhotographer?
    @State private var showsSignIn = false
    @State private var isOpeningChat = false
    @AppStorage("SBSNLaunchNickname") private var nickname = ""
    /// 첫 내 위치로 카메라를 한 번 옮겼는지, 사용자가 손으로 지도를 움직였는지(그러면 옮기지 않는다, 총괄 공통 기준·Android f7f379e)
    @State private var centeredOnce = false
    @State private var userMoved = false
    @State private var focus: GeoPoint?
    @State private var focusRevision = 0

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
            // 앱이 앞에 있을 때만 위치를 받는다(L13). 뒤로 가면 작업이 끝나고 앞으로 오면 다시 받는다.
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                await location.track()
            }
            .navigationDestination(item: $openRoomId) { roomId in
                CustomerChatRoomScreen(roomId: roomId)
            }
            .navigationDestination(item: Binding(get: { profileArtist?.uid }, set: { if $0 == nil { profileArtist = nil } })) { uid in
                CustomerPhotographerProfileView(artistUid: uid, statusLine: profileArtist.map(statusLine)) {
                    startChat(uid)
                }
            }
            .sheet(isPresented: $showsSignIn) {
                SignInSheet(allowsLater: true) { name in
                    nickname = name
                    let artist = selectedPhotographer?.uid
                    Task {
                        await session.accountDidChange()
                        if let artist { await openChat(artistUid: artist) }
                    }
                }
            }
        }
    }

    // MARK: - 작가 카드(2단계)

    /// 누른 핀의 작가(한 명짜리 핀만)
    /// 누른 묶음(둘 이상). 가장 크게 확대해도 같은 200m 칸의 작가들은 한 묶음이라, 묶음을 누르면 목록에서 고르게 한다.
    private var selectedCluster: PublicLocationGrid.MapCluster? {
        guard let selectedUid, selectedUid.hasPrefix("cluster."), let launchMap else { return nil }
        return launchMap.clusters.first { "cluster.\($0.id)" == selectedUid && $0.count > 1 }
    }

    private func clusterList(_ cluster: PublicLocationGrid.MapCluster) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("이 근처 작가 \(cluster.count)명")
                    .font(.headline)
                Spacer()
                Button {
                    selectedUid = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("닫기")
            }
            ForEach(cluster.members.prefix(8), id: \.uid) { member in
                Button {
                    selectedUid = "launch.\(member.uid)"
                } label: {
                    HStack {
                        Text(member.nickname)
                        Spacer()
                        Text(statusLine(member))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityIdentifier("map.cluster.\(member.nickname)")
            }
            if cluster.count > 8 {
                Text("확대하면 더 보입니다").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.cluster")
    }

    private var selectedPhotographer: PublicLocationGrid.MapPhotographer? {
        guard let selectedUid, let launchMap else { return nil }
        // 한 명짜리 핀이거나, 묶음 목록에서 고른 작가
        return launchMap.clusters.flatMap(\.members).first { "launch.\($0.uid)" == selectedUid }
    }

    private func statusLine(_ photographer: PublicLocationGrid.MapPhotographer) -> String {
        if let code = photographer.breakReason {
            return "휴게 중 · \(LaunchMatch.BreakReason(rawValue: code)?.label ?? "잠시 휴식")"
        }
        if photographer.isWithinRadius(of: location.projected) == false {
            return CustomerRequestEligibility.outOfRangeText(photographer.radiusMeters)
        }
        if let end = photographer.availabilityEndsAt {
            return "촬영 가능 · \(LaunchTime.clock(end))까지"
        }
        return "촬영 가능"
    }

    private func photographerCard(_ photographer: PublicLocationGrid.MapPhotographer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(photographer.nickname)
                    .font(.headline)
                Spacer()
                Button {
                    selectedUid = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("닫기")
            }
            Text(statusLine(photographer))
                .font(.subheadline)
                .foregroundStyle(photographer.breakReason == nil && photographer.isWithinRadius(of: location.projected) != false
                                 ? Color.primary : Color.orange)
                .accessibilityIdentifier("map.card.status")
            if let minutes = photographer.recommendedShootMinutes {
                Text("추천 \(minutes)분")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    profileArtist = photographer
                } label: {
                    Text("프로필").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("map.card.profile")
                Button {
                    startChat(photographer.uid)
                } label: {
                    Text("채팅하기").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOpeningChat)
                .accessibilityIdentifier("map.card.chat")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.card")
    }

    /// 연결된 계정이면 바로 방을 열고, 익명이면 로그인 시트 뒤 이어서 연다.
    private func startChat(_ artistUid: String) {
        if AccountService.current?.isLinked == true {
            Task { await openChat(artistUid: artistUid) }
        } else {
            showsSignIn = true
        }
    }

    private func openChat(artistUid: String) async {
        isOpeningChat = true
        defer { isOpeningChat = false }
        do {
            openRoomId = try await LaunchMatchService.openConversation(artistUid: artistUid)
            mapError = nil
        } catch {
            mapError = "대화방을 열지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// Google 지도(D051·L30, 맵 ID 없음). 출시 지도 조회 결과(표시점·묶음)를 그린다(Android 3057de3과 같은 기준).
    private var map: some View {
        GoogleMapView(pins: launchPins, selection: $selectedUid, showsMyLocation: true,
                      focus: focus, focusRevision: focusRevision,
                      onUserMove: { userMoved = true },
                      onIdle: { viewport in
                          lastViewport = viewport
                          // 첫 위치를 기다리는 동안은 서울 기본 화면을 조회하지 않는다("없습니다"가 먼저 뜨지 않게).
                          guard !waitingForFirstLocation else { return }
                          Task { await queryLaunchMap(viewport) }
                      })
        .onChange(of: location.latest == nil, initial: true) { _, isMissing in
            guard !isMissing, !centeredOnce, !userMoved, let latest = location.latest else { return }
            centeredOnce = true
            focus = GeoPoint(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude)
            focusRevision += 1
        }
        .onChange(of: waitingForFirstLocation) { _, waiting in
            // 권한을 거부했거나 사용자가 지도를 움직이면 기다리지 않고 지금 화면을 조회한다.
            guard !waiting, let lastViewport else { return }
            Task { await queryLaunchMap(lastViewport) }
        }
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

    /// 첫 내 위치를 기다리는 중(권한 묻기 전이거나 허용했는데 아직 위치가 없다). 사용자가 지도를 움직이면 끝난다. 시간 제한은 없다.
    private var waitingForFirstLocation: Bool {
        guard !centeredOnce, !userMoved, !authorization.isDenied else { return false }
        return authorization.isAuthorized || authorization.status == .notDetermined
    }

    /// 첫 조회가 끝나기 전(또는 첫 위치를 기다리는 중)이면 "찾는 중"
    private var showsSearching: Bool {
        mapError == nil && (waitingForFirstLocation || launchMap == nil)
    }

    /// 조회 결과가 비었다(서비스 범위 밖 포함). 화면이 넓어 가운데만 조회했으면 다른 곳에 있을 수 있어 말하지 않는다.
    private var showsNoPhotographers: Bool {
        guard !showsSearching, let launchMap else { return false }
        return launchMap.clusters.isEmpty && !launchMap.narrowed
    }

    private var hasBottomPanel: Bool {
        selectedPhotographer != nil || selectedCluster != nil || session.lockWarning != nil || mapError != nil || authorization.isDenied
            || showsNoPhotographers || showsSearching
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cluster = selectedCluster {
                clusterList(cluster)
            }
            if let photographer = selectedPhotographer {
                photographerCard(photographer)
            }
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
            if showsSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("주변 작가를 찾는 중")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("map.searching")
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
