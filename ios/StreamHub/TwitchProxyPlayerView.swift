import SwiftUI
import AVKit

/// Optional HLS playlist-proxy playback. Never sends Twitch login cookies or tokens.
struct TwitchProxyPlayerView: View {
    let channel: String
    @AppStorage("streamhub.twitchProxyURL") private var proxyBase = ""
    @State private var activeProxy: URL?
    @State private var player: AVPlayer?
    @State private var message: String?
    @State private var loading = true
    @AppStorage("streamhub.twitchForwardProxyPreference") private var forwardProxyPreference = "firefox"
    @AppStorage("streamhub.twitchForwardProxyFallback") private var forwardProxyFallback = true
    @State private var forwardProxyStatus: String?
    @State private var resolvingForwardProxy = false

    private var twitchURL: URL {
        URL(string: "https://www.twitch.tv/" + channel)!
    }

    private var proxyCandidates: [URL] {
        let configured = proxyBase.trimmingCharacters(in: .whitespacesAndNewlines)
        // Use the repository author's published HTTPS playlist endpoint as a
        // fallback when no custom endpoint is set. No opaque tweak binary is embedded.
        let raw = configured.isEmpty ? "https://luminous.level3tjg.me" : configured
        guard let base = URLComponents(string: raw),
              base.scheme?.lowercased() == "https", base.host != nil,
              base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil else { return [] }
        let prefix = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let root = prefix.isEmpty ? "" : "/" + prefix
        return [root + "/playlist/" + channel + ".m3u8",
                root + "/playlist/" + channel].compactMap { path -> URL? in
            var components = base
            components.path = path
            components.queryItems = [
                URLQueryItem(name: "platform", value: "web"),
                URLQueryItem(name: "allow_source", value: "true"),
                URLQueryItem(name: "allow_audio_only", value: "true")
            ]
            return components.url
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            } else if loading {
                ProgressView("Connecting to proxy…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            Button("Test Firefox / Chromium HLS playlist") {
                Task { await testForwardProxyPlaylist() }
            }
            .disabled(resolvingForwardProxy)
            if let forwardProxyStatus {
                Text(forwardProxyStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Retry HTTPS playlist proxy") { Task { await start() } }
                .buttonStyle(.bordered)
            Link("Open on Twitch (normal playback)", destination: twitchURL)
                .buttonStyle(.borderedProminent)
            Text("Experimental: Based on the TwitchAdBlock HLS proxy approach. Playback may fail or contain ads. Twitch chat is not included.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
        }
        .padding(.top)
        .navigationTitle(channel)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: proxyBase) { await start() }
        .onDisappear { player?.pause(); player = nil }
    }

    @MainActor
    private func testForwardProxyPlaylist() async {
        resolvingForwardProxy = true
        forwardProxyStatus = "Resolving Twitch playlist through forward proxies…"
        defer { resolvingForwardProxy = false }
        do {
            let result = try await TwitchProxyPlaylistResolver.resolve(
                channel: channel,
                preference: forwardProxyPreference,
                allowFallback: forwardProxyFallback
            )
            forwardProxyStatus = "\(result.endpoint.label) returned a valid HLS playlist. Media playback via HTTP forward proxy is not implemented yet."
        } catch {
            forwardProxyStatus = error.localizedDescription
        }
    }

    @MainActor
    private func start() async {
        player?.pause()
        player = nil
        loading = true
        message = nil
        guard !proxyCandidates.isEmpty else {
            loading = false
            message = "Enter a valid HTTPS playlist proxy URL in Settings."
            return
        }
        var failures: [String] = []
        for url in proxyCandidates {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 12
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let text = String(data: data, encoding: .utf8),
                      text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
                    throw URLError(.badServerResponse)
                }
                let avPlayer = AVPlayer(url: url)
                activeProxy = url
                player = avPlayer
                loading = false
                avPlayer.play()
                return
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        loading = false
        message = "HTTPS playlist proxy unavailable: " + failures.joined(separator: "; ") +
            ". Try another server or use normal Twitch playback."

    }
}

private extension String {
    var withLeadingSlash: String { hasPrefix("/") ? self : "/" + self }
}
