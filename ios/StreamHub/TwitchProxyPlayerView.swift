import SwiftUI
import AVKit

/// Optional HLS playlist-proxy playback. Never sends Twitch login cookies or tokens.
struct TwitchProxyPlayerView: View {
    let channel: String
    @AppStorage("streamhub.twitchProxyURL") private var proxyBase = ""
    @State private var activeProxy: URL?
    @State private var player: AVPlayer?
    @State private var hlsBridge: TwitchHLSBridge?
    @State private var message: String?
    @State private var loading = true
    @AppStorage("streamhub.twitchForwardProxyPreference") private var forwardProxyPreference = "firefox"
    @AppStorage("streamhub.twitchForwardProxyFallback") private var forwardProxyFallback = true
    @State private var forwardProxyStatus: String?
    @State private var resolvingForwardProxy = false
    @State private var playbackDiagnostics: String?
    @State private var relayDiagnostics: [String] = []
    @State private var playbackObserver: NSKeyValueObservation?

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
            Button(resolvingForwardProxy ? "Connecting…" : "Play via Firefox / Chromium proxy") {
                Task { await playForwardProxy() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(resolvingForwardProxy)
            Button("Test direct-only HLS relay (no proxy)") {
                Task { await playForwardProxy(directOnly: true) }
            }
            .buttonStyle(.bordered)
            .disabled(resolvingForwardProxy)
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
            if let playbackDiagnostics {
                Text(playbackDiagnostics)
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(.horizontal)
            }
            if !relayDiagnostics.isEmpty {
                Text(relayDiagnostics.suffix(8).joined(separator: "\n"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
        .onDisappear { playbackObserver?.invalidate(); playbackObserver = nil; player?.pause(); player = nil; hlsBridge?.stop(); hlsBridge = nil }
    }

    @MainActor
    private func playForwardProxy(directOnly: Bool = false) async {
        resolvingForwardProxy = true
        forwardProxyStatus = directOnly ? "Testing direct-only HLS relay (no proxy)…" : "Connecting to Firefox / Chromium HLS proxy…"
        defer { resolvingForwardProxy = false }
        do {
            let result = try await TwitchProxyPlaylistResolver.resolve(
                channel: channel, preference: forwardProxyPreference,
                allowFallback: forwardProxyFallback, directOnly: directOnly
            )
            let endpoints = directOnly ? [] : [result.endpoint] +
                TwitchForwardProxyDiagnostics.ordered(
                    preference: forwardProxyPreference, allowFallback: forwardProxyFallback
                ).filter { $0.host != result.endpoint.host }
            relayDiagnostics = []
            let bridge = TwitchHLSBridge(preferred: result.endpoint, endpoints: endpoints)
            bridge.onDiagnostic = { entry in
                relayDiagnostics.append(entry)
                if relayDiagnostics.count > 20 { relayDiagnostics.removeFirst(relayDiagnostics.count - 20) }
            }
            let localURL = try await bridge.start(masterURL: result.url, masterPlaylist: result.playlist)
            player?.pause()
            hlsBridge?.stop()
            hlsBridge = bridge
            let item = AVPlayerItem(url: localURL)
            playbackObserver?.invalidate()
            playbackDiagnostics = "Waiting for AVPlayer to load HLS media…"
            playbackObserver = item.observe(\.status, options: [.initial, .new]) { observed, _ in
                DispatchQueue.main.async {
                    switch observed.status {
                    case .readyToPlay:
                        playbackDiagnostics = "AVPlayer media ready. Waiting for first video frame…"
                    case .failed:
                        let details = observed.error?.localizedDescription ?? "Unknown AVPlayer error"
                        let underlying = (observed.error as NSError?)?.userInfo[NSUnderlyingErrorKey]
                        playbackDiagnostics = "AVPlayer failed: \(details)" + (underlying.map { " | \($0)" } ?? "")
                    default: break
                    }
                }
            }
            let avPlayer = AVPlayer(playerItem: item)
            player = avPlayer
            loading = false
            message = nil
            forwardProxyStatus = directOnly
                ? "DIRECT-ONLY DIAGNOSTIC: playlists and media bypass both proxies. Ads are not blocked."
                : "Playing through local HLS relay (\(result.endpoint.label) first). Ads are not guaranteed to be removed."
            avPlayer.play()
        } catch {
            forwardProxyStatus = "Forward proxy playback failed: \(error.localizedDescription)"
        }
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
            forwardProxyStatus = "\(result.endpoint.label) returned a valid HLS playlist. Use Play via Firefox / Chromium proxy to test playback."
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
