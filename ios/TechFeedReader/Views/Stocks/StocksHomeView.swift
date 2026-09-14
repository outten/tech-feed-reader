import SwiftUI

/// Wraps a bare symbol string for navigation — avoids using raw
/// String as a .navigationDestination key, which could collide with
/// an unrelated String-valued destination elsewhere in the stack.
struct StockSymbol: Hashable {
    let symbol: String
}

struct StockSearchRoot: Hashable {}

struct StocksHomeView: View {
    @State private var ticker: [TickerEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List(ticker) { entry in
            NavigationLink(value: StockSymbol(symbol: entry.symbol)) {
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.symbol).fontWeight(.semibold)
                        if let name = entry.name {
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let price = entry.price {
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.2f", price))
                            if let changePct = entry.changePct {
                                Text(String(format: "%+.2f%%", changePct))
                                    .font(.caption)
                                    .foregroundStyle(changePct >= 0 ? .green : .red)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Stocks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Search", value: StockSearchRoot())
            }
        }
        .navigationDestination(for: StockSearchRoot.self) { _ in StockSearchView() }
        .navigationDestination(for: StockSymbol.self) { StockDetailView(symbol: $0.symbol) }
        .overlay {
            if isLoading && ticker.isEmpty { ProgressView() }
            if let errorMessage {
                ContentUnavailableView("Couldn't Load Ticker", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            ticker = try await APIClient.shared.fetchStockTicker()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
