import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var skills: [Skill] = []
    var packages: [CapabilityPackage] = []
    var stubs: [StubbedSkill] = []
    var backupSnapshotByID: [String: SkillBackup] = [:]
    var unmanagedSkills: [UnmanagedSkill] = []
    var updates: [SkillUpdateInfo] = []
    var securityScanResults: [Skill.ID: SecurityScanResult] = [:]
    var searchText = ""
    var selectedFilter: LibraryFilter = .all
    var selectedPackageFilter: PackageFilter = .all
    var sortOption: LibrarySortOption = .lastUsedAt
    var selectedRehydrateApp: TargetApp = .codex
    var isLoading = false
    var isCheckingUpdates = false
    var isUpdatingAll = false
    var isBulkStubbing = false
    var hasLoadedOnce = false
    var hasCheckedUpdatesOnce = false
    var lastCheckedUpdatesAt: Date?
    var lastUpdateCheckError: String?
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var automaticUpdateTask: Task<Void, Never>?
    private var isCheckingUpdatesInBackground = false
    private var pendingToggles: Set<String> = []
    private var updatingIDs: Set<String> = []
    private var uninstallingIDs: Set<String> = []
    private var stubbingIDs: Set<String> = []
    private var rehydratingIDs: Set<String> = []
    private var scanningSecurityIDs: Set<String> = []
    private var importingDirectories: Set<String> = []

    var filteredSkills: [Skill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return skills.filter { skill in
            selectedFilter.includes(skill)
        }.filter { skill in
            query.isEmpty
                || skill.name.lowercased().contains(query)
                || skill.description.lowercased().contains(query)
                || skill.sourceLabel.lowercased().contains(query)
                || skill.directory.lowercased().contains(query)
        }.sorted(by: sortOption.areInIncreasingOrder)
    }

    var filteredStubs: [StubbedSkill] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return stubs.filter { stub in
            query.isEmpty
                || stub.skill.name.lowercased().contains(query)
                || stub.skill.description.lowercased().contains(query)
                || stub.skill.sourceLabel.lowercased().contains(query)
                || stub.skill.directory.lowercased().contains(query)
        }
    }

    var filteredPackages: [CapabilityPackage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return packages.filter { package in
            selectedPackageFilter.includes(package)
                && selectedFilter.includes(package, installedSkills: skills)
        }.filter { package in
            query.isEmpty
                || package.name.lowercased().contains(query)
                || package.summary.lowercased().contains(query)
                || package.sourceLabel.lowercased().contains(query)
                || package.source.location.lowercased().contains(query)
                || package.components.all.contains { component in
                    component.name.lowercased().contains(query)
                        || component.id.lowercased().contains(query)
                        || component.kind.lowercased().contains(query)
                }
        }
    }

    var enabledCount: Int {
        skills.filter { $0.enabledAppCount > 0 }.count
    }

    var inactiveCount: Int {
        skills.count - enabledCount
    }

    var unmanagedCount: Int {
        unmanagedSkills.count
    }

    var stubCount: Int {
        stubs.count
    }

    var updatableCount: Int {
        updates.count
    }

    func updates(for package: CapabilityPackage) -> [SkillUpdateInfo] {
        guard !updates.isEmpty else {
            return []
        }

        let relatedIdentifiers = packageRelatedSkillIdentifiers(for: package)
        guard !relatedIdentifiers.isEmpty else {
            return []
        }

        return updates.filter { update in
            relatedIdentifiers.contains(update.id.lowercased())
        }
    }

    func isToggling(skillID: String, app: TargetApp) -> Bool {
        pendingToggles.contains(toggleKey(skillID: skillID, app: app))
    }

    func updateInfo(skillID: String) -> SkillUpdateInfo? {
        updates.first { $0.id == skillID }
    }

    func isUpdating(skillID: String) -> Bool {
        updatingIDs.contains(skillID)
    }

    var isUpdatingAny: Bool {
        isUpdatingAll || !updatingIDs.isEmpty
    }

    func isUninstalling(skillID: String) -> Bool {
        uninstallingIDs.contains(skillID)
    }

    func isStubbing(skillID: String) -> Bool {
        stubbingIDs.contains(skillID)
    }

    func isRehydrating(skillID: String) -> Bool {
        rehydratingIDs.contains(skillID)
    }

    func isImporting(directory: String) -> Bool {
        importingDirectories.contains(directory)
    }

    func isScanningSecurity(skillID: String) -> Bool {
        scanningSecurityIDs.contains(skillID)
    }

    func securityScanResult(skillID: String) -> SecurityScanResult? {
        securityScanResults[skillID]
    }

    func backupSnapshot(for stub: StubbedSkill) -> SkillBackup? {
        backupSnapshotByID[stub.backupId]
    }

    func recoverableStub(for component: PackageComponent) -> StubbedSkill? {
        guard !component.installed,
              component.kind.caseInsensitiveCompare("skill") == .orderedSame
        else {
            return nil
        }

        return stubs.first { stub in
            packageSkillComponent(component, matches: stub.skill)
        }
    }

    @discardableResult
    func rehydrateComponent(_ component: PackageComponent) async -> Bool {
        guard let stub = recoverableStub(for: component) else {
            return false
        }
        return await rehydrate(stub)
    }

    func load() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            skills = try await client.list()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            packages = try await client.listPackages()
                .sorted(by: packageSort)
            stubs = try await client.listStubs()
                .sorted { $0.stubbedAt > $1.stubbedAt }
            await refreshBackupSnapshots()
            unmanagedSkills = try await client.scanUnmanaged()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            securityScanResults = Dictionary(
                try await client.securityScans().map { ($0.skillId, $0.result) },
                uniquingKeysWith: { current, replacement in
                    replacement.scannedAt > current.scannedAt ? replacement : current
                }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startAutomaticUpdateMonitoring() {
        guard automaticUpdateTask == nil else {
            return
        }

        automaticUpdateTask = Task { [weak self] in
            await self?.checkUpdates(silent: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                await self?.checkUpdates(silent: true)
            }
        }
    }

    func checkUpdates(silent: Bool = false) async {
        guard !isCheckingUpdates, !isCheckingUpdatesInBackground else {
            return
        }

        if silent {
            isCheckingUpdatesInBackground = true
        } else {
            isCheckingUpdates = true
        }
        errorMessage = nil
        defer {
            if silent {
                isCheckingUpdatesInBackground = false
            } else {
                isCheckingUpdates = false
            }
            hasCheckedUpdatesOnce = true
        }

        do {
            updates = try await client.checkUpdates()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            lastCheckedUpdatesAt = Date()
            lastUpdateCheckError = nil
        } catch {
            lastUpdateCheckError = error.localizedDescription
            if !silent {
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func update(_ update: SkillUpdateInfo) async -> Bool {
        guard !updatingIDs.contains(update.id) else {
            return false
        }

        updatingIDs.insert(update.id)
        errorMessage = nil
        var didUpdate = false

        do {
            let skill = try await client.update(skillID: update.id)
            updates.removeAll { $0.id == update.id }
            upsertSkill(skill)
            didUpdate = true
        } catch {
            errorMessage = error.localizedDescription
        }

        updatingIDs.remove(update.id)
        return didUpdate
    }

    @discardableResult
    func updateAll() async -> Int {
        guard !isUpdatingAll, !updates.isEmpty else {
            return 0
        }

        isUpdatingAll = true
        defer {
            isUpdatingAll = false
        }

        var updatedCount = 0
        let pendingUpdates = updates
        for update in pendingUpdates {
            if await self.update(update) {
                updatedCount += 1
            }
        }

        return updatedCount
    }

    func setEnabled(_ enabled: Bool, for skill: Skill, app: TargetApp) async {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else {
            return
        }

        let key = toggleKey(skillID: skill.id, app: app)
        guard !pendingToggles.contains(key) else {
            return
        }

        let previous = skills[index]
        pendingToggles.insert(key)
        skills[index].apps.setEnabled(enabled, for: app)
        errorMessage = nil

        do {
            try await client.toggle(skillID: skill.id, app: app, enabled: enabled)
        } catch {
            skills[index] = previous
            errorMessage = error.localizedDescription
        }

        pendingToggles.remove(key)
    }

    @discardableResult
    func uninstall(_ skill: Skill) async -> Bool {
        guard !uninstallingIDs.contains(skill.id) else {
            return false
        }

        uninstallingIDs.insert(skill.id)
        errorMessage = nil
        var didUninstall = false

        do {
            _ = try await client.uninstall(skillID: skill.id)
            skills.removeAll { $0.id == skill.id }
            updates.removeAll { $0.id == skill.id }
            securityScanResults[skill.id] = nil
            didUninstall = true
        } catch {
            errorMessage = error.localizedDescription
        }

        uninstallingIDs.remove(skill.id)
        return didUninstall
    }

    @discardableResult
    func stub(_ skill: Skill) async -> Bool {
        guard !stubbingIDs.contains(skill.id) else {
            return false
        }

        stubbingIDs.insert(skill.id)
        errorMessage = nil
        var didStub = false

        do {
            let stub = try await client.stub(skillID: skill.id)
            skills.removeAll { $0.id == skill.id }
            updates.removeAll { $0.id == skill.id }
            securityScanResults[skill.id] = nil
            upsertStub(stub)
            await refreshBackupSnapshots()
            didStub = true
        } catch {
            errorMessage = error.localizedDescription
        }

        stubbingIDs.remove(skill.id)
        return didStub
    }

    @discardableResult
    func rehydrate(_ stub: StubbedSkill) async -> Bool {
        guard !rehydratingIDs.contains(stub.id) else {
            return false
        }

        rehydratingIDs.insert(stub.id)
        errorMessage = nil
        var didRehydrate = false

        do {
            let skill = try await client.rehydrate(skillID: stub.id, app: selectedRehydrateApp)
            stubs.removeAll { $0.id == stub.id }
            upsertSkill(skill)
            await refreshBackupSnapshots()
            didRehydrate = true
        } catch {
            errorMessage = error.localizedDescription
        }

        rehydratingIDs.remove(stub.id)
        return didRehydrate
    }

    func scanSecurity(_ skill: Skill) async {
        guard !scanningSecurityIDs.contains(skill.id) else {
            return
        }

        scanningSecurityIDs.insert(skill.id)
        errorMessage = nil

        do {
            securityScanResults[skill.id] = try await client.securityScan(
                skillID: skill.id,
                skillDirectory: skill.localStoreURL.path
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        scanningSecurityIDs.remove(skill.id)
    }

    @discardableResult
    func stubAll(_ candidates: [Skill]) async -> Int {
        guard !isBulkStubbing else {
            return 0
        }

        isBulkStubbing = true
        defer { isBulkStubbing = false }

        var stubbedCount = 0
        for candidate in candidates {
            guard
                candidate.enabledAppCount == 0,
                skills.contains(where: { $0.id == candidate.id })
            else {
                continue
            }

            if await stub(candidate) {
                stubbedCount += 1
            }
        }

        return stubbedCount
    }

    @discardableResult
    func importUnmanaged(_ unmanaged: UnmanagedSkill, apps: [TargetApp] = [.claude]) async -> Bool {
        guard !importingDirectories.contains(unmanaged.directory) else {
            return false
        }

        importingDirectories.insert(unmanaged.directory)
        errorMessage = nil
        var didImport = false

        do {
            _ = try await client.importUnmanaged(directory: unmanaged.directory, apps: apps)
            await load()
            didImport = true
        } catch {
            errorMessage = error.localizedDescription
        }

        importingDirectories.remove(unmanaged.directory)
        return didImport
    }

    private func toggleKey(skillID: String, app: TargetApp) -> String {
        "\(skillID)#\(app.rawValue)"
    }

    private func upsertSkill(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }
        skills.append(skill)
        skills.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func upsertStub(_ stub: StubbedSkill) {
        stubs.removeAll { $0.id == stub.id }
        stubs.append(stub)
        stubs.sort { $0.stubbedAt > $1.stubbedAt }
    }

    private func refreshBackupSnapshots() async {
        do {
            let backups = try await client.listBackups()
            backupSnapshotByID = Dictionary(
                backups.map { ($0.backupId, $0) },
                uniquingKeysWith: { current, replacement in
                    replacement.createdAt > current.createdAt ? replacement : current
                }
            )
        } catch {
            // Keep previous snapshots when backup listing is temporarily unavailable.
        }
    }

    private func packageSort(_ left: CapabilityPackage, _ right: CapabilityPackage) -> Bool {
        let leftRank = packageSortRank(left)
        let rightRank = packageSortRank(right)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return left.id < right.id
    }

    private func packageSortRank(_ package: CapabilityPackage) -> Int {
        switch package.type {
        case .composite:
            return 0
        case .standalone:
            return package.source.kind == "builtin" ? 1 : 2
        }
    }

    private func packageRelatedSkillIdentifiers(for package: CapabilityPackage) -> Set<String> {
        let skillComponents = package.components.all.filter { $0.kind.caseInsensitiveCompare("skill") == .orderedSame }
        guard !skillComponents.isEmpty else {
            return []
        }

        var identifiers: Set<String> = []
        for component in skillComponents {
            identifiers.insert(component.id.lowercased())

            if let location = component.location?.trimmingCharacters(in: .whitespacesAndNewlines),
               !location.isEmpty {
                identifiers.insert(location.lowercased())
            }

            for skill in skills where packageSkillComponent(component, matches: skill) {
                identifiers.insert(skill.id.lowercased())
                identifiers.insert(skill.directory.lowercased())
            }
        }
        return identifiers
    }

    private func packageSkillComponent(_ component: PackageComponent, matches skill: Skill) -> Bool {
        if skill.id.caseInsensitiveCompare(component.id) == .orderedSame {
            return true
        }

        if let location = component.location?.trimmingCharacters(in: .whitespacesAndNewlines),
           !location.isEmpty,
           skill.directory.caseInsensitiveCompare(location) == .orderedSame {
            return true
        }

        return skill.name.caseInsensitiveCompare(component.name) == .orderedSame
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case inactive
    case stub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .inactive: "Inactive"
        case .stub: "Stubs"
        }
    }

    func includes(_ skill: Skill) -> Bool {
        switch self {
        case .all: true
        case .active: skill.enabledAppCount > 0
        case .inactive: skill.enabledAppCount == 0
        case .stub: false
        }
    }

    func includes(_ package: CapabilityPackage, installedSkills: [Skill]) -> Bool {
        switch self {
        case .all:
            return true
        case .active:
            if package.type == .composite {
                return package.installedComponentCount > 0
            }
            return matchingSkill(for: package, in: installedSkills).map(includes) ?? package.installed
        case .inactive:
            if package.type == .composite {
                return package.installedComponentCount == 0
            }
            return matchingSkill(for: package, in: installedSkills).map(includes) ?? !package.installed
        case .stub:
            return false
        }
    }

    private func matchingSkill(for package: CapabilityPackage, in installedSkills: [Skill]) -> Skill? {
        guard package.type == .standalone,
              let component = package.components.skills.first ?? package.components.all.first(where: { $0.kind == "skill" }) else {
            return nil
        }

        return installedSkills.first { skill in
            skill.id == component.id
                || skill.directory == component.location
                || skill.name == component.name
        }
    }
}

enum PackageFilter: String, CaseIterable, Identifiable {
    case all
    case composite
    case standalone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .composite: "Composite"
        case .standalone: "Standalone"
        }
    }

    func includes(_ package: CapabilityPackage) -> Bool {
        switch self {
        case .all:
            return true
        case .composite:
            return package.type == .composite
        case .standalone:
            return package.type == .standalone
        }
    }
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case name
    case installedAt
    case lastUsedAt
    case size
    case lastUpdatedAt

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "sort.name"
        case .installedAt: "sort.installedAt"
        case .lastUsedAt: "sort.lastUsedAt"
        case .size: "sort.size"
        case .lastUpdatedAt: "sort.lastUpdatedAt"
        }
    }

    func areInIncreasingOrder(_ left: Skill, _ right: Skill) -> Bool {
        switch self {
        case .name:
            return nameOrder(left, right)
        case .installedAt:
            return timestampOrder(left.installedAt, right.installedAt, left, right)
        case .lastUsedAt:
            return timestampOrder(left.lastUsedAt, right.lastUsedAt, left, right)
        case .size:
            return sizeOrder(left.sizeBytes, right.sizeBytes, left, right)
        case .lastUpdatedAt:
            return timestampOrder(left.updatedAt, right.updatedAt, left, right)
        }
    }

    private func timestampOrder(_ leftValue: Int?, _ rightValue: Int?, _ left: Skill, _ right: Skill) -> Bool {
        let leftTimestamp = leftValue ?? 0
        let rightTimestamp = rightValue ?? 0
        if leftTimestamp != rightTimestamp {
            return leftTimestamp > rightTimestamp
        }
        return nameOrder(left, right)
    }

    private func sizeOrder(_ leftValue: UInt64?, _ rightValue: UInt64?, _ left: Skill, _ right: Skill) -> Bool {
        let leftSize = leftValue ?? 0
        let rightSize = rightValue ?? 0
        if leftSize != rightSize {
            return leftSize > rightSize
        }
        return nameOrder(left, right)
    }

    private func nameOrder(_ left: Skill, _ right: Skill) -> Bool {
        let nameOrder = left.name.localizedCaseInsensitiveCompare(right.name)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return left.id < right.id
    }
}
