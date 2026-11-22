import CoreLocation
import Photos
import SBSNUI
import SBSNBackend
import SwiftUI
import UIKit
import UserNotifications

/// "마이" 탭: 계정·고객지원·약관(빈 페이지), 권한·알림 상태, 개발 메뉴.
/// 출시 계정 칸: 익명으로 둘러보는 중이면 로그인, 로그인했으면 닉네임·로그인 수단·로그아웃(설계 문서 1.1).
struct CustomerAccountSection: View {
    @Binding var showsSignIn: Bool
    @Environment(CustomerSession.self) private var session
    @State private var account = AccountService.current
    @AppStorage("SBSNLaunchNickname") private var nickname = ""

    var body: some View {
        Section("계정") {
            if let account, account.isLinked {
                LabeledContent("닉네임", value: nickname.isEmpty ? "-" : nickname)
                    .accessibilityIdentifier("my.nickname")
                LabeledContent("로그인", value: account.providers.map(Self.providerName).joined(separator: ", "))
                Button("로그아웃", role: .destructive) {
                    Task {
                        await session.reissueAccount()
                        nickname = ""
                        self.account = AccountService.current
                    }
                }
                .accessibilityIdentifier("my.signOut")
                // 계정 삭제(L10): 서버가 지도·데이터·Auth를 정리한다. 접수되면 익명 둘러보기로 돌아간다.
                AccountDeletionButton { _ in
                    await session.reissueAccount()
                    nickname = ""
                    self.account = AccountService.current
                }
            } else {
                Text("로그인 없이 둘러보는 중입니다. 채팅과 촬영 신청은 로그인 뒤 할 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // 시트는 목록(CustomerMyTab)에 붙인다. 이 단추는 로그인하면 사라지므로 여기에 붙이면 시트가 제대로 닫히지 않는다.
                Button("로그인") { showsSignIn = true }
                    .accessibilityIdentifier("my.signIn")
            }
        }
        .onAppear { account = AccountService.current }
        .onChange(of: session.uid) { _, _ in account = AccountService.current }
        .onChange(of: showsSignIn) { _, isShowing in
            if !isShowing { account = AccountService.current }
        }
    }

    static func providerName(_ id: String) -> String {
        switch id {
        case "apple.com": "Apple"
        case "google.com": "Google"
        case "password": "시험 계정"
        default: id
        }
    }
}

struct CustomerMyTab: View {
    @Environment(CustomerSession.self) private var session
    @State private var showsSignIn = false
    @AppStorage("SBSNLaunchNickname") private var nickname = ""

    var body: some View {
        NavigationStack {
            List {
                if Backend.usesLaunchFeatures {
                    // 출시 1단계 계정(D059): 개발용 에뮬레이터를 쓸 때만. sbsn-dev는 지금의 익명 MVP 그대로
                    CustomerAccountSection(showsSignIn: $showsSignIn)
                } else {
                    Section("계정") {
                        CustomerSampleLink(CustomerFeatures.profile)
                        CustomerSampleLink(CustomerFeatures.accountLink)
                    }
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
            .sheet(isPresented: $showsSignIn) {
                SignInSheet(allowsLater: true) { name in
                    nickname = name
                    Task { await session.accountDidChange() }
                }
            }
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
            #if DEBUG
            Section("시험") {
                NavigationLink("사진 앱 저장 시험") { SavedPhotoProbeView() }
            }
            #endif
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
