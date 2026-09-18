import Foundation

/// Mirrors app/main.rb's `slugify` helper — used to compute a catalog
/// "notable player" chip's slug (`"#{team_slug}-#{slugify(name)}"`)
/// client-side so tapping a name can hit GET /api/v1/sports/players/:slug
/// without a new backend endpoint just for this lookup.
func slugify(_ s: String) -> String {
    let nfkd = (s as NSString).decomposedStringWithCompatibilityMapping
    let ascii = nfkd.unicodeScalars.filter { $0.value <= 0x7F }
    var result = String(String.UnicodeScalarView(ascii)).lowercased()
    result = result.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    while result.hasPrefix("-") { result.removeFirst() }
    while result.hasSuffix("-") { result.removeLast() }
    return result
}
