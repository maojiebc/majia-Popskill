import Combine
import SwiftUI

// Long-running work belongs in the main window, not a dismissible overlay.
struct MaintenanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool
    @State private var confirmFullScope = false
    @State private var policy = MaintenancePolicy()

    var body: some View {
        @Bindable var state = model.maintenance
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { model.returnToMatrix() } label: { Label(L("返回能力矩阵"), systemImage: "chevron.left") }
                Text(L("维护中心")).font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(L("管理自动维护…")) { state.settingsSection = .automation; openSettings() }
            }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 14)
            HStack {
                Picker(L("维护对象"), selection: $state.tab) {
                    Text(L("技能来源")).tag(MaintenanceTab.sources)
                    Text(L("Agent CLI")).tag(MaintenanceTab.clis)
                }.pickerStyle(.segmented).frame(width: 280)
                Spacer()
                Text(policy.periodicCheckEnabled ? L("每 \(policy.intervalHours) 小时检查；自动更新按已授权策略执行。") : L("定期检查未开启；已授权的来源仍可能在启动时更新。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 12)
            HStack(spacing: 12) {
                TextField(L("搜索名称或来源"), text: Binding(
                    get: { state.tab == .sources ? state.sourceQuery : state.cliQuery },
                    set: { if state.tab == .sources { state.sourceQuery = $0 } else { state.cliQuery = $0 } }
                )).textFieldStyle(.roundedBorder).focused($searchFocused).frame(maxWidth: 340)
                Picker(L("状态筛选"), selection: Binding(
                    get: { state.tab == .sources ? state.sourceFilter : state.cliFilter },
                    set: { if state.tab == .sources { state.sourceFilter = $0 } else { state.cliFilter = $0 } }
                )) { ForEach(MaintenanceFilter.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 250)
                Spacer()
                if state.tab == .clis {
                    Picker(L("检查范围"), selection: Binding(get: { state.cliScope }, set: { scope in
                        if scope == .all && !model.autoCliPatrol && !state.allCliInspectionAuthorized { confirmFullScope = true }
                        else { state.cliScope = scope }
                    })) { ForEach(CliScanScope.allCases, id: \.self) { Text($0.label).tag($0) } }
                        .fixedSize()
                }
            }.padding(.horizontal, 24).padding(.bottom, 14)
            Divider()
            ZStack {
                sourceList.opacity(state.tab == .sources ? 1 : 0)
                    .disabled(state.tab != .sources).allowsHitTesting(state.tab == .sources).accessibilityHidden(state.tab != .sources)
                cliList.opacity(state.tab == .clis ? 1 : 0)
                    .disabled(state.tab != .clis).allowsHitTesting(state.tab == .clis).accessibilityHidden(state.tab != .clis)
            }
            resultPanel
            Divider()
            footer
        }
        .background(Ink.window).font(.system(size: 13)).buttonStyle(.bordered).controlSize(.regular)
        .onAppear { policy = model.maintenancePolicy }
        .onChange(of: state.searchRequested) { _, _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification,
                    object: model.maintenanceDefaults).receive(on: RunLoop.main)) { _ in policy = model.maintenancePolicy }
        .confirmationDialog(L("检查全部全局 CLI？"), isPresented: $confirmFullScope, titleVisibility: .visible) {
            Button(L("允许本次会话")) { state.allCliInspectionAuthorized = true; state.cliScope = .all }
            Button(L("取消"), role: .cancel) {}
        } message: { Text(L("点击检查时会向 npm registry 发送全部待查全局包名。这里只授权本次会话，不改变自动检查范围。")) }
    }

    private var sourceList: some View {
        @Bindable var state = model.maintenance
        return ScrollView {
            LazyVStack(spacing: 10) {
                if model.filteredMaintenanceSources.isEmpty { emptyState }
                ForEach(model.filteredMaintenanceSources) { entry in sourceRow(entry).id(entry.id) }
            }.scrollTargetLayout().padding(24)
        }.scrollPosition(id: $state.sourceScrollID, anchor: .top)
    }
    private var cliList: some View {
        @Bindable var state = model.maintenance
        return ScrollView {
            LazyVStack(spacing: 10) {
                if model.filteredMaintenanceClis.isEmpty { emptyState }
                ForEach(model.filteredMaintenanceClis) { cli in cliRow(cli).id(cli.id) }
            }.scrollTargetLayout().padding(24)
        }.scrollPosition(id: $state.cliScrollID, anchor: .top)
    }
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(L("没有匹配的项目")).font(.system(size: 16, weight: .medium))
            Text(L("可清除搜索或筛选后再检查；首次读取失败时也可能没有清单。"))
                .foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(40)
    }

    private func sourceRow(_ entry: Entry) -> some View {
        let expanded = model.maintenance.expandedSources.contains(entry.id)
        let check = model.maintenance.sourceChecks[entry.id]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Button { toggleSource(entry.id) } label: {
                    HStack {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.name).fontWeight(.semibold)
                            Text(entry.sourceUrl ?? L("来源待确认")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Text(L("\(entry.allCaps.count) 项能力")).foregroundStyle(.secondary)
                status(entry.id, check: check, hasUpdate: entry.hasUpdate,
                       fallback: entry.isManagedExternally ? L("由原渠道管理") : L("尚未检查"))
                    .frame(width: 120, alignment: .leading)
                Button(L("更新此来源")) { model.runUpdate(entry.id) }
                    .disabled(!entry.hasUpdate || entry.localDrifted || entry.isManagedExternally || model.maintenanceMutationBusy || check?.outcome == .failed)
            }
            if entry.localDrifted { warning(L("检测到本地改动，已阻止覆盖。请先处理或备份本地版本。")) }
            if let error = check?.error { warning(error) }
            if expanded { sourceDetails(entry) }
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.hairline))
    }
    private func sourceDetails(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text(entry.allCaps.map(\.name).joined(separator: " · ")).textSelection(.enabled).foregroundStyle(.secondary)
            HStack {
                if supportsBulkAutomaticUpdate(sourceUrl: entry.sourceUrl, managedExternally: entry.isManagedExternally) {
                    Toggle(L("此来源允许自动更新"), isOn: Binding(get: {
                        model.entries.first { $0.id == entry.id }?.autoUpdate ?? false
                    }, set: { value in
                        if value != entry.autoUpdate { model.toggleAutoUpdate(entry.id) }
                    })).toggleStyle(.switch).fixedSize()
                    Button(L("检查此来源")) { model.checkUpdates(auto: false, only: [entry.id]) }
                        .disabled(model.checkingUpdates || model.maintenanceMutationBusy)
                }
                Spacer()
                if let source = entry.sourceUrl { Button(L("打开来源")) { model.openSourceLink(source) } }
                Menu(L("更多")) {
                    if entry.hasUpdate { Button(L("跳过此版本")) { model.skipUpdate(entry) } }
                    if entry.skippedUpdate { Button(L("恢复更新提醒")) { model.unskipUpdate(entry) } }
                    if !entry.isManagedExternally {
                        Button(L("卸载此来源…"), role: .destructive) { model.removeEntry(entry) }
                    }
                }.disabled(model.maintenanceMutationBusy)
            }
        }
    }
    private func cliRow(_ cli: GlobalCli) -> some View {
        let expanded = model.maintenance.expandedClis.contains(cli.id)
        let check = model.maintenance.cliChecks[cli.id]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Button { toggleCli(cli.id) } label: {
                    HStack {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(cli.maintenanceName).fontWeight(.semibold)
                            Text(cli.maintenanceSummary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                Text("\(cli.installed) → \(cli.latest ?? "—")").monospacedDigit()
                    .frame(width: 190, alignment: .leading)
                status(cli.id, check: check, hasUpdate: cli.hasUpdate,
                       fallback: cli.excluded || !cli.tracksIndex ? L("由原渠道管理") : L("尚未检查"))
                    .frame(width: 120, alignment: .leading)
                Button(L("更新此工具")) { requestCliUpdate(cli) }
                    .disabled(!cli.hasUpdate || model.maintenanceMutationBusy || model.checkingClis || check?.outcome == .failed)
            }
            if !cli.pathMatchesPrefix {
                let path = cli.pathHit ?? "—"
                warning(L("终端正在使用另一份安装：\(path)"))
            }
            if let error = check?.error { warning(error) }
            if expanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("包名：\(cli.name)"))
                    Text(L("安装渠道：\(cli.channel.label)"))
                    if let prefix = cli.prefix { Text(L("安装位置：\(prefix)")) }
                    if let path = cli.pathHit { Text(L("终端命中：\(path)")) }
                    if !cli.safeRecognizedAgentUpdate { Text(L("不在批量升级范围；单独更新前会再次确认目标。")) }
                }.textSelection(.enabled).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.hairline))
    }

    private func status(_ id: String, check: CheckRecord?, hasUpdate: Bool, fallback: String) -> some View {
        let receipt = model.maintenance.report.items.first { $0.id == id }
        let useReceipt = receipt.map { item in
            item.phase.isActive || (check?.checkedAt ?? .distantPast) <= (item.finishedAt ?? model.maintenance.report.startedAt ?? .distantFuture)
        } ?? false
        return VStack(alignment: .leading, spacing: 4) {
            if let receipt, useReceipt {
                HStack(spacing: 6) {
                    if receipt.phase == .running { ProgressView().controlSize(.small) }
                    Text(receipt.phase.label)
                }
            } else {
                Text(check?.outcome.label ?? (hasUpdate ? L("可更新") : fallback))
            }
            if let date = check?.checkedAt { Text(date, style: .relative).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
    private var resultPanel: some View {
        @Bindable var state = model.maintenance
        return Group {
            if !state.report.items.isEmpty {
                DisclosureGroup(isExpanded: $state.showResults) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(state.report.items) { item in
                                HStack(alignment: .top, spacing: 14) {
                                    Text(item.name).fontWeight(.medium).frame(width: 200, alignment: .leading)
                                    Text(item.phase.label).frame(width: 100, alignment: .leading)
                                    Text(item.detail ?? "").foregroundStyle(.secondary).textSelection(.enabled)
                                    Spacer()
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 145)
                } label: {
                    HStack {
                        Text(L("本批结果：已完成 \(state.report.completedCount)/\(state.report.items.count)"))
                        if let name = state.report.runningName { Text(L("正在处理 \(name)")) }
                        if state.report.queuedCount > 0 { Text(L("\(state.report.queuedCount) 项排队")) }
                        Spacer()
                        if model.retryableMaintenanceCount > 0 {
                            Button(L("重试本批失败项（\(model.retryableMaintenanceCount)）")) { model.retryMaintenanceFailures() }
                                .disabled(model.maintenanceMutationBusy || model.checkingClis || model.checkingUpdates)
                        }
                    }
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
    }
    private var footer: some View {
        let state = model.maintenance
        let count = state.tab == .sources ? model.maintenanceSourceTargets.count : model.maintenanceCliTargets.count
        let last = state.tab == .sources ? state.lastSourceCheck : state.lastCliCheck
        return HStack(spacing: 12) {
            if let last {
                Text(L("上次检查")); Text(last, style: .relative)
                if state.tab == .clis, let scope = state.lastCliScope { Text(scope.label) }
            } else { Text(L("尚未检查")) }
            Spacer()
            if state.tab == .sources { Button(L("添加来源…")) { model.sheet = .add } }
            Button(model.checkingClis || model.checkingUpdates ? L("检查中…") : L("检查更新")) {
                if state.tab == .sources { model.checkMaintenanceSources() }
                else { model.checkMaintenanceClis() }
            }.disabled(model.checkingClis || model.checkingUpdates || model.maintenanceMutationBusy)
            Button(L("更新当前结果（\(count)）")) { model.updateMaintenanceSelection() }
                .buttonStyle(.borderedProminent).tint(Ink.ink)
                .disabled(count == 0 || model.checkingClis || model.checkingUpdates || model.maintenanceMutationBusy)
        }.font(.system(size: 12)).padding(20)
    }
    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(Ink.amberText)
            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
    private func toggleSource(_ id: String) {
        if !model.maintenance.expandedSources.insert(id).inserted { model.maintenance.expandedSources.remove(id) }
    }
    private func toggleCli(_ id: String) {
        if !model.maintenance.expandedClis.insert(id).inserted { model.maintenance.expandedClis.remove(id) }
    }
    private func requestCliUpdate(_ cli: GlobalCli) {
        if !cli.safeRecognizedAgentUpdate {
            let alert = NSAlert()
            alert.messageText = L("更新这份安装？")
            let location = cli.prefix ?? cli.channel.label
            alert.informativeText = L("将更新 \(cli.name)，位置：\(location)。这不是符合批量条件的 Agent，请确认安装渠道和路径。")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L("更新此工具")); alert.addButton(withTitle: L("取消"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        model.upgradeCli(cli)
    }
}
