import SwiftUI

struct SettingsView: View {
    @State private var proxyProbeResults: [String] = []
    @State private var probing = false

    @AppStorage("streamhub.twitchProxyEnabled") private var twitchProxyEnabled = false
    @AppStorage("streamhub.twitchProxyURL") private var twitchProxyURL = ""
    @AppStorage("streamhub.twitchForwardProxyPreference") private var forwardProxyPreference = "firefox"
    @AppStorage("streamhub.twitchForwardProxyFallback") private var forwardProxyFallback = true

    var body: some View {
        Form {
            Section("Twitch stream playback") {
                Toggle("Use proxy player for Twitch streams", isOn: $twitchProxyEnabled)
                TextField("HTTPS playlist proxy URL", text: $twitchProxyURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Text("An HTTPS playlist proxy can use the /playlist/CHANNEL.m3u8 format. An optional example is https://luminous.level3tjg.me, published by the TwitchAdBlock developer. Third-party proxies can see your IP and channel requests. Video ads may still appear.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if twitchProxyEnabled && !twitchProxyURL.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("https://") {
                    Text("Enter an HTTPS proxy URL to enable native playback.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Section("HTTP forward proxy diagnostics") {
                Picker("Preferred proxy", selection: $forwardProxyPreference) {
                    Text("Firefox first").tag("firefox")
                    Text("Chromium first").tag("chromium")
                }
                Toggle("Try second proxy if first fails", isOn: $forwardProxyFallback)
                Text("Firefox: firefox.api.cdn-perfprod.com:2023")
                    .font(.caption).textSelection(.enabled)
                Text("Chromium: chromium.api.cdn-perfprod.com:2023")
                    .font(.caption).textSelection(.enabled)
                Button(probing ? "Checking proxies…" : "Test proxy connectivity") {
                    probing = true
                    proxyProbeResults = []
                    Task {
                        let endpoints = TwitchForwardProxyDiagnostics.ordered(
                            preference: forwardProxyPreference, allowFallback: forwardProxyFallback)
                        for endpoint in endpoints {
                            let result = await TwitchForwardProxyDiagnostics.probe(endpoint)
                            await MainActor.run { proxyProbeResults.append(result) }
                        }
                        await MainActor.run { probing = false }
                    }
                }
                .disabled(probing)
                ForEach(proxyProbeResults, id: \.self) { result in
                    Text(result).font(.caption).textSelection(.enabled)
                }
                Text("These are HTTP forward proxies, not HTTPS playlist endpoints. This saves the preferred order for a future native proxy transport; it does not yet route video traffic through them. The HTTPS playlist proxy player above remains the only active proxy playback mode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
