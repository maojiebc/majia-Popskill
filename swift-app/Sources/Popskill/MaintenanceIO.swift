import Foundation

@MainActor
extension AppModel {
    /// Opening a page inventories local installations; it does not grant registry access.
    func loadLocalCliInventoryIfNeeded() {
        guard !fake, !maintenance.cliInventoryLoaded, !checkingClis, upgradingClis.isEmpty else { return }
        checkingClis = true
        let engine = fs
        let reader = cliInventoryReader
        let packages = Set(entries.compactMap { npmPkgName($0.sourceUrl) })
        Task { [weak self] in
            let rows = await Task.detached {
                (reader?(engine, true, false) ?? engine.scanMaintainedClis(extraNpm: packages, full: true, checkVersions: false))
                    .filter { !packages.contains($0.name) || $0.channel != .npm }
            }.value
            guard let self else { return }
            // A local scan must not erase a valid, previously obtained registry result.
            self.globalClis = rows.map { row in
                var row = row
                if let old = self.globalClis.first(where: { $0.id == row.id && $0.installed == row.installed }) {
                    row.latest = old.latest
                }
                return row
            }
            self.checkingClis = false
            self.maintenance.cliInventoryLoaded = true
        }
    }

    /// nil means the existing authorized preference, never an implicit all-package scan.
    func checkCliUpdates(full: Bool? = nil) {
        guard !fake, !checkingClis, upgradingClis.isEmpty else { return }
        let full = full ?? autoCliPatrol
        let scope: CliScanScope = full ? .all : .common
        checkingClis = true
        let engine = fs
        let reader = cliInventoryReader
        let packages = Set(entries.compactMap { npmPkgName($0.sourceUrl) })
        for cli in globalClis where cliInMaintenanceScope(cli, scope: scope) {
            maintenance.cliChecks[cli.id] = CheckRecord(outcome: .checking)
        }
        Task { [weak self] in
            let inspected = await Task.detached {
                let rows = (reader?(engine, full, true) ?? engine.scanMaintainedClis(extraNpm: packages, full: full))
                    .filter { !packages.contains($0.name) || $0.channel != .npm }
                var records: [String: CheckRecord] = [:]
                let checked = rows.map { raw in
                    var cli = raw
                    guard !cli.excluded, cli.tracksIndex else {
                        records[cli.id] = CheckRecord(outcome: .unsupported)
                        return cli
                    }
                    do {
                        switch cli.channel {
                        case .npm: cli.latest = try engine.npmLatestVersion(cli.name)
                        case .pipx, .uv: cli.latest = try engine.pypiLatestVersion(cli.name)
                        case .brew:
                            guard cli.latest != nil else {
                                throw StoreError.resolveFailed(L("Homebrew 检查失败，请重试。"))
                            }
                        }
                        records[cli.id] = CheckRecord(outcome: cli.hasUpdate ? .updateAvailable : .current)
                    } catch {
                        cli.latest = nil
                        records[cli.id] = CheckRecord(outcome: .failed, error: error.localizedDescription)
                    }
                    return cli
                }
                return (checked, records)
            }.value
            guard let self else { return }
            let untouched = self.globalClis.filter { !cliInMaintenanceScope($0, scope: scope) }
            self.globalClis = inspected.0 + untouched
            self.maintenance.cliChecks.merge(inspected.1) { _, new in new }
            self.maintenance.lastCliCheck = Date()
            self.maintenance.lastCliScope = scope
            self.maintenance.cliInventoryLoaded = true
            self.checkingClis = false
        }
    }
}
