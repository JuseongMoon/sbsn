//
//  ContentView.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SBSNCore
import SwiftUI

struct ContentView: View {
    private let role = AppRole.photographer
    /// 맥에서 비교 측정을 자동으로 돌릴 때 실행 인자(-SBSNOpenTransferTest YES)로 실증 화면을 바로 연다.
    @State private var opensTransferTest = UserDefaults.standard.bool(forKey: "SBSNOpenTransferTest")

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack {
                    Image(systemName: "camera")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    Text("십분스냅 작가")
                    Text(role.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NavigationLink("카메라 전송 실증") {
                    CameraTransferTestView()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationDestination(isPresented: $opensTransferTest) {
                CameraTransferTestView()
            }
        }
    }
}

#Preview {
    ContentView()
}
