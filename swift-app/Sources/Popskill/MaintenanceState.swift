import Foundation
import Observation

enum WorkspacePage { case matrix, maintenance }
enum SettingsSection: String, CaseIterable { case tools, automation, data, about }
enum MaintenanceTab: String, CaseIterable { case sources, clis }
enum MaintenanceFilter: String, CaseIterable { case all, updates, issues }
enum CliScanScope: String, CaseIterable { case common, all }
enum CheckOutcome: Sendable { case checking, current, updateAvailable, failed, unsupported }
struct CheckRecord: Sendable {
    var outcome: CheckOutcome
    var checkedAt: Date = Date()
    var error: String?
}

/// View state and action receipts only. The existing entries/globalClis remain the inventory.
@MainActor @Observable
final class MaintenanceState {
    var page: WorkspacePage = .matrix
    var tab: MaintenanceTab = .sources
    var settingsSection: SettingsSection = .tools
    var sourceQuery = ""
    var cliQuery = ""
    var sourceFilter: MaintenanceFilter = .all
    var cliFilter: MaintenanceFilter = .all
    var cliScope: CliScanScope
    var allCliInspectionAuthorized = false
    var sourceScrollID: String?
    var cliScrollID: String?
    var expandedSources: Set<String> = []
    var expandedClis: Set<String> = []
    var searchRequested = 0
    var settingsSearchRequested = 0
    var cliInventoryLoaded = false
    var sourceChecks: [String: CheckRecord] = [:]
    var cliChecks: [String: CheckRecord] = [:]
    var lastCliCheck: Date?
    var lastCliScope: CliScanScope?
    var lastSourceCheck: Date?
    var showResults = false
    var settingsFeedback: String?
    var report: OperationReport {
        didSet {
            if let data = try? JSONEncoder().encode(report) { defaults.set(data, forKey: Self.reportKey) }
        }
    }
    @ObservationIgnored private let defaults: UserDefaults
    private static let reportKey = "maintenance.operation-report.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cliScope = defaults.bool(forKey: "autoCliPatrol") ? .all : .common
        var saved = defaults.data(forKey: Self.reportKey)
            .flatMap { try? JSONDecoder().decode(OperationReport.self, from: $0) } ?? OperationReport()
        saved.recoverInterrupted()
        report = saved
    }
}

extension OperationPhase {
    var label: String {
        switch self {
        case .queued: L("排队中")
        case .running: L("更新中")
        case .succeeded: L("更新完成")
        case .failed: L("更新失败")
        case .unverified: L("版本待确认")
        case .skipped: L("已跳过")
        }
    }
}
extension CheckOutcome {
    var label: String {
        switch self {
        case .checking: L("检查中…")
        case .current: L("已最新")
        case .updateAvailable: L("可更新")
        case .failed: L("检查失败")
        case .unsupported: L("由原渠道管理")
        }
    }
}
extension CliScanScope {
    var label: String { self == .common ? L("常用 AI 工具") : L("全部全局 CLI") }
}
extension MaintenanceFilter {
    var label: String {
        switch self {
        case .all: L("全部")
        case .updates: L("可更新")
        case .issues: L("需处理")
        }
    }
}

func cliInMaintenanceScope(_ cli: GlobalCli, scope: CliScanScope) -> Bool {
    scope == .all || cli.allowlisted || cli.channel != .npm
}

@MainActor
extension AppModel {
    var maintenancePolicy: MaintenancePolicy { MaintenancePolicyStore.loadPolicy(defaults: maintenanceDefaults) }
    var remoteSourceCandidates: [Entry] {
        entries.filter { supportsBulkAutomaticUpdate(sourceUrl: $0.sourceUrl, managedExternally: $0.isManagedExternally) }
    }
    var filteredMaintenanceSources: [Entry] {
        entries.filter { e in
            let matches = maintenance.sourceQuery.isEmpty ||
                "\(e.name) \(e.sourceUrl ?? "")".localizedCaseInsensitiveContains(maintenance.sourceQuery)
            let failed = maintenance.sourceChecks[e.id]?.outcome == .failed ||
                maintenance.report.items.contains { $0.id == e.id && ($0.phase == .failed || $0.phase == .unverified) }
            switch maintenance.sourceFilter {
            case .all: return matches
            case .updates: return matches && e.hasUpdate
            case .issues: return matches && (failed || e.localDrifted || e.sourceUrl == nil || e.allCaps.contains { $0.isBroken(tools) })
            }
        }
    }
    var filteredMaintenanceClis: [GlobalCli] {
        globalClis.filter { c in
            guard cliInMaintenanceScope(c, scope: maintenance.cliScope) else { return false }
            let matches = maintenance.cliQuery.isEmpty ||
                "\(c.name) \(c.maintenanceName)".localizedCaseInsensitiveContains(maintenance.cliQuery)
            let failed = maintenance.cliChecks[c.id]?.outcome == .failed ||
                maintenance.report.items.contains { $0.id == c.id && ($0.phase == .failed || $0.phase == .unverified) }
            switch maintenance.cliFilter {
            case .all: return matches
            case .updates: return matches && c.hasUpdate
            case .issues: return matches && (failed || !c.pathMatchesPrefix || !c.tracksIndex)
            }
        }
    }
    var maintenanceSourceTargets: [Entry] {
        filteredMaintenanceSources.filter {
            $0.hasUpdate && !$0.localDrifted && !$0.isManagedExternally && !updatingIds.contains($0.id)
                && maintenance.sourceChecks[$0.id]?.outcome != .failed
        }
    }
    var maintenanceCliTargets: [GlobalCli] {
        filteredMaintenanceClis.filter {
            $0.safeRecognizedAgentUpdate && !upgradingClis.contains($0.id)
                && maintenance.cliChecks[$0.id]?.outcome != .failed
        }
    }
    func openMaintenance(_ tab: MaintenanceTab? = nil, sourceID: String? = nil) {
        guard sheet == nil else { return }
        fixTarget = nil
        peekTarget = nil
        if let tab { maintenance.tab = tab }
        if let sourceID {
            maintenance.tab = .sources
            maintenance.sourceQuery = ""
            maintenance.sourceFilter = .all
            maintenance.expandedSources.insert(sourceID)
            maintenance.sourceScrollID = sourceID
        }
        maintenance.page = .maintenance
        loadLocalCliInventoryIfNeeded()
    }
    func returnToMatrix() { maintenance.page = .matrix }
    func dismissShortTask() {
        guard !installing else { return }
        sheet = nil
    }
    @discardableResult
    func checkMaintenanceClis() -> Bool {
        guard maintenance.cliScope == .common || autoCliPatrol || maintenance.allCliInspectionAuthorized else {
            sayError(L("请先授权全部全局 CLI 的检查范围。"))
            return false
        }
        checkCliUpdates(full: maintenance.cliScope == .all)
        return true
    }
    func checkMaintenanceSources() {
        let ids = Set(remoteSourceCandidates.map(\.id))
        checkUpdates(auto: false, only: ids)
    }
    func updateMaintenanceSelection() {
        if maintenance.tab == .sources {
            for e in maintenanceSourceTargets { runUpdate(e.id) }
        } else {
            enqueueCliUpgrades(maintenanceCliTargets.map(\.id))
        }
    }
    var retryableMaintenanceCount: Int {
        let report = maintenance.report
        return entries.filter {
            report.failedIDs(kind: .source).contains($0.id) && $0.hasUpdate && !$0.localDrifted
                && !$0.isManagedExternally && maintenance.sourceChecks[$0.id]?.outcome != .failed
        }.count + globalClis.filter {
            report.failedIDs(kind: .cli).contains($0.id) && $0.safeRecognizedAgentUpdate
                && maintenance.cliChecks[$0.id]?.outcome != .failed
        }.count
    }
    func retryMaintenanceFailures() {
        let report = maintenance.report
        for id in report.failedIDs(kind: .source) {
            guard let e = entries.first(where: { $0.id == id }), e.hasUpdate, !e.localDrifted,
                  !e.isManagedExternally, maintenance.sourceChecks[id]?.outcome != .failed else { continue }
            runUpdate(id)
        }
        let ids = report.failedIDs(kind: .cli)
        enqueueCliUpgrades(globalClis.filter {
            ids.contains($0.id) && $0.safeRecognizedAgentUpdate && maintenance.cliChecks[$0.id]?.outcome != .failed
        }.map(\.id))
    }
    /// This does not touch links, store directories, or the source lifecycle.
    @discardableResult
    func setToolPreference(_ id: String, showOnHome: Bool? = nil, defaultTarget: Bool? = nil) -> Bool {
        guard let def = ToolDef.builtins.first(where: { $0.id == id }) else { return false }
        let ok = fake || fs.mutateMeta { meta in
            var item = meta.tools[id] ?? StoreMeta.ToolMeta()
            if let showOnHome, !def.alwaysShow { item.showOnHome = showOnHome }
            if let defaultTarget { item.defaultTarget = defaultTarget }
            meta.tools[id] = item
        }
        if ok { refresh(); maintenance.settingsFeedback = nil }
        else { maintenance.settingsFeedback = L("设置未保存，请检查目录权限和磁盘空间。") }
        return ok
    }
}
