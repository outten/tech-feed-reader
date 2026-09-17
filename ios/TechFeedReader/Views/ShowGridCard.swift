import SwiftUI

/// Cover-art grid tile — mirrors the web app's `.podcast-show-card`,
/// which both Podcasts' "Subscribed Shows" and YouTube's "Subscribed
/// Channels" grids share (Phase 16).
struct ShowGridCard: View {
    let imageURL: URL?
    let title: String
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.secondary.opacity(0.1)
                    }
                } else {
                    Color.secondary.opacity(0.1)
                }
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(meta)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Standard two-up-on-phone, wider-on-iPad grid used by both show grids.
let showGridColumns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
