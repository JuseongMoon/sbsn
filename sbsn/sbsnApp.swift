//
//  sbsnApp.swift
//  sbsn
//
//  Created by 문주성 on 9/8/26.
//

import SBSNBackend
import SwiftUI

@main
struct sbsnApp: App {
    init() {
        Backend.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
