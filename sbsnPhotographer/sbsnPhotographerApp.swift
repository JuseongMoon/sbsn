//
//  sbsnPhotographerApp.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SwiftUI

@main
struct sbsnPhotographerApp: App {
    @UIApplicationDelegateAdaptor(PhotographerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(PhotographerSession.shared)
        }
    }
}
