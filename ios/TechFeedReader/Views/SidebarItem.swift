import Foundation

/// What the sidebar can select — the four fixed "Library" entries plus
/// whichever feed the user picked. Drives MainView's detail column.
enum SidebarItem: Hashable {
    case home
    case allArticles
    case busMode
    case lucky
    case bookmarks
    case search
    case tags
    case topics
    case discoverFeeds
    case muteRules
    case podcasts
    case youtube
    case sports
    case stocks
    case comics
    case npr
    case pbs
    case radio
    case triage
    case digests
    case account
    case feed(Feed)
}
