import Foundation

/// One bucket inside the matrix. The bucket key is either a repo source
/// ("owner/name") or the catch-all `ungrouped`. With the v0.4 matrix
/// extension we group within a single capability `kind`, so the same source
/// bucket can appear in multiple kind sections.
struct MatrixGroup: Identifiable, Equatable {
    let id: String
    let owner: String?
    let name: String?
    let capabilities: [MatrixCapability]

    var label: String {
        if let owner, let name, !owner.isEmpty, !name.isEmpty {
            return "\(owner)/\(name)"
        }
        return id
    }

    var isUngrouped: Bool { id == SkillGrouping.ungroupedID }
}

/// One slice of the matrix per capability kind, plus its grouped buckets.
/// MatrixView renders kind sections in order and the kind chip filter trims
/// this list down before display.
struct CapabilitySection: Identifiable, Equatable {
    let kind: CapabilityKind
    let groups: [MatrixGroup]

    var id: String { kind.rawValue }
    var totalCount: Int { groups.reduce(0) { $0 + $1.capabilities.count } }
}

enum SkillGrouping {
    static let ungroupedID = "ungrouped"

    /// Group capabilities first by `CapabilityKind`, then by `owner/name`
    /// source bucket. Inside each bucket capabilities sort by name
    /// (case-insensitive). Ungrouped is always pinned at the bottom of each
    /// kind section, and kinds without any capabilities are dropped.
    static func sections(_ capabilities: [MatrixCapability]) -> [CapabilitySection] {
        let byKind: [CapabilityKind: [MatrixCapability]] = Dictionary(grouping: capabilities, by: \.kind)
        return CapabilityKind.allCases.compactMap { kind in
            guard let bucket = byKind[kind], !bucket.isEmpty else { return nil }
            return CapabilitySection(kind: kind, groups: group(bucket))
        }
    }

    /// Group a homogeneous capability bucket by `owner/name`. Kept as a
    /// public helper for tests + the special-case "skills only" view in
    /// SpotlightView.
    static func group(_ capabilities: [MatrixCapability]) -> [MatrixGroup] {
        var buckets: [String: (owner: String?, name: String?, capabilities: [MatrixCapability])] = [:]

        for capability in capabilities {
            let key = bucketKey(for: capability)
            if buckets[key] == nil {
                if key == ungroupedID {
                    buckets[key] = (nil, nil, [])
                } else {
                    buckets[key] = (capability.repoOwner, capability.repoName, [])
                }
            }
            buckets[key]?.capabilities.append(capability)
        }

        let groups = buckets.map { key, value -> MatrixGroup in
            let sorted = value.capabilities.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return MatrixGroup(id: key, owner: value.owner, name: value.name, capabilities: sorted)
        }

        return groups.sorted(by: areInOrder)
    }

    private static func bucketKey(for capability: MatrixCapability) -> String {
        if let owner = capability.repoOwner, let name = capability.repoName,
           !owner.isEmpty, !name.isEmpty {
            return "\(owner)/\(name)"
        }
        return ungroupedID
    }

    private static func areInOrder(_ lhs: MatrixGroup, _ rhs: MatrixGroup) -> Bool {
        if lhs.id == ungroupedID { return false }
        if rhs.id == ungroupedID { return true }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }
}
