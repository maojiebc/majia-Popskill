import Foundation

struct PackageSearchHit: Equatable {
    let score: Int
    let matchedComponents: [String]
    let matchedOnName: Bool

    static let recent = PackageSearchHit(score: 0, matchedComponents: [], matchedOnName: false)
}

enum PackageSearchScorer {
    static func score(package: CapabilityPackage, query: String) -> PackageSearchHit? {
        let q = normalized(query)
        guard !q.isEmpty else {
            return nil
        }

        var score = 0
        var matchedOnName = false
        var matchedComponents: [String] = []

        let nameScore = scoreText(package.name, query: q, exact: 1_000, prefix: 760, contains: 430)
        if nameScore > 0 {
            score += nameScore
            matchedOnName = true
        }

        score += scoreText(package.id, query: q, exact: 420, prefix: 260, contains: 160)
        score += scoreText(package.vendor ?? "", query: q, exact: 340, prefix: 220, contains: 120)
        score += scoreText(package.source.location, query: q, exact: 360, prefix: 240, contains: 140)
        score += scoreText(package.summary, query: q, exact: 180, prefix: 120, contains: 70)

        if ["bundle", "package", "suite", "套装"].contains(q) {
            score += package.type == .composite ? 220 : 80
        }

        var seenComponents: Set<String> = []
        for component in package.components.all {
            let componentScore = scoreComponent(component, query: q)
            guard componentScore > 0 else { continue }
            score += component.installed ? componentScore : max(20, componentScore - 35)

            let label = component.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !label.isEmpty, !seenComponents.contains(label.lowercased()) {
                seenComponents.insert(label.lowercased())
                matchedComponents.append(label)
            }
        }

        guard score > 0 else {
            return nil
        }

        return PackageSearchHit(
            score: score,
            matchedComponents: Array(matchedComponents.prefix(3)),
            matchedOnName: matchedOnName
        )
    }

    private static func scoreComponent(_ component: PackageComponent, query: String) -> Int {
        scoreText(component.name, query: query, exact: 260, prefix: 190, contains: 120)
            + scoreText(component.id, query: query, exact: 220, prefix: 150, contains: 90)
            + scoreText(component.kind, query: query, exact: 140, prefix: 90, contains: 40)
            + scoreText(component.location ?? "", query: query, exact: 180, prefix: 120, contains: 80)
            + scoreText(component.status, query: query, exact: 80, prefix: 50, contains: 25)
    }

    private static func scoreText(
        _ text: String,
        query: String,
        exact: Int,
        prefix: Int,
        contains: Int
    ) -> Int {
        let value = normalized(text)
        guard !value.isEmpty else { return 0 }
        if value == query { return exact }
        if value.hasPrefix(query) { return prefix }
        if value.contains(query) { return contains }
        return 0
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
