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
        VStack {
            Image(systemName: "camera")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("십분스냅 작가")
            Text(role.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
