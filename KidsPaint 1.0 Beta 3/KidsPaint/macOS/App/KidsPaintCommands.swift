//
//  KidsPaintCommands.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

struct KidsPaintCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("KidsPaint User Guide") {
                openWindow(id: "user-guide")
            }
            .keyboardShortcut("?", modifiers: [.command, .shift]) // optional
        }
    }
}
