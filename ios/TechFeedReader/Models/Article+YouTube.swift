import Foundation

/// Mirrors app/main.rb's youtube_video_id/youtube_embed_url helpers —
/// client-side instead of a new backend endpoint since it's pure URL
/// parsing with no server state involved.
extension Article {
    var youtubeVideoID: String? {
        guard url.contains("youtube.com") || url.contains("youtu.be") else { return nil }
        let patterns = [
            #"[?&]v=([\w-]{11})"#,
            #"youtube\.com/(?:embed|v|shorts)/([\w-]{11})"#,
            #"youtu\.be/([\w-]{11})"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(url.startIndex..., in: url)
            if let match = regex.firstMatch(in: url, range: range), let group = Range(match.range(at: 1), in: url) {
                return String(url[group])
            }
        }
        return nil
    }

    var youtubeEmbedURL: URL? {
        guard let id = youtubeVideoID else { return nil }
        return URL(string: "https://www.youtube.com/embed/\(id)")
    }

    /// Matches the web app's `youtube_thumbnail_url` helper — every
    /// YouTube video has a guaranteed hqdefault.jpg, so this gives a
    /// grid card a thumbnail even when the article has no explicit
    /// `image_url`.
    var youtubeThumbnailURL: URL? {
        guard let id = youtubeVideoID else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")
    }
}
