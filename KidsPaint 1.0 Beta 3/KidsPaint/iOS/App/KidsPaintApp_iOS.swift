//
//  KidsPaintApp_iOS.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

#if os(iOS)
@main
struct KidsPaintApp_iOS: App {
    @StateObject private var controllerManager = GameControllerManager()
    @State private var showSplash = true
    

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView_iOS()
                    .environmentObject(controllerManager)
                    .preferredColorScheme(.light)

                if showSplash {
                    LaunchSplashOverlay {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showSplash = false
                        }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
        }
    }
}
#endif
