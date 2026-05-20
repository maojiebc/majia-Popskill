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

enum MatrixSortMode: String, CaseIterable, Identifiable {
    case typeDescending
    case typeAscending
    case nameAscending
    case nameDescending
    case callsDescending
    case tokensDescending
    case recentDescending

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .typeDescending: return "matrix.sort.typeDescending"
        case .typeAscending: return "matrix.sort.typeAscending"
        case .nameAscending: return "matrix.sort.nameAscending"
        case .nameDescending: return "matrix.sort.nameDescending"
        case .callsDescending: return "matrix.sort.callsDescending"
        case .tokensDescending: return "matrix.sort.tokensDescending"
        case .recentDescending: return "matrix.sort.recentDescending"
        }
    }

    var symbolName: String {
        switch self {
        case .typeDescending: return "arrow.down"
        case .typeAscending: return "arrow.up"
        case .nameAscending: return "textformat.abc"
        case .nameDescending: return "textformat.abc.dottedunderline"
        case .callsDescending: return "phone.arrow.up.right"
        case .tokensDescending: return "number"
        case .recentDescending: return "clock.arrow.circlepath"
        }
    }
}

enum SkillGrouping {
    static let ungroupedID = "ungrouped"

    /// Group capabilities first by `CapabilityKind`, then by `owner/name`
    /// source bucket. The active matrix sort chooses the row order inside
    /// each bucket. Ungrouped is always pinned at the bottom of each kind
    /// section, and kinds without any capabilities are dropped.
    static func sections(
        _ capabilities: [MatrixCapability],
        sort: MatrixSortMode = .typeDescending,
        usageIndex: MatrixUsageIndex? = nil
    ) -> [CapabilitySection] {
        let byKind: [CapabilityKind: [MatrixCapability]] = Dictionary(grouping: capabilities, by: \.kind)
        let kindOrder: [CapabilityKind] = sort == .typeAscending
            ? Array(CapabilityKind.allCases.reversed())
            : CapabilityKind.allCases

        return kindOrder.compactMap { kind in
            guard let bucket = byKind[kind], !bucket.isEmpty else { return nil }
            return CapabilitySection(kind: kind, groups: group(bucket, sort: sort, usageIndex: usageIndex))
        }
    }

    /// Group a homogeneous capability bucket by `owner/name`. Kept as a
    /// public helper for tests + the special-case "skills only" view in
    /// SpotlightView.
    static func group(
        _ capabilities: [MatrixCapability],
        sort: MatrixSortMode = .typeDescending,
        usageIndex: MatrixUsageIndex? = nil
    ) -> [MatrixGroup] {
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
            let sorted = sortCapabilities(value.capabilities, sort: sort, usageIndex: usageIndex)
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

    private static func sortCapabilities(
        _ capabilities: [MatrixCapability],
        sort: MatrixSortMode,
        usageIndex: MatrixUsageIndex?
    ) -> [MatrixCapability] {
        capabilities.sorted { lhs, rhs in
            switch sort {
            case .nameDescending:
                return nameCompare(lhs, rhs) == .orderedDescending
            case .callsDescending:
                let lhsUsage = usage(for: lhs, usageIndex: usageIndex)
                let rhsUsage = usage(for: rhs, usageIndex: usageIndex)
                if lhsUsage.calls != rhsUsage.calls { return lhsUsage.calls > rhsUsage.calls }
                if lhsUsage.tokens != rhsUsage.tokens { return lhsUsage.tokens > rhsUsage.tokens }
                return nameCompare(lhs, rhs) == .orderedAscending
            case .tokensDescending:
                let lhsUsage = usage(for: lhs, usageIndex: usageIndex)
                let rhsUsage = usage(for: rhs, usageIndex: usageIndex)
                if lhsUsage.tokens != rhsUsage.tokens { return lhsUsage.tokens > rhsUsage.tokens }
                if lhsUsage.calls != rhsUsage.calls { return lhsUsage.calls > rhsUsage.calls }
                return nameCompare(lhs, rhs) == .orderedAscending
            case .recentDescending:
                let lhsUsage = usage(for: lhs, usageIndex: usageIndex)
                let rhsUsage = usage(for: rhs, usageIndex: usageIndex)
                if lhsUsage.lastUsedAt != rhsUsage.lastUsedAt {
                    if let lhsDate = lhsUsage.lastUsedAt, let rhsDate = rhsUsage.lastUsedAt {
                        return lhsDate > rhsDate
                    }
                    return lhsUsage.lastUsedAt != nil
                }
                if lhsUsage.calls != rhsUsage.calls { return lhsUsage.calls > rhsUsage.calls }
                return nameCompare(lhs, rhs) == .orderedAscending
            case .typeAscending, .typeDescending, .nameAscending:
                return nameCompare(lhs, rhs) == .orderedAscending
            }
        }
    }

    private static func nameCompare(_ lhs: MatrixCapability, _ rhs: MatrixCapability) -> ComparisonResult {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    }

    private static func usage(
        for capability: MatrixCapability,
        usageIndex: MatrixUsageIndex?
    ) -> (calls: Int, tokens: Int64, lastUsedAt: Date?) {
        if let packageID = capability.underlyingPackageID,
           let snapshot = usageIndex?.packageSnapshot(for: packageID) {
            return (snapshot.usageEvents, snapshot.totalTokens, snapshot.lastUsedAt)
        }

        if let skillID = capability.underlyingSkillID,
           let snapshot = usageIndex?.skillSnapshot(for: skillID) {
            return (snapshot.usageEvents, snapshot.totalTokens, snapshot.lastUsedAt)
        }

        return (0, 0, nil)
    }

    private static func areInOrder(_ lhs: MatrixGroup, _ rhs: MatrixGroup) -> Bool {
        if lhs.id == ungroupedID { return false }
        if rhs.id == ungroupedID { return true }
        return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
    }
}
