//
//  LaunchSplashOverlay.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
//

import SwiftUI

/// Splash overlay that reveals the KidsPaint wordmark + draws the smile, then fades out.
struct LaunchSplashOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var wordReveal: CGFloat = 0          // 0 -> 1 wipe
    @State private var smileTrim: CGFloat = 0           // 0 -> 1 draw
    @State private var scale: CGFloat = 0.96            // bounce
    @State private var opacity: CGFloat = 1

    var onFinished: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            RainbowBar()
                .frame(width: 128)
                .ignoresSafeArea()

            ZStack {
                // Keep splash white regardless of system appearance
                Color.white.ignoresSafeArea()

                VStack(spacing: 18) {
                    KidsPaintWordmark()
                        .mask(
                            GeometryReader { geo in
                                Rectangle()
                                    .frame(width: geo.size.width * wordReveal)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        )
                        .opacity(wordReveal > 0 ? 1 : 0)

                    SmileMark()
                        .trim(from: 0, to: smileTrim)
                        .stroke(
                            Color(red: 108/255, green: 99/255, blue: 255/255),
                            style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 220, height: 120)
                        .padding(.top, -2)
                }
                .scaleEffect(scale)
                .opacity(opacity)
                .drawingGroup()
            }
        }
        .onAppear { run() }
    }

    private func run() {
        if reduceMotion {
            wordReveal = 1
            smileTrim = 1
            scale = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.linear(duration: 0.25)) { opacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onFinished?()
                }
            }
            return
        }

        // Reveal wordmark
        withAnimation(.easeOut(duration: 0.75)) {
            wordReveal = 1
        }

        // Draw smile
        withAnimation(.easeOut(duration: 0.75).delay(0.25)) {
            smileTrim = 1
        }

        // Gentle bounce
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.35)) {
            scale = 1.0
        }

        // Hold
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeInOut(duration: 0.35)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onFinished?()
            }
        }
    }
}

private struct KidsPaintWordmark: View {
    var body: some View {
        HStack(spacing: 0) {
            letter("K", .red)
            letter("i", .orange)
            letter("d", .yellow)
            letter("s", .green)

            Spacer().frame(width: 10)

            letter("P", .cyan)
            letter("a", .blue)
            letter("i", .indigo)
            letter("n", .purple)
            letter("t", .blue.opacity(0.7))
        }
        .font(.system(size: 72, weight: .heavy, design: .rounded))
        .padding(.horizontal, 24)
    }

    private func letter(_ s: String, _ c: Color) -> some View {
        Text(s).foregroundStyle(c)
    }
}


private struct SmileMark: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * (x / 256.0),
                    y: rect.minY + rect.height * (y / 256.0))
        }
        var p = Path()
        p.move(to: pt(76, 132))
        p.addQuadCurve(to: pt(180, 132), control: pt(128, 176))
        return p
    }
}


