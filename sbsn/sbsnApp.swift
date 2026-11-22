//
//  sbsnApp.swift
//  sbsn
//
//  Created by 문주성 on 9/8/26.
//

import SBSNBackend
import SBSNUI
import SwiftUI

@main
struct sbsnApp: App {
    @UIApplicationDelegateAdaptor(CustomerAppDelegate.self) private var appDelegate

    init() {
        Backend.configure()
        // 지도 키(앱 번들 SBSNSecrets.plist, 커밋하지 않음). 없으면 지도가 회색으로 보인다.
        GoogleMapsSetup.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
