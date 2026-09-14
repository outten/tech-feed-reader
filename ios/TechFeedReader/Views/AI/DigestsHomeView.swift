import SwiftUI

struct DigestsHomeView: View {
    @State private var digests: [DigestSummary] = []
    @State private var isLoading = false
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        List(digests) { digest in
            NavigationLink(value: digest) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(digest.subject ?? "Digest")
                    if let count = digest.articleCount {
                        Text("\(count) articles").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Digests")
        .navigationDestination(for: DigestSummary.self) { DigestDetailView(id: $0.id) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await generate() }
                } label: {
                    if isGenerating { ProgressView() } else { Text("Generate") }
                }
                .disabled(isGenerating)
            }
        }
        .overlay {
            if isLoading && digests.isEmpty { ProgressView() }
            if !isLoading && digests.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Digests Yet", systemImage: "doc.text.below.ecg")
            }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Digests", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            digests = try await APIClient.shared.fetchDigests()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            _ = try await APIClient.shared.generateDigest()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
