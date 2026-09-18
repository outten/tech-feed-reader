import SwiftUI

struct TriageHomeView: View {
    @State private var runs: [TriageSummary] = []
    @State private var isLoading = false
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        List(runs) { run in
            NavigationLink(value: run) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.generatedAt ?? "Triage run")
                    if let unreadCount = run.unreadCount {
                        Text("\(unreadCount) unread").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Triage")
        .navigationDestination(for: TriageSummary.self) { TriageDetailView(id: $0.id) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await runTriage() }
                } label: {
                    if isRunning { ProgressView() } else { Text("Run") }
                }
                .disabled(isRunning)
            }
        }
        .overlay {
            if isLoading && runs.isEmpty { ProgressView() }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Triage", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            runs = try await APIClient.shared.fetchTriageRuns()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runTriage() async {
        isRunning = true
        defer { isRunning = false }
        do {
            _ = try await APIClient.shared.runTriage()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
