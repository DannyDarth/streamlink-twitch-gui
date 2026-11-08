import Foundation

/// Probes HTTP CONNECT proxies using URLSession, independently of AVPlayer.
/// A successful probe proves only that an HTTPS request traversed the proxy;
/// it does not mean AVPlayer can play HLS through that proxy.
enum TwitchForwardProxyDiagnostics {
    struct Endpoint {
        let label: String
        let host: String
        let port: Int
    }

    static let firefox = Endpoint(label: "Firefox PerfProd", host: "firefox.api.cdn-perfprod.com", port: 2023)
    static let chromium = Endpoint(label: "Chromium PerfProd", host: "chromium.api.cdn-perfprod.com", port: 2023)

    static func ordered(preference: String, allowFallback: Bool) -> [Endpoint] {
        let first = preference == "chromium" ? chromium : firefox
        let second = preference == "chromium" ? firefox : chromium
        return allowFallback ? [first, second] : [first]
    }

    static func probe(_ endpoint: Endpoint) async -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": endpoint.host,
            "HTTPPort": endpoint.port,
            "HTTPSEnable": 1,
            "HTTPSProxy": endpoint.host,
            "HTTPSPort": endpoint.port
        ]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: URL(string: "https://www.twitch.tv/robots.txt")!)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "\(endpoint.label): unexpected response"
            }
            return "\(endpoint.label): HTTP \(http.statusCode) (connectivity only)"
        } catch {
            return "\(endpoint.label): \(error.localizedDescription)"
        }
    }
}
