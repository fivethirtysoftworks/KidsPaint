//
//  UserGuideView.swift
//  KidsPaint by Fivethirty Softworks
//  Version 1.0.0 Build 3, Beta 3
//  Updated 12/31/25
//  Created by Cornelius on 12/18/25
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
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 650)
        #endif
    }
}

#if os(macOS)
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

        // Load bundled HTML: `UserGuide.html`
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
#endif

#if os(iOS)
private struct UserGuideWebView: UIViewRepresentable {
    let htmlFileName: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { NSLog("UserGuideWebView: didFinish") }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { NSLog("UserGuideWebView: didFail navigation: \(error.localizedDescription)") }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { NSLog("UserGuideWebView: didFailProvisionalNavigation: \(error.localizedDescription)") }
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator

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
            }
        } else {
            let fallback = "<html><body style='font-family:-apple-system; background:#fff; color:#111; padding:24px;'>" +
                           "<h1>User Guide</h1><p>Missing <b>\(htmlFileName).html</b> in app bundle.</p>" +
                           "</body></html>"
            webView.loadHTMLString(fallback, baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
