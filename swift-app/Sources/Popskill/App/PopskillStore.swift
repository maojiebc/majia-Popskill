import Foundation
import Observation

func popskillUserHomeDirectoryURL() -> URL {
    if let home = ProcessInfo.processInfo.environment["HOME"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !home.isEmpty {
        return URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
    }
    return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
}

private func popskillDefaultCapabilityIDFromEnvironment() -> String? {
    let raw = ProcessInfo.processInfo.environment["POPSKILL_DEFAULT_CAPABILITY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw, !raw.isEmpty else { return nil }
    for prefix in ["bundle:", "skill:", "agent:", "cli:", "mcp:", "config:"] {
        if raw.hasPrefix(prefix) {
            return raw
        }
    }
    return "skill:\(raw)"
}

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
    private static let lastSyncProviderDefaultsKey = "popskill.sync.provider"
    private static let autoSyncEnabledDefaultsKey = "popskill.sync.autoEnabled"
    private static let lastSyncAtDefaultsKey = "popskill.sync.lastSyncAt"
    private static let defaultInstallClaudeDefaultsKey = "popskill.install.default.claude"
    private static let defaultInstallCodexDefaultsKey = "popskill.install.default.codex"
    private static let installVerificationModeDefaultsKey = "popskill.install.verificationMode"
    private static let installAutoUpdatePolicyDefaultsKey = "popskill.install.autoUpdatePolicy"
    private static let quotaMonthlyTokenBudgetDefaultsKey = "popskill.quota.monthlyTokenBudget"
    private static let quotaWarningThresholdDefaultsKey = "popskill.quota.warningThreshold"
    private static let quotaTrackingEnabledDefaultsKey = "popskill.quota.trackingEnabled"

    // ===== Data slices =====
    var skills: [Skill] = []
    var packages: [CapabilityPackage] = []
    var unmanagedSkills: [UnmanagedSkill] = []
    var localAgents: [LocalAgent] = []
    var agentTargets: [AgentTarget] = []
    var sources: [SkillRepository] = []
    var catalogSkills: [CatalogSkill] = []
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
    var catalogRefreshInFlight: Bool = false
    var catalogInstallInFlight: Set<String> = []
    var catalogError: String?
    var readmePreviewStates: [String: ReadmePreviewLoadState] = [:]

    // Per-slice refresh timestamps. Views call refresh*(force: false) from
    // .task on first appearance; if a recent refresh exists we skip the
    // sidecar round-trip. Manual refresh buttons pass force: true to bypass.
    var lastSourcesRefreshAt: Date?
    var lastCatalogRefreshAt: Date?
    var lastUpdatesRefreshAt: Date?
    var lastBackupsRefreshAt: Date?

    // ===== UI state =====
    /// Initial selection honors `POPSKILL_DEFAULT_VIEW` when set (used by
    /// screenshot tooling). Defaults to the matrix.
    var currentSelection: SidebarSelection = {
        if popskillDefaultCapabilityIDFromEnvironment() != nil {
            return .matrix
        }
        if let raw = ProcessInfo.processInfo.environment["POPSKILL_DEFAULT_VIEW"],
           let v = SidebarSelection(rawValue: raw) {
            return v
        }
        return .matrix
    }()
    var searchText: String = ""
    /// Screenshot tooling can open a full-page Inspector directly with
    /// `POPSKILL_DEFAULT_CAPABILITY=skill:owner/repo:name` or a bare skill id.
    var selectedSkillID: String? = popskillDefaultCapabilityIDFromEnvironment()
    var inspectorOpen: Bool = popskillDefaultCapabilityIDFromEnvironment() != nil
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
    var matrixSortMode: MatrixSortMode = .typeDescending
    /// Repo groups the user has explicitly collapsed. Set is keyed by
    /// `MatrixGroup.id` (== "owner/name" or "ungrouped").
    var collapsedGroups: Set<String> = []
    /// Composite packages are expanded by default so the matrix immediately
    /// shows the component tree from the reference design. Users can collapse
    /// noisy bundles without hiding the whole source group.
    var collapsedPackageIDs: Set<String> = []
    /// Matrix bulk-mode selection. IDs are row-scoped: capability rows reuse
    /// `MatrixCapability.id`, while package children use
    /// `bundle-component:<package-id>:<kind>:<component-id>`.
    var matrixBulkSelectedIDs: Set<String> = []
    var matrixBulkActionInFlight: MatrixBulkAction?

    // ===== System state =====
    var lastBootstrapAt: Date?
    var lastSyncAt: Date? {
        didSet {
            if let lastSyncAt {
                userDefaults.set(lastSyncAt.timeIntervalSince1970, forKey: Self.lastSyncAtDefaultsKey)
            } else {
                userDefaults.removeObject(forKey: Self.lastSyncAtDefaultsKey)
            }
        }
    }
    var lastSyncProvider: String = "git" {
        didSet {
            userDefaults.set(lastSyncProvider, forKey: Self.lastSyncProviderDefaultsKey)
        }
    }
    var autoSyncEnabled: Bool = false {
        didSet {
            userDefaults.set(autoSyncEnabled, forKey: Self.autoSyncEnabledDefaultsKey)
        }
    }
    var defaultInstallClaude: Bool = true {
        didSet {
            userDefaults.set(defaultInstallClaude, forKey: Self.defaultInstallClaudeDefaultsKey)
        }
    }
    var defaultInstallCodex: Bool = true {
        didSet {
            userDefaults.set(defaultInstallCodex, forKey: Self.defaultInstallCodexDefaultsKey)
        }
    }
    var installVerificationMode: InstallVerificationMode = .strict {
        didSet {
            userDefaults.set(installVerificationMode.rawValue, forKey: Self.installVerificationModeDefaultsKey)
        }
    }
    var installAutoUpdatePolicy: InstallAutoUpdatePolicy = .weekly {
        didSet {
            userDefaults.set(installAutoUpdatePolicy.rawValue, forKey: Self.installAutoUpdatePolicyDefaultsKey)
        }
    }
    var quotaMonthlyTokenBudget: Int = 2_000_000 {
        didSet {
            userDefaults.set(quotaMonthlyTokenBudget, forKey: Self.quotaMonthlyTokenBudgetDefaultsKey)
        }
    }
    var quotaWarningThresholdPercent: Int = 80 {
        didSet {
            userDefaults.set(quotaWarningThresholdPercent, forKey: Self.quotaWarningThresholdDefaultsKey)
        }
    }
    var quotaTrackingEnabled: Bool = true {
        didSet {
            userDefaults.set(quotaTrackingEnabled, forKey: Self.quotaTrackingEnabledDefaultsKey)
        }
    }
    var defaultInstallTargets: [TargetApp] {
        [defaultInstallClaude ? TargetApp.claude : nil, defaultInstallCodex ? TargetApp.codex : nil].compactMap { $0 }
    }
    var quotaWarningTokenCount: Int64 {
        Int64(max(1, quotaMonthlyTokenBudget)) * Int64(max(0, quotaWarningThresholdPercent)) / 100
    }
    var syncInFlight: Bool = false
    var lastSyncResult: SyncResult?
    var lastAutoSyncAttemptAt: Date?
    var isLoading: Bool = false
    var errorMessage: String?

    // ===== Services =====
    let client: SkillCLIClient
    private let localSkillStoreURL: URL
    private let localPackageStoreURL: URL
    private let userDefaults: UserDefaults

    // Per-skill toggle / uninstall in-flight tracking so the matrix can dim
    // controls during pending IO.
    var pendingToggles: Set<String> = []
    var pendingUninstalls: Set<String> = []

    init(
        client: SkillCLIClient = SkillCLIClient(),
        localSkillStoreURL: URL? = nil,
        localPackageStoreURL: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.client = client
        self.userDefaults = userDefaults
        let ccSwitchURL = popskillUserHomeDirectoryURL()
            .appendingPathComponent(".cc-switch", isDirectory: true)
        self.localSkillStoreURL = localSkillStoreURL ?? ccSwitchURL.appendingPathComponent("skills", isDirectory: true)
        self.localPackageStoreURL = localPackageStoreURL ?? ccSwitchURL.appendingPathComponent("packages", isDirectory: true)
        self.lastSyncProvider = userDefaults.string(forKey: Self.lastSyncProviderDefaultsKey) ?? "git"
        if userDefaults.object(forKey: Self.autoSyncEnabledDefaultsKey) == nil {
            self.autoSyncEnabled = false
        } else {
            self.autoSyncEnabled = userDefaults.bool(forKey: Self.autoSyncEnabledDefaultsKey)
        }
        let storedSyncTimestamp = userDefaults.double(forKey: Self.lastSyncAtDefaultsKey)
        self.lastSyncAt = storedSyncTimestamp > 0 ? Date(timeIntervalSince1970: storedSyncTimestamp) : nil
        self.defaultInstallClaude = Self.boolSetting(
            forKey: Self.defaultInstallClaudeDefaultsKey,
            defaultValue: true,
            defaults: userDefaults
        )
        self.defaultInstallCodex = Self.boolSetting(
            forKey: Self.defaultInstallCodexDefaultsKey,
            defaultValue: true,
            defaults: userDefaults
        )
        self.installVerificationMode = Self.rawStringSetting(
            forKey: Self.installVerificationModeDefaultsKey,
            defaultValue: InstallVerificationMode.strict,
            defaults: userDefaults
        )
        self.installAutoUpdatePolicy = Self.rawStringSetting(
            forKey: Self.installAutoUpdatePolicyDefaultsKey,
            defaultValue: InstallAutoUpdatePolicy.weekly,
            defaults: userDefaults
        )
        self.quotaMonthlyTokenBudget = Self.intSetting(
            forKey: Self.quotaMonthlyTokenBudgetDefaultsKey,
            defaultValue: 2_000_000,
            allowedValues: QuotaBudgetOption.allCases.map(\.rawValue),
            defaults: userDefaults
        )
        self.quotaWarningThresholdPercent = Self.intSetting(
            forKey: Self.quotaWarningThresholdDefaultsKey,
            defaultValue: 80,
            allowedValues: QuotaWarningThresholdOption.allCases.map(\.rawValue),
            defaults: userDefaults
        )
        self.quotaTrackingEnabled = Self.boolSetting(
            forKey: Self.quotaTrackingEnabledDefaultsKey,
            defaultValue: true,
            defaults: userDefaults
        )
    }

    private static func boolSetting(
        forKey key: String,
        defaultValue: Bool,
        defaults: UserDefaults
    ) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }

    private static func rawStringSetting<T: RawRepresentable>(
        forKey key: String,
        defaultValue: T,
        defaults: UserDefaults
    ) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key),
              let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }

    private static func intSetting(
        forKey key: String,
        defaultValue: Int,
        allowedValues: [Int],
        defaults: UserDefaults
    ) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        let value = defaults.integer(forKey: key)
        return allowedValues.contains(value) ? value : defaultValue
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

        await runStartupAutoSyncIfNeeded()

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

    @discardableResult
    func runSync(_ action: SyncAction, provider: SyncProvider? = nil) async -> SyncResult? {
        let selectedProvider = provider ?? SyncProvider(rawValue: lastSyncProvider) ?? .git
        guard selectedProvider.actionable else {
            let result = SyncResult(
                provider: selectedProvider.rawValue,
                action: action.rawValue,
                message: "Sync provider is not available.",
                implemented: false
            )
            lastSyncResult = result
            return result
        }
        guard !syncInFlight else { return nil }

        syncInFlight = true
        defer { syncInFlight = false }

        do {
            let result = try await client.sync(action: action.rawValue, provider: selectedProvider.rawValue)
            lastSyncResult = result
            if result.ok == true, action != .status {
                lastSyncAt = Date()
                if action == .pull {
                    await reloadCoreInventoryAfterSync()
                }
            }
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func runStartupAutoSyncIfNeeded() async {
        guard autoSyncEnabled else { return }
        guard let provider = SyncProvider(rawValue: lastSyncProvider), provider.actionable else { return }

        lastAutoSyncAttemptAt = Date()
        do {
            let result = try await client.sync(action: SyncAction.pull.rawValue, provider: provider.rawValue)
            lastSyncResult = result
            if result.ok == true {
                lastSyncAt = Date()
            }
        } catch {
            lastSyncResult = SyncResult(
                provider: provider.rawValue,
                action: SyncAction.pull.rawValue,
                message: error.localizedDescription
            )
        }
    }

    private func reloadCoreInventoryAfterSync() async {
        async let skillsTask = client.list()
        async let sourcesTask = client.listRepositories()
        async let agentsTask = client.listAgents()
        async let packagesTask = loadPackagesBestEffort()
        async let stubsTask = loadStubsBestEffort()

        do {
            skills = try await skillsTask
            sources = try await sourcesTask
            localAgents = try await agentsTask
            packages = await packagesTask
            stubs = await stubsTask
            lastSourcesRefreshAt = Date()
        } catch {
            errorMessage = error.localizedDescription
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

    func refreshCatalog(force: Bool = false) async {
        guard !catalogRefreshInFlight else { return }
        guard !shouldSkipRefresh(lastCatalogRefreshAt, force: force) else { return }
        catalogRefreshInFlight = true
        catalogError = nil
        defer { catalogRefreshInFlight = false }

        do {
            catalogSkills = try await client.discover(query: nil)
            lastCatalogRefreshAt = Date()
        } catch {
            catalogError = error.localizedDescription
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

    @discardableResult
    func updateInstalledSkill(_ update: SkillUpdateInfo) async -> Bool {
        do {
            let updated = try await client.update(skillID: update.id)
            upsertSkill(updated)
            removePendingUpdate(matching: update.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func installCatalogSkill(_ catalogSkill: CatalogSkill, targetApps: [TargetApp]? = nil) async -> Bool {
        let apps = targetApps ?? defaultInstallTargets
        guard !apps.isEmpty else {
            errorMessage = CatalogInstallError.noDefaultTarget.localizedDescription
            return false
        }
        guard !catalogInstallInFlight.contains(catalogSkill.key) else {
            return false
        }

        catalogInstallInFlight.insert(catalogSkill.key)
        defer { catalogInstallInFlight.remove(catalogSkill.key) }

        do {
            var lastInstalled: Skill?
            for app in apps {
                let installed = try await client.install(skillKey: catalogSkill.key, app: app)
                upsertCatalogInstalledSkill(installed)
                lastInstalled = installed
            }
            markCatalogSkillInstalled(catalogSkill.key)
            lastSyncAt = Date()
            currentSelection = .matrix
            if let lastInstalled {
                selectSkill(lastInstalled.id)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func catalogInstallPlans(_ catalogSkill: CatalogSkill, targetApps: [TargetApp]? = nil) async throws -> [InstallPlan] {
        let apps = targetApps ?? defaultInstallTargets
        guard !apps.isEmpty else {
            throw CatalogInstallError.noDefaultTarget
        }

        var plans: [InstallPlan] = []
        for app in apps {
            plans.append(try await client.installPlan(skillKey: catalogSkill.key, app: app))
        }
        return plans
    }

    @discardableResult
    func repairLinkHealthRow(
        _ row: LinkHealthRow,
        action: LinkRepairAction = .relink
    ) async -> Bool {
        let apps = brokenTargetApps(in: row)
        guard !apps.isEmpty else {
            errorMessage = "No repairable target app found for \(row.skillName)."
            return false
        }

        do {
            if action == .updateAndRelink {
                let updated = try await client.update(skillID: row.skillId)
                upsertSkill(updated)
                removePendingUpdate(matching: row.skillId)
            }

            for app in apps {
                let enabled = action != .unlink
                try await client.toggle(skillID: row.skillId, app: app, enabled: enabled)
                updateSkillApp(skillID: row.skillId, app: app, enabled: enabled)
            }

            linkHealth = try await client.linkHealth()
            return !linkHealthRowStillBroken(skillID: row.skillId)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func upsertStub(_ stub: StubbedSkill) {
        stubs.removeAll { $0.skill.id == stub.skill.id }
        stubs.append(stub)
        stubs.sort { $0.stubbedAt > $1.stubbedAt }
    }

    func upsertSkill(_ skill: Skill) {
        if let idx = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[idx] = skill
        } else {
            skills.append(skill)
        }
    }

    private func markCatalogSkillInstalled(_ key: String) {
        guard let index = catalogSkills.firstIndex(where: { $0.key == key }) else { return }
        catalogSkills[index] = catalogSkills[index].replacingInstalled(true)
    }

    private func upsertCatalogInstalledSkill(_ skill: Skill) {
        var merged = skill
        if let existing = skills.first(where: {
            $0.id.caseInsensitiveCompare(skill.id) == .orderedSame
                || $0.directory.caseInsensitiveCompare(skill.directory) == .orderedSame
        }) {
            for app in TargetApp.supported where existing.apps.isEnabled(app) {
                merged.apps.setEnabled(true, for: app)
            }
        }
        upsertSkill(merged)
    }

    func localSkillDirectoryExists(_ directoryName: String) -> Bool {
        FileManager.default.fileExists(atPath: localSkillStoreURL.appendingPathComponent(directoryName, isDirectory: true).path)
    }

    func localBundleDirectoryExists(_ directoryName: String) -> Bool {
        FileManager.default.fileExists(atPath: localPackageStoreURL.appendingPathComponent(directoryName, isDirectory: true).path)
    }

    @discardableResult
    func createLocalSkill(_ draft: CreatedSkillDraft) async -> Bool {
        do {
            let imported = try await createAndImportLocalSkill(draft)
            for skill in imported {
                upsertSkill(skill)
            }
            packages = await loadPackagesBestEffort()
            lastSyncAt = Date()
            if let first = imported.first {
                selectSkill(first.id)
            }
            currentSelection = .matrix
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func createAndImportLocalSkill(_ draft: CreatedSkillDraft) async throws -> [Skill] {
        guard let directoryName = draft.directoryName else {
            throw CreatedSkillDraftError.invalidName
        }

        if skills.contains(where: { $0.directory.caseInsensitiveCompare(directoryName) == .orderedSame }) {
            throw CreatedSkillDraftError.directoryAlreadyInstalled(directoryName)
        }

        let skillURL = localSkillStoreURL.appendingPathComponent(directoryName, isDirectory: true)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: skillURL.path) {
            throw CreatedSkillDraftError.directoryAlreadyExists(directoryName)
        }

        try fileManager.createDirectory(at: skillURL, withIntermediateDirectories: true)
        do {
            try draft.skillMarkdown.write(
                to: skillURL.appendingPathComponent("SKILL.md"),
                atomically: true,
                encoding: .utf8
            )
            let imported = try await client.importUnmanaged(
                directory: directoryName,
                apps: draft.targetApps
            )
            guard !imported.isEmpty else {
                throw CreatedSkillDraftError.importReturnedNoSkills(directoryName)
            }
            return imported
        } catch {
            try? fileManager.removeItem(at: skillURL)
            throw error
        }
    }

    @discardableResult
    func createLocalBundle(_ draft: CreatedBundleDraft) async -> Bool {
        do {
            let packageID = try await createAndLoadLocalBundle(draft)
            lastSyncAt = Date()
            currentSelection = .matrix
            selectCapability(MatrixCapability.packageCapabilityID(for: packageID))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func createAndLoadLocalBundle(_ draft: CreatedBundleDraft) async throws -> String {
        guard let directoryName = draft.directoryName else {
            throw CreatedBundleDraftError.invalidName
        }
        guard !draft.items.isEmpty else {
            throw CreatedBundleDraftError.emptyBundle
        }

        let packageID = "pkg:local/\(directoryName)"
        if packages.contains(where: { $0.id.caseInsensitiveCompare(packageID) == .orderedSame }) {
            throw CreatedBundleDraftError.directoryAlreadyExists(directoryName)
        }

        let bundleURL = localPackageStoreURL.appendingPathComponent(directoryName, isDirectory: true)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: bundleURL.path) {
            throw CreatedBundleDraftError.directoryAlreadyExists(directoryName)
        }

        try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        do {
            try draft.manifestTOML.write(
                to: bundleURL.appendingPathComponent("popskill.toml"),
                atomically: true,
                encoding: .utf8
            )
            packages = try await client.listPackages()
            guard packages.contains(where: { $0.id.caseInsensitiveCompare(packageID) == .orderedSame }) else {
                throw CreatedBundleDraftError.packageNotReturned(packageID)
            }
            return packageID
        } catch {
            try? fileManager.removeItem(at: bundleURL)
            throw error
        }
    }

    func updateSkillApp(skillID: String, app: TargetApp, enabled: Bool) {
        guard let idx = skills.firstIndex(where: { $0.id == skillID }) else { return }
        skills[idx].apps.setEnabled(enabled, for: app)
    }

    func matrixBulkSelectionState(for capability: MatrixCapability) -> MatrixBulkSelectionState {
        if matrixBulkSelectedIDs.contains(capability.id) {
            return .selected
        }

        guard let package = capability.package else {
            return .off
        }

        return package.components.all.contains { component in
            matrixBulkSelectedIDs.contains(Self.matrixBulkComponentID(packageID: package.id, component: component))
        } ? .mixed : .off
    }

    func matrixBulkSelectionState(packageID: String, component: PackageComponent) -> MatrixBulkSelectionState {
        matrixBulkSelectedIDs.contains(Self.matrixBulkComponentID(packageID: packageID, component: component)) ? .selected : .off
    }

    func toggleMatrixBulkSelection(for capability: MatrixCapability) {
        let ids = matrixBulkRowIDs(for: capability)
        let shouldClear = ids.contains { matrixBulkSelectedIDs.contains($0) }
        if shouldClear {
            matrixBulkSelectedIDs.subtract(ids)
        } else {
            matrixBulkSelectedIDs.formUnion(ids)
        }
    }

    func toggleMatrixBulkComponentSelection(packageID: String, component: PackageComponent) {
        let id = Self.matrixBulkComponentID(packageID: packageID, component: component)
        if matrixBulkSelectedIDs.contains(id) {
            matrixBulkSelectedIDs.remove(id)
        } else {
            matrixBulkSelectedIDs.insert(id)
        }
    }

    func toggleMatrixBulkAll(capabilities: [MatrixCapability]) {
        let ids = matrixBulkRowIDs(in: capabilities)
        guard !ids.isEmpty else { return }
        if ids.allSatisfy({ matrixBulkSelectedIDs.contains($0) }) {
            matrixBulkSelectedIDs.subtract(ids)
        } else {
            matrixBulkSelectedIDs.formUnion(ids)
        }
    }

    func clearMatrixBulkSelection() {
        matrixBulkSelectedIDs.removeAll()
    }

    func matrixBulkAllSelectionState(capabilities: [MatrixCapability]) -> MatrixBulkSelectionState {
        let ids = matrixBulkRowIDs(in: capabilities)
        guard !ids.isEmpty else { return .off }
        let selectedCount = ids.filter { matrixBulkSelectedIDs.contains($0) }.count
        if selectedCount == 0 { return .off }
        return selectedCount == ids.count ? .selected : .mixed
    }

    func matrixBulkSelectionSummary(capabilities: [MatrixCapability]) -> MatrixBulkSelectionSummary {
        var selectedBundleCount = 0
        var selectedStandaloneCount = 0
        var selectedChildCount = 0
        var orphanChildCount = 0

        for capability in capabilities {
            if let package = capability.package {
                let packageSelected = matrixBulkSelectedIDs.contains(capability.id)
                if packageSelected {
                    selectedBundleCount += 1
                }
                for component in package.components.all {
                    let selected = matrixBulkSelectedIDs.contains(Self.matrixBulkComponentID(packageID: package.id, component: component))
                    guard selected else { continue }
                    selectedChildCount += 1
                    if !packageSelected {
                        orphanChildCount += 1
                    }
                }
            } else if matrixBulkSelectedIDs.contains(capability.id) {
                selectedStandaloneCount += 1
            }
        }

        let topLevelCount = selectedBundleCount + selectedStandaloneCount + orphanChildCount
        return MatrixBulkSelectionSummary(
            topLevelCount: topLevelCount,
            leafCount: selectedStandaloneCount + selectedChildCount,
            selectedRowCount: matrixBulkSelectedIDs.count,
            selectedBundleCount: selectedBundleCount,
            selectedStandaloneCount: selectedStandaloneCount,
            selectedChildCount: selectedChildCount
        )
    }

    func matrixBulkSelectedSkillIDs(capabilities: [MatrixCapability]) -> [String] {
        var ids: [String] = []
        var seen: Set<String> = []

        func append(_ skillID: String?) {
            guard let skillID, !seen.contains(skillID) else { return }
            seen.insert(skillID)
            ids.append(skillID)
        }

        for capability in capabilities {
            if matrixBulkSelectedIDs.contains(capability.id) {
                if let package = capability.package {
                    for component in package.components.all {
                        append(skill(for: component)?.id)
                    }
                } else {
                    append(capability.underlyingSkillID)
                }
            }

            guard let package = capability.package else { continue }
            for component in package.components.all where matrixBulkSelectedIDs.contains(Self.matrixBulkComponentID(packageID: package.id, component: component)) {
                append(skill(for: component)?.id)
            }
        }

        return ids
    }

    func matrixBulkSelectedUpdates(capabilities: [MatrixCapability]) -> [SkillUpdateInfo] {
        let selectedSkillIDs = Set(matrixBulkSelectedSkillIDs(capabilities: capabilities))
        guard !selectedSkillIDs.isEmpty else { return [] }
        return updates.filter { update in
            selectedSkillIDs.contains(where: { skillID in
                !update.normalizedIdentifierCandidates.isDisjoint(with: updateIdentifierCandidates(for: skillID))
            })
        }
    }

    @discardableResult
    func matrixBulkSetSelectedSkills(app: TargetApp, enabled: Bool, capabilities: [MatrixCapability]) async -> Bool {
        guard matrixBulkActionInFlight == nil else { return false }
        let skillIDs = matrixBulkSelectedSkillIDs(capabilities: capabilities)
        guard !skillIDs.isEmpty else {
            errorMessage = MatrixBulkError.noToggleableSkills.localizedDescription
            return false
        }

        matrixBulkActionInFlight = app == .claude ? .enableClaude : .enableCodex
        defer { matrixBulkActionInFlight = nil }

        var succeeded = true
        for skillID in skillIDs {
            let key = MatrixCapability.skillToggleKey(for: skillID, app: app)
            guard !pendingToggles.contains(key) else { continue }
            pendingToggles.insert(key)
            do {
                try await client.toggle(skillID: skillID, app: app, enabled: enabled)
                updateSkillApp(skillID: skillID, app: app, enabled: enabled)
            } catch {
                succeeded = false
                errorMessage = error.localizedDescription
            }
            pendingToggles.remove(key)
        }
        return succeeded
    }

    @discardableResult
    func matrixBulkUpdateSelectedSkills(capabilities: [MatrixCapability]) async -> Bool {
        guard matrixBulkActionInFlight == nil else { return false }
        let selectedUpdates = matrixBulkSelectedUpdates(capabilities: capabilities)
        guard !selectedUpdates.isEmpty else {
            errorMessage = MatrixBulkError.noPendingUpdates.localizedDescription
            return false
        }

        matrixBulkActionInFlight = .update
        defer { matrixBulkActionInFlight = nil }

        var succeeded = true
        for update in selectedUpdates {
            let ok = await updateInstalledSkill(update)
            succeeded = succeeded && ok
        }
        return succeeded
    }

    func matrixBulkExportJSONString(capabilities: [MatrixCapability]) throws -> String {
        let payload = MatrixBulkExportPayload(
            summary: matrixBulkSelectionSummary(capabilities: capabilities),
            items: matrixBulkSelectedItems(capabilities: capabilities)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    private func matrixBulkRowIDs(in capabilities: [MatrixCapability]) -> [String] {
        capabilities.flatMap(matrixBulkRowIDs(for:))
    }

    private func matrixBulkRowIDs(for capability: MatrixCapability) -> [String] {
        guard let package = capability.package else {
            return [capability.id]
        }
        return [capability.id] + package.components.all.map {
            Self.matrixBulkComponentID(packageID: package.id, component: $0)
        }
    }

    private func matrixBulkSelectedItems(capabilities: [MatrixCapability]) -> [MatrixBulkSelectedItem] {
        var items: [MatrixBulkSelectedItem] = []
        for capability in capabilities where matrixBulkSelectedIDs.contains(capability.id) {
            items.append(MatrixBulkSelectedItem(
                id: capability.id,
                kind: capability.kind.rawValue,
                name: capability.name,
                packageID: capability.underlyingPackageID,
                componentID: nil,
                skillID: capability.underlyingSkillID
            ))
        }

        for capability in capabilities {
            guard let package = capability.package else { continue }
            for component in package.components.all {
                let componentID = Self.matrixBulkComponentID(packageID: package.id, component: component)
                guard matrixBulkSelectedIDs.contains(componentID) else { continue }
                items.append(MatrixBulkSelectedItem(
                    id: componentID,
                    kind: component.kind,
                    name: component.name,
                    packageID: package.id,
                    componentID: component.displayKey,
                    skillID: skill(for: component)?.id
                ))
            }
        }
        return items
    }

    static func matrixBulkComponentID(packageID: String, component: PackageComponent) -> String {
        "bundle-component:\(packageID):\(component.displayKey)"
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

    private func removePendingUpdate(matching skillID: String) {
        let candidates = updateIdentifierCandidates(for: skillID)
        updates.removeAll { update in
            !update.normalizedIdentifierCandidates.isDisjoint(with: candidates)
        }
    }

    private func brokenTargetApps(in row: LinkHealthRow) -> [TargetApp] {
        (row.deployment?.appLinks ?? [:])
            .filter { $0.value.status.caseInsensitiveCompare("broken") == .orderedSame }
            .keys
            .compactMap(TargetApp.init(rawValue:))
            .sorted { lhs, rhs in
                (TargetApp.supported.firstIndex(of: lhs) ?? Int.max) < (TargetApp.supported.firstIndex(of: rhs) ?? Int.max)
            }
    }

    private func linkHealthRowStillBroken(skillID: String) -> Bool {
        guard let row = linkHealth?.rows.first(where: { $0.skillId == skillID }) else {
            return false
        }
        return row.deployment?.appLinks.values.contains {
            $0.status.caseInsensitiveCompare("broken") == .orderedSame
        } ?? false
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
        guard quotaTrackingEnabled else {
            usageSummary = nil
            usageScanError = nil
            return
        }
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

    func quotaUsageState(for totalTokens: Int64?) -> QuotaUsageState {
        guard quotaTrackingEnabled else {
            return .trackingOff
        }
        guard let totalTokens else {
            return .unavailable
        }
        let budget = Int64(max(1, quotaMonthlyTokenBudget))
        if totalTokens >= budget {
            return .exceeded
        }
        if totalTokens >= quotaWarningTokenCount {
            return .warning
        }
        return .normal
    }

    private static func makeUpdateSkillIDs(from updates: [SkillUpdateInfo]) -> Set<String> {
        Set(updates.flatMap(\.normalizedIdentifierCandidates))
    }
}

enum MatrixBulkSelectionState: Equatable {
    case off
    case mixed
    case selected

    var isSelected: Bool { self == .selected }
    var isMixed: Bool { self == .mixed }
    var isActive: Bool { self != .off }
}

enum MatrixBulkAction: String, Equatable {
    case enableClaude
    case enableCodex
    case update
    case export
    case uninstall
}

struct MatrixBulkSelectionSummary: Codable, Equatable {
    let topLevelCount: Int
    let leafCount: Int
    let selectedRowCount: Int
    let selectedBundleCount: Int
    let selectedStandaloneCount: Int
    let selectedChildCount: Int

    var hasSelection: Bool { topLevelCount > 0 || leafCount > 0 || selectedRowCount > 0 }
}

struct MatrixBulkExportPayload: Codable, Equatable {
    let schemaVersion: Int
    let summary: MatrixBulkSelectionSummary
    let items: [MatrixBulkSelectedItem]

    init(
        schemaVersion: Int = 1,
        summary: MatrixBulkSelectionSummary,
        items: [MatrixBulkSelectedItem]
    ) {
        self.schemaVersion = schemaVersion
        self.summary = summary
        self.items = items
    }
}

struct MatrixBulkSelectedItem: Codable, Equatable {
    let id: String
    let kind: String
    let name: String
    let packageID: String?
    let componentID: String?
    let skillID: String?
}

enum MatrixBulkError: LocalizedError, Equatable {
    case noToggleableSkills
    case noPendingUpdates

    var errorDescription: String? {
        switch self {
        case .noToggleableSkills:
            "No selected local skills can be toggled."
        case .noPendingUpdates:
            "No selected skills have pending updates."
        }
    }
}

enum InstallVerificationMode: String, CaseIterable, Identifiable, Codable {
    case strict, warn, off

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .strict: return "settings.install.strict"
        case .warn: return "settings.install.warn"
        case .off: return "settings.install.off"
        }
    }
}

enum InstallAutoUpdatePolicy: String, CaseIterable, Identifiable, Codable {
    case daily, weekly, manual

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .daily: return "settings.install.daily"
        case .weekly: return "settings.install.weekly"
        case .manual: return "settings.install.manual"
        }
    }
}

enum QuotaBudgetOption: Int, CaseIterable, Identifiable, Codable {
    case halfMillion = 500_000
    case oneMillion = 1_000_000
    case twoMillion = 2_000_000
    case fiveMillion = 5_000_000

    var id: Int { rawValue }
}

enum QuotaWarningThresholdOption: Int, CaseIterable, Identifiable, Codable {
    case sixty = 60
    case eighty = 80
    case ninety = 90

    var id: Int { rawValue }
}

enum QuotaUsageState: Equatable {
    case trackingOff
    case unavailable
    case normal
    case warning
    case exceeded
}

enum LinkRepairAction: Hashable {
    case relink
    case updateAndRelink
    case unlink
}

struct CreatedSkillDraft: Equatable {
    let name: String
    let description: String
    let author: String
    let version: String
    let bodyMarkdown: String
    let targetApps: [TargetApp]

    var directoryName: String? {
        Self.directoryName(from: name)
    }

    var skillMarkdown: String {
        let body = Self.markdownBodyWithoutFrontmatter(bodyMarkdown)
        let contentBody: String
        if body.isEmpty {
            contentBody = "# \(trimmed(name))\n\n\(trimmed(description))"
        } else {
            contentBody = body
        }

        return """
        ---
        name: \(Self.yamlString(trimmed(name)))
        description: \(Self.yamlString(trimmed(description)))
        author: \(Self.yamlString(trimmed(author)))
        version: \(Self.yamlString(trimmed(version)))
        ---

        \(contentBody)
        """
    }

    static func directoryName(from rawName: String) -> String? {
        var previousWasSeparator = false
        var slug = ""

        for scalar in rawName.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if scalar == "_" {
                slug.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                slug.append("-")
                previousWasSeparator = true
            }
        }

        let trimmedSlug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmedSlug.isEmpty ? nil : trimmedSlug
    }

    private static func markdownBodyWithoutFrontmatter(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.hasPrefix("---\n") else {
            return normalized
        }

        let searchStart = normalized.index(normalized.startIndex, offsetBy: 4)
        guard let closeRange = normalized.range(of: "\n---", range: searchStart..<normalized.endIndex) else {
            return normalized
        }

        let bodyStart = normalized.index(closeRange.upperBound, offsetBy: closeRange.upperBound < normalized.endIndex ? 0 : 0)
        let body = normalized[bodyStart...]
            .drop(while: { $0 == "\n" || $0 == " " || $0 == "\t" })
        return String(body)
    }

    private static func yamlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CatalogInstallError: LocalizedError, Equatable {
    case noDefaultTarget

    var errorDescription: String? {
        switch self {
        case .noDefaultTarget:
            "No default install target selected."
        }
    }
}

enum CreatedSkillDraftError: LocalizedError, Equatable {
    case invalidName
    case directoryAlreadyExists(String)
    case directoryAlreadyInstalled(String)
    case importReturnedNoSkills(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "Skill name must contain at least one letter or number."
        case let .directoryAlreadyExists(directory):
            "A local skill directory already exists: \(directory)."
        case let .directoryAlreadyInstalled(directory):
            "Skill is already installed: \(directory)."
        case let .importReturnedNoSkills(directory):
            "skill-cli did not import any skill from \(directory)."
        }
    }
}

struct CreatedBundleDraft: Equatable {
    let name: String
    let version: String
    let upstream: String
    let items: [CreatedBundleItem]

    var directoryName: String? {
        CreatedSkillDraft.directoryName(from: name)
    }

    var manifestTOML: String {
        var lines: [String] = [
            "[bundle]",
            "name = \(Self.tomlString(trimmed(name)))",
            "version = \(Self.tomlString(trimmed(version)))",
            "vendor = \"Local\"",
            "summary = \(Self.tomlString(summary))",
            "upstream = \(Self.tomlString(trimmed(upstream)))",
            ""
        ]

        for item in items {
            lines.append("[[items]]")
            lines.append("id = \(Self.tomlString(item.id))")
            lines.append("kind = \(Self.tomlString(item.kind.rawValue))")
            lines.append("name = \(Self.tomlString(item.name))")
            lines.append("location = \(Self.tomlString(item.location))")
            lines.append("required = true")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private var summary: String {
        "\(items.count) capabilities assembled in Popskill."
    }

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CreatedBundleItem: Equatable {
    let id: String
    let kind: CapabilityKind
    let name: String
    let location: String

    init(id: String, kind: CapabilityKind, name: String, location: String) {
        self.id = id
        self.kind = kind
        self.name = name
        self.location = location
    }

    init?(capability: MatrixCapability) {
        guard capability.kind != .bundle else {
            return nil
        }

        let rawID = capability.underlyingSkillID
            ?? capability.underlyingAgentID
            ?? capability.id.split(separator: ":", maxSplits: 1).last.map(String.init)
            ?? capability.id
        let trimmedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return nil
        }

        id = trimmedID
        kind = capability.kind
        name = capability.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? trimmedID
            : capability.name
        location = capability.directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? trimmedID
            : capability.directory
    }
}

enum CreatedBundleDraftError: LocalizedError, Equatable {
    case invalidName
    case emptyBundle
    case directoryAlreadyExists(String)
    case packageNotReturned(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            "Bundle name must contain at least one letter or number."
        case .emptyBundle:
            "Select at least one capability before publishing a bundle."
        case let .directoryAlreadyExists(directory):
            "A local bundle already exists: \(directory)."
        case let .packageNotReturned(packageID):
            "skill-cli did not return the published bundle: \(packageID)."
        }
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
