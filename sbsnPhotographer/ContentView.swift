//
//  ContentView.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

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
/// 수신·업로드·위치는 화면이 아니라 `PhotographerSession.shared`가 돌려서 탭을 바꿔도 끊기지 않는다.
/// 매칭되면(알림 탭 또는 presence 리스너) 촬영 탭으로 넘어가 티켓 화면을 연다.
struct ContentView: View {
    @Environment(PhotographerSession.self) private var session
    @State private var path: [String] = []
    @State private var selectedTab = PhotographerTab.shoot
    /// 맥에서 측정을 자동으로 돌릴 때 실행 인자(-SBSNOpenTransferTest YES)로 측정 화면을 바로 연다(-SBSNTicketID와 함께).
    @State private var opensTransferTest = UserDefaults.standard.bool(forKey: "SBSNOpenTransferTest")

    var body: some View {
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
            if let ticketID, path.last != ticketID, !opensTransferTest {
                path = [ticketID]
                selectedTab = .shoot
            } else if ticketID == nil {
                path = []
            }
        }
        .onChange(of: session.pendingTicketID) { _, ticketID in
            guard let ticketID else { return }
            session.pendingTicketID = nil
            if session.ticket?.id == ticketID {
                path = [ticketID]
                selectedTab = .shoot
            }
        }
    }

    private var shootTab: some View {
        NavigationStack(path: $path) {
            PhotographerHomeView()
                .navigationDestination(for: String.self) { _ in
                    PhotographerTicketView()
                }
                .navigationDestination(isPresented: Binding(
                    get: { opensTransferTest && session.delivery != nil },
                    set: { opensTransferTest = $0 }
                )) {
                    if let delivery = session.delivery {
                        CameraTransferTestView(model: delivery, showsMeasurements: true)
                    }
                }
        }
    }
}
