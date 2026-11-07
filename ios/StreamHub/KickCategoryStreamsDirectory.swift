import Foundation
import Combine

/// Fetches live channels for a specific Kick game rather than filtering global results.
@MainActor
final class KickCategoryStreamsDirectory: ObservableObject {
    @Published private(set) var streams: [KickStream] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingMore = false
    @Published private(set) var hasMore = true
    @Published private(set) var error: String?

    private let slug: String
    private var page = 1
    private var loaded = false
    private let pageSize = 24

    init(slug: String) { self.slug = slug }

    func loadInitial() async {
        guard !loaded else { return }
        await fetch()
    }

    func refresh() async {
        guard !loading && !loadingMore else { return }
        page = 1
        loaded = false
        hasMore = true
        streams = []
        await fetch()
    }

    func loadMoreIfNeeded(current: KickStream) async {
        guard hasMore && !loading && !loadingMore,
              let index = streams.firstIndex(where: { $0.id == current.id }),
              index >= streams.count - 6 else { return }
        await fetch()
    }

    private func fetch() async {
        guard !loading && !loadingMore && hasMore else { return }
        if page == 1 { loading = true } else { loadingMore = true }
        defer { loading = false; loadingMore = false }
        error = nil

        do {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "kick.com"
            components.path = "/api/v2/categories/" + slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)! + "/livestreams"
            components.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "sort", value: "viewer_count_desc")
            ]
            guard let url = components.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONSerialization.jsonObject(with: data)
            let root = payload as? [String: Any] ?? [:]
            let wrapper = root["data"] as? [String: Any] ?? root
            let rows = (payload as? [[String: Any]])
                ?? (root["data"] as? [[String: Any]])
                ?? (root["livestreams"] as? [[String: Any]])
                ?? (wrapper["data"] as? [[String: Any]])
                ?? (wrapper["livestreams"] as? [[String: Any]])
                ?? []
            let incoming = rows.compactMap(KickStream.init(json:))
            var seen = Set(streams.map(\.id))
            streams.append(contentsOf: incoming.filter { seen.insert($0.id).inserted })
            streams.sort { $0.viewers > $1.viewers }
            let pagination = (wrapper["pagination"] as? [String: Any]) ?? [:]
            let totalPages = (pagination["total_pages"] as? NSNumber)?.intValue
                ?? (root["last_page"] as? NSNumber)?.intValue
                ?? (wrapper["last_page"] as? NSNumber)?.intValue
            hasMore = totalPages.map { page < $0 } ?? (rows.count >= pageSize)
            page += 1
            loaded = true
        } catch {
            self.error = "Could not load streams for this game: \(error.localizedDescription)"
        }
    }
}
