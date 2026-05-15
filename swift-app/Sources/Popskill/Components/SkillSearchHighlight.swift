import SwiftUI

/// State a `PackageRow` needs to render the search-active variant: highlighted name,
/// optional capability summary in place of the package summary, and trigger chips.
struct PackageRowSearchState {
    let query: String
    let hit: SkillSearchHit
    /// Capability summary copied from the standalone underlying skill (when available).
    /// Composite packages have no underlying skill and supply nil — the row falls back
    /// to `package.summary`.
    let capabilitySummary: String?
}

/// Wrap every case-insensitive occurrence of `query` in `text` with accent-tinted
/// background and foreground attributes. Returns a plain `AttributedString` when
/// `query` is nil/empty so callers can pass through unconditionally.
func highlightedSearchString(_ text: String, query: String?) -> AttributedString {
    var attr = AttributedString(text)

    guard let query, !query.isEmpty else {
        return attr
    }

    let lower = text.lowercased()
    let q = query.lowercased()
    guard !lower.isEmpty, !q.isEmpty else {
        return attr
    }

    var searchStart = lower.startIndex
    while searchStart < lower.endIndex,
          let range = lower.range(of: q, range: searchStart..<lower.endIndex) {
        let lowerDistance = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let upperDistance = lower.distance(from: lower.startIndex, to: range.upperBound)

        let attrLower = attr.index(attr.startIndex, offsetByCharacters: lowerDistance)
        let attrUpper = attr.index(attr.startIndex, offsetByCharacters: upperDistance)

        attr[attrLower..<attrUpper].backgroundColor = Color.accentColor.opacity(0.20)
        attr[attrLower..<attrUpper].foregroundColor = Color.accentColor

        searchStart = range.upperBound
    }

    return attr
}
