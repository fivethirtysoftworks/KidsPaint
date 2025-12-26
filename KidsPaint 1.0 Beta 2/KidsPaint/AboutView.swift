//
//  AboutView.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 2, Beta 2
//  Updated 12/25/25
//  Created by Cornelius on 12/25/25.
//

import SwiftUI


struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    private var appVersionAndBuild: String {
        let version = Bundle.main
            .infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let build = Bundle.main
            .infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        return "Version \(version) (\(build))"
    }
    
    private var copyright: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        return "© \(year) Fivethirty Softworks"
    }
    
    private var repoURL: URL {
        URL(string: "https://github.com/fivethirtysoftworks/KidsPaint")!
    }

    private var issuesURL: URL {
        URL(string: "https://github.com/fivethirtysoftworks/KidsPaint/issues")!
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left rainbow bar (matches app icon vibe)
            RainbowBar()
                .frame(width: 128)

            // Main content on white background
            ZStack {
                Color.white

                VStack(spacing: 14) {
                    Image(.mainicon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("KidsPaint")
                            .font(.system(.title, design: .rounded).weight(.semibold))
                            .foregroundStyle(.black)

                        Text("by Fivethirty Softworks")
                            .font(.callout)
                            .foregroundStyle(Color.black.opacity(0.62))

                        Text("A simple open-source painting app for kids (and parents!).")
                            .font(.callout)
                            .foregroundStyle(Color.black.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text("Made in West Virginia. Coded by Sasquatch.")
                            .font(.callout)
                            .foregroundStyle(Color.black.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 4) {
                        Text(appVersionAndBuild)
                        Text(copyright)
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.black.opacity(0.62))

                    HStack(spacing: 10) {
                        Button("User Guide") {
                            openWindow(id: "user-guide")
                        }

                        Button("Source Code") {
                            openURL(repoURL)
                        }

                        Button("Report an Issue") {
                            openURL(issuesURL)
                        }
                    }
                    .buttonStyle(.bordered)

                    Divider()
                        .padding(.top, 2)

                    Text("Trademark Notice: Apple, macOS, iPhone, iPad and related marks are trademarks of Apple Inc. Xbox is a trademark of Microsoft Corporation. PlayStation is a trademark of Sony Interactive Entertainment Inc. All other trademarks are the property of their respective owners. KidsPaint is not affiliated with or endorsed by these companies.")
                        .font(.caption)
                        .foregroundStyle(Color.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                }
                .padding(18)
            }
        }
        .environment(\.colorScheme, .light) // force light appearance for this window
        .frame(minWidth: 560, minHeight: 320)
    }
}

private struct RainbowBar: View {
    var body: some View {
        GeometryReader { geo in
            let stripeCount: CGFloat = 5
            let stripeWidth = geo.size.width / stripeCount

            HStack(spacing: 0) {
                Color(red: 0.95, green: 0.32, blue: 0.26) // red
                    .frame(width: stripeWidth)
                Color(red: 0.98, green: 0.80, blue: 0.18) // yellow
                    .frame(width: stripeWidth)
                Color(red: 0.55, green: 0.78, blue: 0.21) // green
                    .frame(width: stripeWidth)
                Color(red: 0.18, green: 0.67, blue: 0.93) // cyan/blue
                    .frame(width: stripeWidth)
                Color(red: 0.42, green: 0.40, blue: 0.86) // purple
                    .frame(width: stripeWidth)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
