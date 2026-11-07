import SwiftUI

struct SettingsView: View {
    @ObservedObject private var adBlocking = AdBlockingSettings.shared

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Block web advertisements", isOn: $adBlocking.enabled)
                Text("Filters selected advertising and tracking requests in StreamHub's embedded web player. It does not guarantee ad-free streams, and cannot remove advertisements inserted directly into video.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
