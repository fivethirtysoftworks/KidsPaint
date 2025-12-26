//
//  KidsPaintApp.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 2, Beta 2
//  Updated 12/25/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

@main
struct KidsPaintApp: App {
    @StateObject private var controllerManager = GameControllerManager()
    @State private var showSplash = true
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(controllerManager)
                
                if showSplash {
                    LaunchSplashOverlay {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
        }
        .commands {
            // Replace default App Info menu to open About window
            CommandGroup(replacing: .appInfo) {
                Button {
                    openWindow(id: "about")
                } label: {
                    Text("About KidsPaint")
                }
            }
            KidsPaintCommands()
        }
        
        // About window
        Window("About KidsPaint", id: "about") {
            AboutView()
        }
        
        // User Guide window
        Window("User Guide", id: "user-guide") {
            UserGuideView()
        }
        .defaultSize(width: 600, height: 700)
        .windowResizability(.contentSize)
    }
}
