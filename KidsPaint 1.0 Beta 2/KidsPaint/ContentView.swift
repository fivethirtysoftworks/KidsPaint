//
//  ContentView.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 2, Beta 2
//  Updated 12/24/25
//  Created by Cornelius on 12/18/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var canvasState = CanvasState()
    @Environment(\.undoManager) private var undoManager
    @EnvironmentObject private var controllerManager: GameControllerManager

    // Selection / focus
    @State private var selectedStickerID: UUID? = nil
    @FocusState private var canvasFocused: Bool

    // Viewport
    @State private var viewScale: CGFloat = 1.0
    @State private var viewOffset: CGSize = .zero

    // Tool state
    @State private var tool: Tool = .brush
    @State private var selectedColor: Color = .black
    @State private var brushSize: CGFloat = 18
    @State private var brushTip: BrushTip = .round

    // Sticker state
    @State private var selectedSticker: StickerType = .star
    @State private var stickerSize: CGFloat = 512
    @State private var stickerRotation: Angle = .degrees(0)

    @State private var canvasSize: CGSize = .zero

    // UI
    @State private var showClearConfirm = false
    @State private var showMorePopover = false

    private var brushColor: Color {
        tool == .eraser ? canvasState.canvasBackground : selectedColor
    }

    var body: some View {
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
                    canvasState.addStroke(stroke, undoManager: undoManager)
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
                    canvasState.addSticker(stamp, undoManager: undoManager)
                    selectedStickerID = stamp.id
                },
                onCommitStickerTransform: { start, end in
                    canvasState.commitStickerTransform(from: start, to: end, undoManager: undoManager)
                },

                // Controller inputs
                controllerCursorScreen: controllerManager.isConnected ? controllerManager.cursor : nil,
                controllerIsDrawingPressed: controllerManager.isDrawingPressed,
                controllerPlaceStickerToken: controllerManager.placeStickerToken
            )
            .focusable(true)
            .focused($canvasFocused)
            .onTapGesture { canvasFocused = true }
            .onAppear { canvasFocused = true }
            .onAppear {
                canvasSize = geo.size
                controllerManager.canvasSize = geo.size
            }
            .onChange(of: geo.size) { _, newValue in
                canvasSize = newValue
                controllerManager.canvasSize = newValue
            }
        }

        // Controller -> app actions
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
            brushSize = min(120, max(2, brushSize + delta))
            controllerManager.brushSizeDelta = 0
        }
        .onChange(of: controllerManager.zoomDelta) { _, delta in
            guard delta != 0 else { return }
            viewScale = min(6.0, max(0.25, viewScale * (1.0 + delta)))
            controllerManager.zoomDelta = 0
        }
        .onChange(of: controllerManager.undoToken) { _, _ in
            undoManager?.undo()
        }
        .onChange(of: controllerManager.redoToken) { _, _ in
            undoManager?.redo()
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

        .toolbar { topToolbar }
        .safeAreaInset(edge: .bottom) { bottomControlBar }
        .confirmationDialog(
            "Clear everything?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Canvas", role: .destructive) { clearCanvas() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all drawings and stickers.")
        }
        .background(DeleteKeyCatcher { deleteSelectedSticker() })
    }

    // MARK: - Top toolbar (flat)

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("")
                .font(.headline)
        }

        ToolbarItem(placement: .navigation) { toolButton(.brush, icon: "paintbrush.fill", label: "Brush") }
        ToolbarItem(placement: .navigation) { toolButton(.eraser, icon: "eraser.fill", label: "Eraser") }
        ToolbarItem(placement: .navigation) { toolButton(.sticker, icon: "sparkles", label: "Stickers") }
        ToolbarItem(placement: .navigation) { toolButton(.pan, icon: "hand.draw", label: "Pan") }

        ToolbarItem(placement: .primaryAction) {
            toolbarIconButton(system: "arrow.counterclockwise", help: "Reset view") { resetView() }
        }
        ToolbarItem(placement: .primaryAction) {
            toolbarIconButton(system: "photo.on.rectangle", help: "Open image") { openBackgroundImage() }
        }
        ToolbarItem(placement: .primaryAction) {
            toolbarIconButton(system: "square.and.arrow.down", help: "Save PNG") { exportPNG() }
        }
        ToolbarItem(placement: .primaryAction) {
            toolbarIconButton(system: "trash", help: "Clear") { showClearConfirm = true }
        }
        ToolbarItem(placement: .primaryAction) {
            moreButton
        }
    }

    // MARK: - Toolbar buttons (NO rounded backgrounds)

    @ViewBuilder
    private func toolButton(_ toolType: Tool, icon: String, label: String) -> some View {
        Button {
            tool = toolType
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 28)
                .foregroundStyle(tool == toolType ? Color.accentColor : Color.primary.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(label)
    }

    @ViewBuilder
    private func toolbarIconButton(system: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 28)
                .foregroundStyle(Color.primary.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(help)
        .padding(.horizontal, 3)
    }

    private var moreButton: some View {
        Button {
            showMorePopover.toggle()
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 28)
                .foregroundStyle(Color.primary.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help("More")
        .padding(.horizontal, 3)
        .popover(isPresented: $showMorePopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button("Remove Background Image") {
                    canvasState.setBackgroundImage(nil, undoManager: undoManager)
                    showMorePopover = false
                }

                Divider()

                Button("Background: White") {
                    canvasState.setCanvasBackground(.white, undoManager: undoManager)
                    showMorePopover = false
                }

                Button("Background: Light Gray") {
                    canvasState.setCanvasBackground(Color.gray.opacity(0.15), undoManager: undoManager)
                    showMorePopover = false
                }

                Divider()

                Button("Delete Selected Sticker") {
                    deleteSelectedSticker()
                    showMorePopover = false
                }
                .disabled(selectedStickerID == nil)
            }
            .padding(12)
            .frame(minWidth: 240)
        }
    }

    // MARK: - Bottom control bar

    private var bottomControlBar: some View {
        BottomBar(
            tool: tool,
            selectedColor: $selectedColor,
            brushSize: $brushSize,
            brushTip: $brushTip,
            selectedSticker: $selectedSticker,
            stickerSize: $stickerSize,
            onResetStickerRotation: { stickerRotation = .degrees(0) },
            palette: palette
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.primary.opacity(0.12)),
            alignment: .top
        )
    }

    private var palette: [Color] {
        [.black, .blue, .red, .green, .orange, .yellow, .purple, .pink, .brown, .white]
    }

    // MARK: - Actions

    private func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd-yy HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "KidsPaint \(timestamp).png"
    }

    private func resetView() {
        viewScale = 1.0
        viewOffset = .zero
    }

    private func deleteSelectedSticker() {
        guard let id = selectedStickerID else { return }
        canvasState.removeSticker(id: id, undoManager: undoManager)
        selectedStickerID = nil
    }

    private func clearCanvas() {
        canvasState.clearCanvas(undoManager: undoManager)
        selectedStickerID = nil
    }

    private func openBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.title = "Open Background Image"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let img = NSImage(contentsOf: url)
            canvasState.setBackgroundImage(img, undoManager: undoManager)
        }
    }

    private func exportPNG() {
        guard let image = renderExportImage() else { return }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = defaultExportFileName()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? pngData.write(to: url, options: [.atomic])
        }
    }

    private func renderExportImage() -> NSImage? {
        let size = (canvasSize == .zero) ? CGSize(width: 1600, height: 1000) : canvasSize

        let hostingView = NSHostingView(
            rootView: DrawingCanvas(
                strokes: .constant(canvasState.strokes),
                stickers: .constant(canvasState.stickers),
                selectedStickerID: .constant(nil),
                viewScale: .constant(1.0),
                viewOffset: .constant(.zero),
                brushColor: selectedColor,
                brushSize: brushSize,
                brushTip: brushTip,
                background: canvasState.canvasBackground,
                backgroundImage: canvasState.backgroundImage,
                tool: .brush,
                onCommitStroke: { _ in },
                onPlaceSticker: { _ in },
                onCommitStickerTransform: { _, _ in },
                showsSelectionUI: false
            )
            .frame(width: size.width, height: size.height)
        )

        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return nil }
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep)

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - Bottom bar extracted

private struct BottomBar: View {
    let tool: Tool

    @Binding var selectedColor: Color
    @Binding var brushSize: CGFloat
    @Binding var brushTip: BrushTip

    @Binding var selectedSticker: StickerType
    @Binding var stickerSize: CGFloat

    let onResetStickerRotation: () -> Void
    let palette: [Color]

    var body: some View {
        VStack(spacing: 10) {

            if tool != .pan {
                HStack(spacing: 12) {
                    Text("Color")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    ColorSwatches(selectedColor: $selectedColor, palette: palette)

                    Spacer()

                    ColorPicker("", selection: $selectedColor)
                        .labelsHidden()
                        .frame(width: 44)
                }
            }

            HStack(spacing: 14) {
                switch tool {
                case .brush, .eraser:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Text("Size")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.secondary)

                            Slider(value: $brushSize, in: 8...80)
                                .frame(minWidth: 240)

                            Text("\(Int(brushSize))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Color.secondary)
                                .frame(width: 44, alignment: .trailing)

                            Spacer(minLength: 0)
                        }

                        HStack(spacing: 12) {
                            Text("Tip")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.secondary)

                            BrushTipStrip(tip: $brushTip)
                                .frame(width: 340)

                            Spacer(minLength: 0)
                        }
                    }

                case .sticker:
                    Text("Stickers")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    StickerStripView(selected: $selectedSticker)
                        .frame(width: 360)

                    Text("Size")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    Slider(value: $stickerSize, in: 60...860)
                        .frame(minWidth: 220)

                    Button(action: onResetStickerRotation) {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Reset rotation")

                case .pan:
                    Text("Drag to pan. Pinch to zoom.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    Spacer()
                }

                Spacer()
            }
        }
    }
}

// MARK: - Brush tip strip (icons only)

private struct BrushTipStrip: View {
    @Binding var tip: BrushTip

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(BrushTip.allCases) { t in
                    Button {
                        tip = t
                    } label: {
                        Image(t.assetName)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(tip == t ? Color.accentColor : Color.primary.opacity(0.85))
                            .frame(width: 44, height: 32)
                            .overlay(
                                Rectangle()
                                    .frame(height: 2)
                                    .opacity(tip == t ? 1 : 0),
                                alignment: .bottom
                            )
                    }
                    .buttonStyle(.plain)
                    .help(t.label)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Sticker strip (flat)

private struct StickerStripView: View {
    @Binding var selected: StickerType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(StickerType.allCases) { st in
                    StickerIconChip(sticker: st, isSelected: selected == st) {
                        selected = st
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct StickerIconChip: View {
    let sticker: StickerType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: sticker.systemName)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 34, height: 28)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.85))

                Rectangle()
                    .frame(height: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .help("Sticker")
    }
}

// MARK: - Color swatches

private struct ColorSwatches: View {
    @Binding var selectedColor: Color
    let palette: [Color]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(palette, id: \.self) { c in
                Button { selectedColor = c } label: {
                    Circle()
                        .fill(c)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(
                                    Color.primary.opacity(selectedColor == c ? 0.90 : 0.18),
                                    lineWidth: selectedColor == c ? 2 : 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Delete key catcher

private struct DeleteKeyCatcher: NSViewRepresentable {
    var onDelete: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = KeyView()
        v.onDelete = onDelete
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onDelete: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117 {
                onDelete?()
                return
            }
            super.keyDown(with: event)
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
        .environmentObject(GameControllerManager())
}
