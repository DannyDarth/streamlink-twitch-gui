import SwiftUI

struct SettingsView: View {
    @ObservedObject private var adBlocking = AdBlockingSettings.shared

    @AppStorage("streamhub.twitchProxyEnabled") private var twitchProxyEnabled = false
    @AppStorage("streamhub.twitchProxyURL") private var twitchProxyURL = ""

    var body: some View {
        Form {
            Section("Experimental Twitch proxy playback") {
                Toggle("Use proxy player for Twitch streams", isOn: $twitchProxyEnabled)
                TextField("HTTPS playlist proxy base URL", text: $twitchProxyURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("Enter a trusted TTV.LOL-compatible HTTPS playlist proxy. StreamHub requests /playlist/CHANNEL.m3u8 and opens it in a native video player. If unavailable, use Open on Twitch. Public proxies may see your IP address and channel requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if twitchProxyEnabled && !twitchProxyURL.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("https://") {
                    Text("Enter an HTTPS proxy URL to enable native playback.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
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
