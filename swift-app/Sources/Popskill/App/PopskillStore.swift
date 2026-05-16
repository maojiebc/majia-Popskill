import Foundation
import Observation

/// Single source of truth for the v0.3 Popskill app — replaces the 7 separate
/// ViewModels (Library / Agents / Repositories / Backups / Insights / Settings /
/// Idle) of the v0.1-v0.2 era. The HTML prototype settled on a single
/// `state` object backing every view, so SwiftUI follows the same shape.
///
/// Bootstrap loads the bare minimum (installed skills + sources). Per-view
/// data (link health, transcript usage, update list) is lazy-loaded the first
/// time the relevant view appears. See each sprint's view file for the
/// per-view loader.
@MainActor
@Observable
final class PopskillStore {
    // ===== Data slices =====
    var skills: [Skill] = []
    var unmanagedSkills: [UnmanagedSkill] = []
    var localAgents: [LocalAgent] = []
    var agentTargets: [AgentTarget] = []
    var sources: [SkillRepository] = []
    var backups: [SkillBackup] = []
    var updates: [SkillUpdateInfo] = []
    var stubs: [StubbedSkill] = []
    var linkHealth: LinkHealthReport?
    var onboardScan: OnboardScanReport?

    // ===== UI state =====
    /// Initial selection honors `POPSKILL_DEFAULT_VIEW` when set (used by
    /// screenshot tooling). Defaults to the matrix.
    var currentSelection: SidebarSelection = {
        if let raw = ProcessInfo.processInfo.environment["POPSKILL_DEFAULT_VIEW"],
           let v = SidebarSelection(rawValue: raw) {
            return v
        }
        return .matrix
    }()
    var searchText: String = ""
    var selectedSkillID: String? = nil
    var inspectorOpen: Bool = false
    /// Honors `POPSKILL_DEFAULT_OVERLAY=spotlight` for screenshot tooling.
    var spotlightOpen: Bool = {
        ProcessInfo.processInfo.environment["POPSKILL_DEFAULT_OVERLAY"] == "spotlight"
    }()
    /// Toggled by Settings → "Re-run onboarding" and by the first-launch hook
    /// in `RootView`. S6 binds the wizard sheet to this flag. Honors
    /// `POPSKILL_DEFAULT_OVERLAY=onboarding` for screenshot tooling.
    var onboardingOpen: Bool = {
        ProcessInfo.processInfo.environment["POPSKILL_DEFAULT_OVERLAY"] == "onboarding"
    }()

    // ===== Matrix state =====
    var matrixFilter: MatrixFilter = .all
    var matrixTypeFilter: MatrixTypeFilter = .allTypes
    /// Repo groups the user has explicitly collapsed. Set is keyed by
    /// `MatrixGroup.id` (== "owner/name" or "ungrouped").
    var collapsedGroups: Set<String> = []

    // ===== System state =====
    var lastBootstrapAt: Date?
    var lastSyncAt: Date?
    var lastSyncProvider: String = "git"
    var isLoading: Bool = false
    var errorMessage: String?

    // ===== Services =====
    let client = SkillCLIClient()

    // Per-skill toggle / uninstall in-flight tracking so the matrix can dim
    // controls during pending IO.
    var pendingToggles: Set<String> = []
    var pendingUninstalls: Set<String> = []

    init() {}

    // ===== Bootstrap =====

    /// Called once on app launch. Loads the data slices every view depends on.
    /// Per-view detail (insights / link health / onboard scan) is fetched on
    /// demand by each view's `.task` modifier.
    func bootstrap() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        async let skillsTask = client.list()
        async let sourcesTask = client.listRepositories()
        async let agentsTask = client.listAgents()

        do {
            self.skills = try await skillsTask
            self.sources = try await sourcesTask
            self.localAgents = try await agentsTask
            self.lastBootstrapAt = Date()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // ===== Derived =====

    var enabledSkillCount: Int {
        skills.reduce(0) { sum, skill in
            sum + TargetApp.supported.filter { skill.apps.isEnabled($0) }.count
        }
    }

    var pendingUpdateCount: Int { updates.count }
    var brokenLinkCount: Int { linkHealth?.summary.broken ?? 0 }
    var okLinkCount: Int { linkHealth?.summary.ok ?? 0 }

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearchActive: Bool { !trimmedSearch.isEmpty }

    func selectSkill(_ id: String) {
        selectedSkillID = id
        inspectorOpen = true
    }

    func closeInspector() {
        inspectorOpen = false
        selectedSkillID = nil
    }
}
