import SwiftUI

private enum StreamPlatform: String, CaseIterable, Identifiable {
    case twitch = "Twitch"
    case kick = "Kick"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var platform: StreamPlatform = .kick

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Platform", selection: $platform) {
                    ForEach(StreamPlatform.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if platform == .kick {
                    KickDirectoryView()
                } else {
                    TwitchDirectoryView()
                }
            }
            .navigationTitle("StreamHub")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
}

private struct TwitchDirectoryView: View {
    @State private var section = 0
    @State private var search = ""
    @State private var submittedSearch = ""
    @State private var browserResetID = UUID()

    private var browseURL: URL {
        if !submittedSearch.isEmpty {
            var components = URLComponents(string: "https://www.twitch.tv/search")!
            components.queryItems = [URLQueryItem(name: "term", value: submittedSearch)]
            return components.url!
        }
        return URL(string: section == 0
            ? "https://www.twitch.tv/directory/all"
            : "https://www.twitch.tv/directory")!
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Twitch section", selection: $section) {
                Text("Streams").tag(0)
                Text("Games").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .onChange(of: section) { _ in
                submittedSearch = ""
                search = ""
            }

            HStack(spacing: 8) {
                TextField("Search Twitch", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit { submittedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines) }
                Button {
                    submittedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("Search Twitch")
                if !submittedSearch.isEmpty {
                    Button("Clear") {
                        search = ""
                        submittedSearch = ""
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if section == 1 {
                HStack {
                    Button {
                        search = ""
                        submittedSearch = ""
                        browserResetID = UUID()
                    } label: {
                        Label("Back to Games", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Return to all Twitch game categories")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            TwitchBrowserView(url: browseURL)
                .id(browseURL.absoluteString + browserResetID.uuidString)
        }
    }
}

private struct KickDirectoryView: View {
    @StateObject private var directory = KickDirectory()
    @State private var selectedCategory = "All"
    @State private var search = ""
    @State private var kickSection = 0

    private var categories: [String] {
        ["All"] + Array(Set(directory.streams.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    private var visibleStreams: [KickStream] {
        directory.streams.filter { stream in
            (selectedCategory == "All" || stream.category == selectedCategory)
            && (search.isEmpty || stream.channel.localizedCaseInsensitiveContains(search)
                || stream.title.localizedCaseInsensitiveContains(search)
                || stream.category.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Kick section", selection: $kickSection) {
                Text("Streams").tag(0)
                Text("Games").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if kickSection == 1 {
                KickGamesView()
            } else {
            TextField("Search loaded streams or games", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        Button(category) { selectedCategory = category }
                            .buttonStyle(.bordered)
                            .tint(selectedCategory == category ? .green : .gray)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)

            if directory.loading && directory.streams.isEmpty {
                Spacer()
                ProgressView("Loading Kick streams…")
                Spacer()
            } else if let error = directory.error, directory.streams.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text(error).multilineTextAlignment(.center)
                    Button("Retry") { Task { await directory.refresh() } }
                }
                .padding()
                Spacer()
            } else {
                List {
                    ForEach(visibleStreams) { stream in
                        NavigationLink(destination: KickStreamPlayerView(stream: stream)) {
                            KickStreamRow(stream: stream)
                        }
                            .listRowSeparator(.hidden)
                            .task {
                                await directory.loadMoreIfNeeded(current: stream)
                            }
                    }
                    if directory.loadingMore {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                    if let error = directory.error, !directory.streams.isEmpty {
                        Button(error + " — Retry") {
                            Task {
                                if let last = directory.streams.last {
                                    await directory.loadMoreIfNeeded(current: last)
                                }
                            }
                        }
                    }
                    if visibleStreams.isEmpty && !directory.loading {
                        Text("No matching streams in loaded results.")
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
                .refreshable { await directory.refresh() }
            }
        }
        }
        .task(id: kickSection) {
            if kickSection == 0 { await directory.loadInitial() }
        }
    }
}

private struct KickGamesView: View {
    @StateObject private var catalog = KickGamesDirectory()
    @State private var search = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var filtered: [KickGame] {
        catalog.games.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search loaded games", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)
            if catalog.loading && catalog.games.isEmpty {
                Spacer()
                ProgressView("Loading Kick games…")
                Spacer()
            } else if catalog.games.isEmpty, let error = catalog.error {
                Spacer()
                Text(error).multilineTextAlignment(.center)
                Button("Retry") { Task { await catalog.refresh() } }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                        ForEach(filtered) { game in
                            NavigationLink(destination: KickGameDetailView(game: game)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    AsyncImage(url: game.cover) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(.gray.opacity(0.2))
                                            .overlay(Image(systemName: "gamecontroller").foregroundStyle(.secondary))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(0.78, contentMode: .fit)
                                    .clipped()
                                    .cornerRadius(10)

                                    Text(game.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(game.viewers.map { "\($0.formatted()) viewers" } ?? "Viewers unavailable")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .task { await catalog.loadMoreIfNeeded(current: game) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    if catalog.loadingMore {
                        ProgressView().padding()
                    }
                    if let error = catalog.error, !catalog.games.isEmpty {
                        Button(error + " — Retry") {
                            Task {
                                if let last = catalog.games.last {
                                    await catalog.loadMoreIfNeeded(current: last)
                                }
                            }
                        }
                        .padding()
                    }
                    if filtered.isEmpty && !catalog.loading {
                        Text("No matching games in loaded results.")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .refreshable { await catalog.refresh() }
            }
        }
        .task { await catalog.loadInitial() }
    }
}

private struct KickGameDetailView: View {
    let game: KickGame

    var body: some View {
        KickCategoryBrowserView(game: game)
            .navigationTitle(game.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct KickCategoryBrowserView: View {
    let game: KickGame
    @StateObject private var discovery = KickCategoryWebModel()
    @State private var showWebsite = false

    private var url: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "kick.com"
        components.path = "/category/" + game.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        return components.url!
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AsyncImage(url: game.cover) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.gray.opacity(0.2))
                        .overlay(Image(systemName: "gamecontroller").foregroundStyle(.secondary))
                }
                .frame(width: 48, height: 64)
                .clipped()
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name).font(.headline).lineLimit(2)
                    Text("Live streams · Kick")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    discovery.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 36, height: 40)
                }
                .accessibilityLabel("Reload live streams")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            HStack {
                Text(showWebsite ? "Kick website" : "StreamHub list")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(showWebsite ? "Show StreamHub list" : "View on Kick") {
                    showWebsite.toggle()
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            Divider()

            ZStack {
                KickCategoryDiscoveryWebView(url: url, model: discovery)
                    .opacity(showWebsite ? 1 : 0.01)
                    .allowsHitTesting(showWebsite)

                if !showWebsite {
                    if discovery.channels.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.green)
                                .controlSize(.large)
                            Text("Finding live channels…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("If streams do not appear, choose View on Kick.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("View on Kick") { showWebsite = true }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemBackground))
                    } else {
                        List {
                            ForEach(discovery.channels) { channel in
                                NavigationLink {
                                    FilteredWebPlayer(url: URL(string: "https://kick.com/" + channel.slug)!)
                                        .navigationTitle(channel.slug)
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        AsyncImage(url: channel.imageURL) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: {
                                            Rectangle().fill(.gray.opacity(0.2))
                                                .overlay(Image(systemName: "video").foregroundStyle(.secondary))
                                        }
                                        .frame(width: 136, height: 78)
                                        .clipped()
                                        .cornerRadius(8)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(channel.slug).font(.headline).lineLimit(1)
                                            Text(channel.title).font(.subheadline).lineLimit(2)
                                            Text(channel.viewers.isEmpty ? game.name : channel.viewers + " · " + game.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                }
                                .task {
                                    if channel.id == discovery.channels.last?.id {
                                        discovery.loadMore()
                                    }
                                }
                            }
                            Button("Load more streams") { discovery.loadMore() }
                                .frame(maxWidth: .infinity)
                        }
                        .listStyle(.plain)
                        .background(Color(uiColor: .systemBackground))
                    }
                }
            }
        }
        .navigationTitle(game.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct KickStreamRow: View {
    let stream: KickStream

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: stream.thumbnail) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.gray.opacity(0.2))
                    .overlay(Image(systemName: "video").foregroundStyle(.secondary))
            }
            .frame(width: 136, height: 78)
            .clipped()
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 5) {
                Text(stream.channel).font(.headline).lineLimit(1)
                Text(stream.title).font(.subheadline).lineLimit(2)
                Text("\(stream.viewers.formatted()) viewers · \(stream.category)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct KickStreamPlayerView: View {
    let stream: KickStream
    @State private var fullscreen = false

    private var playerURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "kick.com"
        components.path = "/" + stream.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        return components.url!
    }

    var body: some View {
        VStack(spacing: 0) {
            if !fullscreen {
                FilteredWebPlayer(url: playerURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .navigationTitle(stream.channel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    fullscreen = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Fullscreen player")
                ShareLink(item: playerURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share stream")
            }
        }
        .fullScreenCover(isPresented: $fullscreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                FilteredWebPlayer(url: playerURL)
                    .ignoresSafeArea()
                Button {
                    fullscreen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(13)
                        .background(.black.opacity(0.75), in: Circle())
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Exit fullscreen")
                .padding(16)
            }
            .statusBarHidden()
        }
    }
}
