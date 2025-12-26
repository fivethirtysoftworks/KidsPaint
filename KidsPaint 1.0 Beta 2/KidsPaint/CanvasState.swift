//
//  CanvasState.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 2, Beta 2
//  Updated 12/24/25
//  Created by Cornelius on 12/18/25.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class CanvasState: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var stickers: [StickerStamp] = []
    @Published var canvasBackground: Color = .white
    @Published var backgroundImage: NSImage? = nil

    // MARK: - Stroke ops

    func addStroke(_ stroke: Stroke, undoManager: UndoManager?) {
        strokes.append(stroke)
        undoManager?.registerUndo(withTarget: self) { target in
            target.removeStroke(id: stroke.id, undoManager: undoManager)
        }
        undoManager?.setActionName("Stroke")
    }

    func removeStroke(id: UUID, undoManager: UndoManager?) {
        guard let idx = strokes.firstIndex(where: { $0.id == id }) else { return }
        let removed = strokes.remove(at: idx)

        undoManager?.registerUndo(withTarget: self) { target in
            target.insertStroke(removed, at: idx, undoManager: undoManager)
        }
        undoManager?.setActionName("Undo Stroke")
    }

    private func insertStroke(_ stroke: Stroke, at index: Int, undoManager: UndoManager?) {
        let i = max(0, min(index, strokes.count))
        strokes.insert(stroke, at: i)

        undoManager?.registerUndo(withTarget: self) { target in
            target.removeStroke(id: stroke.id, undoManager: undoManager)
        }
        undoManager?.setActionName("Redo Stroke")
    }

    // MARK: - Sticker ops

    func addSticker(_ sticker: StickerStamp, undoManager: UndoManager?) {
        stickers.append(sticker)
        undoManager?.registerUndo(withTarget: self) { target in
            target.removeSticker(id: sticker.id, undoManager: undoManager)
        }
        undoManager?.setActionName("Sticker")
    }

    func removeSticker(id: UUID, undoManager: UndoManager?) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        let removed = stickers.remove(at: idx)

        undoManager?.registerUndo(withTarget: self) { target in
            target.insertSticker(removed, at: idx, undoManager: undoManager)
        }
        undoManager?.setActionName("Undo Sticker")
    }

    private func insertSticker(_ sticker: StickerStamp, at index: Int, undoManager: UndoManager?) {
        let i = max(0, min(index, stickers.count))
        stickers.insert(sticker, at: i)

        undoManager?.registerUndo(withTarget: self) { target in
            target.removeSticker(id: sticker.id, undoManager: undoManager)
        }
        undoManager?.setActionName("Redo Sticker")
    }

    // MARK: - Canvas ops

    func clearCanvas(undoManager: UndoManager?) {
        let prevStrokes = strokes
        let prevStickers = stickers

        strokes = []
        stickers = []

        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreCanvas(strokes: prevStrokes, stickers: prevStickers, undoManager: undoManager)
        }
        undoManager?.setActionName("Clear Canvas")
    }

    private func restoreCanvas(strokes: [Stroke], stickers: [StickerStamp], undoManager: UndoManager?) {
        let curStrokes = self.strokes
        let curStickers = self.stickers

        self.strokes = strokes
        self.stickers = stickers

        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreCanvas(strokes: curStrokes, stickers: curStickers, undoManager: undoManager)
        }
        undoManager?.setActionName("Restore Canvas")
    }

    func setBackgroundImage(_ newImage: NSImage?, undoManager: UndoManager?) {
        let prev = backgroundImage
        backgroundImage = newImage

        undoManager?.registerUndo(withTarget: self) { target in
            target.setBackgroundImage(prev, undoManager: undoManager)
        }
        undoManager?.setActionName(newImage == nil ? "Remove Background" : "Set Background")
    }

    func setCanvasBackground(_ newColor: Color, undoManager: UndoManager?) {
        let prev = canvasBackground
        canvasBackground = newColor

        undoManager?.registerUndo(withTarget: self) { target in
            target.setCanvasBackground(prev, undoManager: undoManager)
        }
        undoManager?.setActionName("Background Color")
    }

    /// Commit a single undo step for sticker move/resize/rotate.
    /// Call this once at the end of a gesture (not continuously during drag).
    func commitStickerTransform(from old: StickerStamp, to new: StickerStamp, undoManager: UndoManager?) {
        guard !stickerTransformEquals(old, new) else { return }

        // The UI likely already applied `new`; we just need to register undo/redo.
        undoManager?.registerUndo(withTarget: self) { target in
            target.applyStickerStamp(old)
            undoManager?.registerUndo(withTarget: target) { target2 in
                target2.applyStickerStamp(new)
            }
        }
        undoManager?.setActionName("Sticker Transform")
    }

    private func applyStickerStamp(_ stamp: StickerStamp) {
        guard let idx = stickers.firstIndex(where: { $0.id == stamp.id }) else { return }
        stickers[idx] = stamp
    }

    private func stickerTransformEquals(_ a: StickerStamp, _ b: StickerStamp) -> Bool {
        a.id == b.id &&
        a.position == b.position &&
        a.scale == b.scale &&
        a.rotationDegrees == b.rotationDegrees
    }
}
