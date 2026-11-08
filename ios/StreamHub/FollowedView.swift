import SwiftUI
import WebKit
import UIKit

/// Followed channels use the providers' own authenticated following pages.
/// Credentials are entered on Twitch/Kick, never collected by StreamHub.
struct FollowedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlatform = 0

    private var followingURL: URL {
        URL(string: selectedPlatform == 0
            ? "https://www.twitch.tv/directory/following"
            : "https://kick.com/following")!
    }

    private func openInBrave(_ url: URL) {
        var components = URLComponents()
        components.scheme = "brave"
        components.host = "open-url"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        guard let braveURL = components.url else {
            UIApplication.shared.open(url)
            return
        }
        UIApplication.shared.open(braveURL, options: [:]) { opened in
            if !opened {
                UIApplication.shared.open(url)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Following platform", selection: $selectedPlatform) {
                Text("Twitch").tag(0)
                Text("Kick").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)

            Text("Twitch opens in Brave for sign-in. Kick uses its website inside StreamHub. StreamHub does not collect your password.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if selectedPlatform == 0 {
                VStack(spacing: 18) {
                    Image(systemName: "safari")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Open your Twitch following page in Brave to sign in and complete verification.")
                        .multilineTextAlignment(.center)
                    Button("Open Twitch in Brave") {
                        openInBrave(followingURL)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("If Brave is not installed, the page opens in your default browser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                FollowingBrowser(url: followingURL)
                    .id(selectedPlatform)
            }
        }
        .navigationTitle("Followed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}

private struct FollowingBrowser: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 14/255, green: 14/255, blue: 16/255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https",
                  let host = url.host?.lowercased() else {
                decisionHandler(.cancel)
                return
            }
            // Allow normal provider authentication redirects inside the web view.
            // Never intercept or read credentials, tokens, or page content.
            if host == "twitch.tv" || host.hasSuffix(".twitch.tv") ||
               host == "kick.com" || host.hasSuffix(".kick.com") ||
               host == "id.twitch.tv" {
                decisionHandler(.allow)
            } else if action.navigationType == .linkActivated {
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
