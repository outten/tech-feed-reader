import SwiftUI

struct TriageDetailView: View {
    let id: Int

    @State private var detail: TriageDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let detail {
                section("Must Read", entries: detail.mustRead)
                section("Optional", entries: detail.optional)
                section("Skip", entries: detail.skip)
            }
        }
        .navigationTitle("Triage")
        .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
        .overlay {
            if isLoading && detail == nil { ProgressView() }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func section(_ title: String, entries: [TriageEntry]) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    if let article = entry.article {
                        NavigationLink(value: article) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(article.title)
                                if let rationale = entry.rationale {
                                    Text(rationale).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await APIClient.shared.fetchTriageDetail(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
