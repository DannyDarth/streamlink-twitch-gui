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
        // Compact only the Twitch Games directory. Leave streams and player pages alone.
        let gamesGridScript = """
        (function() {
          if (window.__streamhubGamesGridInstalled) return;
          window.__streamhubGamesGridInstalled = true;
          const apply = () => {
            if (location.pathname !== '/directory') return;
            const links = [...document.querySelectorAll('a[href*="/directory/category/"]')];
            const groups = new Map();
            for (const link of links) {
              let card = link;
              for (let i = 0; i < 5 && card.parentElement; i++) {
                if (card.querySelector('img') && card.parentElement.querySelectorAll('a[href*="/directory/category/"]').length > 1) break;
                card = card.parentElement;
              }
              const parent = card.parentElement;
              if (!parent) continue;
              const siblings = [...parent.children].filter(el => el.querySelector('a[href*="/directory/category/"]'));
              if (siblings.length < 3) continue;
              if (!groups.has(parent)) groups.set(parent, siblings);
            }
            for (const [parent, siblings] of groups) {
              parent.style.setProperty('display', 'grid', 'important');
              parent.style.setProperty('grid-template-columns', 'repeat(3, minmax(0, 1fr))', 'important');
              parent.style.setProperty('gap', '8px', 'important');
              for (const card of siblings) {
                card.style.setProperty('width', '100%', 'important');
                card.style.setProperty('min-width', '0', 'important');
                card.style.setProperty('max-width', '100%', 'important');
              }
            }
          };
          let scheduled = false;
          const schedule = () => {
            if (scheduled) return;
            scheduled = true;
            requestAnimationFrame(() => { scheduled = false; apply(); });
          };
          new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true});
          schedule();
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: gamesGridScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
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
