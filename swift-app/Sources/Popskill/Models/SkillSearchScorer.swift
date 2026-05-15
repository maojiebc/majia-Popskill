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
        } else if name.contains(q) {
            score += 200
            matchedOnName = true
        }

        for trigger in triggers {
            let lowerTrigger = trigger.lowercased()
            guard lowerTrigger.contains(q), !seenTriggers.contains(lowerTrigger) else {
                continue
            }
            seenTriggers.insert(lowerTrigger)
            score += 100
            matchedTriggers.append(trigger)
        }

        if !summary.isEmpty, summary.contains(q) {
            score += 50
        }

        if description.contains(q) {
            score += 20
        }

        if source.contains(q) {
            score += 10
        }

        if directory.contains(q) {
            score += 5
        }

        guard score > 0 else { return nil }

        return SkillSearchHit(
            score: score,
            matchedTriggers: matchedTriggers,
            matchedOnName: matchedOnName
        )
    }
}
