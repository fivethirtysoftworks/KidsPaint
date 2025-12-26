//
//  UserGuideView.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 2, Beta 2
//  Updated 12/25/25
//  Created by Cornelius on 12/25/25.
//

import SwiftUI
import WebKit

struct UserGuideView: View {
    var body: some View {
        HStack(spacing: 0) {
            RainbowBar()
                .frame(width: 128)

            ZStack {
                Color.white

                UserGuideWebView(htmlFileName: "UserGuide")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(0)
            }
        }
        .environment(\.colorScheme, .light)
        .frame(minWidth: 700, minHeight: 650)
    }
}

private struct UserGuideWebView: NSViewRepresentable {
    let htmlFileName: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NSLog("UserGuideWebView: didFinish")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("UserGuideWebView: didFail navigation: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("UserGuideWebView: didFailProvisionalNavigation: \(error.localizedDescription)")
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        // Load bundled HTML: ensure `UserGuide.html` is included in Copy Bundle Resources.
        if let url = Bundle.main.url(forResource: htmlFileName, withExtension: "html") {
            do {
                let html = try String(contentsOf: url, encoding: .utf8)
                webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
                NSLog("UserGuideWebView: loading \(url.lastPathComponent) from bundle")
            } catch {
                let fallback = "<html><body style='font-family:-apple-system; background:#fff; color:#111; padding:24px;'>" +
                               "<h1>User Guide</h1><p>Failed to read <b>\(htmlFileName).html</b>.</p>" +
                               "<p>Error: \(error.localizedDescription)</p>" +
                               "</body></html>"
                webView.loadHTMLString(fallback, baseURL: nil)
                NSLog("UserGuideWebView: failed to read HTML: \(error.localizedDescription)")
            }
        } else {
            let fallback = "<html><body style='font-family:-apple-system; background:#fff; color:#111; padding:24px;'>" +
                           "<h1>User Guide</h1><p>Missing <b>\(htmlFileName).html</b> in app bundle.</p>" +
                           "<p>In Xcode, select <b>\(htmlFileName).html</b> and enable <b>Target Membership</b> for the KidsPaint app target, then verify it appears under <b>Build Phases → Copy Bundle Resources</b>.</p>" +
                           "</body></html>"
            webView.loadHTMLString(fallback, baseURL: nil)
            NSLog("UserGuideWebView: missing HTML in bundle")
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No-op
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
            .clipped()
        }
    }
}
