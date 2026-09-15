import Foundation

/// Header metadata shown on the article detail screen (Phase 11) — mirrors
/// the web app's `relative_time`/`reading_time_minutes`/`fmt_duration` view
/// helpers in app/main.rb.
extension Article {
    private static let dateFormatterWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let dateFormatterPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var publishedDate: Date? {
        guard let publishedAt else { return nil }
        return Self.dateFormatterWithFraction.date(from: publishedAt) ?? Self.dateFormatterPlain.date(from: publishedAt)
    }

    var relativePublishedTime: String? {
        guard let date = publishedDate else { return nil }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    /// ~200 words per minute, same estimate as the web app.
    var readingTimeMinutes: Int? {
        guard let contentText, !contentText.isEmpty else { return nil }
        let words = contentText.split { $0.isWhitespace || $0.isNewline }.count
        guard words > 0 else { return nil }
        return max(1, Int((Double(words) / 200.0).rounded()))
    }

    var audioDurationText: String? {
        guard let audioDurationSeconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = audioDurationSeconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: TimeInterval(audioDurationSeconds))
    }

    /// Falls back to the feed's cover art, mainly for podcast episodes
    /// where every episode shares the show's artwork.
    var heroImageURL: URL? {
        let own = (imageUrl?.isEmpty == false) ? imageUrl : nil
        guard let candidate = own ?? feed?.imageUrl, !candidate.isEmpty else { return nil }
        return URL(string: candidate)
    }
}
