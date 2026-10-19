//
//  sbsnPhotographerApp.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SBSNBackend
import SwiftUI

@main
struct sbsnPhotographerApp: App {
    init() {
        Backend.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
