import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var skills: [Skill] = []
    var packages: [CapabilityPackage] = []
    var stubs: [StubbedSkill] = []
    var unmanagedSkills: [UnmanagedSkill] = []
    var securityScanResults: [Skill.ID: SecurityScanResult] = [:]
    var searchText = ""
    var selectedFilter: LibraryFilter = .all
    var selectedPackageFilter: PackageFilter = .all
    var selectedRehydrateApp: TargetApp = .codex
    var isLoading = false
    var isBulkStubbing = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var pendingToggles: Set<String> = []
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
        }
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

    func isToggling(skillID: String, app: TargetApp) -> Bool {
        pendingToggles.contains(toggleKey(skillID: skillID, app: app))
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
            securityScanResults[skill.id] = nil
            upsertStub(stub)
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
