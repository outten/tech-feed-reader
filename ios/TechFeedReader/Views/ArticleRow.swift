import SwiftUI

/// Shared row UI for every article list (feed, bookmarks, search, tag,
/// topic) — extracted so read/unread styling stays consistent everywhere
/// instead of copy-pasted per screen.
struct ArticleRow: View {
    let article: Article

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(article.title)
                .fontWeight(article.isRead ? .regular : .semibold)
                .lineLimit(2)
            if let publishedAt = article.publishedAt {
                Text(publishedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
