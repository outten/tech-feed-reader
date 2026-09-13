import SwiftUI

struct DigestDetailView: View {
    let id: Int

    @State private var digest: DigestDetail?
    @State private var isLoading = false
    @State private var isSummarizing = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if let digest {
                    if let summary = digest.llmSummary {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Claude Summary").font(.headline)
                            Text(summary)
                        }
                    } else {
                        Button {
                            Task { await summarize() }
                        } label: {
                            if isSummarizing { ProgressView() } else { Text("Summarize with Claude") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSummarizing)
                    }
                    Divider()
                    Text(digest.textBody ?? "")
                }
            }
            .padding()
        }
        .navigationTitle(digest?.subject ?? "Digest")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading && digest == nil { ProgressView() }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            digest = try await APIClient.shared.fetchDigestDetail(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func summarize() async {
        isSummarizing = true
        defer { isSummarizing = false }
        do {
            digest = try await APIClient.shared.summarizeDigest(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
