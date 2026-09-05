import Foundation

/// 维护中心的机器级策略。
///
/// 技能逐源的 `autoUpdate` 仍写在 store meta，随 store 同步；这里保存的是当前 Mac 的
/// 默认继承与巡检节奏。CLI 安装位置本来就是机器状态，不应跟着 store 漂到另一台 Mac。
struct MaintenancePolicy: Codable, Equatable, Sendable {
    var inheritRemoteAutoUpdate = false
    var periodicCheckEnabled = false
    var autoUpgradeRecognizedAgents = false
    var intervalHours = 24

    static let allowedIntervals = [6, 12, 24, 72]

    var normalized: MaintenancePolicy {
        var value = self
        if !Self.allowedIntervals.contains(value.intervalHours) { value.intervalHours = 24 }
        if !value.periodicCheckEnabled { value.autoUpgradeRecognizedAgents = false }
        return value
    }
}

enum MaintenanceRunOutcome: String, Codable, Sendable {
    case idle, running, success, partial, failed
}

/// 最近一次统一维护的可回看结果。Toast 会消失，这份状态会留在维护中心。
struct MaintenanceRunStatus: Codable, Equatable, Sendable {
    var outcome: MaintenanceRunOutcome = .idle
    var startedAt: Date?
    var finishedAt: Date?
    var checkedSources = 0
    var sourceUpdatesStarted = 0
    var sourceFailures = 0
    var checkedAgents = 0
    var availableAgentUpdates = 0
    var upgradedAgents = 0
    var unresolvedAgents = 0
    var failedAgentUpgrades = 0
    var error: String?

    var summary: String {
        switch outcome {
        case .idle:
            return maintenanceText("尚未运行定时维护。", "Scheduled maintenance has not run yet.")
        case .running:
            return maintenanceText("正在检查技能源与 Agent CLI…", "Checking skill sources and agent CLIs…")
        case .failed:
            return error ?? maintenanceText("维护失败。", "Maintenance failed.")
        case .success, .partial:
            var parts = [
                maintenanceText("来源 \(checkedSources)", "\(checkedSources) sources"),
                maintenanceText("Agent \(checkedAgents)", "\(checkedAgents) agents"),
            ]
            if sourceUpdatesStarted > 0 {
                let ok = max(0, sourceUpdatesStarted - sourceFailures)
                parts.append(maintenanceText("来源更新 \(ok)/\(sourceUpdatesStarted)", "source updates \(ok)/\(sourceUpdatesStarted)"))
            }
            if upgradedAgents > 0 {
                parts.append(maintenanceText("Agent 升级 \(upgradedAgents)", "\(upgradedAgents) agent upgrades"))
            } else if availableAgentUpdates > 0 {
                parts.append(maintenanceText("发现 Agent 更新 \(availableAgentUpdates)", "\(availableAgentUpdates) agent updates found"))
            }
            let uncertain = sourceFailures + unresolvedAgents + failedAgentUpgrades
            if uncertain > 0 {
                parts.append(maintenanceText("异常/未确认 \(uncertain)", "\(uncertain) unresolved"))
            }
            if let error, !error.isEmpty { parts.append(error) }
            return parts.joined(separator: maintenanceText(" · ", " · "))
        }
    }
}

enum MaintenancePolicyStore {
    private static let policyKey = "maintenance.policy.v1"
    private static let knownSourcesKey = "maintenance.known-remote-sources.v1"
    private static let statusKey = "maintenance.last-run.v1"

    static func loadPolicy(defaults: UserDefaults = .standard) -> MaintenancePolicy {
        guard let data = defaults.data(forKey: policyKey),
              let value = try? JSONDecoder().decode(MaintenancePolicy.self, from: data)
        else { return MaintenancePolicy() }
        return value.normalized
    }

    static func savePolicy(_ policy: MaintenancePolicy, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(policy.normalized) else { return }
        defaults.set(data, forKey: policyKey)
    }

    static func loadKnownSourceIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: knownSourcesKey) ?? [])
    }

    static func saveKnownSourceIDs(_ ids: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(ids.sorted(), forKey: knownSourcesKey)
    }

    static func loadStatus(defaults: UserDefaults = .standard) -> MaintenanceRunStatus {
        guard let data = defaults.data(forKey: statusKey),
              let value = try? JSONDecoder().decode(MaintenanceRunStatus.self, from: data)
        else { return MaintenanceRunStatus() }
        return value
    }

    static func saveStatus(_ status: MaintenanceRunStatus, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: statusKey)
    }
}

func maintenanceRunIsDue(
    policy: MaintenancePolicy,
    status: MaintenanceRunStatus,
    now: Date = Date()
) -> Bool {
    let policy = policy.normalized
    guard policy.periodicCheckEnabled, status.outcome != .running else { return false }
    guard let last = status.finishedAt ?? status.startedAt else { return true }
    return now.timeIntervalSince(last) >= TimeInterval(policy.intervalHours * 3600)
}

/// 进程在维护中退出时，UserDefaults 会留下 `.running`。不收口的话下次启动会被
/// “已有任务运行中”的守卫永久挡住。恢复成可解释的 partial，并由调度器立即补跑一次。
func recoveredInterruptedMaintenanceStatus(
    _ status: MaintenanceRunStatus,
    now: Date = Date()
) -> MaintenanceRunStatus {
    guard status.outcome == .running else { return status }
    var recovered = status
    recovered.outcome = .partial
    recovered.finishedAt = now
    recovered.error = maintenanceText(
        "上次维护被中断；现有版本已保留，本次启动会重新检查。",
        "The previous maintenance run was interrupted. Existing versions were kept and will be checked again on this launch."
    )
    return recovered
}

func remoteSourceIDsToInherit(
    current: Set<String>,
    known: Set<String>,
    inherit: Bool
) -> Set<String> {
    inherit ? current.subtracting(known) : []
}

@MainActor
private enum MaintenanceAutomationRegistry {
    static var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
}

@MainActor
extension AppModel {
    /// 退出时必须等真正写盘的动作；只读检查可以安全中断。
    var maintenanceMutationBusy: Bool {
        installing || !updatingIds.isEmpty || !upgradingClis.isEmpty
    }

    private var remoteMaintenanceEntries: [Entry] {
        entries.filter {
            supportsBulkAutomaticUpdate(sourceUrl: $0.sourceUrl, managedExternally: $0.isManagedExternally)
        }
    }

    /// Future defaults never change existing per-source choices. Record the current
    /// inventory before changing the default so the next reconciliation cannot do so either.
    func setFutureSourceAutoUpdate(_ on: Bool) {
        MaintenancePolicyStore.saveKnownSourceIDs(Set(remoteMaintenanceEntries.map(\.id)), defaults: maintenanceDefaults)
        var policy = maintenancePolicy
        policy.inheritRemoteAutoUpdate = on
        MaintenancePolicyStore.savePolicy(policy, defaults: maintenanceDefaults)
    }

    /// An explicit batch action for current sources only. It does not change the future default.
    @discardableResult
    func applyAutoUpdateToExistingSources(_ on: Bool) -> Bool {
        let candidates = remoteMaintenanceEntries
        let ids = Set(candidates.map(\.id))
        let ok = fake || fs.mutateMeta { meta in
            for entry in candidates {
                var item = meta.entries[entry.id] ?? StoreMeta.EntryMeta()
                if item.sourceUrl == nil { item.sourceUrl = entry.sourceUrl }
                item.autoUpdate = on
                meta.entries[entry.id] = item
            }
        }
        guard ok else {
            maintenance.settingsFeedback = L("设置未保存，请检查目录权限和磁盘空间。")
            return false
        }
        for i in entries.indices where ids.contains(entries[i].id) { entries[i].autoUpdate = on }
        MaintenancePolicyStore.saveKnownSourceIDs(ids, defaults: maintenanceDefaults)
        maintenance.settingsFeedback = L("已应用到 \(ids.count) 个现有来源。")
        return true
    }

    /// 识别安装后第一次出现的远端来源，只继承一次。用户之后手动关掉某个来源不会被反复拨回。
    @discardableResult
    func reconcileRemoteSourceDefaults() -> Int {
        let candidates = remoteMaintenanceEntries
        let current = Set(candidates.map(\.id))
        let known = MaintenancePolicyStore.loadKnownSourceIDs(defaults: maintenanceDefaults)
        let policy = MaintenancePolicyStore.loadPolicy(defaults: maintenanceDefaults)
        let newcomers = remoteSourceIDsToInherit(current: current, known: known,
                                                  inherit: policy.inheritRemoteAutoUpdate)
        guard !newcomers.isEmpty else {
            MaintenancePolicyStore.saveKnownSourceIDs(current, defaults: maintenanceDefaults)
            return 0
        }
        let sourceById = Dictionary(uniqueKeysWithValues: candidates.compactMap { entry in
            entry.sourceUrl.map { (entry.id, $0) }
        })

        if !fake {
            let ok = fs.mutateMeta { meta in
                for id in newcomers {
                    var item = meta.entries[id] ?? StoreMeta.EntryMeta()
                    if item.sourceUrl == nil { item.sourceUrl = sourceById[id] }
                    item.autoUpdate = true
                    meta.entries[id] = item
                }
            }
            guard ok else {
                plog.error("新来源自动更新继承写盘失败；保留 known 集合以便下次重试")
                return 0
            }
        }
        for index in entries.indices where newcomers.contains(entries[index].id) {
            entries[index].autoUpdate = true
        }
        MaintenancePolicyStore.saveKnownSourceIDs(current, defaults: maintenanceDefaults)
        plog.info("新远端来源继承自动更新：\(newcomers.count) 个")
        return newcomers.count
    }

    func startMaintenanceAutomation() {
        let id = ObjectIdentifier(self)
        guard MaintenanceAutomationRegistry.tasks[id] == nil else { return }
        _ = reconcileRemoteSourceDefaults()

        let stored = MaintenancePolicyStore.loadStatus(defaults: maintenanceDefaults)
        let recovered = recoveredInterruptedMaintenanceStatus(stored)
        let shouldRetryInterruptedRun = recovered != stored
        if shouldRetryInterruptedRun {
            MaintenancePolicyStore.saveStatus(recovered, defaults: maintenanceDefaults)
            plog.warning("检测到上次维护中断，已收口状态并准备补跑")
        }

        let task = Task { @MainActor [weak self] in
            defer { MaintenanceAutomationRegistry.tasks.removeValue(forKey: id) }
            var retryInterruptedRun = shouldRetryInterruptedRun
            while !Task.isCancelled {
                guard let self else { return }
                _ = self.reconcileRemoteSourceDefaults()
                let policy = MaintenancePolicyStore.loadPolicy(defaults: maintenanceDefaults)
                let status = MaintenancePolicyStore.loadStatus(defaults: maintenanceDefaults)
                if retryInterruptedRun, policy.periodicCheckEnabled {
                    retryInterruptedRun = false
                    await self.performMaintenance(policy: policy, showFeedback: false, force: true)
                } else {
                    retryInterruptedRun = false
                    if maintenanceRunIsDue(policy: policy, status: status) {
                        await self.performMaintenance(policy: policy, showFeedback: false)
                    }
                }
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
            }
        }
        MaintenanceAutomationRegistry.tasks[id] = task
    }

    func stopMaintenanceAutomation() {
        let id = ObjectIdentifier(self)
        MaintenanceAutomationRegistry.tasks.removeValue(forKey: id)?.cancel()
    }

    func runMaintenanceNow(showFeedback: Bool = true) {
        let policy = MaintenancePolicyStore.loadPolicy(defaults: maintenanceDefaults)
        Task { @MainActor [weak self] in
            await self?.performMaintenance(policy: policy, showFeedback: showFeedback, force: true)
        }
    }

    private func performMaintenance(
        policy: MaintenancePolicy,
        showFeedback: Bool,
        force: Bool = false
    ) async {
        let oldStatus = MaintenancePolicyStore.loadStatus(defaults: maintenanceDefaults)
        if oldStatus.outcome == .running || checkingUpdates || checkingClis || maintenanceMutationBusy {
            if showFeedback {
                say(maintenanceText("已有检查或更新正在执行。", "Another check or update is already running."))
            }
            return
        }
        if !force, !maintenanceRunIsDue(policy: policy, status: oldStatus) { return }

        var status = MaintenanceRunStatus(outcome: .running, startedAt: Date())
        status.checkedSources = remoteMaintenanceEntries.count
        MaintenancePolicyStore.saveStatus(status, defaults: maintenanceDefaults)
        if showFeedback {
            say(maintenanceText("正在检查技能源与 Agent CLI…", "Checking skill sources and agent CLIs…"))
        }

        // One scheduled run owns one report across source and CLI phases. An idle
        // gap between those phases is not a new batch; all exit paths close it.
        maintenance.report.beginBatch()
        defer { maintenance.report.endBatch() }

        // 复用现有完整更新链：源内容哈希、漂移保护、回收站与低泄露 CLI 白名单都保持不变。
        checkUpdates(auto: true)
        let checkDeadline = Date().addingTimeInterval(240)
        while (checkingUpdates || checkingClis), Date() < checkDeadline {
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
        }
        guard !checkingUpdates, !checkingClis else {
            status.outcome = .failed
            status.finishedAt = Date()
            status.error = maintenanceText("维护检查超时；旧版本未被删除。", "Maintenance check timed out; existing versions were kept.")
            MaintenancePolicyStore.saveStatus(status, defaults: maintenanceDefaults)
            if showFeedback { sayError(status.summary) }
            return
        }

        let sourceDeadline = Date().addingTimeInterval(420)
        while !updatingIds.isEmpty, Date() < sourceDeadline {
            do { try await Task.sleep(for: .milliseconds(300)) }
            catch { return }
        }
        let sourceReceipts = (maintenance.report.startedAt ?? .distantPast) >= (status.startedAt ?? .distantPast)
            ? maintenance.report.items.filter { $0.kind == .source } : []
        status.sourceUpdatesStarted = sourceReceipts.count
        status.sourceFailures = sourceReceipts.filter { $0.phase != .succeeded && $0.phase != .skipped }.count
        let checkFailures = maintenance.sourceChecks.values.filter {
            $0.checkedAt >= (status.startedAt ?? .distantPast) && $0.outcome == .failed
        }.count
        if checkFailures > 0 { status.error = L("\(checkFailures) 个来源检查失败，请查看维护中心。") }

        let recognized = globalClis.filter { $0.agentDefinition != nil }
        let agentUpdates = recognized.filter(\.safeRecognizedAgentUpdate)
        status.checkedAgents = recognized.count
        status.availableAgentUpdates = agentUpdates.count
        status.unresolvedAgents = recognized.filter {
            !$0.excluded && $0.tracksIndex && $0.latest == nil
        }.count

        if policy.normalized.autoUpgradeRecognizedAgents, !agentUpdates.isEmpty {
            let ids = Set(agentUpdates.map(\.id))
            for cli in agentUpdates { upgradeCli(cli) }
            let upgradeDeadline = Date().addingTimeInterval(600)
            while !upgradingClis.isEmpty, Date() < upgradeDeadline {
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
            }
            let receipts = maintenance.report.items.filter { $0.kind == .cli && ids.contains($0.id) }
            status.failedAgentUpgrades = receipts.filter { $0.phase == .failed }.count
            status.upgradedAgents = receipts.filter { $0.phase == .succeeded }.count
            status.unresolvedAgents += receipts.filter { $0.phase == .unverified || $0.phase.isActive }.count
                + ids.subtracting(Set(receipts.map(\.id))).count
        }

        status.finishedAt = Date()
        let problems = status.sourceFailures + status.unresolvedAgents + status.failedAgentUpgrades + checkFailures
        status.outcome = problems > 0 ? .partial : .success
        MaintenancePolicyStore.saveStatus(status, defaults: maintenanceDefaults)
        plog.info("统一维护完成：\(status.summary, privacy: .public)")
        if showFeedback {
            if status.outcome == .partial { sayError(status.summary) }
            else { say(status.summary) }
        }
    }
}
