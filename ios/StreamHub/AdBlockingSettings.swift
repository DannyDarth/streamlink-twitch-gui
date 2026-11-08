import Foundation
import WebKit

/// Experimental WebKit content blocking inspired by Brave's iOS architecture.
/// This does not reproduce Brave Shields or guarantee Twitch ad removal.
/// The rules target known third-party tracking requests, not Twitch HLS media.
@MainActor
final class AdBlockingSettings {
    static let shared = AdBlockingSettings()
    private init() {}

    private let rules = """
    [
      {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?doubleclick\\\\.net/","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?googlesyndication\\\\.com/","resource-type":["script","image","raw","popup"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?google-analytics\\\\.com/","resource-type":["script","image","raw"]},"action":{"type":"block"}}
    ]
    """

    func configure(_ controller: WKUserContentController, forTwitch: Bool = false) async {
        controller.removeAllContentRuleLists()
        guard UserDefaults.standard.bool(forKey: "streamhub.braveStyleFilteringEnabled") else { return }
        do {
            let list = try await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "streamhub.braveStyleFiltering.v1",
                encodedContentRuleList: rules
            )
            if let list {
                controller.add(list)
            } else {
                NSLog("StreamHub experimental WebKit filtering returned no rule list")
            }
        } catch {
            NSLog("StreamHub experimental WebKit filtering unavailable: %@", error.localizedDescription)
        }
    }
}
