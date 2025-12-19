//
//  DrawingCanvas.swift
//  KidsPaint by Fivethirty Softworks
//
//  Created by Cornelius on 12/18/25.
//
//
import SwiftUI
import AppKit

// MARK: - Mouse tracking view (hover point)

struct MouseTrackingView: NSViewRepresentable {
    var onMove: (CGPoint) -> Void
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = TrackingNSView()
        view.onMove = onMove
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TrackingNSView: NSView {
        var onMove: ((CGPoint) -> Void)?
        var onHover: ((Bool) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            let opts: NSTrackingArea.Options = [
                .activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited
            ]
            addTrackingArea(NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }

        override func mouseMoved(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            onMove?(p)
        }
    }
}

// MARK: - DrawingCanvas

struct DrawingCanvas: View {
    @Binding var strokes: [Stroke]
    @Binding var stickers: [StickerStamp]
    @Binding var selectedStickerID: UUID?

    // ✅ Viewport (pan/zoom)
    @Binding var viewScale: CGFloat
    @Binding var viewOffset: CGSize

    let brushColor: Color
    let brushSize: CGFloat
    let background: Color
    let backgroundImage: NSImage?

    let tool: Tool
    let onCommitStroke: (Stroke) -> Void
    let onPlaceSticker: (CGPoint) -> Void

    var showsSelectionUI: Bool = true

    @State private var currentStroke: Stroke? = nil
    @State private var hoverPointScreen: CGPoint? = nil
    @State private var hovering: Bool = false

    // Sticker manipulation state (screen space)
    @State private var dragStickerID: UUID? = nil
    @State private var dragStickerStartPosCanvas: CGPoint = .zero
    @State private var dragStartPointCanvas: CGPoint = .zero

    @State private var resizingStickerID: UUID? = nil
    @State private var resizingStartScale: CGFloat = 1
    @State private var resizingStartDistCanvas: CGFloat = 1

    @State private var rotatingStickerID: UUID? = nil
    @State private var rotatingStartDegrees: Double = 0
    @State private var rotatingStartAngleCanvas: CGFloat = 0

    // Pan gesture state
    @State private var panStartOffset: CGSize = .zero
    @State private var panStartPointScreen: CGPoint = .zero

    // Pinch state
    @State private var pinchStartScale: CGFloat = 1

    private let baseStickerSize: CGFloat = 90

    var body: some View {
        ZStack {
            MouseTrackingView(
                onMove: { p in hoverPointScreen = p },
                onHover: { h in
                    hovering = h
                    if !h { hoverPointScreen = nil }
                }
            )
            .allowsHitTesting(false)

            Canvas { context, size in
                // Background (not transformed)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))

                // Apply viewport transform to all drawable content
                var t = CGAffineTransform.identity
                t = t.translatedBy(x: viewOffset.width, y: viewOffset.height)
                t = t.scaledBy(x: viewScale, y: viewScale)
                context.concatenate(t)

                // Background image (draw in canvas space)
                if let nsImage = backgroundImage {
                    let img = Image(nsImage: nsImage)
                    let resolved = context.resolve(img)

                    let imgSize = nsImage.size
                    if imgSize.width > 0, imgSize.height > 0 {
                        // fit to *untransformed* size, but we're already in transformed space,
                        // so use size / scale so it fits visually.
                        let logicalSize = CGSize(width: size.width / viewScale, height: size.height / viewScale)

                        let s = min(logicalSize.width / imgSize.width, logicalSize.height / imgSize.height)
                        let drawSize = CGSize(width: imgSize.width * s, height: imgSize.height * s)
                        let drawOrigin = CGPoint(
                            x: (logicalSize.width - drawSize.width) / 2,
                            y: (logicalSize.height - drawSize.height) / 2
                        )
                        context.draw(resolved, in: CGRect(origin: drawOrigin, size: drawSize))
                    }
                }

                // Strokes + in-progress stroke
                for s in strokes { draw(stroke: s, in: &context) }
                if let s = currentStroke { draw(stroke: s, in: &context) }

                // Stickers
                for st in stickers { draw(sticker: st, in: &context) }
            }
            .contentShape(Rectangle())
            .onHover { isHovering in
                guard isHovering else { NSCursor.arrow.set(); return }
                switch tool {
                case .brush: NSCursor.crosshair.set()
                case .eraser: NSCursor.disappearingItem.set()
                case .sticker: NSCursor.dragCopy.set()
                case .pan: NSCursor.openHand.set()
                }
            }
            // ✅ Pan/zoom gestures layered safely
            .gesture(panOrDrawGesture)
            .simultaneousGesture(pinchGesture)

            // Selection UI overlay (in screen space)
            if showsSelectionUI, let sid = selectedStickerID, let st = stickers.first(where: { $0.id == sid }) {
                selectionOverlay(for: st)
            }

            // Brush preview (screen overlay, follows cursor)
            if hovering, let ps = hoverPointScreen, tool != .sticker, tool != .pan {
                let radius = max(4, brushSize / 2) * viewScale
                Circle()
                    .stroke(.primary.opacity(0.35), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(ps)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Gestures

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { m in
                if pinchStartScale == 0 { pinchStartScale = viewScale }
                // clamp
                viewScale = clamp(pinchStartScale * m, 0.25, 6.0)
            }
            .onEnded { _ in
                pinchStartScale = 0
            }
    }

    private var panOrDrawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let screenP = value.location
                let canvasP = screenToCanvas(screenP)

                // pan tool
                if tool == .pan {
                    if value.translation == .zero {
                        panStartOffset = viewOffset
                        panStartPointScreen = value.startLocation
                        NSCursor.closedHand.set()
                    }
                    let dx = screenP.x - panStartPointScreen.x
                    let dy = screenP.y - panStartPointScreen.y
                    viewOffset = CGSize(width: panStartOffset.width + dx, height: panStartOffset.height + dy)
                    return
                }

                // sticker transforms take priority
                if let id = dragStickerID { moveSticker(id: id, currentCanvasPoint: canvasP); return }
                if let id = resizingStickerID { resizeSticker(id: id, currentCanvasPoint: canvasP); return }
                if let id = rotatingStickerID { rotateSticker(id: id, currentCanvasPoint: canvasP); return }

                // first contact: sticker hit test (canvas space)
                if value.translation == .zero {
                    if let hit = hitTestSticker(atCanvas: canvasP) {
                        selectedStickerID = hit.id
                        beginDragSticker(hit, startCanvasPoint: canvasP)
                        return
                    } else {
                        selectedStickerID = nil
                        if tool == .sticker { return }
                    }
                }

                // drawing
                if tool == .sticker { return }
                if currentStroke == nil {
                    currentStroke = Stroke(id: UUID(), points: [canvasP], color: brushColor, lineWidth: brushSize)
                } else {
                    currentStroke?.points.append(canvasP)
                }
            }
            .onEnded { value in
                let screenP = value.location
                let canvasP = screenToCanvas(screenP)

                if tool == .pan { NSCursor.openHand.set(); return }

                if dragStickerID != nil { dragStickerID = nil; return }
                if resizingStickerID != nil { resizingStickerID = nil; return }
                if rotatingStickerID != nil { rotatingStickerID = nil; return }

                if tool == .sticker {
                    if hitTestSticker(atCanvas: canvasP) == nil {
                        onPlaceSticker(canvasP)
                    }
                    return
                }

                guard var s = currentStroke else { return }
                currentStroke = nil
                guard s.points.count >= 2 else { return }
                s.color = brushColor
                s.lineWidth = brushSize
                onCommitStroke(s)
            }
    }

    // MARK: - Coordinate transform

    private func screenToCanvas(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: (p.x - viewOffset.width) / max(0.0001, viewScale),
            y: (p.y - viewOffset.height) / max(0.0001, viewScale)
        )
    }

    private func canvasToScreen(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: p.x * viewScale + viewOffset.width,
            y: p.y * viewScale + viewOffset.height
        )
    }

    // MARK: - Selection overlay + handles (screen space)

    private func selectionOverlay(for sticker: StickerStamp) -> some View {
        let sizeCanvas = baseStickerSize * sticker.scale
        let rectCanvas = CGRect(
            x: sticker.position.x - sizeCanvas / 2,
            y: sticker.position.y - sizeCanvas / 2,
            width: sizeCanvas,
            height: sizeCanvas
        )

        // convert to screen rect (axis aligned)
        let origin = canvasToScreen(rectCanvas.origin)
        let screenSize = CGSize(width: rectCanvas.size.width * viewScale, height: rectCanvas.size.height * viewScale)
        let rect = CGRect(origin: origin, size: screenSize)

        let centerScreen = canvasToScreen(sticker.position)

        return ZStack {
            Rectangle()
                .path(in: rect)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5, 4], dashPhase: 1))
                .foregroundStyle(.primary.opacity(0.55))
                .allowsHitTesting(false)

            RotateHandleView()
                .position(x: rect.midX, y: rect.minY - 22)
                .gesture(rotateHandleGesture(stickerID: sticker.id, centerCanvas: sticker.position))

            ResizeHandleView()
                .position(x: rect.maxX + 2, y: rect.maxY + 2)
                .gesture(resizeHandleGesture(stickerID: sticker.id, centerCanvas: sticker.position))

            // optional: a small center dot
            Circle()
                .fill(.primary.opacity(0.25))
                .frame(width: 5, height: 5)
                .position(centerScreen)
                .allowsHitTesting(false)
        }
    }

    private struct RotateHandleView: View {
        var body: some View {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.primary.opacity(0.35), lineWidth: 1))
                    .shadow(radius: 2)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .frame(width: 22, height: 22)
        }
    }

    private struct ResizeHandleView: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(.primary.opacity(0.35), lineWidth: 1))
                    .shadow(radius: 2)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.8))
            }
            .frame(width: 22, height: 22)
        }
    }

    private func resizeHandleGesture(stickerID: UUID, centerCanvas: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let canvasStart = screenToCanvas(value.startLocation)
                let canvasNow = screenToCanvas(value.location)

                if resizingStickerID == nil {
                    resizingStickerID = stickerID
                    selectedStickerID = stickerID
                    resizingStartScale = stickers.first(where: { $0.id == stickerID })?.scale ?? 1
                    resizingStartDistCanvas = max(10, distance(centerCanvas, canvasStart))
                }
                resizeSticker(id: stickerID, currentCanvasPoint: canvasNow, centerCanvas: centerCanvas)
            }
            .onEnded { _ in resizingStickerID = nil }
    }

    private func rotateHandleGesture(stickerID: UUID, centerCanvas: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let canvasStart = screenToCanvas(value.startLocation)
                let canvasNow = screenToCanvas(value.location)

                if rotatingStickerID == nil {
                    rotatingStickerID = stickerID
                    selectedStickerID = stickerID
                    rotatingStartDegrees = stickers.first(where: { $0.id == stickerID })?.rotationDegrees ?? 0
                    rotatingStartAngleCanvas = angle(centerCanvas, canvasStart)
                }
                rotateSticker(id: stickerID, currentCanvasPoint: canvasNow, centerCanvas: centerCanvas)
            }
            .onEnded { _ in rotatingStickerID = nil }
    }

    // MARK: - Sticker hit testing / manipulation (canvas space)

    private func hitTestSticker(atCanvas point: CGPoint) -> StickerStamp? {
        for st in stickers.reversed() {
            let size = baseStickerSize * st.scale
            let rect = CGRect(
                x: st.position.x - size / 2,
                y: st.position.y - size / 2,
                width: size,
                height: size
            )
            if rect.contains(point) { return st }
        }
        return nil
    }

    private func beginDragSticker(_ sticker: StickerStamp, startCanvasPoint: CGPoint) {
        dragStickerID = sticker.id
        dragStickerStartPosCanvas = sticker.position
        dragStartPointCanvas = startCanvasPoint
    }

    private func moveSticker(id: UUID, currentCanvasPoint: CGPoint) {
        let dx = currentCanvasPoint.x - dragStartPointCanvas.x
        let dy = currentCanvasPoint.y - dragStartPointCanvas.y
        updateSticker(id: id) { st in
            st.position = CGPoint(x: dragStickerStartPosCanvas.x + dx, y: dragStickerStartPosCanvas.y + dy)
        }
    }

    private func resizeSticker(id: UUID, currentCanvasPoint: CGPoint, centerCanvas: CGPoint? = nil) {
        let c = centerCanvas ?? (stickers.first(where: { $0.id == id })?.position ?? .zero)
        let d = max(10, distance(c, currentCanvasPoint))
        let factor = d / max(10, resizingStartDistCanvas)
        let newScale = clamp(resizingStartScale * factor, 0.35, 3.0)
        updateSticker(id: id) { st in st.scale = newScale }
    }

    private func rotateSticker(id: UUID, currentCanvasPoint: CGPoint, centerCanvas: CGPoint? = nil) {
        let c = centerCanvas ?? (stickers.first(where: { $0.id == id })?.position ?? .zero)
        let now = angle(c, currentCanvasPoint)
        let delta = now - rotatingStartAngleCanvas
        let degDelta = Double(delta * 180 / .pi)
        updateSticker(id: id) { st in st.rotationDegrees = rotatingStartDegrees + degDelta }
    }

    private func updateSticker(id: UUID, mutate: (inout StickerStamp) -> Void) {
        guard let idx = stickers.firstIndex(where: { $0.id == id }) else { return }
        var copy = stickers[idx]
        mutate(&copy)
        stickers[idx] = copy
    }

    // MARK: - Drawing

    private func draw(stroke: Stroke, in context: inout GraphicsContext) {
        guard stroke.points.count > 1 else { return }
        var path = Path()
        path.move(to: stroke.points[0])
        for pt in stroke.points.dropFirst() { path.addLine(to: pt) }
        context.stroke(path, with: .color(stroke.color),
                       style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
    }

    private func draw(sticker: StickerStamp, in context: inout GraphicsContext) {
        let text = Text(Image(systemName: sticker.type.systemName))
            .foregroundColor(sticker.color)
        let resolved = context.resolve(text)
        let radians = CGFloat(sticker.rotationDegrees) * .pi / 180.0

        context.drawLayer { layer in
            var t = CGAffineTransform.identity
            t = t.translatedBy(x: sticker.position.x, y: sticker.position.y)
            t = t.rotated(by: radians)
            t = t.scaledBy(x: sticker.scale, y: sticker.scale)
            layer.transform = t
            layer.draw(resolved, at: .zero, anchor: .center)
        }
    }

    // MARK: - Math

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
    private func angle(_ c: CGPoint, _ p: CGPoint) -> CGFloat { atan2(p.y - c.y, p.x - c.x) }
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }
}
