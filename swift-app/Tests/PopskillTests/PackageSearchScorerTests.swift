@testable import Popskill
import Testing

struct PackageSearchScorerTests {
    @Test
    func queryMatchesPackageNameAndSource() {
        let package = demoPackage()

        let hit = PackageSearchScorer.score(package: package, query: "feishu")

        #expect(hit != nil)
        #expect(hit?.matchedOnName == true)
        #expect((hit?.score ?? 0) > 700)
    }

    @Test
    func queryMatchesComponentNamesAndKinds() {
        let package = demoPackage()

        let cliHit = PackageSearchScorer.score(package: package, query: "lark-cli")
        let mcpHit = PackageSearchScorer.score(package: package, query: "mcp")

        #expect(cliHit?.matchedComponents == ["lark-cli"])
        #expect(mcpHit?.matchedComponents.contains("Lark OpenAPI MCP") == true)
    }

    @Test
    func spaceSeparatedQueryMatchesDashedComponentName() {
        let package = demoPackage()

        let hit = PackageSearchScorer.score(package: package, query: "lark cli")

        #expect(hit?.matchedComponents == ["lark-cli"])
        #expect((hit?.score ?? 0) > 0)
    }

    @Test
    func separatedQueryMatchesCompactRepositoryName() {
        let package = demoPackage(
            sourceLocation: "github.com/larksuite/cli",
            repoOwner: "larksuite",
            repoName: "cli"
        )

        let hit = PackageSearchScorer.score(package: package, query: "lark suite")

        #expect(hit != nil)
    }

    @Test
    func unrelatedQueryReturnsNil() {
        let package = demoPackage()

        #expect(PackageSearchScorer.score(package: package, query: "pdf") == nil)
    }

    private func demoPackage(
        sourceLocation: String = "popskill/builtin/lark",
        repoOwner: String = "larksuite",
        repoName: String = "cli"
    ) -> CapabilityPackage {
        CapabilityPackage(
            id: "pkg:lark",
            type: .composite,
            name: "Feishu / Lark",
            vendor: "ByteDance",
            summary: "Composite office package",
            source: PackageSource(
                kind: "builtin",
                location: sourceLocation,
                updateStrategy: "manual",
                repoOwner: repoOwner,
                repoName: repoName,
                repoBranch: "main",
                readmeUrl: nil
            ),
            components: PackageComponents(
                cli: [
                    PackageComponent(
                        id: "lark-cli",
                        name: "lark-cli",
                        kind: "cli",
                        required: true,
                        installed: true,
                        status: "detected",
                        location: nil
                    )
                ],
                skills: [
                    PackageComponent(
                        id: "lark-doc",
                        name: "Lark Doc",
                        kind: "skill",
                        required: true,
                        installed: true,
                        status: "installed",
                        location: "lark-doc"
                    )
                ],
                mcp: [
                    PackageComponent(
                        id: "lark-openapi-mcp",
                        name: "Lark OpenAPI MCP",
                        kind: "mcp",
                        required: false,
                        installed: false,
                        status: "registry-reference",
                        location: "anthropic-mcp-registry/bytedance/lark-openapi-mcp"
                    )
                ],
                agents: []
            ),
            configSchema: [],
            installed: true,
            lifecycle: .untracked
        )
    }
}
