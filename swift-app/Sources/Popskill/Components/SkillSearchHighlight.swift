import SwiftUI

/// Shared search-active row state used by every Library/Agent row that wants
/// to highlight matches and surface trigger chips. Owners pick a sensible
/// `capabilitySummary` (e.g. underlying skill's summary for a standalone
/// package, agent's own summary for an AgentRow) or nil to fall back to the
/// row's default description text.
struct LibrarySearchRowState {
    let query: String
    let hit: SkillSearchHit
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
