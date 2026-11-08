import SwiftUI

@main
struct StreamHubApp: App {
    init() {
        // Retire all saved adblocking/proxy experiments before any WKWebView
        // or Twitch player is created, even if Settings is never opened.
        for key in [
            "streamhub.twitchClientAdFiltering",
            "streamhub.twitchWebAdDiagnostics",
            "streamhub.braveStyleFilteringEnabled",
            "streamhub.autoReturnOnTwitchAdMarker",
            "streamhub.twitchProxyEnabled",
            "streamhub.twitchProxyURL",
            "streamhub.twitchForwardProxyPreference",
            "streamhub.twitchForwardProxyFallback"
        ] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
