import Combine
import SwiftUI

/// One native Settings scene sharing the application's model; no second scanner or scheduler.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var policy = MaintenancePolicy()
    @State private var meta = StoreMeta()
    @State private var sparkleAuto = false
    @State private var trash: [StoreFS.TrashItem] = []
    @State private var trashQuery = ""
    @FocusState private var trashSearchFocused: Bool
    @State private var bulkValue = true
    @State private var confirmBulk = false
    @State private var confirmAllCli = false
    @State private var confirmEmptyTrash = false

    var body: some View {
        @Bindable var state = model.maintenance
        VStack(spacing: 0) {
            TabView(selection: $state.settingsSection) {
                tools.tabItem { Label(L("工具"), systemImage: "wrench.and.screwdriver") }.tag(SettingsSection.tools)
                automation.tabItem { Label(L("自动维护"), systemImage: "clock.arrow.circlepath") }.tag(SettingsSection.automation)
                data.tabItem { Label(L("数据与恢复"), systemImage: "externaldrive") }.tag(SettingsSection.data)
                about.tabItem { Label(L("关于"), systemImage: "info.circle") }.tag(SettingsSection.about)
            }
            if let message = state.settingsFeedback {
                Text(message).font(.system(size: 12)).foregroundStyle(Ink.secondary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
        }
        .font(.system(size: 13))
        .controlSize(.regular)
        .frame(width: 780, height: 660)
        .background(Ink.window)
        .onChange(of: state.settingsSearchRequested) { _, _ in
            state.settingsSection = .data; trashSearchFocused = true
        }
        .onAppear { reload(); policy = model.maintenancePolicy; sparkleAuto = model.sparkleAutoCheckGet?() ?? false }
        .onChange(of: model.tools) { _, _ in meta = model.fs.loadMeta() }
        .onChange(of: model.entries) { _, _ in reload() }
        .onChange(of: model.toast) { _, value in
            if model.toastIsError { model.maintenance.settingsFeedback = value }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification,
                    object: model.maintenanceDefaults).receive(on: RunLoop.main)) { _ in policy = model.maintenancePolicy }
        .confirmationDialog(L("应用到现有来源？"), isPresented: $confirmBulk, titleVisibility: .visible) {
            Button(L("应用设置")) { _ = model.applyAutoUpdateToExistingSources(bulkValue) }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("将修改 \(model.remoteSourceCandidates.count) 个现有远端来源；不改变新来源默认值，本地改动保护仍然有效。"))
        }
        .confirmationDialog(L("允许检查全部全局 CLI？"), isPresented: $confirmAllCli, titleVisibility: .visible) {
            Button(L("允许后续检查")) { model.autoCliPatrol = true; state.cliScope = .all }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("手动和自动检查将向 npm registry 发送全部待查全局包名。不需要全量检查时，请保持常用工具范围。"))
        }
        .confirmationDialog(L("清空回收站？"), isPresented: $confirmEmptyTrash, titleVisibility: .visible) {
            Button(L("永久删除全部备份"), role: .destructive) {
                do { try model.fs.emptyTrash(); reload(); state.settingsFeedback = L("回收站已清空") }
                catch { state.settingsFeedback = error.localizedDescription }
            }
            Button(L("取消"), role: .cancel) {}
        } message: { Text(L("永久删除全部 \(trash.count) 项备份，不可恢复。")) }
    }

    private var toolRows: [ToolDef] {
        ToolDef.builtins.filter { def in
            def.alwaysShow || model.detectedOptionals.contains { $0.id == def.id } || model.tools.contains { $0.id == def.id }
        }
    }
    private var tools: some View {
        Form {
            Section {
                ForEach(toolRows, id: \.id) { def in
                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(def.name).fontWeight(.semibold)
                            Text(model.tools.first { $0.id == def.id }?.connected == true
                                 || model.detectedOptionals.contains { $0.id == def.id }
                                 ? L("本机已发现") : L("未发现工具目录"))
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if def.alwaysShow {
                            Text(L("固定显示")).foregroundStyle(.secondary).frame(width: 110)
                        } else {
                            Toggle(L("首页显示"), isOn: Binding(
                                get: { meta.tools[def.id]?.showOnHome ?? false },
                                set: { _ = model.setToolPreference(def.id, showOnHome: $0); meta = model.fs.loadMeta() }
                            )).toggleStyle(.switch).fixedSize()
                        }
                        Toggle(L("默认挂载"), isOn: Binding(
                            get: { meta.tools[def.id]?.defaultTarget ?? def.alwaysShow },
                            set: { _ = model.setToolPreference(def.id, defaultTarget: $0); meta = model.fs.loadMeta() }
                        )).toggleStyle(.switch).fixedSize()
                    }.padding(.vertical, 6)
                }
            } header: { Text(L("工具")) } footer: {
                Text(L("首页显示只影响界面；默认挂载只影响以后安装。这里不会改动已有技能链接或创建工具目录。"))
            }
        }.formStyle(.grouped)
    }

    private var automation: some View {
        Form {
            Section {
                Toggle(L("应用运行时定期检查"), isOn: policyBinding(\.periodicCheckEnabled))
                Picker(L("检查间隔"), selection: Binding(get: { policy.intervalHours }, set: {
                    var next = policy; next.intervalHours = $0; save(next)
                })) {
                    ForEach(MaintenancePolicy.allowedIntervals, id: \.self) { h in Text(L("\(h) 小时")).tag(h) }
                }.disabled(!policy.periodicCheckEnabled)
                Toggle(L("允许已识别的 Agent 自动升级"), isOn: policyBinding(\.autoUpgradeRecognizedAgents))
                    .disabled(!policy.periodicCheckEnabled)
                Toggle(L("后续检查包含全部全局 npm CLI"), isOn: Binding(
                    get: { model.autoCliPatrol },
                    set: { value in
                        if value { confirmAllCli = true }
                        else { model.autoCliPatrol = false; model.maintenance.cliScope = .common }
                    }))
            } header: { Text(L("检查与自动升级")) } footer: {
                Text(L("只在 Popskill 运行时执行。自动升级仅限明确识别且安装渠道、路径符合条件的 Agent；不保证上游新版没有问题。"))
            }
            Section {
                Toggle(L("新来源默认允许自动更新"), isOn: Binding(
                    get: { policy.inheritRemoteAutoUpdate },
                    set: { model.setFutureSourceAutoUpdate($0); policy = model.maintenancePolicy }))
                Text(L("只影响以后新添加的来源，不覆盖现有来源的选择。"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Text(L("现有来源已开启 \(model.remoteSourceCandidates.filter(\.autoUpdate).count)/\(model.remoteSourceCandidates.count)"))
                    Spacer()
                    Picker(L("批量设置"), selection: $bulkValue) {
                        Text(L("开启")).tag(true); Text(L("停用")).tag(false)
                    }.labelsHidden().frame(width: 90)
                    Button(L("应用到现有来源…")) { confirmBulk = true }
                        .disabled(model.remoteSourceCandidates.isEmpty || model.maintenanceMutationBusy)
                }
            } header: { Text(L("技能源自动更新")) }
        }.formStyle(.grouped)
    }

    private var data: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("技能目录")).fontWeight(.semibold)
                    Text(abbrev(model.fs.env.storeRoot.path)).textSelection(.enabled).foregroundStyle(.secondary)
                    Text(model.syncInfo.isGitRepo ? L("已配置 Git；提交状态不代表远端已同步。") : L("未配置跨设备同步，不影响本机使用。"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("导入未托管目录")) { model.importUnmanaged(); reload() }
                    .disabled(model.maintenanceMutationBusy)
                Button(L("在访达中显示")) { model.openStore() }
            }
            Divider()
            HStack {
                Text(L("备份与回收站（\(trash.count)）")).fontWeight(.semibold)
                Spacer()
                Button(L("打开文件夹")) { model.openTrash() }
                Button(L("清空回收站…"), role: .destructive) { confirmEmptyTrash = true }
                    .disabled(trash.isEmpty || model.maintenanceMutationBusy)
            }
            TextField(L("搜索全部备份"), text: $trashQuery).textFieldStyle(.roundedBorder).focused($trashSearchFocused)
            Text(L("原位置为空时可恢复；同名仍存在时不覆盖。CLI 包管理器升级不提供这里的文件夹回滚。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            List(trash.filter { trashQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(trashQuery) }) { item in
                backupRow(item)
            }.listStyle(.inset)
            if trash.isEmpty { Text(L("暂无备份")).foregroundStyle(.secondary) }
        }.padding(20)
    }
    private func backupRow(_ item: StoreFS.TrashItem) -> some View {
        let dest = model.fs.env.storeRoot.appendingPathComponent(item.kindDir).appendingPathComponent(item.name)
        let conflict = FileManager.default.fileExists(atPath: dest.path) || model.fs.isSymlink(dest)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).fontWeight(.medium)
                HStack {
                    Text(item.kindDir)
                    if let date = item.date { Text(date, style: .date); Text(date, style: .time) }
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                if conflict { Text(L("原位置已有同名内容；保留现状，请先查看备份。"))
                    .font(.system(size: 12)).foregroundStyle(Ink.amberText) }
            }
            Spacer()
            Button(L("查看备份")) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Button(L("恢复")) { model.restoreTrashItem(item); reload(); model.maintenance.settingsFeedback = model.toast }
                .disabled(conflict || model.maintenanceMutationBusy)
        }.padding(.vertical, 6)
    }

    private var about: some View {
        Form {
            Section {
                Text("Popskill \(popskillVersion)").font(.system(size: 22, weight: .semibold))
                Text(L("本地 AI 能力管理器")).foregroundStyle(.secondary)
                if model.checkAppUpdate != nil {
                    Button(L("检查 Popskill 更新…")) { model.checkAppUpdate?() }
                }
                if model.sparkleAutoCheckGet != nil {
                    Toggle(L("自动检查 Popskill 更新"), isOn: Binding(get: { sparkleAuto }, set: {
                        model.sparkleAutoCheckSet?($0)
                        sparkleAuto = model.sparkleAutoCheckGet?() ?? false
                    }))
                }
            }
            Section {
                Button(L("使用帮助")) { NSWorkspace.shared.open(URL(string: "https://github.com/maojiebc/majia-Popskill#readme")!) }
                Button(L("报告问题…")) { model.reportIssue() }
                Text("MIT").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private func reload() { meta = model.fs.loadMeta(); trash = model.fs.listTrash() }
    private func policyBinding(_ path: WritableKeyPath<MaintenancePolicy, Bool>) -> Binding<Bool> {
        Binding(get: { policy[keyPath: path] }, set: { var next = policy; next[keyPath: path] = $0; save(next) })
    }
    private func save(_ next: MaintenancePolicy) {
        MaintenancePolicyStore.savePolicy(next.normalized, defaults: model.maintenanceDefaults)
        policy = model.maintenancePolicy
        model.startMaintenanceAutomation()
    }
}
