//
//  CanvasTypes.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

enum Tool: String, CaseIterable {
    case brush, eraser, sticker, pan
}

enum BrushTip: String, CaseIterable, Identifiable, Hashable {
    case round, square, spray
    case chisel, crayon, neon

    var id: String { rawValue }
    
    var assetName: String { "tip_" + rawValue }

    var label: String {
        switch self {
        case .round: return "Round"
        case .square: return "Square"
        case .spray: return "Spray"
        case .chisel: return "Chisel"
        case .crayon: return "Crayon"
        case .neon: return "Neon"
        }
    }

    var systemImage: String {
        switch self {
        case .round: return "circle.fill"
        case .square: return "square.fill"
        case .spray: return "dot.radiowaves.left.and.right"
        case .chisel: return "rectangle.rotate"
        case .crayon: return "scribble"
        case .neon: return "sparkles"
        }
    }
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

    var label: String { rawValue.capitalized }
}

struct Stroke: Identifiable, Hashable {
    let id: UUID
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
    var tip: BrushTip
}

struct StickerStamp: Identifiable, Hashable {
    let id: UUID
    var type: StickerType
    var position: CGPoint
    var scale: CGFloat
    var rotationDegrees: Double
    var color: Color
}

