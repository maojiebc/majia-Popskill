@testable import Popskill
import Testing

struct RepositoryInputTests {
    @Test
    func parsesOwnerAndNameFields() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: " anthropics ",
            nameInput: " skills "
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
    func rejectsIncompleteInput() {
        let parts = RepositoriesViewModel.normalizedRepositoryParts(
            ownerInput: "maojiebc",
            nameInput: ""
        )

        #expect(parts?.owner == nil)
        #expect(parts?.name == nil)
    }
}
