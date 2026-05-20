import Foundation

/// Result of scoring a `Skill` against a search query.
///
/// Used by the Library view model to rank `filteredSkills` / `filteredPackages`
/// when the user types in the toolbar search field, and by `PackageRow` to render
/// trigger chips that explain *why* a skill matched.
struct SkillSearchHit: Equatable {
    /// Higher is better. 0 is impossible (no-match returns nil).
    let score: Int
    /// The triggerScenarios that contained the query, for display as chips.
    /// Already trimmed and de-duplicated.
    let matchedTriggers: [String]
    /// True if the query landed inside the skill name. Used by the UI to decide
    /// whether to surface the capability summary as a secondary line.
    let matchedOnName: Bool
}

enum SkillSearchScorer {
    /// Score a single skill against a normalized lowercase query.
    /// Returns nil when the query does not match any searchable field.
    ///
    /// Scoring weights (descending):
    ///   name == query          1000
    ///   name hasPrefix query    500
    ///   name contains query     200
    ///   trigger contains query  100  (per matching trigger)
    ///   summary contains query   50
    ///   description contains     20
    ///   sourceLabel contains     10
    ///   directory contains        5
    static func score(skill: Skill, query: String) -> SkillSearchHit? {
        let q = query.lowercased()
        guard !q.isEmpty else { return nil }

        let name = skill.name.lowercased()
        let summary = (skill.capabilitySummary ?? "").lowercased()
        let description = skill.description.lowercased()
        let triggers = skill.triggerScenarios ?? []
        let source = skill.sourceLabel.lowercased()
        let directory = skill.directory.lowercased()

        var score = 0
        var matchedOnName = false
        var matchedTriggers: [String] = []
        var seenTriggers: Set<String> = []

        if name == q {
            score += 1000
            matchedOnName = true
        } else if name.hasPrefix(q) {
            score += 500
            matchedOnName = true
        } else if matches(name, query: q) {
            score += 200
            matchedOnName = true
        }

        for trigger in triggers {
            let lowerTrigger = trigger.lowercased()
            guard matches(lowerTrigger, query: q), !seenTriggers.contains(lowerTrigger) else {
                continue
            }
            seenTriggers.insert(lowerTrigger)
            score += 100
            matchedTriggers.append(trigger)
        }

        if !summary.isEmpty, matches(summary, query: q) {
            score += 50
        }

        if matches(description, query: q) {
            score += 20
        }

        if matches(source, query: q) {
            score += 10
        }

        if matches(directory, query: q) {
            score += 5
        }

        guard score > 0 else { return nil }

        return SkillSearchHit(
            score: score,
            matchedTriggers: matchedTriggers,
            matchedOnName: matchedOnName
        )
    }

    /// Mirror of `score(skill:query:)` for `LocalAgent`. Same weight curve, but
    /// uses `categoryLabel` and `fileName` as auxiliary fields instead of
    /// `sourceLabel`/`directory`. Returns nil when no field matches.
    static func score(agent: LocalAgent, query: String) -> SkillSearchHit? {
        let q = query.lowercased()
        guard !q.isEmpty else { return nil }

        let name = agent.name.lowercased()
        let summary = (agent.capabilitySummary ?? "").lowercased()
        let description = agent.description.lowercased()
        let triggers = agent.triggerScenarios ?? []
        let category = agent.categoryLabel.lowercased()
        let fileName = agent.fileName.lowercased()

        var score = 0
        var matchedOnName = false
        var matchedTriggers: [String] = []
        var seenTriggers: Set<String> = []

        if name == q {
            score += 1000
            matchedOnName = true
        } else if name.hasPrefix(q) {
            score += 500
            matchedOnName = true
        } else if matches(name, query: q) {
            score += 200
            matchedOnName = true
        }

        for trigger in triggers {
            let lower = trigger.lowercased()
            guard matches(lower, query: q), !seenTriggers.contains(lower) else { continue }
            seenTriggers.insert(lower)
            score += 100
            matchedTriggers.append(trigger)
        }

        if !summary.isEmpty, matches(summary, query: q) {
            score += 50
        }
        if matches(description, query: q) {
            score += 20
        }
        if matches(category, query: q) {
            score += 10
        }
        if matches(fileName, query: q) {
            score += 5
        }

        guard score > 0 else { return nil }

        return SkillSearchHit(
            score: score,
            matchedTriggers: matchedTriggers,
            matchedOnName: matchedOnName
        )
    }

    private static func matches(_ text: String, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        if text.contains(query) {
            return true
        }
        guard containsCJKScalar(query), containsCJKScalar(text) else {
            return false
        }
        return text.containsCharactersInOrder(query)
    }

    private static func containsCJKScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }
    }
}

private extension String {
    func containsCharactersInOrder(_ query: String) -> Bool {
        var searchStart = startIndex
        for character in query {
            guard let match = self[searchStart...].firstIndex(of: character) else {
                return false
            }
            searchStart = index(after: match)
        }
        return true
    }
}
