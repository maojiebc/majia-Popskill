import SwiftUI

// 维护中心（v2.21）：把来源自动更新、Agent CLI 识别、版本检查与升级收成一个闭环。
// npm 全量扫描只在打开本页时发生；启动检查仍只发送内置白名单包名。

struct CliSheet: View {
    @Environment(AppModel.self) private var model
    @State private var hoverRow: String?
    @State private var showAll = false

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
                .frame(maxHeight: 560)
                foot
            }
            // 旧表先显示，后台重新扫。打开面板才全量看 npm；日常自动检查仍是低泄露白名单。
            .onAppear { model.checkCliUpdates() }
        }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(maintenanceText("维护中心", "Maintenance Center"))
                    .font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
                Text(maintenanceText(
                    "统一管理技能源自动更新与本机 Agent CLI：先识别真实安装位置，再决定检查和升级。",
                    "Manage source auto-updates and local agent CLIs in one place: detect the real installation first, then check and upgrade."
                ))
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
                PsSwitch(on: sourceAutoAll) { setAllSourceAutoUpdate(!sourceAutoAll) }
                    .help(maintenanceText(
                        "一次打开或关闭所有 GitHub / npm / well-known 来源的自动更新",
                        "Enable or disable auto-update for every GitHub, npm, and well-known source"
                    ))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.hairline, lineWidth: 1))

            HStack(spacing: 8) {
                Text(maintenanceText(
                    "安全边界：更新前仍检查本地改动；改过的技能、Marketplace 插件和本地路径不会被批量覆盖。",
                    "Safety boundary: local edits are still checked; modified skills, Marketplace plugins, and local paths are never bulk-overwritten."
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
            return maintenanceText("还没有可自动更新的远端来源。", "No remote source is eligible for auto-update yet.")
        }
        if sourceAutoAll {
            return maintenanceText("启动后自动检查，有新版就更新；失败会保留旧版。", "Check on launch and update when a new version exists; failures keep the old version intact.")
        }
        if enabledSourceCount > 0 {
            return maintenanceText("已有 \(enabledSourceCount) 个开启；点右侧可一次覆盖全部。", "\(enabledSourceCount) sources are enabled; use the switch to cover all of them.")
        }
        return maintenanceText("不再逐个进来源开关，一次覆盖当前全部来源。", "Turn on every current source at once instead of enabling them one by one.")
    }

    private func setAllSourceAutoUpdate(_ on: Bool) {
        guard !sourceCandidates.isEmpty else { return }
        let targets = sourceCandidates.filter { $0.autoUpdate != on }
        for entry in targets { model.toggleAutoUpdate(entry.id) }
        model.say(on
            ? maintenanceText("已为 \(targets.count) 个来源开启自动更新", "Auto-update enabled for \(targets.count) sources")
            : maintenanceText("已关闭 \(targets.count) 个来源的自动更新", "Auto-update disabled for \(targets.count) sources"))
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
        model.globalClis.filter(\.safeRecognizedAgentUpdate)
    }
    private var pathConflictCount: Int {
        model.globalClis.filter { !$0.pathMatchesPrefix }.count
    }

    private var emptyMessage: String {
        if model.checkingClis {
            return maintenanceText("正在扫描 npm / Homebrew / pipx / uv…", "Scanning npm, Homebrew, pipx, and uv…")
        }
        return showAll
            ? maintenanceText("没有发现可巡检的全局 CLI。", "No globally installed CLI was found.")
            : maintenanceText("没有发现 Agent CLI；切到“全部”可查看其它工具。", "No agent CLI was found; switch to All to inspect other tools.")
    }

    private var tableHead: some View {
        HStack(spacing: 10) {
            Text(maintenanceText("工具与说明", "TOOL & DESCRIPTION"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(maintenanceText("类型", "ROLE")).frame(width: 86, alignment: .leading)
            Text(maintenanceText("安装位置", "INSTALL")).frame(width: 92, alignment: .leading)
            Text(maintenanceText("版本", "VERSION")).frame(width: 104, alignment: .trailing)
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
                    Text(maintenanceText("PATH 命中另一份：\(abbrev(cli.pathHit ?? ""))",
                                         "PATH resolves another copy: \(abbrev(cli.pathHit ?? ""))"))
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
            .help(cli.pathHit.map { maintenanceText("命令行命中 \(abbrev($0))", "Command resolves to \(abbrev($0))") }
                ?? cli.channel.label)

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
                    Text(maintenanceText("不自动升", "manual"))
                        .font(.ui(9.5)).foregroundStyle(Ink.tertiary)
                        .help(maintenanceText("基础工具不在一键升级范围", "Foundation tools are excluded from one-click upgrades"))
                } else if cli.hasUpdate {
                    Button { model.upgradeCli(cli) } label: {
                        Text(maintenanceText("升级", "Upgrade"))
                            .font(.ui(10.5, .semibold)).foregroundStyle(Color(hex: 0x5A4A14))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Ink.amberBadgeBg))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.amberBadgeBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(upgradeCommandHelp(cli))
                } else {
                    Text(cli.latest == nil ? "" : maintenanceText("已最新", "Current"))
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
        .accessibilityLabel("\(cli.maintenanceName), v\(cli.installed)")
    }

    // ── 底部操作 ──────────────────────────────────────────

    private var foot: some View {
        HStack {
            Text(maintenanceText(
                "升级会写回当前命令真正所在的渠道与前缀，不另装第二份。",
                "Upgrades are written back to the channel and prefix the command actually uses—no duplicate copy is installed."
            ))
            .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
            Spacer()
            Button { model.checkUpdates() } label: {
                Text(model.checkingUpdates || model.checkingClis
                     ? maintenanceText("检查中…", "Checking…")
                     : maintenanceText("检查来源与 CLI", "Check sources & CLIs"))
                    .font(.ui(11.5, .semibold)).foregroundStyle(Ink.secondary2)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.checkingUpdates || model.checkingClis)

            if !recognizedAgentUpdates.isEmpty {
                Button { upgradeRecognizedAgents() } label: {
                    Text(maintenanceText("升级已识别 Agent (\(recognizedAgentUpdates.count))",
                                         "Upgrade agents (\(recognizedAgentUpdates.count))"))
                        .font(.ui(11.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Ink.ink))
                }
                .buttonStyle(.plain)
                .help(maintenanceText("只批量升级精确识别、列入安全目录的 Agent CLI",
                                      "Bulk-upgrade only exactly recognized agent CLIs in the safe catalog"))
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
            return maintenanceText("从 GitHub / 本地安装，不跟 PyPI 同名包比版本",
                                   "Installed from GitHub or a local path; not compared with a PyPI namesake")
        }
        if cli.latest == nil {
            return maintenanceText("版本查询失败或尚未完成——重新检查即可重试",
                                   "Version lookup failed or is still pending—run Check again to retry")
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
