import SwiftUI

/// 16:9-thumbnail grid tile with a play-icon overlay — mirrors the web
/// app's `.youtube-video-card`. Powers YouTube's "Recent Videos" grid
/// (Phase 16), a section that has no iOS equivalent before this.
struct VideoGridCard: View {
    let imageURL: URL?
    let title: String
    let meta: String
    let isRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
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
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(meta)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(isRead ? 0.65 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

let videoGridColumns = [GridItem(.adaptive(minimum: 170), spacing: 12)]
