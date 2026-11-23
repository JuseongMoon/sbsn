//
//  ContentView.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 작가 앱의 하단 탭.
enum PhotographerTab: Hashable {
    case shoot
    case chat
    case history
    case my
}

/// 작가 앱의 뿌리 화면: 촬영 · 채팅 · 내역 · 마이 탭(D066 S1).
/// 출시 티켓(시작 대기·촬영 중)이 있으면 촬영 탭이 그 티켓 화면이다.
///
/// 업로드·위치는 화면이 아니라 `PhotographerSession.shared`가 돌려서 탭을 바꿔도 끊기지 않는다.
/// 매칭되면(매칭 알림) 촬영 탭으로 넘어가 티켓 화면을 열고, 촬영이 끝나면 사진 고르기 화면으로 간다.
struct ContentView: View {
    @Environment(PhotographerSession.self) private var session
    @State private var path: [PhotographerRoute] = []
    @State private var selectedTab = PhotographerTab.shoot
    @State private var launch = PhotographerLaunchModel()

    var body: some View {
        @Bindable var session = session
        Group {
            if session.account?.isLinked != true {
                // 출시 1단계(D051·D059·D063): 작가 앱은 Google·Apple로 로그인한 뒤 쓴다.
                SignInSheet(allowsLater: false) { nickname in
                    UserDefaults.standard.set(nickname, forKey: "SBSNLaunchNickname")
                    Task { await session.accountDidChange(nickname: nickname) }
                }
            } else {
                tabs
            }
        }
        // 계정 삭제 뒤 안내. 탭이 로그인 관문으로 바뀌어도 보이게 뿌리에 둔다.
        .accountDeletionNotice($session.accountNotice)
        .launchToast(Binding(get: { launch.toast }, set: { launch.toast = $0 }))
        .environment(launch)
        // 출시 대화·신청·티켓은 연결된 계정만 듣는다(규칙).
        .task(id: "\(session.uid ?? "-")#\(session.account?.isLinked == true)") {
            let session = session
            launch.latestLocation = { session.location.latest }
            launch.onMeetupChange = { session.setLaunchMeetupActive($0) }
            launch.start(uid: session.account?.isLinked == true ? session.uid : nil)
            await LaunchPush.registerIfLinked(role: .photographer)
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            shootTab
                .tabItem { Label("촬영", systemImage: "camera") }
                .tag(PhotographerTab.shoot)
            PhotographerChatTab()
                .tabItem { Label("채팅", systemImage: "bubble.left.and.bubble.right") }
                .badge(launch.totalUnread)
                .tag(PhotographerTab.chat)
            PhotographerHistoryTab()
                .tabItem { Label("내역", systemImage: "list.bullet.rectangle") }
                .tag(PhotographerTab.history)
            PhotographerMyTab()
                .tabItem { Label("마이", systemImage: "person.crop.circle") }
                .tag(PhotographerTab.my)
        }
        .onChange(of: launch.activeTicket?.id) { _, ticketId in
            if ticketId != nil { selectedTab = .shoot }
        }
        // 출시 알림을 누르면: 대화방은 채팅 탭에서 그 방, 진행 중 티켓은 촬영 탭(끝났으면 그 대화방)
        .onChange(of: session.pendingLaunchDestination, initial: true) { _, destination in
            guard let destination else { return }
            session.pendingLaunchDestination = nil
            switch destination {
            case .ticket(let ticketId, _) where launch.activeTicket?.id == ticketId:
                selectedTab = .shoot
            case .ticket(_, let roomId), .room(let roomId):
                launch.chatPath = [roomId]
                selectedTab = .chat
            }
        }
        .onChange(of: launch.requestedTab) { _, tab in
            guard let tab else { return }
            launch.requestedTab = nil
            selectedTab = tab
        }
        // 촬영 중에는 홈으로 돌아가지 않게 티켓 화면을 경로에 둔다.
        .onChange(of: session.ticket?.id, initial: true) { _, ticketID in
            if let ticketID {
                if path.last != .live(ticketID) {
                    path = [.live(ticketID)]
                    selectedTab = .shoot
                }
            } else if case .live = path.last {
                path = []
            }
        }
        .onChange(of: session.pendingRoute) { _, route in
            guard let route else { return }
            session.pendingRoute = nil
            path = [route]
            selectedTab = .shoot
        }
    }

    @ViewBuilder
    private var shootTab: some View {
        if let ticket = launch.activeTicket {
            NavigationStack {
                PhotographerLaunchTicketView(ticket: ticket)
                    .id(ticket.id)
            }
        } else {
            mvpShootTab
        }
    }

    private var mvpShootTab: some View {
        NavigationStack(path: $path) {
            PhotographerHomeView()
                .navigationDestination(for: PhotographerRoute.self) { route in
                    switch route {
                    case .live: PhotographerTicketView()
                    case .gallery(let ticketID): GalleryRouteView(ticketID: ticketID)
                    }
                }
        }
    }
}
