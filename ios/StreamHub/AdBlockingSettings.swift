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

    // Experimental client-side ad-request filtering only. Twitch also stitches
    // advertisements into HLS playlists; these rules cannot remove those ads.
    private let twitchClientAdRules = """
    [
      {"trigger":{"url-filter":"^https://edge\\\\.ads\\\\.twitch\\\\.tv/ads([/?]|$)","resource-type":["raw","script"],"if-domain":["*twitch.tv"]},"action":{"type":"block"}}
    ]
    """

    func configure(_ controller: WKUserContentController, forTwitch: Bool = false) async {
        controller.removeAllContentRuleLists()
        if UserDefaults.standard.bool(forKey: "streamhub.braveStyleFilteringEnabled") {
            do {
                let list = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "streamhub.braveStyleFiltering.v1",
                    encodedContentRuleList: rules
                )
                if let list { controller.add(list) }
            } catch {
                NSLog("StreamHub tracker filtering unavailable: %@", error.localizedDescription)
            }
        }
        if forTwitch && UserDefaults.standard.bool(forKey: "streamhub.twitchClientAdFiltering") {
            do {
                let list = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "streamhub.twitchClientAdFiltering.v1",
                    encodedContentRuleList: twitchClientAdRules
                )
                if let list { controller.add(list) }
            } catch {
                NSLog("StreamHub Twitch client ad filtering unavailable: %@", error.localizedDescription)
            }
        }
    }
}
