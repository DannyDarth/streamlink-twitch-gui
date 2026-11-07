import SwiftUI
import WebKit

struct KickCategoryChannel: Identifiable, Decodable {
    let slug: String
    let title: String
    let thumbnail: String?
    let viewers: String
    var id: String { slug }
    var imageURL: URL? { thumbnail.flatMap(URL.init(string:)) }
}

@MainActor
final class KickCategoryWebModel: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var channels: [KickCategoryChannel] = []
    @Published var status = "Loading live streams…"
    @Published var isReady = false
    weak var webView: WKWebView?
    private var previousCount = 0

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let json = message.body as? String,
              let data = json.data(using: .utf8),
              let incoming = try? JSONDecoder().decode([KickCategoryChannel].self, from: data) else { return }
        // Do not discard previously discovered streams while the site updates.
        var bySlug = Dictionary(uniqueKeysWithValues: channels.map { ($0.slug, $0) })
        for channel in incoming { bySlug[channel.slug] = channel }
        let order = channels.map(\.slug) + incoming.map(\.slug)
        var seen = Set<String>()
        channels = order.compactMap { slug in
            guard seen.insert(slug).inserted else { return nil }
            return bySlug[slug]
        }
        if !channels.isEmpty {
            isReady = true
            status = ""
        }
    }

    func loadMore() {
        webView?.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight);", completionHandler: nil)
    }

    func reload() {
        channels = []
        isReady = false
        status = "Loading live streams…"
        webView?.reload()
    }
}

/// Keeps Kick's actual category website running for discovery and pagination,
/// but presents discovered channel cards with native SwiftUI.
struct KickCategoryDiscoveryWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: KickCategoryWebModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "streamhubChannels")
        config.userContentController.addUserScript(WKUserScript(source: Self.discoveryScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        model.webView = web
        Task { @MainActor in
            await AdBlockingSettings.shared.configure(config.userContentController)
            web.load(URLRequest(url: url))
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: KickCategoryWebModel
        init(model: KickCategoryWebModel) { self.model = model }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            Task { @MainActor in self.model.userContentController(userContentController, didReceive: message) }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                if self.model.channels.isEmpty {
                    self.model.status = "Looking for live channels…"
                }
            }
        }
    }

    private static let discoveryScript = """
    (function() {
      if (window.__streamhubDiscover) return;
      function collect() {
        const results = [];
        const seen = new Set();
        const blocked = new Set(['category','categories','search','following','browse','login','signup','dashboard','settings','clips','videos']);
        document.querySelectorAll('a[href]').forEach(a => {
          let url;
          try { url = new URL(a.href, location.href); } catch (_) { return; }
          if (!/(^|\\.)kick\\.com$/.test(url.hostname)) return;
          const parts = url.pathname.split('/').filter(Boolean);
          if (parts.length !== 1) return;
          const slug = parts[0];
          if (blocked.has(slug.toLowerCase()) || seen.has(slug)) return;
          let card = a;
          for (let i = 0; i < 5 && card.parentElement; i++) {
            if (card.querySelector('img') && card.textContent.trim().length > 12) break;
            card = card.parentElement;
          }
          const img = card.querySelector('img[src], img[data-src]');
          if (!img) return;
          const src = img.currentSrc || img.src || img.getAttribute('data-src');
          if (!src || /avatar|profile|userpic/i.test(src)) return;
          const text = (card.innerText || card.textContent || '').trim();
          if (!text) return;
          const lines = text.split('\\n').map(s => s.trim()).filter(Boolean);
          const viewers = (text.match(/(?:[\\d,.]+[KMB]?\\s*(?:viewers|watching))/i) || [])[0] || '';
          const title = lines.filter(s => s !== slug && !/^[\\d,.]+[KMB]?\\s*(?:viewers|watching)$/i.test(s)).slice(0,3).join(' · ').slice(0,180);
          seen.add(slug);
          results.push({slug, title: title || slug, thumbnail: src, viewers});
        });
        if (results.length) window.webkit.messageHandlers.streamhubChannels.postMessage(JSON.stringify(results));
      }
      let queued = false;
      function schedule() {
        if (queued) return;
        queued = true;
        setTimeout(() => { queued = false; collect(); }, 400);
      }
      new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true});
      window.addEventListener('scroll', schedule, {passive:true});
      schedule();
    })();
    """
}
