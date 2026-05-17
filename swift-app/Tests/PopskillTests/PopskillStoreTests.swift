@testable import Popskill
import Testing

@MainActor
struct PopskillStoreTests {
    @Test
    func selectSkillNormalizesRawSkillIDForMatrixInspector() {
        let store = PopskillStore()

        store.selectSkill("owner/repo:demo-skill")

        #expect(store.selectedSkillID == "skill:owner/repo:demo-skill")
        #expect(store.inspectorOpen == true)
    }

    @Test
    func selectCapabilityKeepsAlreadyNamespacedCapabilityID() {
        let store = PopskillStore()

        store.selectCapability("agent:engineering/backend-architect")

        #expect(store.selectedSkillID == "agent:engineering/backend-architect")
        #expect(store.inspectorOpen == true)
    }

    @Test
    func closeInspectorClearsSelection() {
        let store = PopskillStore()
        store.selectSkill("demo-skill")

        store.closeInspector()

        #expect(store.selectedSkillID == nil)
        #expect(store.inspectorOpen == false)
    }
}
