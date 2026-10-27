import MapKit
import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 촬영 가능한 작가를 지도에서 고르고 확정하는 화면. 활성 티켓이 없을 때만 보인다.
///
/// 작가 목록 리스너는 이 화면이 떠 있는 동안만 붙고, 마커는 `Map`의 selection으로 고른다.
/// 고객이 위치 권한을 거부해도 지도와 작가 마커는 보여야 하므로 카메라는 내 위치를 못 받으면 서울로 둔다.
struct PhotographerMapView: View {
    let myUid: String

    @Environment(CustomerSession.self) private var session
    @State private var authorization = CustomerLocationAuthorization()
    @State private var photographers: [PhotographerPresence] = []
    @State private var selectedUid: String?
    @State private var position = MapCameraPosition.userLocation(fallback: PhotographerMapView.seoul)
    @State private var hasFramedPhotographers = false
    /// `isSelectable`은 시각에 따라 달라지므로 주기적으로 갱신해 오래된 작가를 지도에서 뺀다.
    @State private var now = Date()
    @State private var listenError: String?
    @State private var listenerGeneration = 0
    @State private var isConfirming = false
    @State private var confirmFailure: ConfirmFailure?
    /// 확정이 거부된 작가. 리스너가 갱신되기 전이라도 바로 지도에서 뺀다.
    @State private var rejectedUids: Set<String> = []

    static let seoul = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        latitudinalMeters: 5000, longitudinalMeters: 5000
    ))

    struct ConfirmFailure {
        let message: String
        /// `alreadyMatched`일 때 서버가 알려 준 진행 중인 티켓
        let existingTicketId: String?
    }

    private struct Marker: Identifiable {
        let presence: PhotographerPresence
        let coordinate: CLLocationCoordinate2D

        var id: String { presence.uid }
    }

    private var markers: [Marker] {
        photographers.compactMap { presence in
            guard presence.isSelectable(at: now), !rejectedUids.contains(presence.uid), let location = presence.location else { return nil }
            return Marker(presence: presence, coordinate: location.coordinate)
        }
    }

    private var selectedPhotographer: PhotographerPresence? {
        markers.first { $0.id == selectedUid }?.presence
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedUid) {
                UserAnnotation()
                ForEach(markers) { marker in
                    Annotation(marker.presence.displayName, coordinate: marker.coordinate) {
                        markerView(isSelected: marker.id == selectedUid)
                            .accessibilityIdentifier("marker.\(marker.presence.displayName)")
                    }
                    .tag(marker.id)
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .navigationTitle("십분스냅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { debugMenu }
            .task { authorization.requestWhenInUseIfNeeded() }
            .task(id: listenerGeneration) { await listen() }
            .task { await tickClock() }
            .onChange(of: markers.map(\.id)) { _, ids in
                if let selectedUid, !ids.contains(selectedUid) {
                    self.selectedUid = nil
                }
                // 작가가 처음 보일 때 한 번, 작가들이 모두 보이게 맞춘다. 기본 위치(서울 시청)에 두면 멀리 있는
                // 작가 마커가 화면 밖에 남는다(실기기에서 확인). 내 위치를 못 잡으면 `positionedByUser`도 믿을 수 없어 따로 기억한다.
                if !ids.isEmpty, !hasFramedPhotographers, let region = Self.region(covering: markers.map(\.coordinate)) {
                    hasFramedPhotographers = true
                    position = .region(region)
                }
            }
        }
    }

    /// 좌표들을 모두 담는 영역. 한 명이면 그 주변 2km, 여럿이면 여백을 30% 둔다.
    static func region(covering coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000)
        }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (latitudes.min()! + latitudes.max()!) / 2,
                                            longitude: (longitudes.min()! + longitudes.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.3, 0.02),
                                    longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.3, 0.02))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func markerView(isSelected: Bool) -> some View {
        Image(systemName: "camera.circle.fill")
            .font(isSelected ? .largeTitle : .title)
            .foregroundStyle(isSelected ? Color.accentColor : Color.orange)
            .background(Circle().fill(.white).padding(2))
    }

    // MARK: - 하단 패널

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let warning = session.lockWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = session.debugMessage {
                HStack {
                    Text(message)
                        .font(.caption)
                        .textSelection(.enabled)
                    Spacer()
                    Button("닫기") { session.dismissDebugMessage() }
                        .font(.caption)
                }
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
            Button {
                confirm(photographer)
            } label: {
                Group {
                    if isConfirming {
                        ProgressView()
                    } else {
                        Text("이 작가와 촬영 확정")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("customer.confirm")
            .disabled(isConfirming)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    // MARK: - 디버그

    private var debugMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("익명 계정 재발급", systemImage: "person.badge.plus") {
                    Task { await session.reissueAccount() }
                }
                Button("활성 티켓 로컬 정리", systemImage: "trash") {
                    session.clearLocalTicketForDebug()
                }
            } label: {
                Image(systemName: "ladybug")
            }
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

    /// 확정 트랜잭션. 성공하면 세션이 티켓 화면으로 넘긴다. 거부되면 안내만 남기고 지도에 머문다.
    private func confirm(_ photographer: PhotographerPresence) {
        guard !isConfirming else { return }
        guard session.isOnline else {
            confirmFailure = ConfirmFailure(message: "인터넷 연결을 확인해 주세요.", existingTicketId: nil)
            return
        }
        isConfirming = true
        confirmFailure = nil
        Task {
            defer { isConfirming = false }
            do {
                let ticketId = try await TicketService.confirm(photographer: photographer, customerUid: myUid)
                session.rememberTicket(ticketId)
            } catch let error as TicketService.ConfirmError {
                rejectedUids.insert(photographer.uid)
                selectedUid = nil
                if case .alreadyMatched(let existing) = error {
                    confirmFailure = ConfirmFailure(message: error.localizedDescription, existingTicketId: existing)
                } else {
                    confirmFailure = ConfirmFailure(message: error.localizedDescription, existingTicketId: nil)
                }
            } catch {
                confirmFailure = ConfirmFailure(message: "확정하지 못했습니다: \(error.localizedDescription)", existingTicketId: nil)
            }
        }
    }
}
