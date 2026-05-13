import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var skills: [Skill] = []
    var unmanagedSkills: [UnmanagedSkill] = []
    var searchText = ""
    var selectedFilter: LibraryFilter = .all
    var isLoading = false
    var hasLoadedOnce = false
    var errorMessage: String?

    private let client = SkillCLIClient()
    private var pendingToggles: Set<String> = []
    private var uninstallingIDs: Set<String> = []
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

    var enabledCount: Int {
        skills.filter { $0.enabledAppCount > 0 }.count
    }

    var inactiveCount: Int {
        skills.count - enabledCount
    }

    var unmanagedCount: Int {
        unmanagedSkills.count
    }

    func isToggling(skillID: String, app: TargetApp) -> Bool {
        pendingToggles.contains(toggleKey(skillID: skillID, app: app))
    }

    func isUninstalling(skillID: String) -> Bool {
        uninstallingIDs.contains(skillID)
    }

    func isImporting(directory: String) -> Bool {
        importingDirectories.contains(directory)
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
            unmanagedSkills = try await client.scanUnmanaged()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
            didUninstall = true
        } catch {
            errorMessage = error.localizedDescription
        }

        uninstallingIDs.remove(skill.id)
        return didUninstall
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
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case inactive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .active: "Active"
        case .inactive: "Inactive"
        }
    }

    func includes(_ skill: Skill) -> Bool {
        switch self {
        case .all: true
        case .active: skill.enabledAppCount > 0
        case .inactive: skill.enabledAppCount == 0
        }
    }
}
