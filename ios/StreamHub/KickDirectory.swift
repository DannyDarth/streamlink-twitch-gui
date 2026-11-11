import Foundation
import Combine

struct KickStream: Identifiable, Decodable {
    let id: String
    let slug: String
    let channel: String
    let title: String
    let viewers: Int
    let thumbnail: URL?
    let category: String

    init?(json: [String: Any]) {
        let channelData = json["channel"] as? [String: Any] ?? [:]
        let slug = (channelData["slug"] as? String) ?? (json["channel_slug"] as? String) ?? (json["slug"] as? String) ?? ""
        guard !slug.isEmpty else { return nil }
        self.slug = slug
        self.id = slug
        let user = channelData["user"] as? [String: Any] ?? [:]
        self.channel = (user["username"] as? String) ?? slug
        self.title = (json["session_title"] as? String) ?? (json["title"] as? String) ?? ""
        self.viewers = (json["viewer_count"] as? NSNumber)?.intValue ?? (json["viewers"] as? NSNumber)?.intValue ?? 0
        let categoryData = json["category"] as? [String: Any] ?? [:]
        let categories = json["categories"] as? [[String: Any]] ?? []
        self.category = (categoryData["name"] as? String) ?? (categories.first?["name"] as? String) ?? ""
        let thumbnailData = json["thumbnail"] as? [String: Any] ?? [:]
        let raw = (json["thumbnail"] as? String) ?? (json["thumbnail_url"] as? String) ?? (thumbnailData["src"] as? String) ?? (thumbnailData["url"] as? String) ?? ""
        // Do not pass untrusted non-HTTPS image URLs to AsyncImage.
        if let imageURL = URL(string: raw),
           imageURL.scheme?.lowercased() == "https",
           imageURL.host != nil {
            self.thumbnail = imageURL
        } else {
            self.thumbnail = nil
        }
    }
}

@MainActor
final class KickDirectory: ObservableObject {
    @Published private(set) var streams: [KickStream] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    private var cursor: String?
    private var loaded = false

    func refresh() async {
        guard !loading && !loadingMore else { return }
        cursor = nil
        loaded = false
        hasMore = true
        streams = []
        await fetch(append: false)
    }

    func loadInitial() async {
        guard !loaded else { return }
        await fetch(append: false)
    }

    func loadMoreIfNeeded(current: KickStream) async {
        guard hasMore && !loading && !loadingMore else { return }
        guard let index = streams.firstIndex(where: { $0.id == current.id }),
              index >= streams.count - 6 else { return }
        await fetch(append: true)
    }

    private func fetch(append: Bool) async {
        guard !loading && !loadingMore else { return }
        if append { loadingMore = true } else { loading = true }
        defer { loading = false; loadingMore = false }
        error = nil

        var components = URLComponents(string: "https://web.kick.com/api/v1/livestreams")!
        var query = [
            URLQueryItem(name: "limit", value: "24"),
            URLQueryItem(name: "sort", value: "viewer_count_desc"),
            URLQueryItem(name: "display_language", value: "en")
        ]
        if append, let cursor { query.append(URLQueryItem(name: "after", value: cursor)) }
        components.queryItems = query
        guard let url = components.url else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            // Redirects must not move Kick API data to an unexpected origin.
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.url?.scheme?.lowercased() == "https",
                  http.url?.host?.lowercased() == "web.kick.com",
                  data.count <= 5_000_000 else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONSerialization.jsonObject(with: data)
            let root = payload as? [String: Any] ?? [:]
            let wrapped = root["data"] as? [String: Any] ?? root
            let rows = (payload as? [[String: Any]])
                ?? (root["data"] as? [[String: Any]])
                ?? (wrapped["livestreams"] as? [[String: Any]])
                ?? (wrapped["data"] as? [[String: Any]])
                ?? []
            let incoming = rows.compactMap(KickStream.init(json:))
            var combined = append ? streams : []
            let existing = Set(combined.map(\.id))
            combined.append(contentsOf: incoming.filter { !existing.contains($0.id) })
            combined.sort { $0.viewers > $1.viewers }
            streams = combined
            let pagination = wrapped["pagination"] as? [String: Any] ?? [:]
            let next = (pagination["next_cursor"] as? String) ?? (wrapped["next_cursor"] as? String)
            hasMore = !rows.isEmpty && next != nil && next != cursor
            cursor = next
            loaded = true
        } catch {
            self.error = "Could not load Kick streams: \(error.localizedDescription)"
        }
    }
}
