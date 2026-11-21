//
//  ContentView.swift
//  sbsn
//
//  Created by 문주성 on 9/8/26.
//

import SwiftUI

/// 고객 앱의 하단 탭.
enum CustomerTab: Hashable {
    case shoot
    case photos
    case my
}

/// 고객 앱의 뿌리 화면. 로그인한 뒤 촬영 · 내 사진 · 마이 탭을 보여 준다.
///
/// 촬영 탭은 활성 티켓이 있으면 티켓 화면, 없으면 작가 지도다. 활성 티켓이 생기면(확정, 서버 잠금 복원) 촬영 탭으로 넘긴다.
/// 티켓의 오래 도는 작업은 탭 뷰 배경의 `TicketBackgroundWork`가 맡는다(다른 탭에 있어도 끊기지 않게).
struct ContentView: View {
    @State private var session = CustomerSession()
    @State private var workspaces = TicketWorkspaceStore()
    @State private var selectedTab = CustomerTab.shoot

    var body: some View {
        Group {
            switch session.phase {
            case .signingIn:
                ProgressView("로그인 중…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("로그인하지 못했습니다", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("다시 시도") {
                        Task { await session.start() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .ready:
                if let uid = session.uid {
                    tabs(uid: uid)
                }
            }
        }
        .environment(session)
        .task { await session.start() }
    }

    private func tabs(uid: String) -> some View {
        let workspace = workspaces.workspace(ticketId: session.activeTicketId, uid: uid)
        return TabView(selection: $selectedTab) {
            Group {
                if let workspace {
                    // 티켓이 바뀌면 화면 상태도 새로 만든다.
                    CustomerTicketView(workspace: workspace)
                        .id(workspace.ticketId)
                } else {
                    PhotographerMapView(myUid: uid)
                }
            }
            .tabItem { Label("촬영", systemImage: "camera") }
            .tag(CustomerTab.shoot)

            MyPhotosTab(selectedTab: $selectedTab)
                .tabItem { Label("내 사진", systemImage: "photo.on.rectangle") }
                .tag(CustomerTab.photos)

            CustomerMyTab()
                .tabItem { Label("마이", systemImage: "person.crop.circle") }
                .tag(CustomerTab.my)
        }
        .background {
            if let workspace {
                TicketBackgroundWork(workspace: workspace)
                    .id(workspace.ticketId)
            }
        }
        .onChange(of: session.activeTicketId) { _, ticketId in
            if ticketId != nil {
                selectedTab = .shoot
            }
        }
    }
}

#Preview {
    ContentView()
}
