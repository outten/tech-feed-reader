import Foundation

/// What the sidebar can select — the four fixed "Library" entries plus
/// whichever feed the user picked. Drives MainView's detail column.
enum SidebarItem: Hashable {
    case bookmarks
    case search
    case tags
    case topics
    case discoverFeeds
    case muteRules
    case feed(Feed)
}
