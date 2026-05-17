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
    var updates: [SkillUpdateInfo] = [] {
        didSet {
            updateSkillIDs = Self.makeUpdateSkillIDs(from: updates)
        }
    }
    private(set) var updateSkillIDs: Set<String> = []
    var stubs: [StubbedSkill] = []
    var linkHealth: LinkHealthReport?
    var onboardScan: OnboardScanReport?
    var usageSummary: UsageSummary?
    var usageScanError: String?
    var usageScanInFlight: Bool = false

    // Per-slice refresh timestamps. Views call refresh*(force: false) from
    // .task on first appearance; if a recent refresh exists we skip the
    // sidecar round-trip. Manual refresh buttons pass force: true to bypass.
    var lastSourcesRefreshAt: Date?
    var lastUpdatesRefreshAt: Date?
    var lastBackupsRefreshAt: Date?

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
            let now = Date()
            self.skills = try await skillsTask
            self.sources = try await sourcesTask
            self.localAgents = try await agentsTask
            self.lastBootstrapAt = now
            // Bootstrap counts as a fresh sources fetch — secondary views
            // that .task into refreshSources won't double-pull immediately.
            self.lastSourcesRefreshAt = now
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: Cached refresh helpers
    //
    // Each secondary view (Sources / Updates / Backups) hits sidecar on its
    // first appearance, but switching back and forth between sidebar entries
    // doesn't need a fresh round-trip every time. A 30-second TTL keeps the
    // UI snappy without going stale; manual refresh buttons pass
    // `force: true` to bypass.

    private static let refreshTTL: TimeInterval = 30

    func refreshSources(force: Bool = false) async {
        guard !shouldSkipRefresh(lastSourcesRefreshAt, force: force) else { return }
        do {
            sources = try await client.listRepositories()
            lastSourcesRefreshAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshUpdates(force: Bool = false) async {
        guard !shouldSkipRefresh(lastUpdatesRefreshAt, force: force) else { return }
        do {
            updates = try await client.checkUpdates()
            lastUpdatesRefreshAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshBackups(force: Bool = false) async {
        guard !shouldSkipRefresh(lastBackupsRefreshAt, force: force) else { return }
        do {
            backups = try await client.listBackups()
            lastBackupsRefreshAt = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shouldSkipRefresh(_ lastRefresh: Date?, force: Bool) -> Bool {
        guard !force, let lastRefresh else { return false }
        return Date().timeIntervalSince(lastRefresh) < Self.refreshTTL
    }

    // ===== Derived =====

    var enabledSkillCount: Int {
        skills.reduce(0) { sum, skill in
            sum + TargetApp.supported.filter { skill.apps.isEnabled($0) }.count
        }
    }

    /// Unified capability list the matrix renders against. Recomputed every
    /// access — cheap, since `skills` / `localAgents` are pure value arrays
    /// and `MatrixCapability.fromX` is just a struct re-pack. Kept derived
    /// rather than stored so toggle / install / uninstall actions only need
    /// to mutate `skills` / `localAgents` and the matrix follows.
    var capabilities: [MatrixCapability] {
        skills.map(MatrixCapability.fromSkill) + localAgents.map(MatrixCapability.fromAgent)
    }

    var pendingUpdateCount: Int { updates.count }
    var brokenLinkCount: Int { linkHealth?.summary.broken ?? 0 }
    var okLinkCount: Int { linkHealth?.summary.ok ?? 0 }

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearchActive: Bool { !trimmedSearch.isEmpty }

    /// O(1) update lookup for matrix rows and filters. `SkillUpdateInfo.id`
    /// may be scoped ("owner/name:skill") or path-like, so both the full id
    /// and its useful suffixes are indexed once when `updates` changes.
    func hasPendingUpdate(for capability: MatrixCapability) -> Bool {
        guard let skillID = capability.underlyingSkillID else { return false }
        return updateIdentifierCandidates(for: skillID).contains { updateSkillIDs.contains($0) }
    }

    private func updateIdentifierCandidates(for skillID: String) -> Set<String> {
        let normalizedID = skillID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedID.isEmpty else { return [] }

        var candidates: Set<String> = [normalizedID]
        if let scopedSuffix = normalizedID.split(separator: ":").last {
            candidates.insert(String(scopedSuffix))
        }
        if let pathSuffix = normalizedID.split(separator: "/").last {
            candidates.insert(String(pathSuffix))
        }
        return candidates
    }

    func selectSkill(_ skillID: String) {
        selectCapability(MatrixCapability.skillCapabilityID(for: skillID))
    }

    func selectCapability(_ capabilityID: String) {
        selectedSkillID = capabilityID
        inspectorOpen = true
    }

    func closeInspector() {
        inspectorOpen = false
        selectedSkillID = nil
    }

    // MARK: Usage scanner

    /// Walk `~/.claude/projects/**/*.jsonl` off the main thread and post the
    /// `UsageSummary` back when done. Insights view drives this on first
    /// appearance and via its refresh button. Errors land in `usageScanError`
    /// — surfacing them lets the user know "I scanned but the dir was
    /// missing" vs. "I haven't scanned yet".
    func refreshUsageScan() async {
        guard !usageScanInFlight else { return }
        usageScanInFlight = true
        usageScanError = nil
        defer { usageScanInFlight = false }

        let scanner = TranscriptUsageScanner()
        do {
            let summary = try await Task.detached(priority: .utility) {
                try scanner.scan()
            }.value
            self.usageSummary = summary
        } catch {
            self.usageScanError = error.localizedDescription
        }
    }

    private static func makeUpdateSkillIDs(from updates: [SkillUpdateInfo]) -> Set<String> {
        Set(updates.flatMap(\.normalizedIdentifierCandidates))
    }
}
