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
    var packages: [CapabilityPackage] = []
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
    var updatesRefreshInFlight: Bool = false
    var readmePreviewStates: [String: ReadmePreviewLoadState] = [:]

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
    /// Composite packages are expanded by default so the matrix immediately
    /// shows the component tree from the reference design. Users can collapse
    /// noisy bundles without hiding the whole source group.
    var collapsedPackageIDs: Set<String> = []

    // ===== System state =====
    var lastBootstrapAt: Date?
    var lastSyncAt: Date?
    var lastSyncProvider: String = "git"
    var isLoading: Bool = false
    var errorMessage: String?

    // ===== Services =====
    let client: SkillCLIClient

    // Per-skill toggle / uninstall in-flight tracking so the matrix can dim
    // controls during pending IO.
    var pendingToggles: Set<String> = []
    var pendingUninstalls: Set<String> = []

    init(client: SkillCLIClient = SkillCLIClient()) {
        self.client = client
    }

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
        async let packagesTask = loadPackagesBestEffort()
        async let stubsTask = loadStubsBestEffort()

        do {
            let now = Date()
            self.skills = try await skillsTask
            self.sources = try await sourcesTask
            self.localAgents = try await agentsTask
            self.packages = await packagesTask
            self.stubs = await stubsTask
            self.lastBootstrapAt = now
            // Bootstrap counts as a fresh sources fetch — secondary views
            // that .task into refreshSources won't double-pull immediately.
            self.lastSourcesRefreshAt = now
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func loadPackagesBestEffort() async -> [CapabilityPackage] {
        do {
            return try await client.listPackages()
        } catch {
            return []
        }
    }

    private func loadStubsBestEffort() async -> [StubbedSkill] {
        do {
            return try await client.listStubs()
        } catch {
            return []
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
        guard !updatesRefreshInFlight else { return }
        guard !shouldSkipRefresh(lastUpdatesRefreshAt, force: force) else { return }
        updatesRefreshInFlight = true
        defer { updatesRefreshInFlight = false }

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

    func refreshStubs() async {
        do {
            stubs = try await client.listStubs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func upsertStub(_ stub: StubbedSkill) {
        stubs.removeAll { $0.skill.id == stub.skill.id }
        stubs.append(stub)
        stubs.sort { $0.stubbedAt > $1.stubbedAt }
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
        compositePackages.map { MatrixCapability.fromPackage($0, skills: skills) }
            + skills.map(MatrixCapability.fromSkill)
            + localAgents.map(MatrixCapability.fromAgent)
    }

    var compositePackages: [CapabilityPackage] {
        packages.filter { $0.type == .composite }
    }

    var bundleCount: Int { compositePackages.count }
    var pendingUpdateCount: Int { updates.count }
    var brokenLinkCount: Int { linkHealth?.summary.broken ?? 0 }
    var okLinkCount: Int { linkHealth?.summary.ok ?? 0 }

    var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearchActive: Bool { !trimmedSearch.isEmpty }

    func showMatrix(
        filter: MatrixFilter = .all,
        typeFilter: MatrixTypeFilter = .allTypes,
        clearSearch: Bool = true
    ) {
        currentSelection = .matrix
        matrixFilter = filter
        matrixTypeFilter = typeFilter
        inspectorOpen = false
        selectedSkillID = nil
        if clearSearch {
            searchText = ""
        }
    }

    func showSettings() {
        currentSelection = .settings
    }

    func matrixFilterCount(_ filter: MatrixFilter) -> Int {
        capabilities.filter { filter.includes(capability: $0, store: self) }.count
    }

    func matrixTypeFilterCount(_ typeFilter: MatrixTypeFilter) -> Int {
        capabilities.filter { typeFilter.includes(capability: $0) }.count
    }

    func matrixShortcutCounts() -> MatrixShortcutCounts {
        let currentCapabilities = capabilities
        let filterCounts = Dictionary(uniqueKeysWithValues: MatrixFilter.allCases.map { filter in
            (filter, currentCapabilities.filter { filter.includes(capability: $0, store: self) }.count)
        })
        let typeCounts = Dictionary(uniqueKeysWithValues: MatrixTypeFilter.allCases.map { filter in
            (filter, currentCapabilities.filter { filter.includes(capability: $0) }.count)
        })
        return MatrixShortcutCounts(
            capabilityCount: currentCapabilities.count,
            filterCounts: filterCounts,
            typeCounts: typeCounts
        )
    }

    /// O(1) update lookup for matrix rows and filters. `SkillUpdateInfo.id`
    /// may be scoped ("owner/name:skill") or path-like, so both the full id
    /// and its useful suffixes are indexed once when `updates` changes.
    func hasPendingUpdate(for capability: MatrixCapability) -> Bool {
        if let package = capability.package {
            return updates.contains { update in
                package.matchingSkillComponent(for: update) != nil
            }
        }
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

    func togglePackageExpansion(_ packageID: String) {
        if collapsedPackageIDs.contains(packageID) {
            collapsedPackageIDs.remove(packageID)
        } else {
            collapsedPackageIDs.insert(packageID)
        }
    }

    func skill(for component: PackageComponent) -> Skill? {
        skills.first { component.matchesSkill($0) }
    }

    func closeInspector() {
        inspectorOpen = false
        selectedSkillID = nil
    }

    // MARK: README previews

    func readmePreviewState(for skill: Skill) -> ReadmePreviewLoadState? {
        readmePreviewStates[skill.id]
    }

    func loadReadmePreview(for skill: Skill, force: Bool = false) async {
        if !force {
            switch readmePreviewStates[skill.id] {
            case .loading, .loaded:
                return
            case .failed, .none:
                break
            }
        }

        guard let readmeURL = skill.markdownURL else {
            readmePreviewStates[skill.id] = .failed(ReadmePreviewError.missing.localizedDescription)
            return
        }

        let skillID = skill.id
        let skillName = skill.name
        readmePreviewStates[skillID] = .loading

        do {
            let preview = try await Task.detached(priority: .utility) {
                try ReadmePreview.load(
                    skillID: skillID,
                    skillName: skillName,
                    readmeURL: readmeURL
                )
            }.value
            readmePreviewStates[skillID] = .loaded(preview)
        } catch {
            readmePreviewStates[skillID] = .failed(error.localizedDescription)
        }
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

struct MatrixShortcutCounts: Equatable {
    let capabilityCount: Int
    private let filterCounts: [MatrixFilter: Int]
    private let typeCounts: [MatrixTypeFilter: Int]

    init(
        capabilityCount: Int,
        filterCounts: [MatrixFilter: Int],
        typeCounts: [MatrixTypeFilter: Int]
    ) {
        self.capabilityCount = capabilityCount
        self.filterCounts = filterCounts
        self.typeCounts = typeCounts
    }

    func count(for filter: MatrixFilter) -> Int {
        filterCounts[filter] ?? 0
    }

    func count(for filter: MatrixTypeFilter) -> Int {
        typeCounts[filter] ?? 0
    }
}
