import SwiftUI

// 维护中心（v2.21）：把来源自动更新、Agent CLI 识别、版本检查与升级收成一个闭环。
// npm 全量扫描只在打开本页时发生；定时巡检仍只发送内置白名单包名。

struct CliSheet: View {
    @Environment(AppModel.self) private var model
    @State private var hoverRow: String?
    @State private var showAll = false
    @State private var policy = MaintenancePolicyStore.loadPolicy()
    @State private var runStatus = MaintenancePolicyStore.loadStatus()

    var body: some View {
        SheetShell(width: 720, onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                head
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        automationPanel
                        inventorySummary
                        inventory
                    }
                    .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
                }
                .frame(maxHeight: 580)
                foot
            }
            // 旧表先显示，后台重新扫。打开面板才全量看 npm；日常定时检查仍是低泄露白名单。
            .onAppear {
                policy = MaintenancePolicyStore.loadPolicy()
                runStatus = MaintenancePolicyStore.loadStatus()
                _ = model.reconcileRemoteSourceDefaults()
                model.checkCliUpdates()
            }
            .task {
                while !Task.isCancelled {
                    policy = MaintenancePolicyStore.loadPolicy()
                    runStatus = MaintenancePolicyStore.loadStatus()
                    do { try await Task.sleep(for: .seconds(1)) }
                    catch { return }
                }
            }
        }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("CLI 巡检"))
                    .font(.ui(9.5, .bold)).kerning(0.6).foregroundStyle(Ink.tertiary)
                Text(maintenanceText("维护中心", "Maintenance Center"))
                    .font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
                Text(maintenanceText(
                    "统一管理技能源自动更新与本机 Agent CLI。",
                    "Manage source auto-updates and local agent CLIs in one place."
                ) + " " + L("按真实安装位置升级：npm 多前缀、Homebrew、pipx、uv。基础工具只展示不升级。"))
                .font(.ui(11.5)).foregroundStyle(Ink.secondary)
            }
            Spacer()
            Button { model.sheet = nil } label: {
                Text("esc")
                    .font(.mono(11))
                    .foregroundStyle(Color(hex: 0x666666))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 13, trailing: 20))
        .background(Ink.chrome)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    // ── 自动更新策略 ──────────────────────────────────────

    private var automationPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(maintenanceText("自动更新", "AUTOMATIC UPDATES"))
                .font(.ui(10.5, .bold)).kerning(0.6).foregroundStyle(Ink.tertiary)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(maintenanceText("全部远端技能源", "All remote skill sources"))
                            .font(.ui(12.5, .semibold)).foregroundStyle(Ink.ink)
                        Text("\(enabledSourceCount)/\(sourceCandidates.count)")
                            .font(.mono(10)).foregroundStyle(sourceAutoAll ? Ink.green : Ink.tertiary)
                    }
                    Text(sourcePolicyDescription)
                        .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                PsSwitch(on: sourceAutoAll && policy.inheritRemoteAutoUpdate) {
                    setAllSourceAutoUpdate(!(sourceAutoAll && policy.inheritRemoteAutoUpdate))
                }
                .help(maintenanceText(
                    "一次覆盖当前全部 GitHub / npm / well-known 来源，并作为未来新来源的默认值",
                    "Cover all current GitHub, npm, and well-known sources and use the choice as the default for new sources"
                ))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.hairline, lineWidth: 1))

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(maintenanceText("定时维护巡检", "Scheduled maintenance"))
                            .font(.ui(12.5, .semibold)).foregroundStyle(Ink.ink)
                        Text(maintenanceText(
                            "应用运行时按节奏检查已开启的技能源与内置 Agent 白名单。",
                            "While Popskill is running, periodically check enabled skill sources and the built-in agent allowlist."
                        ))
                        .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                    }
                    Spacer(minLength: 12)
                    PsSwitch(on: policy.periodicCheckEnabled) { togglePeriodicCheck() }
                }

                if policy.periodicCheckEnabled {
                    HStack(spacing: 8) {
                        Text(maintenanceText("间隔", "Interval"))
                            .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                        ForEach(MaintenancePolicy.allowedIntervals, id: \.self) { hours in
                            intervalButton(hours)
                        }
                        Spacer()
                        Text(maintenanceText("安全 Agent 自动升级", "Auto-upgrade safe agents"))
                            .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                        PsSwitch(on: policy.autoUpgradeRecognizedAgents) { toggleAgentAutoUpgrade() }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.hairline, lineWidth: 1))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(runStatus.summary)
                        .font(.ui(10.5, .medium))
                        .foregroundStyle(runStatus.outcome == .partial || runStatus.outcome == .failed ? Ink.amberText : Ink.secondary2)
                    if let date = runStatus.finishedAt ?? runStatus.startedAt {
                        Text(maintenanceText("最近运行：", "Last run: ") + relativeMaintenanceDate(date))
                            .font(.ui(9.5)).foregroundStyle(Ink.tertiary)
                    }
                }
                Spacer()
                Button { model.runMaintenanceNow() } label: {
                    Text(runStatus.outcome == .running
                         ? maintenanceText("运行中…", "Running…")
                         : maintenanceText("立即运行", "Run now"))
                        .font(.ui(10.5, .semibold)).foregroundStyle(Color(hex: 0x444444))
                        .padding(.horizontal, 9).frame(height: 25)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.control2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(runStatus.outcome == .running || model.checkingUpdates || model.checkingClis)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                Text(maintenanceText(
                    "安全边界：更新前仍检查本地改动；改过的技能、Marketplace 插件、本地路径和 PATH 冲突 CLI 不会被批量覆盖。",
                    "Safety boundary: local edits are checked; modified skills, Marketplace plugins, local paths, and PATH-conflicted CLIs are never bulk-overwritten."
                ))
                .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                Spacer()
                if driftedSourceCount > 0 {
                    Text(maintenanceText("跳过本地改动 \(driftedSourceCount)", "Skip \(driftedSourceCount) local edits"))
                        .font(.ui(9.5, .semibold)).foregroundStyle(Ink.amberText)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Ink.amberBadgeBg))
                        .overlay(Capsule().stroke(Ink.amberBadgeBorder, lineWidth: 1))
                }
            }
        }
    }

    private var sourceCandidates: [Entry] {
        model.entries.filter {
            supportsBulkAutomaticUpdate(sourceUrl: $0.sourceUrl, managedExternally: $0.isManagedExternally)
        }
    }

    private var enabledSourceCount: Int { sourceCandidates.filter(\.autoUpdate).count }
    private var driftedSourceCount: Int { sourceCandidates.filter(\.localDrifted).count }
    private var sourceAutoAll: Bool {
        !sourceCandidates.isEmpty && enabledSourceCount == sourceCandidates.count
    }

    private var sourcePolicyDescription: String {
        guard !sourceCandidates.isEmpty else {
            return policy.inheritRemoteAutoUpdate
                ? maintenanceText("当前没有远端来源；以后新添加的来源会默认开启。", "No remote source yet; newly added remote sources will default to on.")
                : maintenanceText("还没有可自动更新的远端来源。", "No remote source is eligible for auto-update yet.")
        }
        if sourceAutoAll && policy.inheritRemoteAutoUpdate {
            return maintenanceText("当前来源全部开启，未来新增远端来源也会自动继承。", "All current sources are enabled and future remote sources will inherit the policy.")
        }
        if enabledSourceCount > 0 {
            return maintenanceText("已有 \(enabledSourceCount) 个开启；右侧开关会同时覆盖当前与未来来源。", "\(enabledSourceCount) sources are enabled; the switch covers both current and future sources.")
        }
        return maintenanceText("一次开启当前全部来源，并记住为未来新来源的默认值。", "Enable every current source and remember the choice for future sources.")
    }

    private func setAllSourceAutoUpdate(_ on: Bool) {
        if model.setAllRemoteSourceAutoUpdate(on) {
            policy = MaintenancePolicyStore.loadPolicy()
        }
    }

    private func togglePeriodicCheck() {
        var next = policy
        next.periodicCheckEnabled.toggle()
        if !next.periodicCheckEnabled { next.autoUpgradeRecognizedAgents = false }
        savePolicy(next)
    }

    private func toggleAgentAutoUpgrade() {
        var next = policy
        next.autoUpgradeRecognizedAgents.toggle()
        if next.autoUpgradeRecognizedAgents { next.periodicCheckEnabled = true }
        savePolicy(next)
    }

    private func savePolicy(_ next: MaintenancePolicy) {
        policy = next.normalized
        MaintenancePolicyStore.savePolicy(policy)
        model.startMaintenanceAutomation()
    }

    private func intervalButton(_ hours: Int) -> some View {
        Button { var next = policy; next.intervalHours = hours; savePolicy(next) } label: {
            Text(hours == 72 ? maintenanceText("3 天", "3d") : "\(hours)h")
                .font(.mono(9.5, .semibold))
                .foregroundStyle(policy.intervalHours == hours ? .white : Ink.secondary2)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(policy.intervalHours == hours ? Ink.ink : Ink.chrome))
                .overlay(Capsule().stroke(Ink.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func relativeMaintenanceDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = l10nLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // ── CLI 清单 ──────────────────────────────────────────

    private var inventorySummary: some View {
        HStack(spacing: 8) {
            summaryChip(
                value: recognizedAgentCount,
                label: maintenanceText("已识别 Agent", "recognized agents"),
                emphasis: false
            )
            summaryChip(
                value: recognizedAgentUpdates.count,
                label: maintenanceText("可安全升级", "safe updates"),
                emphasis: !recognizedAgentUpdates.isEmpty
            )
            summaryChip(
                value: pathConflictCount,
                label: maintenanceText("PATH 冲突", "PATH conflicts"),
                emphasis: pathConflictCount > 0
            )
            Spacer()
            HStack(spacing: 5) {
                Text(maintenanceText("仅看 Agent", "Agents only"))
                    .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                PsSwitch(on: !showAll) { showAll.toggle() }
                Text(maintenanceText("全部", "All"))
                    .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
            }
        }
    }

    private func summaryChip(value: Int, label: String, emphasis: Bool) -> some View {
        HStack(spacing: 5) {
            Text("\(value)").font(.mono(11, .bold)).monospacedDigit()
            Text(label).font(.ui(10.5))
        }
        .foregroundStyle(emphasis ? Ink.amberText : Ink.secondary2)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(emphasis ? Ink.amberBadgeBg : Ink.chrome))
        .overlay(Capsule().stroke(emphasis ? Ink.amberBadgeBorder : Ink.hairline, lineWidth: 1))
    }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: 0) {
            if visibleClis.isEmpty {
                Text(emptyMessage)
                    .font(.ui(11.5)).foregroundStyle(Ink.tertiary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                tableHead
                ForEach(visibleClis) { cli in row(cli) }
            }
        }
    }

    private var visibleClis: [GlobalCli] {
        let rows = showAll ? model.globalClis : model.globalClis.filter(\.looksLikeAgent)
        return rows.sorted { a, b in
            let ar = a.agentDefinition != nil ? 0 : (a.looksLikeAgent ? 1 : 2)
            let br = b.agentDefinition != nil ? 0 : (b.looksLikeAgent ? 1 : 2)
            if ar != br { return ar < br }
            if a.hasUpdate != b.hasUpdate { return a.hasUpdate }
            return a.maintenanceName.localizedStandardCompare(b.maintenanceName) == .orderedAscending
        }
    }

    private var recognizedAgentCount: Int {
        model.globalClis.filter { $0.agentDefinition != nil }.count
    }
    private var recognizedAgentUpdates: [GlobalCli] {
        model.globalClis.filter {
            $0.safeRecognizedAgentUpdate && $0.pathMatchesPrefix && !$0.excluded && $0.tracksIndex
        }
    }
    private var pathConflictCount: Int {
        model.globalClis.filter { !$0.pathMatchesPrefix }.count
    }

    private var emptyMessage: String {
        if model.checkingClis { return L("正在扫描全局 npm 包…") }
        return showAll
            ? L("没有发现可巡检的 CLI（或未安装 Node.js / Homebrew / pipx）")
            : maintenanceText("没有发现 Agent CLI；切到“全部”可查看其它工具。", "No agent CLI was found; switch to All to inspect other tools.")
    }

    private var tableHead: some View {
        HStack(spacing: 10) {
            Text(L("包名") + " / " + maintenanceText("说明", "DESCRIPTION"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(maintenanceText("类型", "ROLE")).frame(width: 86, alignment: .leading)
            Text(L("位置")).frame(width: 92, alignment: .leading)
            Text(L("已装") + " / " + L("最新")).frame(width: 104, alignment: .trailing)
            Color.clear.frame(width: 70)
        }
        .font(.ui(9.5, .bold)).tracking(0.5)
        .foregroundStyle(Ink.tertiary)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    private func row(_ cli: GlobalCli) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cli.maintenanceName)
                        .font(.ui(11.8, .semibold)).foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    if cli.maintenanceName != cli.name {
                        Text(cli.name)
                            .font(.mono(9.5)).foregroundStyle(Ink.tertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(cli.maintenanceSummary)
                    .font(.ui(9.8)).foregroundStyle(Ink.tertiary)
                    .lineLimit(2)
                if !cli.pathMatchesPrefix {
                    Text(L("PATH 命中另一份") + "：" + abbrev(cli.pathHit ?? ""))
                        .font(.ui(9.3)).foregroundStyle(Ink.amberText)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(cli.maintenanceRole)
                .font(.ui(9.5, .semibold))
                .foregroundStyle(cli.agentDefinition != nil ? Ink.blue : Ink.tertiary)
                .lineLimit(2)
                .frame(width: 86, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(cli.channel.label)
                    .font(.ui(9.5, .semibold)).foregroundStyle(Ink.secondary2)
                Text(cli.prefix.map(abbrev) ?? cli.channel.label)
                    .font(.mono(9.5)).foregroundStyle(Ink.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(width: 92, alignment: .leading)
            .help(cli.pathHit.map { L("命令行命中 \(abbrev($0))") } ?? cli.channel.label)

            VStack(alignment: .trailing, spacing: 1) {
                Text("v\(cli.installed)")
                    .font(.mono(10.5)).foregroundStyle(Ink.secondary2).monospacedDigit()
                Text(cli.latest.map { "→ v\($0)" } ?? "—")
                    .font(.mono(9.5)).monospacedDigit()
                    .foregroundStyle(cli.hasUpdate ? Ink.amberText : Ink.tertiary)
            }
            .frame(width: 104, alignment: .trailing)
            .help(cliLatestHelp(cli))

            Group {
                if model.upgradingClis.contains(cli.id) {
                    UpdatingDot()
                } else if cli.excluded {
                    Text(L("不自动升"))
                        .font(.ui(9.5)).foregroundStyle(Ink.tertiary)
                        .help(L("基础工具（node / npm / TypeScript 等）不在一键升级范围"))
                } else if cli.hasUpdate {
                    Button { model.upgradeCli(cli) } label: {
                        Text(L("升级"))
                            .font(.ui(10.5, .semibold)).foregroundStyle(Color(hex: 0x5A4A14))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Ink.amberBadgeBg))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.amberBadgeBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(upgradeCommandHelp(cli))
                } else {
                    Text(cli.latest == nil ? "" : L("已最新"))
                        .font(.ui(10)).foregroundStyle(Ink.green)
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hoverRow == cli.id ? Ink.chrome : .clear))
        .onHover { hoverRow = $0 ? cli.id : (hoverRow == cli.id ? nil : hoverRow) }
        .overlay(alignment: .bottom) { Ink.tableHairline.frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(cli.maintenanceName)，已装 \(cli.installed)"))
    }

    // ── 底部操作 ──────────────────────────────────────────

    private var foot: some View {
        HStack {
            Text(L("升级打回这份 CLI 真正所在的前缀，避免升错副本。"))
                .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
            Spacer()
            Button { model.checkUpdates() } label: {
                Text(model.checkingUpdates || model.checkingClis ? L("检查中…") : L("重新扫描"))
                    .font(.ui(11.5, .semibold)).foregroundStyle(Ink.secondary2)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.checkingUpdates || model.checkingClis)

            if !recognizedAgentUpdates.isEmpty {
                Button { upgradeRecognizedAgents() } label: {
                    Text(L("全部升级 (\(recognizedAgentUpdates.count))"))
                        .font(.ui(11.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Ink.ink))
                }
                .buttonStyle(.plain)
                .help(L("一键只升常用白名单；其它全局包装在行内点升级。"))
            }
        }
        .padding(EdgeInsets(top: 11, leading: 20, bottom: 13, trailing: 20))
        .background(Ink.chrome)
        .overlay(alignment: .top) { Ink.hairline.frame(height: 1) }
    }

    private func upgradeRecognizedAgents() {
        for cli in recognizedAgentUpdates { model.upgradeCli(cli) }
        model.say(maintenanceText("已将 \(recognizedAgentUpdates.count) 个 Agent CLI 加入升级队列",
                                  "Queued \(recognizedAgentUpdates.count) agent CLIs for upgrade"))
    }

    private func cliLatestHelp(_ cli: GlobalCli) -> String {
        if !cli.tracksIndex {
            return L("从 GitHub / 本地安装，不跟 PyPI 同名包比版本")
        }
        if cli.latest == nil {
            return L("版本查询失败（网络）——点右下重新扫描")
        }
        return ""
    }

    private func upgradeCommandHelp(_ cli: GlobalCli) -> String {
        if cli.channel == .npm {
            return "npm i -g --prefix \(cli.prefix ?? "") \(cli.name)@\(cli.latest ?? "")"
        }
        return maintenanceText("通过 \(cli.channel.label) 升级 \(cli.maintenanceName) → \(cli.latest ?? "")",
                               "Upgrade \(cli.maintenanceName) via \(cli.channel.label) → \(cli.latest ?? "")")
    }
}
