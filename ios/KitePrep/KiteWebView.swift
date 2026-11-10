import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Shows the Kite Prep web app that ships inside the app bundle (the `web` folder) in a full-screen web view.
///
/// The files are served through a custom URL scheme (kiteprep://app/...) instead of file:// URLs, so the
/// page has one stable origin. That keeps its saved progress (localStorage) between launches, and it lets the
/// Desmos pad load its scripts. Nothing comes from the internet, so the app works offline.
struct KiteWebView: UIViewRepresentable {
    static let scheme = "kiteprep"
    static let startURL = URL(string: "kiteprep://app/index.html")!

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(context.coordinator, forURLScheme: Self.scheme)
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.dataDetectorTypes = []

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(named: "Backdrop")
        web.scrollView.backgroundColor = UIColor(named: "Backdrop")
        // The page pads itself for the notch and home indicator (viewport-fit=cover + env(safe-area-inset-*)).
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        web.allowsBackForwardNavigationGestures = false
        #if DEBUG
        if #available(iOS 16.4, *) {
            web.isInspectable = true
        }
        #endif
        web.load(URLRequest(url: Self.startURL))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKURLSchemeHandler, WKNavigationDelegate, WKUIDelegate {
        private let root: URL = Bundle.main.bundleURL.appendingPathComponent("web", isDirectory: true).standardizedFileURL

        // MARK: Serve the bundled files

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }
            var path = url.path
            if path.isEmpty || path == "/" {
                path = "/index.html"
            }
            let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
            guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
                let missing = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1",
                                              headerFields: ["Content-Type": "text/plain"])!
                urlSchemeTask.didReceive(missing)
                urlSchemeTask.didReceive(Data())
                urlSchemeTask.didFinish()
                return
            }
            let headers = [
                "Content-Type": Self.mimeType(for: file.pathExtension),
                "Content-Length": String(data.count),
                "Cache-Control": "no-cache",
            ]
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            urlSchemeTask.didReceive(ok)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

        static func mimeType(for ext: String) -> String {
            switch ext.lowercased() {
            case "html", "htm": return "text/html; charset=utf-8"
            case "js": return "text/javascript; charset=utf-8"
            case "css": return "text/css; charset=utf-8"
            case "json": return "application/json"
            case "svg": return "image/svg+xml"
            case "png": return "image/png"
            case "woff2": return "font/woff2"
            default: return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            }
        }

        // MARK: Links to websites (like the IRSC page) open in Safari

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
                decisionHandler(.cancel)
                return
            }
            if ["kiteprep", "about", "blob", "data"].contains(scheme) {
                decisionHandler(.allow)
                return
            }
            if let frame = navigationAction.targetFrame, !frame.isMainFrame {
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url)
            }
            return nil
        }

        // If iOS shuts down the page to free memory, load it again. Progress is already saved.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.load(URLRequest(url: KiteWebView.startURL))
        }

        #if DEBUG
        // Test hook for the simulator check in GitHub Actions: `-kiteScript "<js>"` runs once after the page loads.
        private var ranTestScript = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !ranTestScript, let script = UserDefaults.standard.string(forKey: "kiteScript") else { return }
            ranTestScript = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                webView.evaluateJavaScript(script, completionHandler: nil)
            }
        }
        #endif
    }
}
