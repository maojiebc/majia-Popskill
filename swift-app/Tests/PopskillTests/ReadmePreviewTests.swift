@testable import Popskill
import Testing

struct ReadmePreviewTests {
    @Test
    func excerptDropsYAMLFrontmatter() {
        let content = """
        ---
        name: demo-skill
        description: Internal metadata
        ---

        # Demo Skill

        Use this when the user asks for a demo.
        """

        let excerpt = ReadmePreview.makeExcerpt(from: content)

        #expect(excerpt.text.hasPrefix("# Demo Skill"))
        #expect(!excerpt.text.contains("description: Internal metadata"))
        #expect(excerpt.text.contains("Use this when"))
        #expect(excerpt.truncated == false)
    }

    @Test
    func excerptCompactsBlankRunsAndTruncatesByLineCount() {
        let content = """
        # Demo


        One


        Two
        Three
        Four
        """

        let excerpt = ReadmePreview.makeExcerpt(from: content, maxCharacters: 200, maxLines: 5)

        #expect(excerpt.text == "# Demo\n\nOne\n\nTwo")
        #expect(excerpt.truncated)
    }

    @Test
    func excerptTruncatesByCharacterBudget() {
        let excerpt = ReadmePreview.makeExcerpt(
            from: "# Demo Skill\nThis line is longer than the budget.",
            maxCharacters: 12,
            maxLines: 10
        )

        #expect(excerpt.text == "# Demo Skill")
        #expect(excerpt.truncated)
    }
}
