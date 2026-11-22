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
    case history
    case my
}

/// 작가 앱의 뿌리 화면: 촬영 · 내역 · 마이 탭.
///
/// 업로드·위치는 화면이 아니라 `PhotographerSession.shared`가 돌려서 탭을 바꿔도 끊기지 않는다.
/// 매칭되면(알림 탭 또는 presence 리스너) 촬영 탭으로 넘어가 티켓 화면을 열고, 촬영이 끝나면 사진 고르기 화면으로 간다.
struct ContentView: View {
    @Environment(PhotographerSession.self) private var session
    @State private var path: [PhotographerRoute] = []
    @State private var selectedTab = PhotographerTab.shoot

    var body: some View {
        @Bindable var session = session
        Group {
            if Backend.usesLaunchFeatures && session.account?.isLinked != true {
                // 출시 1단계(D051·D059): 작가 앱은 Google·Apple로 로그인한 뒤 쓴다. 개발용 에뮬레이터를 쓸 때만(sbsn-dev는 지금의 익명 MVP 그대로).
                SignInSheet(allowsLater: false) { nickname in
                    UserDefaults.standard.set(nickname, forKey: "SBSNLaunchNickname")
                    Task { await session.accountDidChange(nickname: nickname) }
                }
            } else {
                tabs
            }
        }
        // 계정 삭제 뒤 알림. 탭이 로그인 관문으로 바뀌어도 보이게 뿌리에 둔다.
        .alert(session.accountNotice ?? "", isPresented: Binding(
            get: { session.accountNotice != nil },
            set: { if !$0 { session.accountNotice = nil } }
        )) {
            Button("확인", role: .cancel) {}
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            shootTab
                .tabItem { Label("촬영", systemImage: "camera") }
                .tag(PhotographerTab.shoot)
            PhotographerHistoryTab()
                .tabItem { Label("내역", systemImage: "list.bullet.rectangle") }
                .tag(PhotographerTab.history)
            PhotographerMyTab()
                .tabItem { Label("마이", systemImage: "person.crop.circle") }
                .tag(PhotographerTab.my)
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

    private var shootTab: some View {
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
