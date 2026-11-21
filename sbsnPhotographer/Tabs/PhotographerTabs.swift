import CoreLocation
import Observation
import SBSNUI
import SwiftUI
import UIKit
import UserNotifications

/// "내역" 탭: 촬영 이력·판매·정산·품질(모두 빈 페이지).
struct PhotographerHistoryTab: View {
    var body: some View {
        NavigationStack {
            List {
                Section("촬영") {
                    PhotographerSampleLink(PhotographerFeatures.history)
                    PhotographerSampleLink(PhotographerFeatures.sales)
                }
                Section("정산") {
                    PhotographerSampleLink(PhotographerFeatures.settlement)
                }
                Section("품질") {
                    PhotographerSampleLink(PhotographerFeatures.feedback)
                    PhotographerSampleLink(PhotographerFeatures.disputes)
                }
            }
            .navigationTitle("내역")
        }
    }
}

/// "마이" 탭: 작가 정보·고객지원·약관(빈 페이지), 권한·알림 상태, 개발 메뉴.
struct PhotographerMyTab: View {
    var body: some View {
        NavigationStack {
            List {
                Section("작가 정보") {
                    PhotographerSampleLink(PhotographerFeatures.portfolio)
                    PhotographerSampleLink(PhotographerFeatures.registration)
                    PhotographerSampleLink(PhotographerFeatures.originals)
                }
                PhotographerPermissionsSection()
                Section {
                    PhotographerSampleLink(PhotographerFeatures.support)
                    PhotographerSampleLink(PhotographerFeatures.terms)
                }
                Section {
                    NavigationLink("개발") { PhotographerDeveloperPage() }
                        .accessibilityIdentifier("my.developer")
                }
            }
            .navigationTitle("마이")
        }
    }
}

/// 위치·알림·로컬 네트워크 권한 상태. 탭을 열 때와 앱이 앞으로 올 때(설정에서 돌아왔을 때) 다시 읽는다.
struct PhotographerPermissionsSection: View {
    @State private var location = LocationAuthorizationStatus()
    @State private var notifications = UNAuthorizationStatus.notDetermined
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            row("위치", value: locationText, id: "permission.location")
            row("알림", value: notificationText, id: "permission.notifications")
            row("로컬 네트워크", value: "설정에서 확인", id: "permission.localNetwork")
        } header: {
            Text("권한·알림")
        } footer: {
            Text("위치는 촬영 가능인 동안 고객 지도와 만나는 지도에, 알림은 매칭·채팅·구매를 받을 때 씁니다. 로컬 네트워크 허용 여부는 앱이 읽을 수 없어, 카메라가 붙지 않으면 설정에서 확인해 주세요.")
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    private func row(_ title: String, value: String, id: String) -> some View {
        HStack(spacing: 16) {
            LabeledContent(title, value: value)
                .accessibilityIdentifier(id)
            Button("설정") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func refresh() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var locationText: String {
        switch location.status {
        case .authorizedAlways: "항상 허용"
        case .authorizedWhenInUse: "앱 사용 중 허용"
        case .denied: "꺼짐"
        case .restricted: "제한됨"
        case .notDetermined: "묻기 전"
        @unknown default: "알 수 없음"
        }
    }

    private var notificationText: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "켜짐"
        case .denied: "꺼짐"
        case .notDetermined: "묻기 전"
        @unknown default: "알 수 없음"
        }
    }
}

/// 위치 권한 상태만 읽는다(위치 수신은 `PhotographerLocationTracker`가 한다).
@Observable
@MainActor
final class LocationAuthorizationStatus: NSObject, CLLocationManagerDelegate {
    private(set) var status = CLAuthorizationStatus.notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    // CoreLocation이 부르는 콜백은 격리 밖이므로 값만 꺼내 메인으로 넘긴다.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}

/// 시험용 메뉴. 예전 홈 화면의 "개발" 섹션을 옮겼다.
/// "예시 화면 전체"는 티켓이 있어야 닿는 예시 화면(고객 브리프, 타이머 등)도 시뮬레이터에서 열 수 있게 모아 둔 것이다.
struct PhotographerDeveloperPage: View {
    @Environment(PhotographerSession.self) private var session
    @State private var showsChatReport = false
    @State private var showsChatBlock = false

    var body: some View {
        List {
            Section {
                if let delivery = session.delivery {
                    NavigationLink("카메라 전송 측정") {
                        CameraTransferTestView(model: delivery, showsMeasurements: true)
                    }
                }
                LabeledContent("작가 ID", value: session.uid ?? "-")
                    .font(.caption)
                    .textSelection(.enabled)
                Button("진행 중인 촬영 로컬 정리", role: .destructive) {
                    session.clearLocalTicket()
                }
                .disabled(session.ticket == nil)
                Button("익명 계정 재발급", role: .destructive) {
                    Task { await session.resetAnonymousAccount() }
                }
            }
            #if DEBUG
            Section("시험") {
                NavigationLink("메타데이터 경로 시험") { MetadataProbeView() }
                    .accessibilityIdentifier("dev.metadataProbe")
            }
            #endif
            Section("예시 화면 전체(\(PhotographerFeatures.all.count))") {
                ForEach(PhotographerFeatures.all) { PhotographerSampleLink($0) }
                Button("채팅 신고 시트") { showsChatReport = true }
                Button("채팅 차단 시트") { showsChatBlock = true }
            }
        }
        .sampleChatSafetySheets(target: "고객", cancelsShoot: true, showsReport: $showsChatReport, showsBlock: $showsChatBlock)
        .navigationTitle("개발")
        .navigationBarTitleDisplayMode(.inline)
    }
}
