//
//  ContentView.swift
//  KidsPaint by Fivethirty Softworks
//
//  Created by Cornelius on 12/18/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    // Canvas state
    @State private var strokes: [Stroke] = []
    @State private var stickers: [StickerStamp] = []
    @State private var selectedStickerID: UUID? = nil

    @State private var canvasBackground: Color = .white
    @State private var backgroundImage: NSImage? = nil

    // Viewport
    @State private var viewScale: CGFloat = 1.0
    @State private var viewOffset: CGSize = .zero

    // Tool state
    @State private var tool: Tool = .brush
    @State private var selectedColor: Color = .black
    @State private var brushSize: CGFloat = 18

    // Sticker state
    @State private var selectedSticker: StickerType = .star
    @State private var stickerSize: CGFloat = 512   // bigger default
    @State private var stickerRotation: Angle = .degrees(0)

    @State private var canvasSize: CGSize = .zero

    // UI
    @State private var showClearConfirm = false

    private var brushColor: Color {
        tool == .eraser ? canvasBackground : selectedColor
    }

    var body: some View {
        GeometryReader { geo in
            DrawingCanvas(
                strokes: $strokes,
                stickers: $stickers,
                selectedStickerID: $selectedStickerID,
                viewScale: $viewScale,
                viewOffset: $viewOffset,
                brushColor: brushColor,
                brushSize: brushSize,
                background: canvasBackground,
                backgroundImage: backgroundImage,
                tool: tool,
                onCommitStroke: { stroke in
                    strokes.append(stroke)
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
                    stickers.append(stamp)
                    selectedStickerID = stamp.id
                }
            )
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { oldValue, newValue in
                canvasSize = newValue
            }
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

    // MARK: - Top toolbar

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("KidsPaint")
                .font(.headline)
        }

        ToolbarItemGroup(placement: .navigation) {
            Picker("", selection: $tool) {
                Image(systemName: "paintbrush.fill").tag(Tool.brush)
                Image(systemName: "eraser.fill").tag(Tool.eraser)
                Image(systemName: "sparkles").tag(Tool.sticker)
                Image(systemName: "hand.draw").tag(Tool.pan)
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .frame(width: 220)
            .help("Tool")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { resetView() } label: { Image(systemName: "arrow.counterclockwise") }
                .help("Reset view")

            Button { openBackgroundImage() } label: { Image(systemName: "photo.on.rectangle") }
                .help("Open image")

            Button { exportPNG() } label: { Image(systemName: "square.and.arrow.down") }
                .help("Save PNG")

            Button { showClearConfirm = true } label: { Image(systemName: "trash") }
                .help("Clear")

            Menu {
                Button("Remove Background Image") { backgroundImage = nil }
                Button("Background: White") { canvasBackground = .white }
                Button("Background: Light Gray") { canvasBackground = Color.gray.opacity(0.15) }
                Divider()
                Button("Delete Selected Sticker") { deleteSelectedSticker() }
                    .disabled(selectedStickerID == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Bottom control bar

    private var bottomControlBar: some View {
        BottomBar(
            tool: tool,
            selectedColor: $selectedColor,
            brushSize: $brushSize,
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

    private func resetView() {
        viewScale = 1.0
        viewOffset = .zero
    }

    private func deleteSelectedSticker() {
        guard let id = selectedStickerID else { return }
        stickers.removeAll { $0.id == id }
        selectedStickerID = nil
    }

    private func clearCanvas() {
        strokes = []
        stickers = []
        selectedStickerID = nil
    }

    private func openBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.title = "Open Background Image"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            backgroundImage = NSImage(contentsOf: url)
        }
    }

    private func exportPNG() {
        guard let image = renderExportImage() else { return }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "KidsPaint.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? pngData.write(to: url, options: [.atomic])
        }
    }

    private func renderExportImage() -> NSImage? {
        let size = (canvasSize == .zero) ? CGSize(width: 1600, height: 1000) : canvasSize

        let hostingView = NSHostingView(
            rootView: DrawingCanvas(
                strokes: .constant(strokes),
                stickers: .constant(stickers),
                selectedStickerID: .constant(nil),
                viewScale: .constant(1.0),
                viewOffset: .constant(.zero),
                brushColor: selectedColor,
                brushSize: brushSize,
                background: canvasBackground,
                backgroundImage: backgroundImage,
                tool: .brush,
                onCommitStroke: { _ in },
                onPlaceSticker: { _ in },
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
                    Text("Size")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    Slider(value: $brushSize, in: 8...80)
                        .frame(minWidth: 240)

                    Text("\(Int(brushSize))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                        .frame(width: 44, alignment: .trailing)

                case .sticker:
                    Text("Stickers")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    StickerStripView(selected: $selectedSticker)
                        .frame(width: 360)

                    Text("Size")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    Slider(value: $stickerSize, in: 60...860) // larger range
                        .frame(minWidth: 220)

                    Button(action: onResetStickerRotation) {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)

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

// MARK: - Sticker strip (icons only)

private struct StickerStripView: View {
    @Binding var selected: StickerType

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
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
            Image(systemName: sticker.systemName)
                .font(.system(size: 22, weight: .semibold))   // bigger icons
                .frame(width: 44, height: 36)
                .foregroundStyle(Color.primary.opacity(0.9))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(isSelected ? 0.35 : 0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
