import SwiftUI

struct RadioStationsView: View {
    @EnvironmentObject var audioPlayer: AudioPlayerViewModel
    @State private var groups: [RadioGroup] = []
    @State private var followedIds: Set<Int> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(groups) { group in
                Section(group.group) {
                    ForEach(group.stations) { station in
                        HStack {
                            Button {
                                if let playable = PlayableItem(radioStation: station) {
                                    audioPlayer.play(playable)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                    if let genre = station.genre {
                                        Text(genre).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Button {
                                Task { await toggleFollow(station) }
                            } label: {
                                Image(systemName: followedIds.contains(station.id) ? "heart.fill" : "heart")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Radio")
        .overlay {
            if isLoading && groups.isEmpty { ProgressView() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.fetchRadioStations()
            groups = response.groups
            followedIds = Set(response.followedIds)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow(_ station: RadioStation) async {
        do {
            if followedIds.contains(station.id) {
                try await APIClient.shared.unfollowRadioStation(id: station.id)
                followedIds.remove(station.id)
            } else {
                try await APIClient.shared.followRadioStation(id: station.id)
                followedIds.insert(station.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
