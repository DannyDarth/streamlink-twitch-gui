import Foundation
import WebKit

/// Compatibility shim for existing web player call sites.
/// The previous ad and cosmetic filters have been removed from StreamHub iOS.
/// Twitch playback filtering is now handled by optional HLS proxy playback.
@MainActor
final class AdBlockingSettings {
    static let shared = AdBlockingSettings()
    private init() {}
    func configure(_ controller: WKUserContentController, forTwitch: Bool = false) async {
        controller.removeAllContentRuleLists()
    }
}
