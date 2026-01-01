//
//  GameControllerManager.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI
import Combine
import GameController
import CoreGraphics

@MainActor
final class GameControllerManager: ObservableObject {

    enum ToolCommand: Equatable {
        case setBrush
        case setEraser
        case setSticker
        case setPan
        case none
    }

    // Connection
    @Published private(set) var isConnected: Bool = false

    // Cursor in canvas LOCAL coordinates (0...canvasSize)
    @Published var cursor: CGPoint = CGPoint(x: 200, y: 200)

    // Held while drawing (A / Cross)
    @Published var isDrawingPressed: Bool = false

    // One-shot actions (token increments)
    @Published var placeStickerToken: Int = 0
    @Published var undoToken: Int = 0
    @Published var redoToken: Int = 0

    // Tool commands (one-shot)
    @Published var toolCommand: ToolCommand = .none

    // Brush size nudges (one-shot)
    @Published var brushSizeDelta: CGFloat = 0

    // Zoom nudges (continuous analog mapped to a small delta)
    @Published var zoomDelta: CGFloat = 0

    // Color cycling (one-shot, token + direction)
    @Published var colorCycleToken: Int = 0
    @Published var colorCycleDirection: Int = 0   // -1 = left, +1 = right

    // Brush tip cycling (one-shot, token + direction)
    @Published var tipCycleToken: Int = 0
    @Published var tipCycleDirection: Int = 0     // -1 = previous, +1 = next

    // Clamp the cursor
    var canvasSize: CGSize = .zero

    private var controller: GCController?
    private var moveVector: CGVector = .zero
    private var timer: Timer?
    private var lastTick: TimeInterval = 0

    
    private var activeTool: ToolCommand = .setBrush

    init() {
        if let first = GCController.controllers().first {
            attach(first)
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let c = note.object as? GCController else { return }
            Task { @MainActor in
                self?.attach(c)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let c = note.object as? GCController else { return }
            Task { @MainActor in
                self?.detachIfCurrentController(c)
            }
        }

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func attach(_ c: GCController) {
        controller = c
        isConnected = true

        
        let profile = c.physicalInputProfile
        if profile.elements.isEmpty == false {
            configurePhysicalInputProfile(profile)
        } else if let pad = c.extendedGamepad {
            configureExtendedGamepad(pad)
        } else if let micro = c.microGamepad {
            configureMicroGamepad(micro)
        }

        startTicking()
    }

    private func detachIfCurrentController(_ c: GCController) {
        if controller === c { detach() }
    }
    private func configurePhysicalInputProfile(_ profile: GCPhysicalInputProfile) {
        // Cursor move (left stick)
        if let leftStick = profile.elements[GCInputLeftThumbstick] as? GCControllerDirectionPad {
            leftStick.valueChangedHandler = { [weak self] (_ dpad: GCControllerDirectionPad, _ x: Float, _ y: Float) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.moveVector = CGVector(dx: CGFloat(x), dy: CGFloat(-y))
                }
            }
        }

        // Left stick click (L3) -> Brush tool
        if let l3 = profile.elements[GCInputLeftThumbstickButton] as? GCControllerButtonInput {
            l3.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.activeTool = .setBrush
                    self?.toolCommand = .setBrush
                }
            }
        }

        // A / Cross
        if let a = profile.elements[GCInputButtonA] as? GCControllerButtonInput {
            a.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.activeTool == .setSticker {
                        if pressed { self.placeStickerToken &+= 1 }
                        self.isDrawingPressed = false
                    } else {
                        self.isDrawingPressed = pressed
                    }
                }
            }
        }

        // Tools (B/X/Y)
        if let b = profile.elements[GCInputButtonB] as? GCControllerButtonInput {
            b.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.activeTool = .setEraser
                    self?.toolCommand = .setEraser
                }
            }
        }
        if let x = profile.elements[GCInputButtonX] as? GCControllerButtonInput {
            x.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.activeTool = .setSticker
                    self?.toolCommand = .setSticker
                }
            }
        }
        if let y = profile.elements[GCInputButtonY] as? GCControllerButtonInput {
            y.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.activeTool = .setPan
                    self?.toolCommand = .setPan
                }
            }
        }

        // D-pad (colors/tips)
        if let dpad = profile.elements[GCInputDirectionPad] as? GCControllerDirectionPad {
            dpad.left.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.colorCycleDirection = -1
                    self?.colorCycleToken &+= 1
                }
            }
            dpad.right.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.colorCycleDirection = 1
                    self?.colorCycleToken &+= 1
                }
            }
            dpad.up.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.tipCycleDirection = -1
                    self?.tipCycleToken &+= 1
                }
            }
            dpad.down.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in
                    self?.tipCycleDirection = 1
                    self?.tipCycleToken &+= 1
                }
            }
        }

        // Brush size (shoulders)
        if let lb = profile.elements[GCInputLeftShoulder] as? GCControllerButtonInput {
            lb.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in self?.brushSizeDelta = -2 }
            }
        }
        if let rb = profile.elements[GCInputRightShoulder] as? GCControllerButtonInput {
            rb.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in self?.brushSizeDelta = +2 }
            }
        }

        // Zoom (triggers)
        if let lt = profile.elements[GCInputLeftTrigger] as? GCControllerButtonInput {
            lt.valueChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let v = CGFloat(value)
                    self.zoomDelta = (v > 0.25) ? -0.02 * v : 0
                }
            }
        }
        if let rt = profile.elements[GCInputRightTrigger] as? GCControllerButtonInput {
            rt.valueChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let v = CGFloat(value)
                    self.zoomDelta = (v > 0.25) ? +0.02 * v : 0
                }
            }
        }

        // Undo / Redo
        if let menu = profile.elements[GCInputButtonMenu] as? GCControllerButtonInput {
            menu.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in self?.undoToken &+= 1 }
            }
        }
        if let options = profile.elements[GCInputButtonOptions] as? GCControllerButtonInput {
            options.pressedChangedHandler = { [weak self] (_ button: GCControllerButtonInput, _ value: Float, _ pressed: Bool) in
                guard pressed else { return }
                Task { @MainActor in self?.redoToken &+= 1 }
            }
        }
    }

    private func detach() {
        controller = nil
        isConnected = false
        isDrawingPressed = false
        moveVector = .zero
        stopTicking()
    }

    private func startTicking() {
        stopTicking()
        lastTick = Date.timeIntervalSinceReferenceDate
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard isConnected else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let dt = max(0.0, min(0.05, now - lastTick))
        lastTick = now

        let speed: CGFloat = 900
        let dx = CGFloat(moveVector.dx) * speed * CGFloat(dt)
        let dy = CGFloat(moveVector.dy) * speed * CGFloat(dt)

        if dx != 0 || dy != 0 {
            var next = cursor
            next.x += dx
            next.y += dy

            if canvasSize.width > 0 { next.x = min(canvasSize.width, max(0, next.x)) }
            if canvasSize.height > 0 { next.y = min(canvasSize.height, max(0, next.y)) }

            cursor = next
        }
    }

    private func configureExtendedGamepad(_ pad: GCExtendedGamepad) {

        // Cursor move
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            Task { @MainActor in
                self.moveVector = CGVector(dx: CGFloat(x), dy: CGFloat(-y))
            }
        }

        // Left stick click (L3) -> Brush tool (if available)
        pad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.activeTool = .setBrush
                self?.toolCommand = .setBrush
            }
        }

        // A / Cross: draw when in brush/eraser/pan; place sticker when in sticker tool
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            Task { @MainActor in
                if self.activeTool == .setSticker {
                    // One-shot sticker placement on press
                    if pressed { self.placeStickerToken &+= 1 }
                    self.isDrawingPressed = false
                } else {
                    // Brush/eraser drawing (tap vs hold behavior is implemented by the canvas)
                    self.isDrawingPressed = pressed
                }
            }
        }

        // Tools
        pad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.activeTool = .setEraser
                self?.toolCommand = .setEraser
            }
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.activeTool = .setSticker
                self?.toolCommand = .setSticker
            }
        }
        pad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.activeTool = .setPan
                self?.toolCommand = .setPan
            }
        }

        // D-pad left/right -> cycle colors
        pad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.colorCycleDirection = -1
                self?.colorCycleToken &+= 1
            }
        }
        pad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.colorCycleDirection = 1
                self?.colorCycleToken &+= 1
            }
        }

        // D-pad up/down -> cycle brush tips
        pad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.tipCycleDirection = -1
                self?.tipCycleToken &+= 1
            }
        }
        pad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in
                self?.tipCycleDirection = 1
                self?.tipCycleToken &+= 1
            }
        }

        // Brush size
        pad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.brushSizeDelta = -2 }
        }
        pad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.brushSizeDelta = +2 }
        }

        // Zoom
        pad.leftTrigger.valueChangedHandler = { [weak self] _, value, _ in
            guard let self else { return }
            Task { @MainActor in
                let v = CGFloat(value)
                self.zoomDelta = (v > 0.25) ? -0.02 * v : 0
            }
        }
        pad.rightTrigger.valueChangedHandler = { [weak self] _, value, _ in
            guard let self else { return }
            Task { @MainActor in
                let v = CGFloat(value)
                self.zoomDelta = (v > 0.25) ? +0.02 * v : 0
            }
        }

        // Undo / Redo (Menu / Options)
        pad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            Task { @MainActor in self?.undoToken &+= 1 }
        }

        if let options = pad.buttonOptions {
            options.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in self?.redoToken &+= 1 }
            }
        }
    }

    private func configureMicroGamepad(_ pad: GCMicroGamepad) {
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            guard let self else { return }
            Task { @MainActor in
                self.moveVector = CGVector(dx: CGFloat(x), dy: CGFloat(-y))

                // Best-effort tip cycling for micro gamepads: tap up/down past a threshold
                if y > 0.85 {
                    self.tipCycleDirection = -1
                    self.tipCycleToken &+= 1
                } else if y < -0.85 {
                    self.tipCycleDirection = 1
                    self.tipCycleToken &+= 1
                }
            }
        }

        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard let self else { return }
            Task { @MainActor in self.isDrawingPressed = pressed }
        }
    }
}
