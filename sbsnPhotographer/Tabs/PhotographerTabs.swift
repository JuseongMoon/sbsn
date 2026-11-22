import SBSNCore
import CoreLocation
import Observation
import SBSNBackend
import SBSNUI
import SwiftUI
import UIKit
import UserNotifications

/// "내역" 탭: 공개한 촬영(구매 기한 동안), 촬영 이력·판매·정산·품질(예시 화면).
struct PhotographerHistoryTab: View {
    @Environment(PhotographerSession.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if session.recentPublishedGalleries.isEmpty {
                        Text("최근 7일 동안 공개한 촬영이 없습니다.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recentPublishedGalleries) { gallery in
                        NavigationLink {
                            PublishedGalleryView(ticketID: gallery.ticketID)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(LaunchTime.dayClock(gallery.publishedAt)) 공개 · \(gallery.photoCount)장")
                                Text("구매 기한 \(LaunchTime.dayClock(gallery.purchaseClosesAt))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("history.published")
                    }
                } header: {
                    Text("공개한 촬영")
                }
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
/// 출시 계정 칸(D059·D063): 닉네임·로그인 수단·로그아웃·계정 삭제. 고객 `CustomerAccountSection`과 같은 식별자.
/// 작가 앱은 처음부터 로그인하므로 "로그인" 단추가 없다. 로그아웃·삭제하면 로그인 화면으로 돌아간다.
struct PhotographerAccountSection: View {
    @Environment(PhotographerSession.self) private var session
    @AppStorage("SBSNLaunchNickname") private var nickname = ""

    var body: some View {
        Section {
            LabeledContent("닉네임", value: nickname.isEmpty ? "-" : nickname)
                .accessibilityIdentifier("my.nickname")
            LabeledContent("로그인", value: (session.account?.providers ?? []).map(Self.providerName).joined(separator: ", "))
            Button("로그아웃", role: .destructive) {
                Task {
                    await session.resetAnonymousAccount()
                    nickname = ""
                }
            }
            .accessibilityIdentifier("my.signOut")
            AccountDeletionButton(audience: .photographer) { notice in
                session.accountNotice = notice
                await session.resetAnonymousAccount()
                nickname = ""
            }
        } header: {
            Text("계정")
        } footer: {
            Text("촬영 가능은 운영 승인을 받은 작가 계정만 켤 수 있습니다.")
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

struct PhotographerMyTab: View {
    var body: some View {
        NavigationStack {
            List {
                PhotographerAccountSection()
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
        } header: {
            Text("권한·알림")
        } footer: {
            Text("위치는 촬영 가능인 동안 고객 지도와 만나는 지도에, 알림은 매칭·채팅·구매·공개 알림을 받을 때 씁니다. 사진은 고를 때마다 선택기로 고르므로 사진 보관함 권한이 필요 없습니다.")
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
    @State private var testPhotosLeft: Int?
    @State private var ticketCleanup: String?
    @State private var showsChatBlock = false

    var body: some View {
        List {
            Section {
                LabeledContent("작가 ID", value: session.uid ?? "-")
                    .font(.caption)
                    .textSelection(.enabled)
                Button("진행 중인 촬영 로컬 정리", role: .destructive) {
                    session.clearLocalTicket()
                }
                .disabled(session.ticket == nil)
                LabeledContent("출시 발행", value: session.launchPublisher.status ?? "-")
                    .font(.caption)
                    .accessibilityIdentifier("dev.launchPublish")
            }
            #if DEBUG
            // 출시 로그인 제공자 시험(총괄 순서 2번, sbsn-dev는 Auth만·함수 호출 없음)
            LaunchAuthProbeSection {
                await session.accountDidChange(nickname: "")
            } onSignOut: {
                await session.resetAnonymousAccount()
            }
            Section("시험") {
                NavigationLink("메타데이터 경로 시험") { MetadataProbeView() }
                    .accessibilityIdentifier("dev.metadataProbe")
                Button("고르기 화면 시험(서버 없음)") { session.openDebugGallery() }
                    .accessibilityIdentifier("dev.debugGallery")
                // 자동 시험이 넣은 사진(`Documents/TestPhotos/`)은 기기에서 직접 지울 길이 없어(devicectl은 복사만) 여기서 지운다.
                Button("시험 사진 폴더 지우기(Documents/TestPhotos)", role: .destructive) {
                    let folder = URL.documentsDirectory.appending(path: "TestPhotos", directoryHint: .isDirectory)
                    try? FileManager.default.removeItem(at: folder)
                    testPhotosLeft = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))?.count ?? 0
                }
                .accessibilityIdentifier("dev.deleteTestPhotos")
                if let testPhotosLeft {
                    Text("시험 사진 남은 파일 \(testPhotosLeft)개")
                        .accessibilityIdentifier("dev.testPhotosLeft")
                }
                Button("목록의 티켓 폴더 지우기(Documents/DeleteTickets.txt)", role: .destructive) {
                    ticketCleanup = session.deleteListedTicketFolders()
                }
                .accessibilityIdentifier("dev.deleteListedTickets")
                if let ticketCleanup {
                    Text(ticketCleanup)
                        .accessibilityIdentifier("dev.ticketCleanup")
                }
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
