import SwiftUI
import WebKit

/// Provider-authenticated followed channels; credentials stay inside WKWebView.
struct FollowedView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlatform = 0
    @State private var selectedTwitchChannel: FollowedTwitchChannel?

    private var followingURL: URL {
        URL(string: selectedPlatform == 0
            ? "https://www.twitch.tv/directory/following"
            : "https://kick.com/following")!
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

            Text("Sign in on each service to view your followed channels. Twitch streams open in StreamHub's native player; Kick continues using its website.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            FollowingBrowser(url: followingURL,
                             interceptTwitchChannels: selectedPlatform == 0,
                             playbackSuspended: selectedTwitchChannel != nil,
                             onTwitchChannel: { channel in
                                 guard selectedTwitchChannel == nil else { return }
                                 selectedTwitchChannel = FollowedTwitchChannel(name: channel)
                             })
                .id(selectedPlatform)
        }
        .navigationTitle("Followed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .fullScreenCover(item: $selectedTwitchChannel) { selection in
            TwitchEmbeddedPlayerView(channel: selection.name, onReturnToWebPlayer: {
                selectedTwitchChannel = nil
                UIApplication.shared.open(URL(string: "https://www.twitch.tv/" + selection.name)!)
            })
        }
    }
}

private struct FollowedTwitchChannel: Identifiable {
    let name: String
    var id: String { name }
}

private struct FollowingBrowser: UIViewRepresentable {
    let url: URL
    let interceptTwitchChannels: Bool
    let playbackSuspended: Bool
    let onTwitchChannel: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let tapScript = """
        (function() {
          if (window.__streamhubFollowingTap) return;
          window.__streamhubFollowingTap = true;
          const reserved = new Set(['home','following','directory','search','settings','videos','downloads',
            'subscriptions','inventory','wallet','drops','p','login','signup',
            'moderator','popout','clip','clips','collections','products']);
          document.addEventListener('click', function(event) {
            if (!window.__streamhubFollowingIntercept || !event.isTrusted ||
                event.defaultPrevented || event.button !== 0 ||
                event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
            const a = event.target.closest && event.target.closest('a[href]');
            if (!a) return;
            let u;
            try { u = new URL(a.href, location.href); } catch (_) { return; }
            if (!['www.twitch.tv','m.twitch.tv','twitch.tv'].includes(u.hostname)) return;
            const parts = u.pathname.split('/').filter(Boolean);
            if (parts.length !== 1 || !/^[A-Za-z0-9_]{3,25}$/.test(parts[0]) ||
                reserved.has(parts[0].toLowerCase())) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            window.webkit?.messageHandlers?.followedTwitchChannel?.postMessage(parts[0]);
          }, true);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: tapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        // Hide Twitch's native-app upsell without clicking its buttons or
        // changing the page route. Run after DOM changes because Twitch is an SPA.
        let hideAppPromptScript = """
        (function() {
          if (window.__streamhubHideAppPromptInstalled) return;
          window.__streamhubHideAppPromptInstalled = true;
          const hide = () => {
            if (!/(^|\\.)twitch\\.tv$/.test(location.hostname)) return;
            const elements = document.querySelectorAll('button, [role="button"]');
            for (const button of elements) {
              const label = (button.textContent || '').trim().replace(/\\s+/g, ' ');
              if (label !== 'Keep using web') continue;
              let sheet = button;
              for (let i = 0; i < 7 && sheet.parentElement; i++) {
                sheet = sheet.parentElement;
                const text = (sheet.innerText || '').slice(0, 350);
                if (!text.includes('Open in App')) continue;
                if (text.length > 220) break;
                if (sheet === document.body || sheet === document.documentElement) break;
                // The prompt may be in a modal dialog or a bottom-sheet portal.
                const dialog = sheet.closest('[role="dialog"], [aria-modal="true"]');
                const target = dialog || sheet;
                target.style.setProperty('display', 'none', 'important');
                target.setAttribute('aria-hidden', 'true');
                // A dismissed bottom sheet must not keep scrolling locked.
                if (document.body.style.overflow === 'hidden') document.body.style.overflow = '';
                if (document.documentElement.style.overflow === 'hidden') document.documentElement.style.overflow = '';
                break;
              }
            }
          };
          let scheduled = false;
          new MutationObserver(() => {
            if (scheduled) return;
            scheduled = true;
            requestAnimationFrame(() => { scheduled = false; hide(); });
          }).observe(document.documentElement, { childList: true, subtree: true });
          hide();
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: hideAppPromptScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        configuration.userContentController.add(context.coordinator, name: "followedTwitchChannel")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 14/255, green: 14/255, blue: 16/255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onTwitchChannel = onTwitchChannel
        context.coordinator.interceptTwitchChannels = interceptTwitchChannels
        context.coordinator.playbackSuspended = playbackSuspended
        // The signed-in Twitch/Kick browser must never start on an insecure URL.
        if url.scheme?.lowercased() == "https", url.host != nil,
           url.user == nil, url.password == nil {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTwitchChannel = onTwitchChannel
        coordinator.interceptTwitchChannels = interceptTwitchChannels
        coordinator.syncInterception()
        if coordinator.playbackSuspended != playbackSuspended {
            coordinator.playbackSuspended = playbackSuspended
            if playbackSuspended {
                webView.stopLoading()
                webView.loadHTMLString("", baseURL: nil)
            } else if url.scheme?.lowercased() == "https",
                      url.user == nil, url.password == nil,
                      let host = url.host?.lowercased(),
                      host == "twitch.tv" || host.hasSuffix(".twitch.tv") ||
                      host == "kick.com" || host.hasSuffix(".kick.com") {
                // Revalidate on resume as well as on initial load, since this
                // browser retains the user's authenticated website sessions.
                webView.load(URLRequest(url: url))
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var onTwitchChannel: ((String) -> Void)?
        var interceptTwitchChannels = false
        var playbackSuspended = false

        func syncInterception() {
            webView?.evaluateJavaScript("window.__streamhubFollowingIntercept = " +
                (interceptTwitchChannels ? "true" : "false") + ";", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncInterception()
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // Only the top-level Twitch page may request native playback.
            // Ignore forged messages from embedded third-party frames.
            let origin = message.frameInfo.securityOrigin
            guard message.frameInfo.isMainFrame,
                  origin.protocol.lowercased() == "https",
                  ["twitch.tv", "www.twitch.tv", "m.twitch.tv"].contains(origin.host.lowercased()),
                  message.name == "followedTwitchChannel", interceptTwitchChannels,
                  !playbackSuspended,
                  let channel = message.body as? String,
                  channel.range(of: "^[A-Za-z0-9_]{3,25}$", options: .regularExpression) != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.onTwitchChannel?(channel) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "about",
                  url.user == nil, url.password == nil,
                  let host = url.host?.lowercased() ?? (scheme == "about" ? "" : nil) else {
                decisionHandler(.cancel)
                return
            }
            // Only the empty bootstrap page is expected; reject other about: URLs.
            if scheme == "about" {
                decisionHandler(url.absoluteString == "about:blank" ? .allow : .cancel)
                return
            }
            if interceptTwitchChannels, !playbackSuspended,
               action.targetFrame?.isMainFrame == true,
               ["twitch.tv","www.twitch.tv","m.twitch.tv"].contains(host) {
                let parts = url.pathComponents.filter { $0 != "/" }
                let reserved: Set<String> = ["home","following","directory","search","settings","videos","downloads",
                    "subscriptions","inventory","wallet","drops","p","login","signup",
                    "moderator","popout","clip","clips","collections","products"]
                if parts.count == 1, let channel = parts.first,
                   !reserved.contains(channel.lowercased()),
                   channel.range(of: "^[A-Za-z0-9_]{3,25}$", options: .regularExpression) != nil {
                    decisionHandler(.cancel)
                    DispatchQueue.main.async { [weak self] in self?.onTwitchChannel?(channel) }
                    return
                }
            }
            if host == "twitch.tv" || host.hasSuffix(".twitch.tv") ||
               host == "kick.com" || host.hasSuffix(".kick.com") ||
               host == "id.twitch.tv" {
                decisionHandler(.allow)
            } else if action.targetFrame?.isMainFrame == true ||
                      action.targetFrame == nil {
                // Do not follow untrusted top-level redirects inside the signed-in browser.
                decisionHandler(.cancel)
                if action.navigationType == .linkActivated {
                    UIApplication.shared.open(url)
                }
            } else {
                // Keep HTTPS subframes for legitimate login and media resources.
                decisionHandler(.allow)
            }
        }
    }
}
