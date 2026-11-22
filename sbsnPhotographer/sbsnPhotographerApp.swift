//
//  sbsnPhotographerApp.swift
//  sbsnPhotographer
//
//  Created by 문주성 on 10/17/26.
//

import SBSNUI
import SwiftUI

@main
struct sbsnPhotographerApp: App {
    @UIApplicationDelegateAdaptor(PhotographerAppDelegate.self) private var appDelegate

    init() {
        // 지도 키(앱 번들 SBSNSecrets.plist, 커밋하지 않음). 없으면 지도가 회색으로 보인다.
        GoogleMapsSetup.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(PhotographerSession.shared)
        }
    }
}
