import SwiftUI

struct StockSearchView: View {
    @State private var query = ""
    @State private var results: [StockSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(results) { result in
            NavigationLink(value: StockSymbol(symbol: result.symbol)) {
                VStack(alignment: .leading) {
                    Text(result.symbol).fontWeight(.semibold)
                    if let description = result.description {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Search Stocks")
        .navigationDestination(for: StockSymbol.self) { StockDetailView(symbol: $0.symbol) }
        .searchable(text: $query, prompt: "Symbol or company name")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty { results = [] }
        }
        .overlay {
            if isLoading { ProgressView() }
            if let errorMessage {
                ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if !isLoading && results.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await APIClient.shared.searchStocks(query: query)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
