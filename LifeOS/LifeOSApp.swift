//
//  LifeOSApp.swift
//  LifeOS
//
//  Created by Tanmay Roy on 12/22/25.
//

import SwiftUI

@main
struct LifeOSApp: App {
    init() {
        NotificationService.shared.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
