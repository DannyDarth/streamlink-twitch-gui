import SwiftUI
import WebKit

/// Twitch's public mobile browsing pages provide live channels, category art,
/// viewer information, and channel playback without shipping API credentials.
struct TwitchBrowserView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.webView = webView
        context.coordinator.currentRootURL = url
        Task { @MainActor in
            await AdBlockingSettings.shared.configure(configuration.userContentController)
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentRootURL != url {
            context.coordinator.currentRootURL = url
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var currentRootURL: URL?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let host = destination.host?.lowercased() ?? ""
            if destination.scheme == "https" &&
                (host == "twitch.tv" || host.hasSuffix(".twitch.tv") ||
                 host == "twitchcdn.net" || host.hasSuffix(".twitchcdn.net")) {
                decisionHandler(.allow)
            } else if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                UIApplication.shared.open(destination)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
