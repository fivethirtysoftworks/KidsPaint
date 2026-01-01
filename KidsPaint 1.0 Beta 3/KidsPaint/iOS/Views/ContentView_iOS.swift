//
//  ContentView_iOS.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

private extension Color {
    /// KidsPaint “logo purple” (matches the app logo)
    static let kidsPaintPurple = Color(red: 0.43, green: 0.40, blue: 0.86)
}

struct ContentView_iOS: View {
    @StateObject private var canvasState = CanvasState()
    @Environment(\.undoManager) private var undoManager
    @State private var capturedUndoManager: UndoManager? = nil
    @State private var canvasFocused: Bool = true
    @StateObject private var controllerManager = GameControllerManager()

    @State private var selectedStickerID: UUID? = nil

    @State private var viewScale: CGFloat = 1.0
    @State private var viewOffset: CGSize = .zero

    @State private var tool: Tool = .brush
    @State private var selectedColor: Color = .black
    @State private var brushSize: CGFloat = 18
    @State private var brushTip: BrushTip = .round

    @State private var selectedSticker: StickerType = .star
    @State private var stickerSize: CGFloat = 256
    @State private var stickerRotation: Angle = .degrees(0)

    @State private var showClearConfirm = false
    @State private var showPicker = false
    @State private var pickedItem: PhotosPickerItem? = nil

    private var brushColor: Color {
        tool == .eraser ? canvasState.canvasBackground : selectedColor
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kidsPaintPurple
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    GeometryReader { geo in
                        DrawingCanvas(
                            strokes: $canvasState.strokes,
                            stickers: $canvasState.stickers,
                            selectedStickerID: $selectedStickerID,
                            viewScale: $viewScale,
                            viewOffset: $viewOffset,
                            brushColor: brushColor,
                            brushSize: brushSize,
                            brushTip: brushTip,
                            background: canvasState.canvasBackground,
                            backgroundImage: canvasState.backgroundImage,
                            tool: tool,
                            onCommitStroke: { stroke in
                                canvasState.addStroke(stroke, undoManager: capturedUndoManager)
                            },
                            onPlaceSticker: { canvasPoint in
                                let stamp = StickerStamp(
                                    id: UUID(),
                                    type: selectedSticker,
                                    position: canvasPoint,
                                    scale: stickerSize / 90.0,
                                    rotationDegrees: stickerRotation.degrees,
                                    color: selectedColor
                                )
                                canvasState.addSticker(stamp, undoManager: capturedUndoManager)
                                selectedStickerID = stamp.id
                            },
                            onCommitStickerTransform: { start, end in
                                canvasState.commitStickerTransform(from: start, to: end, undoManager: capturedUndoManager)
                            },
                            controllerCursorScreen: controllerManager.isConnected ? controllerManager.cursor : nil,
                            controllerIsDrawingPressed: controllerManager.isDrawingPressed,
                            controllerPlaceStickerToken: controllerManager.placeStickerToken
                        )
                        .onAppear { controllerManager.canvasSize = geo.size }
                        .onChange(of: geo.size) { _, newSize in
                            controllerManager.canvasSize = newSize
                        }
                    }

                    Divider()
                    bottomControlBar
                }
                // Move toolbar/controller/other modifiers here to apply to VStack:
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { tool = .brush } label: {
                            Image(systemName: "paintbrush.fill")
                                .foregroundStyle(iconColor(active: tool == .brush))
                        }
                        Button { tool = .eraser } label: {
                            Image(systemName: "eraser.fill")
                                .foregroundStyle(iconColor(active: tool == .eraser))
                        }
                        Button { tool = .sticker } label: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(iconColor(active: tool == .sticker))
                        }
                        Button { tool = .pan } label: {
                            Image(systemName: "hand.draw")
                                .foregroundStyle(iconColor(active: tool == .pan))
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            capturedUndoManager?.undo()
                        } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!(capturedUndoManager?.canUndo ?? false))

                        Button {
                            capturedUndoManager?.redo()
                        } label: { Image(systemName: "arrow.uturn.forward") }
                        .disabled(!(capturedUndoManager?.canRedo ?? false))

                        Button { resetView() } label: { Image(systemName: "arrow.counterclockwise") }
                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            Image(systemName: "photo.on.rectangle")
                        }
                        Button { exportPNG() } label: { Image(systemName: "square.and.arrow.up") }
                        Button(role: .destructive) { showClearConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                        .confirmationDialog("Clear everything?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                            Button("Clear Canvas", role: .destructive) {
                                canvasState.clearCanvas(undoManager: capturedUndoManager)
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This will remove all brush strokes and stickers.")
                        }
                    }
                }
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                // Controller -> app actions (match macOS)
                .onChange(of: controllerManager.toolCommand) { _, cmd in
                    switch cmd {
                    case .setBrush: tool = .brush
                    case .setEraser: tool = .eraser
                    case .setSticker: tool = .sticker
                    case .setPan: tool = .pan
                    case .none: break
                    }
                    if cmd != .none { controllerManager.toolCommand = .none }
                }
                .onChange(of: controllerManager.brushSizeDelta) { _, delta in
                    guard delta != 0 else { return }
                    if tool == .sticker {
                        stickerSize = min(420, max(64, stickerSize + (delta * 8)))
                    } else {
                        brushSize = min(80, max(2, brushSize + delta))
                    }
                    controllerManager.brushSizeDelta = 0
                }
                .onChange(of: controllerManager.zoomDelta) { _, delta in
                    guard delta != 0 else { return }
                    // Smooth multiplicative zoom
                    viewScale = min(6.0, max(0.25, viewScale * (1.0 + delta)))
                    controllerManager.zoomDelta = 0
                }
                .onChange(of: controllerManager.undoToken) { _, _ in
                    capturedUndoManager?.undo()
                }
                .onChange(of: controllerManager.redoToken) { _, _ in
                    capturedUndoManager?.redo()
                }

                // D-Pad left/right -> cycle palette colors
                .onChange(of: controllerManager.colorCycleToken) { _, _ in
                    let step = controllerManager.colorCycleDirection
                    guard step != 0 else { return }
                    let colors = palette
                    guard !colors.isEmpty else { return }
                    let currentIndex = colors.firstIndex(where: { $0 == selectedColor }) ?? 0
                    let nextIndex = (currentIndex + step + colors.count) % colors.count
                    selectedColor = colors[nextIndex]
                }

                // D-Pad up/down -> cycle brush tips
                .onChange(of: controllerManager.tipCycleToken) { _, _ in
                    let step = controllerManager.tipCycleDirection
                    guard step != 0 else { return }
                    let tips = BrushTip.allCases
                    guard !tips.isEmpty else { return }
                    let currentIndex = tips.firstIndex(of: brushTip) ?? 0
                    let nextIndex = (currentIndex + step + tips.count) % tips.count
                    brushTip = tips[nextIndex]
                }
                .onAppear {
                    capturedUndoManager = undoManager
                }
                .onChange(of: undoManager) { _, newValue in
                    capturedUndoManager = newValue
                }
                .onChange(of: pickedItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let ui = UIImage(data: data) {
                            await MainActor.run {
                                canvasState.setBackgroundImage(ui, undoManager: capturedUndoManager)
                            }
                        }
                    }
                }
            }
        }
    }

    private var bottomControlBar: some View {
        VStack(spacing: 10) {
            // Color row (affects new strokes + new stickers)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(palette.indices, id: \.self) { i in
                        let c = palette[i]
                        Button {
                            selectedColor = c
                        } label: {
                            Circle()
                                .fill(c)
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(selectedColor == c ? 0.65 : 0.18), lineWidth: selectedColor == c ? 3 : 1)
                                )
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }

                    ColorPicker("", selection: $selectedColor, supportsOpacity: true)
                        .labelsHidden()
                        .frame(width: 44, height: 34)
                        .padding(.vertical, 6)
                }
                .padding(.horizontal, 14)
            }

            // Tool-specific row
            if tool == .brush || tool == .eraser {
                controlPill {
                    HStack(spacing: 10) {
                        ForEach(BrushTip.allCases, id: \.self) { tip in
                            Button {
                                brushTip = tip
                            } label: {
                                brushTipIcon(tip)
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 40, height: 34)
                                    .foregroundStyle(iconColor(active: brushTip == tip))
                                    .background {
                                        if brushTip == tip {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.14))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 14)
            } else if tool == .sticker {
                controlPill {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(StickerType.allCases, id: \.self) { st in
                                Button {
                                    selectedSticker = st
                                } label: {
                                    Image(systemName: st.systemName)
                                        .font(.system(size: 20, weight: .semibold))
                                        .frame(width: 44, height: 34)
                                        .foregroundStyle(iconColor(active: selectedSticker == st))
                                        .background {
                                            if selectedSticker == st {
                                                Capsule()
                                                    .fill(Color.primary.opacity(0.14))
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.horizontal, 14)
            }

            // Size slider (brush/eraser or sticker)
            HStack(spacing: 12) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 10))
                    .opacity(0.65)

                if tool == .sticker {
                    Slider(value: $stickerSize, in: 64...420)
                        .tint(.kidsPaintPurple)
                } else {
                    Slider(value: $brushSize, in: 2...80)
                        .tint(.kidsPaintPurple)
                }

                Image(systemName: "circle.fill")
                    .font(.system(size: 20))
                    .opacity(0.65)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .padding(.top, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func controlPill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Slightly more opaque than the bar's ultraThinMaterial
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1))
    }

    private func iconColor(active: Bool) -> Color {
        active ? .kidsPaintPurple : .primary
    }

    private var palette: [Color] {
        [.black, .white, .red, .orange, .yellow, .green, .mint, .blue, .purple, .pink]
    }
    @ViewBuilder
    private func brushTipIcon(_ tip: BrushTip) -> some View {
    #if canImport(UIKit)
        if UIImage(named: tip.assetName) != nil {
            Image(tip.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .padding(7)
        } else {
            Image(systemName: tip.systemImage)
                .renderingMode(.template)
                .padding(7)
        }
    #else
        Image(systemName: tip.systemImage)
            .renderingMode(.template)
            .padding(7)
    #endif
    }

    private func resetView() {
        withAnimation(.easeInOut(duration: 0.2)) {
            viewScale = 1.0
            viewOffset = .zero
        }
    }

    private func exportPNG() {
    #if canImport(UIKit)
        // UIKit presentation must happen on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async { exportPNG() }
            return
        }

        // Render a deterministic export size (keeps output consistent)
        let exportSize = CGSize(width: 1024, height: 768)

        let exportView = DrawingCanvas(
            strokes: .constant(canvasState.strokes),
            stickers: .constant(canvasState.stickers),
            selectedStickerID: .constant(nil),
            viewScale: .constant(viewScale),
            viewOffset: .constant(viewOffset),
            brushColor: brushColor,
            brushSize: brushSize,
            brushTip: brushTip,
            background: canvasState.canvasBackground,
            backgroundImage: canvasState.backgroundImage,
            tool: .pan,
            onCommitStroke: { _ in },
            onPlaceSticker: { _ in },
            onCommitStickerTransform: { _, _ in },
            controllerCursorScreen: nil,
            controllerIsDrawingPressed: false,
            controllerPlaceStickerToken: 0
        )
        .frame(width: exportSize.width, height: exportSize.height)
        .background(Color.white)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = UIScreen.main.scale

        guard let uiImage = renderer.uiImage else { return }

        let av = UIActivityViewController(activityItems: [uiImage], applicationActivities: nil)

        guard let presenter = topMostViewController() else { return }

        // iPad: configure popover anchor or UIKit will assert/crash
        if let popover = av.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }

        // If something is already presented, present from that instead
        let target = presenter.presentedViewController ?? presenter
        target.present(av, animated: true)
    #else
        _ = ()
    #endif
    }

    #if canImport(UIKit)
    private func topMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }

        let windows = scenes.flatMap { $0.windows }
        let keyWindow = windows.first(where: { $0.isKeyWindow }) ?? windows.first

        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}

#if canImport(UIKit)
private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first(where: { $0.isKeyWindow }) }
}
#endif
