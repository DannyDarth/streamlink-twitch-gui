import SwiftUI
import WebKit

/// Twitch's public mobile browsing pages provide live channels, category art,
/// viewer information, and channel playback without shipping API credentials.
struct TwitchBrowserView: UIViewRepresentable {
    let url: URL
    var allowedWebChannel: String? = nil
    var playbackSuspended: Bool = false
    var onChannelSelected: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Preserve the shared website session used by Twitch authentication.
        // Do not switch to an ephemeral store: that would discard login state.
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Set a dark page canvas before Twitch's own styles load to prevent
        // the bright white flash during initial navigation and tab switches.
        let darkStartupScript = """
        (function() {
          if (document.getElementById('streamhub-startup-background')) return;
          const style = document.createElement('style');
          style.id = 'streamhub-startup-background';
          style.textContent = 'html, body { background-color: #0e0e10 !important; }';
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: darkStartupScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
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
        // Prime thumbnails just ahead of the viewport without changing Twitch's
        // own infinite-scroll, DOM layout, navigation, or video playback.
        let streamLoadingScript = """
        (function() {
          if (window.__streamhubStreamImagesInstalled) return;
          window.__streamhubStreamImagesInstalled = true;

          const isDirectory = () => {
            const path = location.pathname;
            return path === '/directory/all' || path.startsWith('/directory/category/');
          };
          const prepared = new WeakSet();
          const observer = new IntersectionObserver(entries => {
            if (!isDirectory()) return;
            for (const entry of entries) {
              if (!entry.isIntersecting) continue;
              const img = entry.target;
              img.loading = 'eager';
              img.setAttribute('fetchpriority', 'high');
              observer.unobserve(img);
            }
          }, { rootMargin: '650px 0px', threshold: 0 });

          function scan() {
            if (!isDirectory()) return;
            document.querySelectorAll('img[loading="lazy"], img[data-src]').forEach(img => {
              if (prepared.has(img)) return;
              prepared.add(img);
              observer.observe(img);
            });
          }
          let pending = false;
          function schedule() {
            if (pending) return;
            pending = true;
            setTimeout(() => { pending = false; scan(); }, 250);
          }
          new MutationObserver(schedule).observe(document.documentElement, {
            childList: true, subtree: true
          });
          window.addEventListener('scroll', schedule, { passive: true });
          scan();
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: streamLoadingScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        // Twitch uses client-side routing for stream cards, so WKNavigationDelegate
        // often never receives a .linkActivated navigation. Intercept genuine taps
        // on channel anchors before Twitch's SPA click handler consumes them.
        let channelTapScript = """
        (function() {
          if (window.__streamhubChannelTapInstalled) return;
          window.__streamhubChannelTapInstalled = true;
          const reserved = new Set(['home','following','directory','search','settings','videos','downloads','subscriptions',
            'inventory','wallet','drops','p','login','signup','moderator','popout',
            'clip','clips','collections','products','activity']);
          document.addEventListener('click', function(event) {
            if (!window.__streamhubProxyEnabled) return;
            if (!event.isTrusted || event.defaultPrevented || event.button !== 0 ||
                event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
            const anchor = event.target.closest && event.target.closest('a[href]');
            if (!anchor) return;
            let target;
            try { target = new URL(anchor.href, location.href); } catch (_) { return; }
            if (!['www.twitch.tv','m.twitch.tv','twitch.tv'].includes(target.hostname)) return;
            const parts = target.pathname.split('/').filter(Boolean);
            if (parts.length !== 1 || !/^[a-zA-Z0-9_]{3,25}$/.test(parts[0]) ||
                reserved.has(parts[0].toLowerCase())) return;
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.streamhubChannelTap) {
              event.preventDefault();
              event.stopImmediatePropagation();
              window.webkit.messageHandlers.streamhubChannelTap.postMessage(parts[0]);
            }
          }, true);
          // Only genuine user taps open StreamHub playback. Twitch may change
          // routes automatically during sign-in, including to profile pages.
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: channelTapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )
        configuration.userContentController.add(context.coordinator, name: "streamhubChannelTap")
        // Opt-in Twitch-specific player diagnostics. Observe ad state without
        // modifying media requests or removing playlist segments.
        if UserDefaults.standard.bool(forKey: "streamhub.twitchWebAdDiagnostics") {
            let adObservationScript = """
            (function() {
              if (window.__streamhubAdObserverInstalled) return;
              window.__streamhubAdObserverInstalled = true;
              let last = '';
              function scan() {
                const text = (document.body?.innerText || '').slice(0, 30000);
                const adVisible = /commercial break in progress|advertisement|ad break/i.test(text);
                const video = document.querySelector('video');
                const state = adVisible ? 'Possible Twitch ad UI visible'
                    : video && !video.paused ? 'Video playing; no ad UI detected'
                    : 'No active video or ad UI detected';
                if (state === last) return;
                last = state;
                window.webkit?.messageHandlers?.streamhubAdState?.postMessage(state);
              }
              setInterval(scan, 2000);
              document.addEventListener('playing', scan, true);
            })();
            """
            configuration.userContentController.addUserScript(
                WKUserScript(source: adObservationScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
            configuration.userContentController.add(context.coordinator, name: "streamhubAdState")
        }


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

        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Browsed pages may share an authenticated website data store.
        // Keep Web Inspector unavailable in production.
        if #available(iOS 16.4, *) {
            webView.isInspectable = false
        }
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 14/255, green: 14/255, blue: 16/255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        context.coordinator.webView = webView
        context.coordinator.onChannelSelected = onChannelSelected
        context.coordinator.allowedWebChannel = allowedWebChannel
        context.coordinator.currentRootURL = url
        context.coordinator.playbackSuspended = playbackSuspended
        context.coordinator.proxyEnabled = true
        Task { @MainActor in
            await AdBlockingSettings.shared.configure(configuration.userContentController, forTwitch: true)
            if !context.coordinator.playbackSuspended {
                webView.load(URLRequest(url: url))
            }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onChannelSelected = onChannelSelected
        context.coordinator.allowedWebChannel = allowedWebChannel
        context.coordinator.proxyEnabled = true
        context.coordinator.syncProxySetting()
        if context.coordinator.playbackSuspended != playbackSuspended {
            context.coordinator.playbackSuspended = playbackSuspended
            if playbackSuspended {
                // A hidden WKWebView can continue playing Twitch audio and ads.
                // Unload its page entirely before the native player opens.
                webView.stopLoading()
                webView.loadHTMLString("", baseURL: nil)
            } else {
                webView.load(URLRequest(url: url))
            }
        }
        if context.coordinator.currentRootURL != url {
            context.coordinator.currentRootURL = url
            if !playbackSuspended { webView.load(URLRequest(url: url)) }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var currentRootURL: URL?
        var onChannelSelected: ((String) -> Void)?
        var proxyEnabled = false
        var playbackSuspended = false
        var allowedWebChannel: String?
        private var lastReportedChannel: String?

        func syncProxySetting() {
            guard let webView else { return }
            webView.evaluateJavaScript("window.__streamhubProxyEnabled = " + (proxyEnabled ? "true" : "false") + ";", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            syncProxySetting()
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // Do not trust messages from third-party frames or redirected pages.
            let origin = message.frameInfo.securityOrigin
            guard message.frameInfo.isMainFrame,
                  origin.protocol.lowercased() == "https",
                  ["twitch.tv", "www.twitch.tv", "m.twitch.tv"].contains(origin.host.lowercased())
            else { return }
            if message.name == "streamhubAdState" {
                // Diagnostic messages originate in webpage JavaScript. Log only
                // the exact known states, never arbitrary webpage-supplied text.
                guard let state = message.body as? String,
                      ["Possible Twitch ad UI visible",
                       "Video playing; no ad UI detected",
                       "No active video or ad UI detected"].contains(state) else { return }
                NSLog("StreamHub Twitch web player: %@", state)
                return
            }
            guard message.name == "streamhubChannelTap",
                  true,
                  let channel = message.body as? String,
                  channel.range(of: "^[A-Za-z0-9_]{3,25}$", options: .regularExpression) != nil else { return }
            guard channel.lowercased() != "home", channel.lowercased() != "following",
                  channel.lowercased() != "activity",
                  allowedWebChannel?.lowercased() != channel.lowercased(),
                  lastReportedChannel != channel else { return }
            lastReportedChannel = channel
            DispatchQueue.main.async { [weak self] in self?.onChannelSelected?(channel) }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            lastReportedChannel = nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Never load an untrusted scheme into the embedded browser.
            // Allow third-party HTTPS subresources/frames needed by Twitch.
            let scheme = destination.scheme?.lowercased() ?? ""
            guard scheme == "https" || scheme == "about" else {
                decisionHandler(.cancel)
                return
            }
            if scheme == "about" {
                // Only the browser's empty bootstrap document is expected.
                decisionHandler(destination.absoluteString == "about:blank" ? .allow : .cancel)
                return
            }
            // Reject HTTPS URLs with embedded credentials or no hostname.
            // Preserve legitimate Twitch HTTPS navigation and media frames.
            guard destination.host != nil,
                  destination.user == nil, destination.password == nil else {
                decisionHandler(.cancel)
                return
            }
            let host = destination.host?.lowercased() ?? ""
            if navigationAction.navigationType == .linkActivated,
               let callback = onChannelSelected,
               navigationAction.targetFrame?.isMainFrame == true,
               host == "www.twitch.tv" || host == "m.twitch.tv" || host == "twitch.tv" {
                let parts = destination.pathComponents.filter { $0 != "/" }
                let reserved: Set<String> = ["home", "following", "directory", "search", "settings", "videos", "downloads", "subscriptions", "inventory", "wallet", "drops", "p", "login", "signup", "moderator", "popout", "clip", "clips", "collections", "products", "activity"]
                if parts.count == 1, let channel = parts.first,
                   !reserved.contains(channel.lowercased()),
                   allowedWebChannel?.lowercased() != channel.lowercased(),
                   channel.range(of: "^[A-Za-z0-9_]{3,25}$", options: .regularExpression) != nil {
                    decisionHandler(.cancel)
                    DispatchQueue.main.async { callback(channel) }
                    return
                }
            }

            if destination.scheme == "https" &&
                (host == "twitch.tv" || host.hasSuffix(".twitch.tv") ||
                 host == "twitchcdn.net" || host.hasSuffix(".twitchcdn.net")) {
                decisionHandler(.allow)
            } else if navigationAction.targetFrame?.isMainFrame == true ||
                      navigationAction.targetFrame == nil {
                // Block untrusted top-level redirects and links. Do not
                // automatically hand them to Safari or another external app.
                // Twitch navigation and third-party HTTPS media frames are
                // handled by the allow rules above and below.
                decisionHandler(.cancel)
            } else {
                // Third-party HTTPS iframes may be required for Twitch login/media.
                decisionHandler(.allow)
            }
        }
    }
}
