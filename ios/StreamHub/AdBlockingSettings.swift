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

    private init() {
        enabled = UserDefaults.standard.object(forKey: "streamhub.adBlockingEnabled") as? Bool ?? true
    }

    /// Conservative rules: block known third-party ad/tracking hosts, not video or
    /// platform API endpoints. Server-side ads inside HLS cannot be removed here.
    private let rules = """
    [
      {"trigger":{"url-filter":".*","if-domain":["*doubleclick.net","*googlesyndication.com","*googleadservices.com","*adnxs.com","*pubmatic.com","*rubiconproject.com","*taboola.com","*outbrain.com"]},"action":{"type":"block"}}
    ]
    """

    func configure(_ controller: WKUserContentController) async {
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
        } catch {
            NSLog("StreamHub: could not compile web content filtering rules: %@", String(describing: error))
        }
    }
}
