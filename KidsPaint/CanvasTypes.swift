//
//  CanvasTypes.swift
//  KidsPaint by Fivethirty Softworks
//
//  Created by Cornelius on 12/18/25.
//

import SwiftUI

enum Tool: String, CaseIterable {
    case brush, eraser, sticker, pan
}

enum StickerType: String, CaseIterable, Identifiable, Hashable {
    case star, heart, smile, flower
    case sun, moon, cloud, bolt
    case balloon, crown, music, paw

    var id: String { rawValue }

    var systemName: String {
        switch self {
        case .star: return "star.fill"
        case .heart: return "heart.fill"
        case .smile: return "face.smiling.fill"
        case .flower: return "camera.macro"

        case .sun: return "sun.max.fill"
        case .moon: return "moon.stars.fill"
        case .cloud: return "cloud.fill"
        case .bolt: return "bolt.fill"

        case .balloon: return "balloon.2.fill"
        case .crown: return "crown.fill"
        case .music: return "music.note"
        case .paw: return "pawprint.fill"
        }
    }

    // Kept for future (you may not show labels in UI)
    var label: String { rawValue.capitalized }
}

struct Stroke: Identifiable, Hashable {
    let id: UUID
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
}

struct StickerStamp: Identifiable, Hashable {
    let id: UUID
    var type: StickerType
    var position: CGPoint
    var scale: CGFloat
    var rotationDegrees: Double
    var color: Color
}
