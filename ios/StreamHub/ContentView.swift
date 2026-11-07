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
                    ContentUnavailableViewPlaceholder()
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

private struct ContentUnavailableViewPlaceholder: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "play.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.purple)
            Text("Twitch browsing is next")
                .font(.headline)
            Text("Kick discovery is being built first. Twitch will be added in the next phase.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KickDirectoryView: View {
    @StateObject private var directory = KickDirectory()
    @State private var selectedCategory = "All"
    @State private var search = ""

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
                        KickStreamRow(stream: stream)
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
        .task { await directory.loadInitial() }
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
