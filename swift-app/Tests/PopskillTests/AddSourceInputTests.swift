@testable import Popskill
import Testing

/// Pure parser tests for `AddSourceInput.parse`. The popover that wraps it is
/// validated by tapping a real sidecar in smoke tests, but the parser itself
/// is value logic and worth locking down so future format additions don't
/// regress the existing forms.
struct AddSourceInputTests {
    @Test
    func parsesPlainOwnerNamePair() {
        let result = AddSourceInput.parse("anthropics/skills")
        #expect(result?.owner == "anthropics")
        #expect(result?.name == "skills")
        #expect(result?.branch == "main")
    }

    @Test
    func parsesOwnerNameWithBranch() {
        let result = AddSourceInput.parse("anthropics/skills@v2")
        #expect(result?.owner == "anthropics")
        #expect(result?.name == "skills")
        #expect(result?.branch == "v2")
    }

    @Test
    func tolerantOfGithubURL() {
        let result = AddSourceInput.parse("https://github.com/anthropics/skills")
        #expect(result?.owner == "anthropics")
        #expect(result?.name == "skills")
        #expect(result?.branch == "main")
    }

    @Test
    func tolerantOfGithubURLWithDotGitSuffix() {
        let result = AddSourceInput.parse("https://github.com/anthropics/skills.git")
        #expect(result?.owner == "anthropics")
        #expect(result?.name == "skills")
    }

    @Test
    func trimsLeadingTrailingWhitespace() {
        let result = AddSourceInput.parse("  anthropics/skills  ")
        #expect(result?.owner == "anthropics")
        #expect(result?.name == "skills")
    }

    @Test
    func emptyStringReturnsNil() {
        #expect(AddSourceInput.parse("") == nil)
        #expect(AddSourceInput.parse("   ") == nil)
    }

    @Test
    func malformedInputReturnsNil() {
        #expect(AddSourceInput.parse("anthropics") == nil)
        #expect(AddSourceInput.parse("anthropics/skills/extra") == nil)
        #expect(AddSourceInput.parse("/skills") == nil)
        #expect(AddSourceInput.parse("anthropics/") == nil)
    }

    @Test
    func emptyBranchAfterAtFallsBackToMain() {
        let result = AddSourceInput.parse("anthropics/skills@")
        #expect(result?.branch == "main")
    }
}
