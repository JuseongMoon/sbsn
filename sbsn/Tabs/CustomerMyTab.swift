import CoreLocation
import Photos
import SBSNUI
import SwiftUI
import UIKit
import UserNotifications

/// "마이" 탭: 계정·고객지원·약관(빈 페이지), 권한·알림 상태, 개발 메뉴.
struct CustomerMyTab: View {
    var body: some View {
        NavigationStack {
            List {
                Section("계정") {
                    CustomerSampleLink(CustomerFeatures.profile)
                    CustomerSampleLink(CustomerFeatures.accountLink)
                }
                CustomerPermissionsSection()
                Section("고객지원") {
                    CustomerSampleLink(CustomerFeatures.help)
                    CustomerSampleLink(CustomerFeatures.inquiry)
                    CustomerSampleLink(CustomerFeatures.refund)
                }
                Section {
                    CustomerSampleLink(CustomerFeatures.terms)
                    CustomerSampleLink(CustomerFeatures.events)
                }
                Section {
                    NavigationLink("개발") { CustomerDeveloperPage() }
                        .accessibilityIdentifier("my.developer")
                }
            }
            .navigationTitle("마이")
        }
    }
}

/// 위치·사진 추가·알림 권한 상태. 탭을 열 때와 앱이 앞으로 올 때(설정에서 돌아왔을 때) 다시 읽는다.
struct CustomerPermissionsSection: View {
    @State private var location = CustomerLocationAuthorization()
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    @State private var notifications = UNAuthorizationStatus.notDetermined
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            row("위치", value: locationText, id: "permission.location")
            row("사진", value: photosText, id: "permission.photos")
            row("알림", value: notificationText, id: "permission.notifications")
        } header: {
            Text("권한·알림")
        } footer: {
            Text("위치는 작가 지도와 만나는 동안, 사진은 구매한 사진을 저장할 때, 알림은 작가 메시지와 촬영 상태를 받을 때 씁니다.")
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
        photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private var locationText: String {
        switch location.status {
        case .authorizedAlways, .authorizedWhenInUse: "허용됨"
        case .denied: "꺼짐"
        case .restricted: "제한됨"
        case .notDetermined: "묻기 전"
        @unknown default: "알 수 없음"
        }
    }

    private var photosText: String {
        switch photos {
        case .authorized: "허용됨"
        case .limited: "일부 허용"
        case .denied: "꺼짐"
        case .restricted: "제한됨"
        case .notDetermined: "첫 구매 때 묻기"
        @unknown default: "알 수 없음"
        }
    }

    private var notificationText: String {
        switch notifications {
        case .authorized, .provisional, .ephemeral: "켜짐"
        case .denied: "꺼짐"
        case .notDetermined: "매칭 뒤 묻기"
        @unknown default: "알 수 없음"
        }
    }
}

/// 시험용 메뉴. 예전 지도 화면 벌레 아이콘 메뉴를 옮겼다.
/// "예시 화면 전체"는 티켓이 있어야 닿는 예시 화면(촬영 안내, 추천 순서 등)도 시뮬레이터에서 열 수 있게 모아 둔 것이다.
struct CustomerDeveloperPage: View {
    @Environment(CustomerSession.self) private var session
    @State private var showsChatReport = false
    @State private var showsChatBlock = false

    var body: some View {
        List {
            Section {
                LabeledContent("고객 ID", value: session.uid ?? "-")
                    .font(.caption)
                    .textSelection(.enabled)
                LabeledContent("진행 중인 촬영", value: session.activeTicketId ?? "없음")
                    .font(.caption)
            }
            Section {
                Button("익명 계정 재발급", systemImage: "person.badge.plus", role: .destructive) {
                    Task { await session.reissueAccount() }
                }
                Button("활성 티켓 로컬 정리", systemImage: "trash", role: .destructive) {
                    session.clearLocalTicketForDebug()
                }
            }
            if let message = session.debugMessage {
                Section {
                    Text(message)
                        .font(.caption)
                        .textSelection(.enabled)
                    Button("닫기") { session.dismissDebugMessage() }
                }
            }
            Section("예시 화면 전체(\(CustomerFeatures.all.count))") {
                ForEach(CustomerFeatures.all) { CustomerSampleLink($0) }
                Button("채팅 신고 시트") { showsChatReport = true }
                Button("채팅 차단 시트") { showsChatBlock = true }
            }
        }
        .sampleChatSafetySheets(target: "하린 작가", cancelsShoot: true, showsReport: $showsChatReport, showsBlock: $showsChatBlock)
        .navigationTitle("개발")
        .navigationBarTitleDisplayMode(.inline)
    }
}
