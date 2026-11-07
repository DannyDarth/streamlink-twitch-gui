import Foundation
import Combine

struct KickGame: Identifiable {
    let slug: String
    let name: String
    let cover: URL?
    let viewers: Int?
    var id: String { slug }

    init?(json: [String: Any]) {
        guard let name = (json["name"] as? String) ?? (json["slug"] as? String),
              !name.isEmpty else { return nil }
        self.name = name
        self.slug = (json["slug"] as? String) ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
        let banner = json["banner"] ?? json["thumbnail"] ?? json["image"]
        let image = banner as? [String: Any] ?? [:]
        let raw = (banner as? String) ?? (image["src"] as? String)
            ?? (image["url"] as? String) ?? (image["responsive"] as? String)
            ?? (json["banner_url"] as? String) ?? (json["thumbnail_url"] as? String) ?? ""
        let first = raw.components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).first ?? ""
        self.cover = URL(string: first)
        let value = json["viewers"] ?? json["viewer_count"]
        if let number = value as? NSNumber {
            self.viewers = number.intValue
        } else if let string = value as? String, let count = Int(string) {
            self.viewers = count
        } else {
            self.viewers = nil
        }
    }
}

@MainActor
final class KickGamesDirectory: ObservableObject {
    @Published private(set) var games: [KickGame] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var hasMore = true
    @Published private(set) var error: String?
    private var page = 1
    private var loaded = false

    func loadInitial() async {
        guard !loaded else { return }
        await fetch()
    }

    func refresh() async {
        guard !loading && !loadingMore else { return }
        page = 1
        loaded = false
        hasMore = true
        games = []
        await fetch()
    }

    func loadMoreIfNeeded(current: KickGame) async {
        guard hasMore && !loading && !loadingMore,
              let index = games.firstIndex(where: { $0.id == current.id }),
              index >= games.count - 8 else { return }
        await fetch()
    }

    private func fetch() async {
        guard !loading && !loadingMore && hasMore else { return }
        if page == 1 { loading = true } else { loadingMore = true }
        defer { loading = false; loadingMore = false }
        error = nil
        do {
            var parts = URLComponents(string: "https://kick.com/api/v1/subcategories")!
            parts.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: "32")
            ]
            var request = URLRequest(url: parts.url!)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONSerialization.jsonObject(with: data)
            let root = payload as? [String: Any] ?? [:]
            let wrapper = root["data"] as? [String: Any] ?? [:]
            let rows = (payload as? [[String: Any]])
                ?? (root["data"] as? [[String: Any]])
                ?? (wrapper["data"] as? [[String: Any]])
                ?? (root["subcategories"] as? [[String: Any]])
                ?? []
            let incoming = rows.compactMap(KickGame.init(json:))
            var seen = Set(games.map(\.id))
            games.append(contentsOf: incoming.filter { seen.insert($0.id).inserted })
            hasMore = rows.count >= 32 && !incoming.isEmpty
            page += 1
            loaded = true
        } catch {
            self.error = "Could not load Kick games: \(error.localizedDescription)"
        }
    }
}
