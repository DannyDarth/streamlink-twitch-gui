import SwiftUI

private enum StreamPlatform: String, CaseIterable, Identifiable {
    case twitch = "Twitch"
    case kick = "Kick"
    var id: String { rawValue }
    var tint: Color { self == .twitch ? Color(red: 0.57, green: 0.27, blue: 1) : .green }
}

struct ContentView: View {
    @State private var platform: StreamPlatform = .kick

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Platform", selection: $platform) {
                    ForEach(StreamPlatform.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(platform.tint)

                Text("\(platform.rawValue) streams")
                    .font(.title2.bold())
                Text("StreamHub iOS is ready for live discovery integration.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 30)
            .navigationTitle("StreamHub")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
}
