//
//  ContentView.swift
//  sbsn
//
//  Created by 문주성 on 9/8/26.
//

import SwiftUI

/// 고객 앱의 뿌리 화면. 로그인한 뒤 활성 티켓이 있으면 티켓 화면, 없으면 작가 지도를 보여 준다.
struct ContentView: View {
    @State private var session = CustomerSession()

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
                    if let ticketId = session.activeTicketId {
                        // 티켓이 바뀌면 화면 상태(리스너·사진 캐시)도 새로 만든다.
                        CustomerTicketView(ticketId: ticketId, myUid: uid)
                            .id(ticketId)
                    } else {
                        PhotographerMapView(myUid: uid)
                    }
                }
            }
        }
        .environment(session)
        .task { await session.start() }
    }
}

#Preview {
    ContentView()
}
