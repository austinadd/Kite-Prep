import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

/// Shows the Kite Prep web app that ships inside the app bundle (the `web` folder) in a full-screen web view.
///
/// The files are served through a custom URL scheme (kiteprep://app/...) instead of file:// URLs, so the
/// page has one stable origin. That keeps its saved progress (localStorage) between launches, and it lets the
/// Desmos pad load its scripts. Everything ships in the app, so it works offline. The one exception is the
/// Official tab, which asks College Board's question bank for real SAT questions through `NetBridge`.
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
        let net = NetBridge()
        config.userContentController.add(net, name: "kiteNet")

        let web = WKWebView(frame: .zero, configuration: config)
        net.webView = web
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
        // Test hook for the simulator checks in GitHub Actions: `-kiteScript "<js>"` runs once after the page loads.
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

/// Lets the page fetch official SAT questions from College Board's free question bank (the Official tab in
/// Practice). The page posts `{id, url, method, body}` to `window.webkit.messageHandlers.kiteNet`, and the reply
/// comes back through `window.__kiteNet([id, status, text, error])`. Only these two College Board hosts are allowed.
@MainActor
final class NetBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    private static let hosts: Set<String> = ["qbank-api.collegeboard.org", "saic.collegeboard.org"]

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let id = (body["id"] as? NSNumber)?.intValue else { return }
        guard let text = body["url"] as? String, let url = URL(string: text), url.scheme == "https",
              let host = url.host, Self.hosts.contains(host) else {
            finish(id: id, status: 0, text: "", error: "That address isn't allowed.")
            return
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        if (body["method"] as? String) == "POST" {
            request.httpMethod = "POST"
            request.httpBody = Data(((body["body"] as? String) ?? "").utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let send = request
        Task { [weak self] in
            var status = 0
            var reply = ""
            var failure = ""
            do {
                let (data, response) = try await URLSession.shared.data(for: send)
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                reply = String(decoding: data, as: UTF8.self)
            } catch {
                failure = error.localizedDescription.isEmpty ? "network error" : error.localizedDescription
            }
            self?.finish(id: id, status: status, text: reply, error: failure)
        }
    }

    private func finish(id: Int, status: Int, text: String, error: String) {
        let payload: [Any] = [id, status, text, error]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let args = String(data: json, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__kiteNet && window.__kiteNet(" + args + ")", completionHandler: nil)
    }
}
