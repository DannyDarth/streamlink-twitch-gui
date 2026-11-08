import SwiftUI
import WebKit

/// Use only for approved embed URLs; the caller must supply a valid HTTPS URL.
/// Each new web view applies the user's current filtering preference.
struct FilteredWebPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        Task { @MainActor in
            await AdBlockingSettings.shared.configure(configuration.userContentController)
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Playback URLs are immutable for each player instance.
    }
}
