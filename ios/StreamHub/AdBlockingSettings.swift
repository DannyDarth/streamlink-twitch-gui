import Foundation
import Combine
import WebKit

/// Controls optional filtering in StreamHub's own embedded web player.
@MainActor
final class AdBlockingSettings: ObservableObject {
    static let shared = AdBlockingSettings()
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "streamhub.adBlockingEnabled") }
    }

    @Published var experimentalTwitchFiltering: Bool {
        didSet { UserDefaults.standard.set(experimentalTwitchFiltering, forKey: "streamhub.experimentalTwitchFiltering") }
    }

    private init() {
        enabled = UserDefaults.standard.object(forKey: "streamhub.adBlockingEnabled") as? Bool ?? true
        experimentalTwitchFiltering = UserDefaults.standard.object(forKey: "streamhub.experimentalTwitchFiltering") as? Bool ?? false
    }

    /// Conservative rules: block known third-party ad/tracking hosts, not video or
    /// platform API endpoints. Server-side ads inside HLS cannot be removed here.
    private let rules = """
    [
      {"trigger":{"url-filter":".*","if-domain":["*doubleclick.net","*googlesyndication.com","*googleadservices.com","*adnxs.com","*pubmatic.com","*rubiconproject.com","*taboola.com","*outbrain.com"]},"action":{"type":"block"}}
    ]
    """

    private static let twitchCosmeticScript = """
    (() => {
      if (!location.hostname.endsWith('twitch.tv')) return;
      const hide = () => {
        document.querySelectorAll('[data-a-target="video-ad-label"], [data-test-selector="ad-banner-default-text"]').forEach(label => {
          const banner = label.closest('[data-a-target="video-ad-label"], [data-test-selector="ad-banner-default-text"]');
          if (banner) banner.style.display = 'none';
        });
      };
      new MutationObserver(hide).observe(document.documentElement, {childList: true, subtree: true});
      hide();
    })();
    """

    func configure(_ controller: WKUserContentController, forTwitch: Bool = false) async {
        controller.removeAllContentRuleLists()
        guard enabled else { return }
        do {
            guard let list = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "StreamHubBasicAdFiltering", encodedContentRuleList: rules
            )
            else {
                NSLog("StreamHub: web content filtering returned no rule list")
                return
            }
            controller.add(list)
            if forTwitch && experimentalTwitchFiltering {
                controller.addUserScript(WKUserScript(source: Self.twitchCosmeticScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
        } catch {
            NSLog("StreamHub: could not compile web content filtering rules: %@", String(describing: error))
        }
    }
}
