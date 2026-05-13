@testable import Popskill
import Testing

struct RepositoryInputTests {
    @Test
    func parsesOwnerAndNameFields() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: " anthropics ",
            nameInput: " skills.git "
        )

        #expect(parts?.owner == "anthropics")
        #expect(parts?.name == "skills")
    }

    @Test
    func parsesOwnerSlashRepoInput() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "maojiebc/majia-skills",
            nameInput: ""
        )

        #expect(parts?.owner == "maojiebc")
        #expect(parts?.name == "majia-skills")
    }

    @Test
    func parsesGitHubURLs() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "https://github.com/maojiebc/majia-skills.git",
            nameInput: ""
        )

        #expect(parts?.owner == "maojiebc")
        #expect(parts?.name == "majia-skills")
    }

    @Test
    func parsesSSHGitHubURLs() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "git@github.com:maojiebc/majia-skills.git",
            nameInput: ""
        )

        #expect(parts?.owner == "maojiebc")
        #expect(parts?.name == "majia-skills")
    }

    @Test
    func parsesGitHubTreeURLs() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "https://github.com/maojiebc/majia-skills/tree/dev",
            nameInput: ""
        )

        #expect(parts?.owner == "maojiebc")
        #expect(parts?.name == "majia-skills")
    }

    @Test
    func stripsOnlyGitSuffix() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "maojiebc/widget.git-tools.git",
            nameInput: ""
        )

        #expect(parts?.owner == "maojiebc")
        #expect(parts?.name == "widget.git-tools")
    }

    @Test
    func rejectsIncompleteInput() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "maojiebc",
            nameInput: ""
        )

        #expect(parts?.owner == nil)
        #expect(parts?.name == nil)
    }

    @Test
    func rejectsEmptyNameAfterGitSuffixStripping() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "maojiebc",
            nameInput: ".git"
        )

        #expect(parts?.owner == nil)
        #expect(parts?.name == nil)
    }
}
