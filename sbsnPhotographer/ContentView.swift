//
//  ContentView.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SBSNCore
import SwiftUI

struct ContentView: View {
    @Environment(PhotographerSession.self) private var session
    @State private var path: [String] = []
    /// 맥에서 측정을 자동으로 돌릴 때 실행 인자(-SBSNOpenTransferTest YES)로 측정 화면을 바로 연다(-SBSNTicketID와 함께).
    @State private var opensTransferTest = UserDefaults.standard.bool(forKey: "SBSNOpenTransferTest")

    var body: some View {
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
        // 매칭되면(알림 탭 또는 presence 리스너) 티켓 화면으로 간다. 촬영 중에는 홈으로 돌아가지 않게 막는다.
        .onChange(of: session.ticket?.id, initial: true) { _, ticketID in
            if let ticketID, path.last != ticketID, !opensTransferTest {
                path = [ticketID]
            } else if ticketID == nil {
                path = []
            }
        }
        .onChange(of: session.pendingTicketID) { _, ticketID in
            guard let ticketID else { return }
            session.pendingTicketID = nil
            if session.ticket?.id == ticketID {
                path = [ticketID]
            }
        }
    }
}
