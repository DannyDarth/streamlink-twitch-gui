import Foundation

/// Resolve a Twitch HLS master playlist using the same HTTP forward-proxy
/// approach as streamlink-ttvlol. This does not yet proxy AVPlayer media segments.
enum TwitchProxyPlaylistResolver {
    struct Result {
        let endpoint: TwitchForwardProxyDiagnostics.Endpoint
        let url: URL
        let playlist: String
        let playbackIdentity: String
        let proxyFailure: String?
    }

    enum ResolutionError: LocalizedError {
        case invalidChannel, tokenUnavailable, invalidPlaylist, noProxySucceeded(String)
        var errorDescription: String? {
            switch self {
            case .invalidChannel: return "Invalid Twitch channel"
            case .tokenUnavailable: return "Twitch did not issue a playback token"
            case .invalidPlaylist: return "Server did not return a valid HLS playlist"
            case .noProxySucceeded(let details): return "All forward proxies failed: \(details)"
            }
        }
    }

    private struct TokenResponse: Decodable {
        struct DataValue: Decodable {
            struct Token: Decodable { let value: String; let signature: String }
            let streamPlaybackAccessToken: Token?
        }
        let data: DataValue?
    }

    /// MIT-licensed level3tjg/TwitchAdBlock-inspired strategy: use a new random
    /// platform identifier for the Twitch access-token request. Unlike its
    /// Logos tweak, this runs entirely inside StreamHub's own URLSession.
    static func resolveTwitchAdBlock(channel: String, proxyBase: URL) async throws -> Result {
        guard channel.range(of: "^[A-Za-z0-9_]{3,25}$", options: .regularExpression) != nil else {
            throw ResolutionError.invalidChannel
        }
        let randomPlatform = UUID().uuidString
        let token = try await playbackToken(
            channel: channel, playerType: "site", platform: randomPlatform
        )
        var components = URLComponents(string: "https://usher.ttvnw.net/api/v2/channel/hls/\(channel.lowercased()).m3u8")!
        components.queryItems = [
            URLQueryItem(name: "sig", value: token.signature),
            URLQueryItem(name: "token", value: token.value),
            URLQueryItem(name: "allow_source", value: "true"),
            URLQueryItem(name: "allow_audio_only", value: "true"),
            URLQueryItem(name: "platform", value: randomPlatform),
            URLQueryItem(name: "supported_codecs", value: "h264"),
            URLQueryItem(name: "p", value: String(Int.random(in: 1...999999)))
        ]
        guard let url = components.url else { throw ResolutionError.invalidPlaylist }
        // The upstream project supports its own Luminous URL form. Test it first
        // and fall back to the direct randomized-platform manifest if unavailable.
        // The upstream TwitchAdBlock implementation uses /playlist/CHANNEL
        // (without .m3u8). Some servers also accept the .m3u8 suffix.
        // Try both, recording which endpoint actually succeeded.
        var proxyComponents = URLComponents(url: proxyBase, resolvingAgainstBaseURL: false)
        let prefix = proxyComponents?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let root = prefix.isEmpty ? "" : "/" + prefix
        proxyComponents?.queryItems = nil
        proxyComponents?.path = root + "/playlist/" + channel.lowercased()
        let upstreamURL = proxyComponents?.url
        proxyComponents?.path = root + "/playlist/" + channel.lowercased() + ".m3u8"
        let legacyURL = proxyComponents?.url
        let candidates: [(String, URL)] = [
            ("TwitchAdBlock /playlist/channel", upstreamURL),
            ("TwitchAdBlock /playlist/channel.m3u8", legacyURL),
            ("randomized Twitch token", url)
        ].compactMap { title, target in target.map { (title, $0) } }
        var errors: [String] = []
        for (identity, candidate) in candidates {
            do {
                var request = URLRequest(url: candidate)
                request.timeoutInterval = 12
                request.setValue("https://player.twitch.tv", forHTTPHeaderField: "Referer")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ResolutionError.invalidPlaylist
                }
                let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                guard (200...299).contains(http.statusCode) else {
                    throw ResolutionError.noProxySucceeded("HTTP \(http.statusCode), content-type \(contentType)")
                }
                guard let playlist = String(data: data, encoding: .utf8),
                      playlist.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
                    // Never display response bodies: they can include stream credentials.
                    throw ResolutionError.noProxySucceeded("HTTP \(http.statusCode), content-type \(contentType), \(data.count) bytes, not HLS")
                }
                return Result(endpoint: TwitchForwardProxyDiagnostics.firefox,
                              url: candidate, playlist: playlist, playbackIdentity: identity,
                              proxyFailure: identity == "randomized Twitch token" ? errors.joined(separator: "; ") : nil)
            } catch {
                errors.append("\(identity): \(error.localizedDescription)")
            }
        }
        throw ResolutionError.noProxySucceeded(errors.joined(separator: "; "))
    }

    static func resolve(channel: String, preference: String, allowFallback: Bool, directOnly: Bool = false, playerType: String = "site", platform: String = "web") async throws -> Result {
        guard channel.range(of: "^[A-Za-z0-9_]{3,25}$", options: .regularExpression) != nil else {
            throw ResolutionError.invalidChannel
        }
        let token = try await playbackToken(channel: channel, playerType: playerType, platform: platform)
        var components = URLComponents(string: "https://usher.ttvnw.net/api/channel/hls/\(channel).m3u8")!
        components.path = "/api/v2/channel/hls/\(channel.lowercased()).m3u8"
        components.queryItems = [
            URLQueryItem(name: "sig", value: token.signature),
            URLQueryItem(name: "token", value: token.value),
            URLQueryItem(name: "allow_source", value: "true"),
            URLQueryItem(name: "allow_audio_only", value: "true"),
            URLQueryItem(name: "platform", value: platform),
            URLQueryItem(name: "supported_codecs", value: "h264"),
            URLQueryItem(name: "p", value: String(Int.random(in: 1...999999)))
        ]
        let playlistURL = components.url!
        if directOnly {
            var request = URLRequest(url: playlistURL)
            request.setValue("https://player.twitch.tv", forHTTPHeaderField: "Referer")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let playlist = String(data: data, encoding: .utf8),
                  playlist.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
                throw ResolutionError.invalidPlaylist
            }
            return Result(endpoint: TwitchForwardProxyDiagnostics.firefox, url: playlistURL, playlist: playlist, playbackIdentity: directOnly ? "direct Twitch HLS" : "forward proxy HLS", proxyFailure: nil)
        }
        var failures: [String] = []
        for endpoint in TwitchForwardProxyDiagnostics.ordered(preference: preference, allowFallback: allowFallback) {
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 12
                configuration.timeoutIntervalForResource = 18
                configuration.connectionProxyDictionary = [
                    "HTTPEnable": 1, "HTTPProxy": endpoint.host, "HTTPPort": endpoint.port,
                    "HTTPSEnable": 1, "HTTPSProxy": endpoint.host, "HTTPSPort": endpoint.port
                ]
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                var request = URLRequest(url: playlistURL)
                request.setValue("https://player.twitch.tv", forHTTPHeaderField: "Referer")
                request.setValue("https://player.twitch.tv", forHTTPHeaderField: "Origin")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let playlist = String(data: data, encoding: .utf8),
                      playlist.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else {
                    throw ResolutionError.invalidPlaylist
                }
                return Result(endpoint: endpoint, url: playlistURL, playlist: playlist, playbackIdentity: "forward proxy HLS", proxyFailure: nil)
            } catch {
                failures.append("\(endpoint.label): \(error.localizedDescription)")
            }
        }
        throw ResolutionError.noProxySucceeded(failures.joined(separator: "; "))
    }

    private static func playbackToken(channel: String, playerType: String, platform: String) async throws -> TokenResponse.DataValue.Token {
        let url = URL(string: "https://gql.twitch.tv/gql")!
        let payload: [String: Any] = [
            "operationName": "PlaybackAccessToken",
            "variables": [
                "isLive": true, "login": channel.lowercased(), "isVod": false, "vodID": "",
                "playerType": playerType, "platform": platform
            ] as [String: Any],
            "extensions": [
                "persistedQuery": [
                    "version": 1,
                    "sha256Hash": "ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9"
                ] as [String: Any]
            ] as [String: Any]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("kimne78kx3ncx6brgo4mv6wki5h1ko", forHTTPHeaderField: "Client-ID")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let token = try JSONDecoder().decode(TokenResponse.self, from: data).data?.streamPlaybackAccessToken else {
            throw ResolutionError.tokenUnavailable
        }
        return token
    }
}
