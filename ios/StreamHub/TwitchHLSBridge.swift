import Foundation
import Network

/// Local HLS bridge: AVPlayer reads localhost URLs while URLSession fetches
/// upstream playlists and media through the selected HTTP CONNECT proxy.
/// This bridge is scoped to a single player and must be stopped on dismissal.
final class TwitchHLSBridge {
    private let queue = DispatchQueue(label: "streamhub.hls.bridge")
    var onDiagnostic: ((String) -> Void)?
    private func log(_ message: String) { DispatchQueue.main.async { [weak self] in self?.onDiagnostic?(message) } }
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let lock = NSLock()
    private var resources: [String: URL] = [:]
    private var nextID = 0
    private let endpoints: [TwitchForwardProxyDiagnostics.Endpoint]
    private let preferred: TwitchForwardProxyDiagnostics.Endpoint
    private let sessionByHost: [String: URLSession]
    private(set) var port: UInt16 = 0

    init(preferred: TwitchForwardProxyDiagnostics.Endpoint,
         endpoints: [TwitchForwardProxyDiagnostics.Endpoint]) {
        self.preferred = preferred
        self.endpoints = endpoints
        var sessions: [String: URLSession] = [:]
        for endpoint in endpoints {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 35
            config.connectionProxyDictionary = [
                "HTTPEnable": 1, "HTTPProxy": endpoint.host, "HTTPPort": endpoint.port,
                "HTTPSEnable": 1, "HTTPSProxy": endpoint.host, "HTTPSPort": endpoint.port
            ]
            sessions[endpoint.host] = URLSession(configuration: config)
        }
        sessionByHost = sessions
    }

    func start(masterURL: URL, masterPlaylist: String) async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            let gate = NSLock()
            var completed = false
            func finish(_ result: Result<URL, Error>) {
                gate.lock()
                defer { gate.unlock() }
                guard !completed else { return }
                completed = true
                continuation.resume(with: result)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self, let port = listener.port?.rawValue else {
                        finish(.failure(URLError(.cannotConnectToHost)))
                        return
                    }
                    self.port = port
                    self.log("Local HLS server ready on port \(port)")
                    self.lock.lock()
                    self.resources["master"] = masterURL
                    self.lock.unlock()
                    finish(.success(URL(string: "http://127.0.0.1:\(port)/master.m3u8")!))
                case .failed(let error): finish(.failure(error))
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection, masterPlaylist: masterPlaylist, masterURL: masterURL)
            }
            listener.start(queue: queue)
        }
    }

    private func handle(_ connection: NWConnection, masterPlaylist: String, masterURL: URL) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  let first = request.components(separatedBy: "\r\n").first,
                  (first.hasPrefix("GET ") || first.hasPrefix("HEAD ")),
                  let path = first.split(separator: " ").dropFirst().first else {
                self.reply(connection, status: 400, contentType: "text/plain", body: Data())
                return
            }
            let isHead = first.hasPrefix("HEAD ")
            let rangeHeader = request.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("range:") }?.dropFirst(6).trimmingCharacters(in: .whitespaces)
            let cleanPath = String(path).components(separatedBy: "?").first ?? ""
            self.log("Local request: \(first)")
            if cleanPath == "/master.m3u8" {
                let body = self.rewrite(masterPlaylist, base: masterURL)
                self.reply(connection, status: 200, contentType: "application/vnd.apple.mpegurl",
                           body: Data(body.utf8), headOnly: isHead)
                return
            }
            let identifier = String(cleanPath.dropFirst())
            self.lock.lock()
            let upstream = self.resources[identifier]
            self.lock.unlock()
            guard let upstream else {
                self.log("Missing local resource: \(identifier)")
                self.reply(connection, status: 404, contentType: "text/plain", body: Data())
                return
            }
            Task {
                do {
                    let (bytes, response) = try await self.fetch(upstream, range: rangeHeader)
                    self.log("Fetched \(upstream.pathExtension.isEmpty ? "media" : upstream.pathExtension): \(bytes.count) bytes, HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
                    let isPlaylist = upstream.pathExtension.lowercased() == "m3u8" ||
                        type.contains("mpegurl") || bytes.starts(with: Data("#EXTM3U".utf8))
                    if isPlaylist, let text = String(data: bytes, encoding: .utf8) {
                        self.reply(connection, status: 200, contentType: "application/vnd.apple.mpegurl",
                                   body: Data(self.rewrite(text, base: upstream).utf8), headOnly: isHead)
                    } else {
                        let upstreamStatus = (response as? HTTPURLResponse)?.statusCode ?? 200
                        let contentRange = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range")
                        self.reply(connection, status: upstreamStatus,
                                   contentType: type.isEmpty ? "application/octet-stream" : type,
                                   body: bytes, headOnly: isHead, contentRange: contentRange)
                    }
                } catch {
                    self.log("Upstream fetch failed: \(error.localizedDescription)")
                    self.reply(connection, status: 502, contentType: "text/plain",
                               body: Data(error.localizedDescription.utf8))
                }
            }
        }
    }

    private func fetch(_ url: URL, range: String? = nil) async throws -> (Data, URLResponse) {
        var lastError: Error = URLError(.cannotConnectToHost)
        for endpoint in endpoints {
            guard let session = sessionByHost[endpoint.host] else { continue }
            do {
                var request = URLRequest(url: url)
                request.setValue("https://player.twitch.tv", forHTTPHeaderField: "Referer")
                if let range { request.setValue(range, forHTTPHeaderField: "Range") }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                return (data, response)
            } catch { lastError = error }
        }
        throw lastError
    }

    private func register(_ reference: String, base: URL) -> String {
        guard let resolved = URL(string: reference, relativeTo: base)?.absoluteURL,
              resolved.scheme == "https" || resolved.scheme == "http" else { return reference }
        lock.lock()
        nextID += 1
        let key = "hls\(nextID)" + (resolved.pathExtension.isEmpty ? "" : "." + resolved.pathExtension)
        resources[key] = resolved
        lock.unlock()
        return "http://127.0.0.1:\(port)/\(key)"
    }

    private func rewrite(_ playlist: String, base: URL) -> String {
        playlist.components(separatedBy: "\n").map { line in
            if line.hasPrefix("#") {
                // HLS keys, maps, and media URI attributes also need local URLs.
                let pattern = "URI=\\\"([^\\\"]+)\\\""
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return line }
                let ns = line as NSString
                let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
                var output = line
                for match in matches.reversed() {
                    let uri = ns.substring(with: match.range(at: 1))
                    let replacement = register(uri, base: base)
                    if let range = Range(match.range(at: 1), in: output) {
                        output.replaceSubrange(range, with: replacement)
                    }
                }
                return output
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? line : register(trimmed, base: base)
        }.joined(separator: "\n")
    }

    private func reply(_ connection: NWConnection, status: Int, contentType: String,
                       body: Data, headOnly: Bool = false, contentRange: String? = nil) {
        let reason = status == 200 ? "OK" : status == 206 ? "Partial Content" : "Error"
        var header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n"
        if let contentRange { header += "Content-Range: \(contentRange)\r\n" }
        header += "\r\n"
        var payload = Data(header.utf8)
        if !headOnly { payload.append(body) }
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let active = connections
        connections.removeAll()
        lock.unlock()
        active.forEach { $0.cancel() }
        sessionByHost.values.forEach { $0.invalidateAndCancel() }
    }

    deinit { stop() }
}
