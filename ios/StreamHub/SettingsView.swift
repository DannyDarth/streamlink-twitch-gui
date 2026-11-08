import SwiftUI

struct SettingsView: View {
    @ObservedObject private var adBlocking = AdBlockingSettings.shared

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Block web advertisements", isOn: $adBlocking.enabled)
                Toggle("Experimental Twitch ad filtering", isOn: $adBlocking.experimentalTwitchFiltering)
                    .disabled(!adBlocking.enabled)
                Text("Experimental filtering hides selected Twitch ad labels, but cannot reliably remove pre-roll or mid-roll video ads. Reopen the Twitch page after changing this setting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Filters selected advertising and tracking requests in StreamHub's embedded web player. It does not guarantee ad-free streams, and cannot remove advertisements inserted directly into video.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
