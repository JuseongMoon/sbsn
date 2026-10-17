//
//  ContentView.swift
//  sbsn
//
//  Created by 문주성 on 9/8/26.
//

import SBSNCore
import SwiftUI

struct ContentView: View {
    private let role = AppRole.customer

    var body: some View {
        VStack {
            Image(systemName: "camera.viewfinder")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("십분스냅")
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
