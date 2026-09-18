import SwiftUI

/// 16:9-thumbnail grid tile with a play overlay — mirrors the web app's
/// `.youtube-video-card`. Powers YouTube's "Recent Videos" grid
/// (Phase 16), a section that has no iOS equivalent before this.
///
/// Wrapped in its own card background (not just image + floating text)
/// so adjacent tiles read as distinct units instead of a wall of
/// thumbnails — a plain image-and-text stack let neighboring thumbnails
/// visually blend together with no sense of "this is one tappable
/// video."
struct VideoGridCard: View {
    let imageURL: URL?
    let title: String
    let meta: String
    let isRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // `Color.clear` (not the AsyncImage itself) drives the 16:9
            // frame, so the size is fixed the instant the row lays out —
            // the image is only ever an overlay filling already-settled
            // bounds. Sizing the frame from the AsyncImage's own content
            // instead let the tile's height jump/relayout the moment the
            // image finished loading (visible as a flicker, and could
            // squeeze the title/meta text out of the visible row).
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    Group {
                        if let imageURL {
                            AsyncImage(url: imageURL) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.secondary.opacity(0.15)
                            }
                        } else {
                            Color.secondary.opacity(0.15)
                        }
                    }
                    .clipped()
                }
                .overlay {
                    // Dark scrim behind the play icon (matches the web's
                    // `rgba(0,0,0,0.55)` circle) — a plain white glyph
                    // reads poorly against a bright thumbnail.
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Image(systemName: "play.rectangle.fill").font(.caption2)
                    Text("Watch · \(meta)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .opacity(isRead ? 0.65 : 1.0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

let videoGridColumns = [GridItem(.adaptive(minimum: 180), spacing: 14)]
