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
        }
    }
}

#Preview {
    ContentView()
}
