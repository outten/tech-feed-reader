import SwiftUI
import Charts

struct StockDetailView: View {
    let symbol: String

    @State private var detail: StockDetail?
    @State private var news: [Article] = []
    @State private var isFollowed = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var history: StockHistoryResponse?
    @State private var selectedDays = 30
    @State private var isLoadingHistory = false
    private static let dayRanges = [7, 30, 60, 90]

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if let quote = detail?.quote {
                Section("Quote") {
                    if let price = quote.price {
                        HStack {
                            Text("Price")
                            Spacer()
                            Text(String(format: "%.2f", price))
                        }
                    }
                    if let change = quote.change, let changePct = quote.changePct {
                        HStack {
                            Text("Change")
                            Spacer()
                            Text(String(format: "%+.2f (%+.2f%%)", change, changePct))
                                .foregroundStyle(change >= 0 ? .green : .red)
                        }
                    }
                }
            }
            if detail?.quote != nil {
                Section {
                    Picker("Range", selection: $selectedDays) {
                        ForEach(Self.dayRanges, id: \.self) { Text("\($0)D").tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let points = history?.points, !points.isEmpty {
                        Chart(points, id: \.t) {
                            LineMark(x: .value("Date", $0.date), y: .value("Price", $0.c))
                            AreaMark(x: .value("Date", $0.date), y: .value("Price", $0.c))
                                .foregroundStyle(.linearGradient(
                                    colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
                                ))
                        }
                        .chartYAxis { AxisMarks(position: .trailing) }
                        .frame(height: 180)
                    } else if isLoadingHistory {
                        ProgressView().frame(height: 180, alignment: .center)
                    } else {
                        Text("No chart data available").foregroundStyle(.secondary).frame(height: 180, alignment: .center)
                    }
                }
            }
            if !news.isEmpty {
                Section("News") {
                    ForEach(news) { article in
                        NavigationLink(value: article) {
                            ArticleRow(article: article)
                        }
                    }
                }
            }
        }
        .navigationTitle(detail?.quote?.name ?? symbol)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isFollowed ? "Unfollow" : "Follow") {
                    Task { await toggleFollow() }
                }
            }
        }
        .navigationDestination(for: Article.self) { ArticleDetailView(article: $0) }
        .overlay {
            if isLoading && detail == nil { ProgressView() }
        }
        .task { await load() }
        .task(id: selectedDays) { await loadHistory() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let detailResult = APIClient.shared.fetchStockDetail(symbol: symbol)
            async let newsResult = APIClient.shared.fetchStockNews(symbol: symbol)
            detail = try await detailResult
            news = try await newsResult
            isFollowed = detail?.followed ?? false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        history = try? await APIClient.shared.fetchStockHistory(symbol: symbol, days: selectedDays)
    }

    private func toggleFollow() async {
        do {
            if isFollowed {
                try await APIClient.shared.unfollowStock(symbol: symbol)
            } else {
                try await APIClient.shared.followStock(symbol: symbol, name: detail?.quote?.name)
            }
            isFollowed.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
