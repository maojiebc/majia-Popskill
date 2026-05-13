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
    func sectionAccentIndexWrapsForwardAndBackward() {
        #expect(PopskillSectionAccent.index(for: 0) == 0)
        #expect(PopskillSectionAccent.index(for: 4) == 0)
        #expect(PopskillSectionAccent.index(for: -1) == 3)
    }
}
