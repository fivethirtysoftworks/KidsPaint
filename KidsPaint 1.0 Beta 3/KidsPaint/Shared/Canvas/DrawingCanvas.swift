//
//  DrawingCanvas.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

// MARK: - Mouse tracking view (hover point)

#if os(macOS)
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

#endif

// MARK: - DrawingCanvas

struct DrawingCanvas: View {
    @Binding var strokes: [Stroke]
    @Binding var stickers: [StickerStamp]
    @Binding var selectedStickerID: UUID?

    // Viewport (pan/zoom)
    @Binding var viewScale: CGFloat
    @Binding var viewOffset: CGSize

    let brushColor: Color
    let brushSize: CGFloat
    let brushTip: BrushTip
    let background: Color
    let backgroundImage: PlatformImage?

    let tool: Tool
    let onCommitStroke: (Stroke) -> Void
    let onPlaceSticker: (CGPoint) -> Void


    var onCommitStickerTransform: (StickerStamp, StickerStamp) -> Void = { _, _ in }

    var showsSelectionUI: Bool = true

    // MARK: - Game controller input (macOS)
    // Cursor is in LOCAL (screen) coordinates of the canvas view.
    // When nil, controller input is inactive.
    var controllerCursorScreen: CGPoint? = nil
    var controllerIsDrawingPressed: Bool = false

    var controllerPlaceStickerToken: Int = 0

    @State private var currentStroke: Stroke? = nil
    @State private var hoverPointScreen: CGPoint? = nil
    @State private var hovering: Bool = false

    @State private var lastControllerPlaceStickerToken: Int = 0

    // Sticker manipulation state (screen space)
    @State private var dragStickerID: UUID? = nil
    @State private var dragStickerStartPosCanvas: CGPoint = .zero
    @State private var dragStartPointCanvas: CGPoint = .zero

    // Snapshots used to create a single undo step per gesture
    @State private var dragStickerStartStamp: StickerStamp? = nil

    @State private var resizingStickerID: UUID? = nil
    @State private var resizingStartScale: CGFloat = 1
    @State private var resizingStartDistCanvas: CGFloat = 1
    @State private var resizingStartStamp: StickerStamp? = nil

    @State private var rotatingStickerID: UUID? = nil
    @State private var rotatingStartDegrees: Double = 0
    @State private var rotatingStartAngleCanvas: CGFloat = 0
    @State private var rotatingStartStamp: StickerStamp? = nil

    // Pan gesture state
    @State private var panStartOffset: CGSize = .zero
    @State private var panStartPointScreen: CGPoint = .zero

    // Pinch state
    @State private var pinchStartScale: CGFloat = 1

    private let baseStickerSize: CGFloat = 90

    // Recolor palette for selected stickers
    private let stickerRecolorPalette: [Color] = [.black, .white, .red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]

    var body: some View {
        ZStack {
#if os(macOS)
            MouseTrackingView(
                onMove: { p in hoverPointScreen = p },
                onHover: { h in
                    hovering = h
                    if !h { hoverPointScreen = nil }
                }
            )
            .allowsHitTesting(false)
            #endif

            Canvas { context, size in
                // Background (not transformed)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))

                // Apply viewport transform to all drawable content
                var t = CGAffineTransform.identity
                t = t.translatedBy(x: viewOffset.width, y: viewOffset.height)
                t = t.scaledBy(x: viewScale, y: viewScale)
                context.concatenate(t)

                // Background image (draw in canvas space)
                if let img = backgroundImage {
                    #if os(macOS)
                    let swiftUIImage = Image(nsImage: img)
                    let imgSize = img.size
                    #else
                    let swiftUIImage = Image(uiImage: img)
                    let imgSize = img.size
                    #endif

                    let resolved = context.resolve(swiftUIImage)
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
#if os(macOS)
            .onHover { isHovering in
                guard isHovering else { NSCursor.arrow.set(); return }
                switch tool {
                case .brush: NSCursor.crosshair.set()
                case .eraser: NSCursor.disappearingItem.set()
                case .sticker: NSCursor.dragCopy.set()
                case .pan: NSCursor.openHand.set()
                }
            }
            #endif
            // Pan/zoom gestures layered safely
            .gesture(panOrDrawGesture)
            .simultaneousGesture(pinchGesture)

            // Selection UI overlay (in screen space)
            if showsSelectionUI, let sid = selectedStickerID, let st = stickers.first(where: { $0.id == sid }) {
                selectionOverlay(for: st)
            }

            // Brush preview (screen overlay, follows cursor)
            if hovering, let ps = hoverPointScreen, tool != .sticker, tool != .pan {
                let radius = max(4, brushSize / 2) * viewScale
                Group {
                    switch brushTip {
                    case .round, .spray, .crayon, .neon:
                        Circle()
                            .stroke(.primary.opacity(0.35), lineWidth: 1)
                            .frame(width: radius * 2, height: radius * 2)
                    case .square:
                        Rectangle()
                            .stroke(.primary.opacity(0.35), lineWidth: 1)
                            .frame(width: radius * 2, height: radius * 2)
                    case .chisel:
                        Rectangle()
                            .stroke(.primary.opacity(0.35), lineWidth: 1)
                            .frame(width: radius * 2, height: radius)
                            .rotationEffect(.degrees(30))
                    }
                }
                .position(ps)
                .allowsHitTesting(false)
            }

            // Controller cursor overlay (high-visibility)
            if let cp = controllerCursorScreen {
                ZStack {
                    // Black “outline” layer
                    ZStack {
                        Circle()
                            .stroke(Color.black.opacity(0.90), lineWidth: 4)
                            .frame(width: 34, height: 34)

                        Rectangle()
                            .fill(Color.black.opacity(0.90))
                            .frame(width: 22, height: 4)

                        Rectangle()
                            .fill(Color.black.opacity(0.90))
                            .frame(width: 4, height: 22)
                    }

                    // White “inner” layer
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.98), lineWidth: 2)
                            .frame(width: 34, height: 34)

                        Rectangle()
                            .fill(Color.white.opacity(0.98))
                            .frame(width: 22, height: 2)

                        Rectangle()
                            .fill(Color.white.opacity(0.98))
                            .frame(width: 2, height: 22)
                    }
                }
                .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                .position(cp)
                .allowsHitTesting(false)
            }
        }
        // Clear sticker selection when switching away from sticker tool
        .onChange(of: tool) { _, newTool in
            if newTool != .sticker {
                selectedStickerID = nil
                dragStickerID = nil
                resizingStickerID = nil
                rotatingStickerID = nil
            }
        }
        // MARK: - Controller -> canvas
        .onChange(of: controllerIsDrawingPressed) { _, pressed in
            guard let screenP = controllerCursorScreen else { return }
            guard tool != .sticker, tool != .pan else { return }
            let canvasP = screenToCanvas(screenP)

            if pressed {
                // Begin a stroke at current cursor.
                currentStroke = Stroke(id: UUID(), points: [canvasP], color: brushColor, lineWidth: brushSize, tip: brushTip)
            } else {
                // End + commit
                guard var s = currentStroke else { return }
                currentStroke = nil

                // If the user just tapped (no movement), synthesize a tiny segment so a dot renders.
                if s.points.count == 1 {
                    let p = s.points[0]
                    // Small offset in canvas space; effectively a dot at typical zoom levels.
                    s.points.append(CGPoint(x: p.x + 0.5, y: p.y))
                }

                guard s.points.count >= 2 else { return }
                s.color = brushColor
                s.lineWidth = brushSize
                s.tip = brushTip
                onCommitStroke(s)
            }
        }
        .onChange(of: controllerCursorScreen) { _, newValue in
            guard controllerIsDrawingPressed else { return }
            guard tool != .sticker, tool != .pan else { return }
            guard let screenP = newValue else { return }
            let canvasP = screenToCanvas(screenP)

            if currentStroke == nil {
                currentStroke = Stroke(id: UUID(), points: [canvasP], color: brushColor, lineWidth: brushSize, tip: brushTip)
            } else {
                currentStroke?.points.append(canvasP)
            }
        }
        .onChange(of: controllerPlaceStickerToken) { _, token in
            guard token != lastControllerPlaceStickerToken else { return }
            lastControllerPlaceStickerToken = token
            guard tool == .sticker else { return }
            guard let screenP = controllerCursorScreen else { return }
            let canvasP = screenToCanvas(screenP)
            if hitTestSticker(atCanvas: canvasP) == nil {
                onPlaceSticker(canvasP)
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

    private func selectionOverlay(for sticker: StickerStamp) -> some View {
        let sizeCanvas = baseStickerSize * sticker.scale
        let rectCanvas = CGRect(
            x: sticker.position.x - sizeCanvas / 2,
            y: sticker.position.y - sizeCanvas / 2,
            width: sizeCanvas,
            height: sizeCanvas
        )

        // Convert to screen space
        let origin = canvasToScreen(rectCanvas.origin)
        let screenSize = CGSize(
            width: rectCanvas.width * viewScale,
            height: rectCanvas.height * viewScale
        )
        let rect = CGRect(origin: origin, size: screenSize)

        // More aggressive inset to compensate for SF Symbols internal padding.
        // Clamped so it behaves across sticker sizes/zoom levels.
        let visualInset = min(44, max(8, rect.width * 0.28))
        let visualRect = rect.insetBy(dx: visualInset, dy: visualInset)

        // --- Scale handle size and gap with zoom ---
        let handleVisualScale = clamp(1 / viewScale, 0.6, 1.2)
        let handleSize: CGFloat = 22 * handleVisualScale
        let handleGap: CGFloat = 1 * handleVisualScale

        let centerScreen = canvasToScreen(sticker.position)

        return ZStack {
            // Delete handle (top-right corner)
            Button {
                // Remove sticker and clear selection
                stickers.removeAll { $0.id == sticker.id }
                if selectedStickerID == sticker.id { selectedStickerID = nil }
            } label: {
                DeleteHandleView()
                    .frame(width: handleSize, height: handleSize)
            }
            .buttonStyle(.plain)
            .position(
                x: visualRect.maxX + (handleSize / 2 + handleGap),
                y: visualRect.minY - (handleSize / 2 + handleGap)
            )
            .accessibilityLabel("Delete Sticker")

            // Rotate handle (just above top edge)
            RotateHandleView()
                .frame(width: handleSize, height: handleSize)
                .position(
                    x: visualRect.midX,
                    y: visualRect.minY - (handleSize / 2 + handleGap)
                )
                .gesture(
                    rotateHandleGesture(
                        stickerID: sticker.id,
                        centerCanvas: sticker.position
                    )
                )

            // Resize handle (bottom-right corner)
            ResizeHandleView()
                .frame(width: handleSize, height: handleSize)
                .position(
                    x: visualRect.maxX + (handleSize / 2 + handleGap),
                    y: visualRect.maxY + (handleSize / 2 + handleGap)
                )
                .gesture(
                    resizeHandleGesture(
                        stickerID: sticker.id,
                        centerCanvas: sticker.position
                    )
                )

            // Recolor palette (below sticker)
            HStack(spacing: 8) {
                ForEach(Array(stickerRecolorPalette.enumerated()), id: \.offset) { _, c in
                    Button {
                        updateSticker(id: sticker.id) { $0.color = c }
                    } label: {
                        Circle()
                            .fill(c)
                            .frame(width: handleSize * 0.8, height: handleSize * 0.8)
                            .overlay(
                                Circle().stroke(
                                    .primary.opacity(sticker.color == c ? 0.7 : 0.18),
                                    lineWidth: sticker.color == c ? 2 : 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.18), lineWidth: 1))
            .shadow(radius: 2)
            .position(
                x: visualRect.midX,
                y: visualRect.maxY + handleSize + (handleSize * 0.9)
            )

            // Center dot (debug / optional)
            Circle()
                .fill(.primary.opacity(0.25))
                .frame(width: 5, height: 5)
                .position(centerScreen)
                .allowsHitTesting(false)
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

    // (Duplicate selectionOverlay(for:) removed.)

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
        }
    }

    private struct DeleteHandleView: View {
        var body: some View {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.primary.opacity(0.35), lineWidth: 1))
                    .shadow(radius: 2)
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.8))
            }
        }
    }

    private var panOrDrawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let canvasStart = screenToCanvas(value.startLocation)
                let canvasNow = screenToCanvas(value.location)

                switch tool {
                case .pan:
                    if panStartPointScreen == .zero {
                        panStartPointScreen = value.startLocation
                        panStartOffset = viewOffset
                    }
                    let dx = value.location.x - panStartPointScreen.x
                    let dy = value.location.y - panStartPointScreen.y
                    viewOffset = CGSize(width: panStartOffset.width + dx, height: panStartOffset.height + dy)

                case .sticker:
                    // Drag existing sticker if we started on one; otherwise place on end.
                    if dragStickerID == nil {
                        if let hit = hitTestSticker(atCanvas: canvasStart) {
                            selectedStickerID = hit.id
                            beginDragSticker(hit, startCanvasPoint: canvasStart)
                        }
                    }
                    if let id = dragStickerID {
                        moveSticker(id: id, currentCanvasPoint: canvasNow)
                    }

                case .brush, .eraser:
                    if currentStroke == nil {
                        currentStroke = Stroke(
                            id: UUID(),
                            points: [canvasStart],
                            color: brushColor,
                            lineWidth: brushSize,
                            tip: brushTip
                        )
                    }
                    currentStroke?.points.append(canvasNow)
                }
            }
            .onEnded { value in
                let canvasStart = screenToCanvas(value.startLocation)
                let canvasEnd = screenToCanvas(value.location)

                switch tool {
                case .pan:
                    panStartPointScreen = .zero

                case .sticker:
                    if let id = dragStickerID {
                        if let startStamp = dragStickerStartStamp,
                           let endStamp = stickers.first(where: { $0.id == id }) {
                            onCommitStickerTransform(startStamp, endStamp)
                        }
                        dragStickerStartStamp = nil
                        dragStickerID = nil
                    } else {
                        // No drag happened; place a new sticker if we didn't start on one.
                        if hitTestSticker(atCanvas: canvasStart) == nil {
                            onPlaceSticker(canvasEnd)
                        }
                    }

                case .brush, .eraser:
                    guard var s = currentStroke else { return }
                    currentStroke = nil
                    guard s.points.count >= 2 else { return }
                    s.color = brushColor
                    s.lineWidth = brushSize
                    s.tip = brushTip
                    onCommitStroke(s)
                }
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
                    resizingStartStamp = stickers.first(where: { $0.id == stickerID })
                    resizingStartScale = stickers.first(where: { $0.id == stickerID })?.scale ?? 1
                    resizingStartDistCanvas = max(10, distance(centerCanvas, canvasStart))
                }
                resizeSticker(id: stickerID, currentCanvasPoint: canvasNow, centerCanvas: centerCanvas)
            }
            .onEnded { _ in
                if let start = resizingStartStamp,
                   let end = stickers.first(where: { $0.id == stickerID }) {
                    onCommitStickerTransform(start, end)
                }
                resizingStartStamp = nil
                resizingStickerID = nil
            }
    }

    private func rotateHandleGesture(stickerID: UUID, centerCanvas: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let canvasStart = screenToCanvas(value.startLocation)
                let canvasNow = screenToCanvas(value.location)

                if rotatingStickerID == nil {
                    rotatingStickerID = stickerID
                    selectedStickerID = stickerID
                    rotatingStartStamp = stickers.first(where: { $0.id == stickerID })
                    rotatingStartDegrees = stickers.first(where: { $0.id == stickerID })?.rotationDegrees ?? 0
                    rotatingStartAngleCanvas = angle(centerCanvas, canvasStart)
                }
                rotateSticker(id: stickerID, currentCanvasPoint: canvasNow, centerCanvas: centerCanvas)
            }
            .onEnded { _ in
                if let start = rotatingStartStamp,
                   let end = stickers.first(where: { $0.id == stickerID }) {
                    onCommitStickerTransform(start, end)
                }
                rotatingStartStamp = nil
                rotatingStickerID = nil
            }
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
        dragStickerStartStamp = sticker
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
        var degDelta = Double(delta * 180 / .pi)
        // Snap rotation if Shift is pressed
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.shift) {
            let unsnapped = rotatingStartDegrees + degDelta
            let snapAngle: Double = 15
            let snapped = (unsnapped / snapAngle).rounded() * snapAngle
            degDelta = snapped - rotatingStartDegrees
        }
        #endif
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

        switch stroke.tip {

        case .round, .square:
            var path = Path()
            path.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() { path.addLine(to: pt) }

            let cap: CGLineCap = (stroke.tip == .square) ? .square : .round
            context.stroke(
                path,
                with: .color(stroke.color),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: cap, lineJoin: .round)
            )

        case .spray:
            let baseRadius = max(1, stroke.lineWidth * 0.12)
            let spread = max(2, stroke.lineWidth * 0.55)
            let dotsPerPoint = max(6, Int(stroke.lineWidth * 0.35))

            for (i, p) in stroke.points.enumerated() {
                let seed = stableSeed(strokeID: stroke.id, index: i)
                var rng = LCG(seed: seed)

                for _ in 0..<dotsPerPoint {
                    let a = rng.nextUnit() * CGFloat.pi * 2
                    let r = sqrt(rng.nextUnit()) * spread
                    let dx = cos(a) * r
                    let dy = sin(a) * r

                    let dotR = baseRadius * (0.7 + 0.6 * rng.nextUnit())
                    let rect = CGRect(x: p.x + dx - dotR, y: p.y + dy - dotR, width: dotR * 2, height: dotR * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(stroke.color.opacity(0.28)))
                }
            }

        case .chisel:
            // Stamp a short angled rectangle along the path direction.
            // IMPORTANT: Build a transformed Path and fill it so it respects the current
            // viewport transform (pan/zoom) already applied to the GraphicsContext.
            let thickness = stroke.lineWidth
            let length = stroke.lineWidth * 1.6

            for i in 1..<stroke.points.count {
                let p0 = stroke.points[i - 1]
                let p1 = stroke.points[i]
                let a = atan2(p1.y - p0.y, p1.x - p0.x)

                let baseRect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
                var xform = CGAffineTransform.identity
                xform = xform.translatedBy(x: p1.x, y: p1.y)
                xform = xform.rotated(by: a + .pi / 6)

                let stamp = Path(baseRect).applying(xform)
                context.fill(stamp, with: .color(stroke.color))
            }

        case .crayon:
            // Textured round stroke: base stroke + grain pass
            var path = Path()
            path.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() { path.addLine(to: pt) }

            context.stroke(
                path,
                with: .color(stroke.color.opacity(0.85)),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )

            let grainDots = max(8, Int(stroke.lineWidth * 0.6))
            for (i, p) in stroke.points.enumerated() {
                let seed = stableSeed(strokeID: stroke.id, index: i)
                var rng = LCG(seed: seed)

                for _ in 0..<grainDots {
                    let a = rng.nextUnit() * CGFloat.pi * 2
                    let r = rng.nextUnit() * stroke.lineWidth * 0.45
                    let dx = cos(a) * r
                    let dy = sin(a) * r
                    let d: CGFloat = 1.2

                    let rect = CGRect(x: p.x + dx - d, y: p.y + dy - d, width: d * 2, height: d * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(stroke.color.opacity(0.25)))
                }
            }

        case .neon:
            // Glow: wide soft under-stroke + crisp core
            var path = Path()
            path.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() { path.addLine(to: pt) }

            context.stroke(
                path,
                with: .color(stroke.color.opacity(0.35)),
                style: StrokeStyle(lineWidth: stroke.lineWidth * 2.2, lineCap: .round, lineJoin: .round)
            )

            context.stroke(
                path,
                with: .color(stroke.color),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func draw(sticker: StickerStamp, in context: inout GraphicsContext) {
        let text = Text(Image(systemName: sticker.type.systemName))
            // Render at the same base size used by hit-testing/selection overlay.
            .font(.system(size: baseStickerSize, weight: .regular))
            .foregroundColor(sticker.color)
        let resolved = context.resolve(text)
        let radians = CGFloat(sticker.rotationDegrees) * .pi / 180.0

        var t = CGAffineTransform.identity
        t = t.translatedBy(x: sticker.position.x, y: sticker.position.y)
        t = t.rotated(by: radians)
        t = t.scaledBy(x: sticker.scale, y: sticker.scale)

        // IMPORTANT: Concatenate onto the current context so the parent viewport transform
        // (pan/zoom) remains in effect.
        var c = context
        c.concatenate(t)
        c.draw(resolved, at: .zero, anchor: .center)
    }

    // MARK: - Math

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
    private func angle(_ c: CGPoint, _ p: CGPoint) -> CGFloat { atan2(p.y - c.y, p.x - c.x) }
    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }

    // MARK: - Deterministic spray helpers

    private func stableSeed(strokeID: UUID, index: Int) -> UInt64 {
        let parts = strokeID.uuidString.utf8.reduce(UInt64(1469598103934665603)) { h, b in
            (h ^ UInt64(b)) &* 1099511628211
        }
        return parts ^ (UInt64(index) &* 0x9E3779B97F4A7C15)
    }

    private struct LCG {
        var state: UInt64
        init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1
            return state
        }

        mutating func nextUnit() -> CGFloat {
            let v = (next() >> 40) & 0xFFFFFF
            return CGFloat(v) / CGFloat(0x1000000)
        }
    }
}
