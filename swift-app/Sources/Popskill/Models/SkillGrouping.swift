import Foundation

/// One repo bucket inside the matrix. Skills missing repo info land in the
/// `ungrouped` bucket so the list never disappears just because metadata is
/// thin. The matrix view uses `id` for the collapsed-state set.
struct MatrixGroup: Identifiable, Equatable {
    let id: String
    let owner: String?
    let name: String?
    let skills: [Skill]

    /// User-facing label. "owner/name" for a normal repo, "其他" / "Other" for
    /// the catch-all bucket — leave that translation to the call site.
    var label: String {
        if let owner, let name, !owner.isEmpty, !name.isEmpty {
            return "\(owner)/\(name)"
        }
        return id
    }

    var isUngrouped: Bool { id == SkillGrouping.ungroupedID }
}

enum SkillGrouping {
    static let ungroupedID = "ungrouped"

    /// Group skills by repo owner/name. Buckets are sorted alphabetically, with
    /// `ungrouped` always pinned at the bottom. Inside a bucket, skills sort
    /// by name (case-insensitive) so the matrix is stable across refreshes.
    static func group(_ skills: [Skill]) -> [MatrixGroup] {
        var buckets: [String: (owner: String?, name: String?, skills: [Skill])] = [:]

        for skill in skills {
            let key = bucketKey(for: skill)
            if buckets[key] == nil {
                if key == ungroupedID {
                    buckets[key] = (nil, nil, [])
                } else {
                    buckets[key] = (skill.repoOwner, skill.repoName, [])
                }
            }
            buckets[key]?.skills.append(skill)
        }

        let groups = buckets.map { key, value -> MatrixGroup in
            let sorted = value.skills.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return MatrixGroup(id: key, owner: value.owner, name: value.name, skills: sorted)
        }

        return groups.sorted(by: areInOrder)
    }

    private static func bucketKey(for skill: Skill) -> String {
        if let owner = skill.repoOwner, let name = skill.repoName,
           !owner.isEmpty, !name.isEmpty {
            return "\(owner)/\(name)"
        }
        return ungroupedID
    }

    private static func areInOrder(_ lhs: MatrixGroup, _ rhs: MatrixGroup) -> Bool {
        // Ungrouped always last.
        if lhs.id == ungroupedID { return false }
        if rhs.id == ungroupedID { return true }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }
}
