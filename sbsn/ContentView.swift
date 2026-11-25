//
//  ContentView.swift
//  sbsn
//
//  Created by 문주성 on 9/8/26.
//

import SBSNBackend
import SBSNCore
import SBSNUI
import SwiftUI

/// 고객 앱의 하단 탭.
enum CustomerTab: Hashable {
    case shoot
    case chat
    case photos
    case my
}

/// 고객 앱의 뿌리 화면. 촬영 · 채팅 · 내 사진 · 마이 탭(D066 S1).
///
/// 촬영 탭은 출시 티켓(시작 대기·촬영 중)이 있으면 그 티켓 화면, 없으면 작가 지도다. 매칭되면 촬영 탭으로 넘긴다.
/// 갤러리 v2 전까지 이전 방식 티켓(MVP, `tickets/`)은 그 화면을 그대로 쓴다(3단계에서 바꾼다).
/// 티켓의 오래 도는 작업은 탭 뷰 배경의 `TicketBackgroundWork`가 맡는다(다른 탭에 있어도 끊기지 않게).
struct ContentView: View {
    @State private var session = CustomerSession()
    @State private var workspaces = TicketWorkspaceStore()
    @State private var galleries = GalleryStore()
    @State private var selectedTab = CustomerTab.shoot
    @State private var photosPath: [String] = []
    @State private var launch = CustomerLaunchModel()
    private let router = CustomerNotificationRouter.shared

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
        // 계정 삭제 뒤 안내. 로그아웃으로 탭이 다시 그려져도 보이게 뿌리에 둔다.
        .accountDeletionNotice(Binding(get: { session.accountNotice }, set: { session.accountNotice = $0 }))
        .launchToast(Binding(get: { launch.toast }, set: { launch.toast = $0 }))
        .environment(session)
        .environment(galleries)
        .environment(launch)
        .task { await session.start() }
        // 출시 대화·신청·티켓은 연결된 계정만 듣는다(규칙). 익명 → 연결은 uid가 같아 계정 판수로 다시 본다.
        .task(id: "\(session.uid ?? "-")#\(session.accountRevision)") {
            launch.start(uid: AccountService.current?.isLinked == true ? session.uid : nil)
            await LaunchPush.registerIfLinked(role: .customer)
        }
        .task(id: session.uid) {
            if let uid = session.uid { await galleries.start(uid: uid) }
        }
    }

    private func tabs(uid: String) -> some View {
        let workspace = workspaces.workspace(ticketId: session.activeTicketId, uid: uid)
        return TabView(selection: $selectedTab) {
            Group {
                if let ticket = launch.activeTicket {
                    CustomerLaunchTicketView(ticket: ticket)
                        .id(ticket.id)
                } else if let workspace {
                    // 티켓이 바뀌면 화면 상태도 새로 만든다.
                    CustomerTicketView(workspace: workspace)
                        .id(workspace.ticketId)
                } else {
                    PhotographerMapView()
                }
            }
            .tabItem { Label("촬영", systemImage: "camera") }
            .tag(CustomerTab.shoot)

            CustomerChatTab()
                .tabItem { Label("채팅", systemImage: "bubble.left.and.bubble.right") }
                .badge(launch.totalUnread)
                .tag(CustomerTab.chat)

            MyPhotosTab(selectedTab: $selectedTab, path: $photosPath)
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
        .onChange(of: launch.activeTicket?.id) { _, ticketId in
            if ticketId != nil {
                selectedTab = .shoot
            }
        }
        // 출시 알림을 누르면: 대화방은 채팅 탭에서 그 방, 진행 중 티켓은 촬영 탭(끝났으면 그 대화방)
        .onChange(of: router.pendingLaunchDestination, initial: true) { _, destination in
            guard let destination else { return }
            router.pendingLaunchDestination = nil
            switch destination {
            case .ticket(let ticketId, _) where launch.activeTicket?.id == ticketId:
                selectedTab = .shoot
            case .ticket(_, let roomId), .room(let roomId):
                launch.chatPath = [roomId]
                selectedTab = .chat
            case .gallery(let ticketId), .galleryPhoto(let ticketId, _):
                // 보정본 알림(galleryPhoto)은 3단계 고객 갤러리 화면에서 그 사진을 바로 연다(지금은 그 촬영까지).
                // 3단계 갤러리 v2 화면이 들어오기 전에는 내 사진 탭의 그 촬영으로 간다.
                galleries.remember(ticketId)
                photosPath = [ticketId]
                selectedTab = .photos
            }
        }
        .onChange(of: launch.requestedTab) { _, tab in
            guard let tab else { return }
            launch.requestedTab = nil
            selectedTab = tab
        }
        // 공개 알림을 누르면 그 갤러리로 간다. 진행 중인 촬영이면 촬영 탭이 이미 그 화면이다.
        .onChange(of: router.pendingGalleryTicketID, initial: true) { _, ticketID in
            guard let ticketID else { return }
            router.pendingGalleryTicketID = nil
            galleries.remember(ticketID)
            if session.activeTicketId == ticketID {
                selectedTab = .shoot
            } else {
                photosPath = [ticketID]
                selectedTab = .photos
            }
        }
    }
}

#Preview {
    ContentView()
}
