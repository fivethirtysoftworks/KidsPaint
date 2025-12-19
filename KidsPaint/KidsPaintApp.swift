//
//  KidsPaintApp.swift
//  KidsPaint by Fivethirty Softworks
//
//  Created by Cornelius on 12/18/25.
//

import SwiftUI

@main
struct KidsPaintApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        // User Guide window
        Window("User Guide", id: "user-guide") {
            UserGuideView()
        }
        .defaultSize(width: 600, height: 700)
        .windowResizability(.contentSize)
        .commands {
            KidsPaintCommands()
        }
    }
}
