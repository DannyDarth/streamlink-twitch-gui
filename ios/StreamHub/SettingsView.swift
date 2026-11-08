import SwiftUI

/// Clean slate for Twitch playback experiments. The previous adblocking and
/// proxy controls are intentionally removed from Settings.
struct SettingsView: View {
    private let retiredKeys = [
        "streamhub.twitchClientAdFiltering",
        "streamhub.twitchWebAdDiagnostics",
        "streamhub.braveStyleFilteringEnabled",
        "streamhub.autoReturnOnTwitchAdMarker",
        "streamhub.twitchProxyEnabled",
        "streamhub.twitchProxyURL",
        "streamhub.twitchForwardProxyPreference",
        "streamhub.twitchForwardProxyFallback"
    ]

    var body: some View {
        Form {
            Section("Playback") {
                Text("Twitch and Kick use their regular players.")
                Text("Previous experimental adblocking, playlist proxy, and forward-proxy settings have been retired while we prepare a fresh implementation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            // Remove persisted opt-ins, including those left enabled by older
            // sideloaded builds. Default behavior is ordinary web playback.
            for key in retiredKeys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
