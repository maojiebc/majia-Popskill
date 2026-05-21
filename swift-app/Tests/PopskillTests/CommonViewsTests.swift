@testable import Popskill
import Testing

struct CommonViewsTests {
    @Test
    func avatarPaletteIndexIsStable() {
        let first = InitialAvatarView.stablePaletteIndex(for: "owner/repo:skill", paletteCount: 6)
        let second = InitialAvatarView.stablePaletteIndex(for: "owner/repo:skill", paletteCount: 6)

        #expect(first == second)
    }

    @Test
    func avatarPaletteIndexStaysInRange() {
        let index = InitialAvatarView.stablePaletteIndex(for: "skill", paletteCount: 6)

        #expect((0..<6).contains(index))
    }

    @Test
    func avatarPaletteIndexHandlesEmptyPalettes() {
        let index = InitialAvatarView.stablePaletteIndex(for: "skill", paletteCount: 0)

        #expect(index == 0)
    }

    @Test
    func packageAvatarInitialsFollowMajiaDashRules() {
        #expect(PackageAvatar.computeInitials(for: "caveman") == "CA")
        #expect(PackageAvatar.computeInitials(for: "lark-doc") == "LD")
        #expect(PackageAvatar.computeInitials(for: "majia-ota-skill") == "MOS")
        #expect(PackageAvatar.computeInitials(for: "baoyu-article-illustrator") == "BAI")
        #expect(PackageAvatar.computeInitials(for: "baoyu-image-cards-helper") == "BIC")
        #expect(PackageAvatar.computeInitials(for: "agent-skill-pack-cli-tool") == "ASP")
    }

    @Test
    func packageAvatarInitialsHandleEdges() {
        #expect(PackageAvatar.computeInitials(for: "_internal-skill") == "IS")
        #expect(PackageAvatar.computeInitials(for: "lark-doc-v2") == "LDV")
        #expect(PackageAvatar.computeInitials(for: "  opennews  ") == "OP")
        #expect(PackageAvatar.computeInitials(for: "---") == "S")
    }

    @Test
    func packageComponentTreePrefixMarksLastRow() {
        #expect(PackageComponentTreePrefix.value(index: 0, count: 1) == "└─")
        #expect(PackageComponentTreePrefix.value(index: 0, count: 3) == "├─")
        #expect(PackageComponentTreePrefix.value(index: 1, count: 3) == "├─")
        #expect(PackageComponentTreePrefix.value(index: 2, count: 3) == "└─")
        #expect(PackageComponentTreePrefix.value(index: 0, count: 0) == "├─")
    }

    @Test
    func sectionAccentIndexWrapsForwardAndBackward() {
        #expect(PopskillSectionAccent.index(for: 0) == 0)
        #expect(PopskillSectionAccent.index(for: 4) == 0)
        #expect(PopskillSectionAccent.index(for: -1) == 3)
    }
}
