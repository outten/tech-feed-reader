import SwiftUI

/// Phase 15 — first-run onboarding, mirroring the web `/welcome` flow:
/// pick topic chips, subscribe to a curated set of starter feeds per
/// topic.
struct WelcomeView: View {
    let onSubscribed: () -> Void

    @State private var chips: [OnboardingChip] = []
    @State private var selected: Set<String> = []
    @State private var isLoading = false
    @State private var isSubscribing = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("Welcome! Pick a few topics to get started — we'll subscribe you to some curated feeds.")
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(chips) { chip in
                chipRow(chip)
            }
        }
        .navigationTitle("Welcome")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await subscribe() }
                } label: {
                    if isSubscribing { ProgressView() } else { Text("Subscribe") }
                }
                .disabled(selected.isEmpty || isSubscribing)
            }
        }
        .overlay {
            if isLoading && chips.isEmpty { ProgressView() }
        }
        .task { await load() }
    }

    private func chipRow(_ chip: OnboardingChip) -> some View {
        Button {
            if selected.contains(chip.topic) { selected.remove(chip.topic) } else { selected.insert(chip.topic) }
        } label: {
            HStack {
                Text("\(chip.emoji ?? "") \(chip.label)")
                Spacer()
                if selected.contains(chip.topic) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            chips = try await APIClient.shared.fetchOnboardingChips()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func subscribe() async {
        isSubscribing = true
        defer { isSubscribing = false }
        do {
            try await APIClient.shared.subscribeOnboarding(topics: Array(selected))
            onSubscribed()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
