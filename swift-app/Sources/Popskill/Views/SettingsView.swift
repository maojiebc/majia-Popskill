import SwiftUI

/// 设置 — tabbed ledger settings (连接 / 同步 / 源 / 安装 / 配额 / 关于).
/// Real wiring: 同步 drives the actual `SyncProvider` + push/pull; 源 · 已添加的源
/// lists the real `store.sources`; install defaults / quota preferences persist
/// through `PopskillStore`.
@MainActor
struct SettingsView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var tab: SettingsTab = .connect
    @State private var syncProvider: SyncProvider = .git
    @State private var pendingMutation: Set<String> = []
    @State private var pendingRemoval: SkillRepository?
    @State private var exportingDiagnostics = false

    var body: some View {
        VStack(spacing: 0) {
            hero
            tabsBand
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content
                    Color.clear.frame(height: 8)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.horizontal, 28).padding(.vertical, 22)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.popMainBackground)
        }
        .popPageBackground()
        .onAppear { if let p = SyncProvider(rawValue: store.lastSyncProvider) { syncProvider = p } }
        .confirmationDialog(
            localization.string("sources.row.remove.confirm.title"),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingRemoval {
                Button(localization.string("sources.row.remove.confirm.button"), role: .destructive) { Task { await remove(pendingRemoval) } }
            }
            Button(localization.string("sources.add.cancel"), role: .cancel) { pendingRemoval = nil }
        }
    }

    // MARK: Hero + tabs

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                LocalizedText("sidebar.settings").font(.system(size: 25, weight: .bold)).tracking(-0.6).foregroundStyle(Color.popLabel)
                LocalizedText("settings.subtitle2").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x6F6B5E)).frame(maxWidth: 560, alignment: .leading)
            }
            Spacer(minLength: 8)
            LedgerPrimaryButton(title: localization.string("settings.save")) { store.currentSelection = .matrix }
        }
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    private var tabsBand: some View {
        HStack(spacing: 6) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                Button { tab = t } label: {
                    LocalizedText(t.titleKey)
                        .font(.system(size: 12, weight: tab == t ? .semibold : .medium))
                        .foregroundStyle(tab == t ? Color.popAccent : Color(hex: 0x5E5A4E))
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(tab == t ? Color.popAccentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .background(Color.popMainBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .connect: connectTab
        case .sync:    syncTab
        case .sources: sourcesTab
        case .install: installTab
        case .quota:   quotaTab
        case .about:   aboutTab
        }
    }

    // MARK: 连接

    private var connectTab: some View {
        section("settings.tool.title") {
            VStack(spacing: 10) {
                ForEach(store.toolConnections) { connection in
                    toolCard(connection)
                }
                dashedRow("settings.tool.add", "settings.tool.addDesc")
            }
            .task {
                if store.agentTargets.isEmpty {
                    await store.refreshAgentTargets()
                }
            }
        }
    }

    private func toolCard(_ connection: ToolConnection) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Text(toolMark(for: connection.app))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(toolMarkColor(for: connection.app), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.displayName).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Color.popLabel)
                    Text(toolMeta(connection)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.popSecondaryLabel)
                }
                Spacer()
                connectionBadge(detected: connection.detected)
            }
            .padding(.horizontal, 16).padding(.top, 13).padding(.bottom, 12)
            row("settings.tool.root", "settings.tool.rootDesc") { pathField((connection.skillRootPath as NSString).abbreviatingWithTildeInPath) }
            row("settings.tool.default", "settings.tool.defaultDesc", last: true) { defaultToolControl(connection) }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
    }

    private func toolMeta(_ connection: ToolConnection) -> String {
        let state = localization.string(connection.detected ? "Detected" : "Missing")
        let summary = connection.detectionSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? state : "\(state) · \(summary)"
    }

    private func toolMark(for app: TargetApp) -> String {
        switch app {
        case .claude: "C"
        case .codex: "Cx"
        case .gemini: "G"
        case .opencode: "Oc"
        case .hermes: "H"
        }
    }

    private func toolMarkColor(for app: TargetApp) -> Color {
        switch app {
        case .claude: Color(hex: 0xC8643C)
        case .codex: Color(hex: 0x111111)
        case .gemini: Color(hex: 0x1F4ED8)
        case .opencode: Color(hex: 0x4F46E5)
        case .hermes: Color(hex: 0x7C3AED)
        }
    }

    @ViewBuilder
    private func defaultToolControl(_ connection: ToolConnection) -> some View {
        switch connection.app {
        case .claude:
            Toggle("", isOn: $store.defaultInstallClaude)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!connection.detected)
        case .codex:
            Toggle("", isOn: $store.defaultInstallCodex)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!connection.detected)
        default:
            badge(localization.string("settings.install.manual"), ok: connection.definition.quickToggle)
        }
    }

    private func connectionBadge(detected: Bool) -> some View {
        badge(localization.string(detected ? "Detected" : "Missing"), ok: detected)
    }

    // MARK: 同步

    private var syncTab: some View {
        section("settings.sync.title") {
            VStack(spacing: 0) {
                row("settings.sync.storePath", "settings.sync.storePathDesc") { pathField(ssotPath) }
                row("settings.sync.backend", "settings.sync.backendDesc") {
                    LedgerSegmented(
                        options: SyncProvider.allCases.filter { $0 != .webdav }.map { LedgerSegmentOption(label: localization.string($0.titleKey)) },
                        selection: localization.string(syncProvider.titleKey)
                    ) { picked in
                        if let p = SyncProvider.allCases.first(where: { localization.string($0.titleKey) == picked }) {
                            syncProvider = p
                            store.lastSyncProvider = p.rawValue
                            if !p.actionable { store.autoSyncEnabled = false }
                        }
                    }
                }
                row("settings.sync.auto", "settings.sync.autoDesc") {
                    Toggle("", isOn: Binding(
                        get: { store.autoSyncEnabled && syncProvider.actionable },
                        set: { store.autoSyncEnabled = $0 && syncProvider.actionable }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!syncProvider.actionable)
                }
                row("settings.sync.actions", "settings.sync.actionsDesc", last: store.lastSyncResult == nil) {
                    HStack(spacing: 6) {
                        syncActionButton("settings.sync.push", .push, primary: true)
                        syncActionButton("settings.sync.pull", .pull, primary: false)
                        syncActionButton("settings.sync.status", .status, primary: false)
                        if store.syncInFlight { ProgressView().controlSize(.small) }
                    }
                }
                if let result = store.lastSyncResult {
                    syncResultRow(result, last: true)
                }
            }
            .modifier(CardChrome())
        }
    }

    private func syncActionButton(_ key: String, _ action: SyncAction, primary: Bool) -> some View {
        Button { Task { await runSync(action) } } label: {
            LocalizedText(key).font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(primary ? .white : Color.popLabel)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(primary ? Color.popLabel : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(primary ? Color.popLabel : Color.popControlStroke, lineWidth: 1))
        }.buttonStyle(.plain).disabled(store.syncInFlight || !syncProvider.actionable)
    }

    private func syncResultRow(_ result: SyncResult, last: Bool) -> some View {
        let summary = syncSummary(for: result)
        return row(
            syncResultTitle(for: summary.state),
            summary.message,
            rawTitle: true,
            rawDesc: true,
            last: last
        ) {
            syncResultBadge(summary.state)
        }
    }

    private func syncSummary(for result: SyncResult) -> SyncResultSummary {
        let provider = SyncProvider(rawValue: result.provider) ?? syncProvider
        return result.summary(
            successMessage: localization.string(
                "settings.sync.done",
                localizedActionName(result.action),
                localization.string(provider.titleKey)
            ),
            emptyMessage: localization.string("settings.sync.noDetails")
        )
    }

    private func localizedActionName(_ rawAction: String) -> String {
        switch rawAction {
        case SyncAction.push.rawValue: return localization.string("settings.sync.push")
        case SyncAction.pull.rawValue: return localization.string("settings.sync.pull")
        case SyncAction.status.rawValue: return localization.string("settings.sync.status")
        default: return rawAction
        }
    }

    private func syncResultTitle(for state: SyncResultSummary.State) -> String {
        switch state {
        case .success: return localization.string("settings.sync.result.success")
        case .failure: return localization.string("settings.sync.result.failure")
        case .unavailable: return localization.string("settings.sync.result.unavailable")
        case .unknown: return localization.string("settings.sync.result.unknown")
        }
    }

    private func syncResultBadge(_ state: SyncResultSummary.State) -> some View {
        let ok: Bool
        let text: String
        switch state {
        case .success:
            ok = true
            text = localization.string("common.enabled")
        case .failure:
            ok = false
            text = localization.string("settings.sync.result.failure")
        case .unavailable:
            ok = false
            text = localization.string("settings.sync.result.unavailable")
        case .unknown:
            ok = false
            text = localization.string("settings.sync.result.unknown")
        }
        return badge(text, ok: ok)
    }

    // MARK: 源

    private var sourcesTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("settings.registry.title", note: "settings.registry.note") {
                VStack(spacing: 0) {
                    registryRow("GH", Color(hex: 0x111111), "GitHub", "api.github.com", "settings.registry.tokenSet", ok: true, last: false)
                    registryRow("Cw", Color(hex: 0x1F7A6E), "ClawHub", "https://clawhub.dev/registry", "settings.registry.public", ok: false, last: false)
                    registryRow("npm", Color(hex: 0xCB3837), "npm", "https://registry.npmjs.org", "settings.registry.public", ok: false, last: false)
                    registryRow("~/", Color(hex: 0x8A8676), localization.string("settings.registry.local"), "~/work/my-skills/", "settings.registry.watching", ok: true, last: true)
                }
                .modifier(CardChrome())
            }
            section(localization.string("settings.added.title", store.sources.count), rawTitle: true, note: "settings.added.note") {
                if store.sources.isEmpty {
                    dashedRow("settings.added.add", "settings.added.addDesc")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(store.sources.enumerated()), id: \.element.id) { i, repo in
                            addedSourceRow(repo, last: i == store.sources.count - 1)
                        }
                    }
                    .modifier(CardChrome())
                }
            }
        }
    }

    private func registryRow(_ mark: String, _ bg: Color, _ name: String, _ endpoint: String, _ badgeKey: String, ok: Bool, last: Bool) -> some View {
        HStack(spacing: 12) {
            sourceMark(mark, bg)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popLabel)
                Text(endpoint).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.popSecondaryLabel).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            badge(localization.string(badgeKey), ok: ok)
            registryStatusIcon(ok: ok)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    private func addedSourceRow(_ repo: SkillRepository, last: Bool) -> some View {
        HStack(spacing: 12) {
            sourceMark("GH", Color(hex: 0x111111))
            VStack(alignment: .leading, spacing: 2) {
                Text("github.com/\(repo.label)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.popLabel).lineLimit(1).truncationMode(.middle)
                Text(localization.string("sources.row.branch", repo.branch)).font(.system(size: 11)).foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
            if pendingMutation.contains(repo.id) {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(get: { repo.enabled }, set: { v in Task { await setEnabled(repo, enabled: v) } })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            Button { pendingRemoval = repo } label: {
                LocalizedText("sources.row.remove").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(hex: 0x9A8A8A))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    // MARK: 安装 / 配额 / 关于

    private var installTab: some View {
        section("settings.install.title") {
            VStack(spacing: 0) {
                row("settings.install.target", "settings.install.targetDesc") {
                    HStack(spacing: 14) {
                        HStack(spacing: 7) {
                            Toggle("", isOn: $store.defaultInstallClaude)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            Text(verbatim: "Claude").font(.system(size: 12.5))
                        }
                        HStack(spacing: 7) {
                            Toggle("", isOn: $store.defaultInstallCodex)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                            Text(verbatim: "Codex").font(.system(size: 12.5))
                        }
                    }
                }
                row("settings.install.verify", "settings.install.verifyDesc") {
                    LedgerSegmented(
                        options: InstallVerificationMode.allCases.map { .init(label: localization.string($0.titleKey)) },
                        selection: localization.string(store.installVerificationMode.titleKey)
                    ) { picked in
                        if let mode = InstallVerificationMode.allCases.first(where: { localization.string($0.titleKey) == picked }) {
                            store.installVerificationMode = mode
                        }
                    }
                }
                row("settings.install.autoUpdate", "settings.install.autoUpdateDesc", last: true) { autoUpdateMenu }
            }
            .modifier(CardChrome())
        }
    }

    private var quotaTab: some View {
        section("settings.quota.title") {
            VStack(spacing: 0) {
                row("settings.quota.budget", "settings.quota.budgetDesc") {
                    quotaBudgetMenu
                        .disabled(!store.quotaTrackingEnabled)
                        .opacity(store.quotaTrackingEnabled ? 1 : 0.5)
                }
                row("settings.quota.threshold", "settings.quota.thresholdDesc") {
                    quotaThresholdMenu
                        .disabled(!store.quotaTrackingEnabled)
                        .opacity(store.quotaTrackingEnabled ? 1 : 0.5)
                }
                row("settings.quota.track", "settings.quota.trackDesc", last: true) {
                    Toggle("", isOn: $store.quotaTrackingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
            .modifier(CardChrome())
        }
    }

    private var aboutTab: some View {
        section("settings.about.title") {
            VStack(spacing: 0) {
                row(localization.string("settings.about.app"), localization.string("settings.about.appDesc", appVersion, store.skills.count), rawTitle: true, rawDesc: true) { selectChip("settings.about.checkUpdate") }
                row("settings.about.reonboard", "settings.about.reonboardDesc") {
                    Button { store.onboardingOpen = true } label: { selectChipLabel(localization.string("settings.onboarding.openButton")) }.buttonStyle(.plain)
                }
                row(
                    "settings.about.diagnostics",
                    diagnosticsDescription,
                    rawDesc: store.lastDiagnosticsExportURL != nil,
                    last: true
                ) {
                    Button { exportDiagnostics() } label: {
                        if exportingDiagnostics {
                            ProgressView().controlSize(.small)
                        } else {
                            selectChipLabel(localization.string("settings.about.export"))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(exportingDiagnostics)
                }
            }
            .modifier(CardChrome())
        }
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "popskill v\($0)" } ?? "popskill"
    }

    private var diagnosticsDescription: String {
        guard let url = store.lastDiagnosticsExportURL else {
            return localization.string("settings.about.diagnosticsDesc")
        }
        return localization.string("settings.about.diagnosticsExported", (url.path as NSString).abbreviatingWithTildeInPath)
    }

    // MARK: Reusable bits

    @ViewBuilder
    private func section<C: View>(_ titleKey: String, rawTitle: Bool = false, note: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group { if rawTitle { Text(titleKey) } else { LocalizedText(titleKey) } }
                .font(.system(size: 10.5, weight: .bold)).tracking(0.7).textCase(.uppercase).foregroundStyle(Color.popTertiaryLabel)
            if let note { LocalizedText(note).font(.system(size: 11.5)).foregroundStyle(Color.popTertiaryLabel).padding(.bottom, 2) }
            content()
        }
    }

    private func row<C: View>(_ title: String, _ desc: String, rawTitle: Bool = false, rawDesc: Bool = false, last: Bool = false, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Group { if rawTitle { Text(title) } else { LocalizedText(title) } }.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popLabel)
                Group { if rawDesc { Text(desc) } else { LocalizedText(desc) } }.font(.system(size: 11.5)).foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    private func dashedRow(_ title: String, _ desc: String) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                LocalizedText(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popLabel)
                LocalizedText(desc).font(.system(size: 11.5)).foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
            selectChip("settings.selectType")
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.popControlStroke))
    }

    private func defaultToolToggle(name: String) -> some View {
        let binding: Binding<Bool> = name == "Codex CLI" ? $store.defaultInstallCodex : $store.defaultInstallClaude
        return Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
    }

    private var autoUpdateMenu: some View {
        Menu {
            ForEach(InstallAutoUpdatePolicy.allCases) { policy in
                Button { store.installAutoUpdatePolicy = policy } label: {
                    optionLabel(localization.string(policy.titleKey), selected: policy == store.installAutoUpdatePolicy)
                }
            }
        } label: {
            selectChipLabel(localization.string(store.installAutoUpdatePolicy.titleKey))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var quotaBudgetMenu: some View {
        Menu {
            ForEach(QuotaBudgetOption.allCases) { option in
                Button { store.quotaMonthlyTokenBudget = option.rawValue } label: {
                    optionLabel(quotaBudgetLabel(option.rawValue), selected: option.rawValue == store.quotaMonthlyTokenBudget)
                }
            }
        } label: {
            selectChipLabel(quotaBudgetLabel(store.quotaMonthlyTokenBudget))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var quotaThresholdMenu: some View {
        Menu {
            ForEach(QuotaWarningThresholdOption.allCases) { option in
                Button { store.quotaWarningThresholdPercent = option.rawValue } label: {
                    optionLabel("\(option.rawValue)%", selected: option.rawValue == store.quotaWarningThresholdPercent)
                }
            }
        } label: {
            selectChipLabel("\(store.quotaWarningThresholdPercent)%")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func pathField(_ value: String) -> some View {
        HStack(spacing: 0) {
            Text(value).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.popLabel).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
            LocalizedText("settings.browse").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color(hex: 0x5E5A4E))
                .padding(.horizontal, 11).padding(.vertical, 7).background(Color.popSurface)
                .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0xECE9E0)).frame(width: 1) }
        }
        .frame(width: 340)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.popControlStroke, lineWidth: 1))
    }

    private func selectChip(_ key: String) -> some View { selectChipLabel(localization.string(key)) }
    private func selectChipLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.popLabel)
            Text(verbatim: "▾").font(.system(size: 10)).foregroundStyle(Color.popTertiaryLabel)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.popControlStroke, lineWidth: 1))
    }

    private func optionLabel(_ text: String, selected: Bool) -> some View {
        HStack {
            Text(text)
            if selected {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    private func quotaBudgetLabel(_ value: Int) -> String {
        let formatted = Self.decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return "\(formatted) tokens"
    }

    private func sourceMark(_ mark: String, _ bg: Color) -> some View {
        Text(mark).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
            .frame(width: 30, height: 30).background(bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func registryStatusIcon(ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ok ? Color.popStatusOK : Color.popTertiaryLabel)
            .frame(width: 22, height: 22)
    }

    private var connectedBadge: some View { badge(localization.string("settings.connected"), ok: true) }
    private func badge(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(ok ? Color(hex: 0x1A9A4E) : Color(hex: 0xC4BFB0)).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(ok ? Color(hex: 0x1A7A3E) : Color.popTertiaryLabel)
        }
        .padding(.leading, 7).padding(.trailing, 8).padding(.vertical, 2)
        .background(ok ? Color(hex: 0xF3F8F4) : Color.popMainBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(ok ? Color(hex: 0xCFE0D2) : Color(hex: 0xE2DFD3), lineWidth: 1))
    }

    private var ssotPath: String {
        let path = popskillUserHomeDirectoryURL()
            .appendingPathComponent(".cc-switch", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)
            .path
        return (path as NSString).abbreviatingWithTildeInPath
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    // MARK: Actions

    @MainActor private func runSync(_ action: SyncAction) async {
        await store.runSync(action, provider: syncProvider)
    }

    @MainActor private func setEnabled(_ repo: SkillRepository, enabled: Bool) async {
        guard !pendingMutation.contains(repo.id) else { return }
        pendingMutation.insert(repo.id); defer { pendingMutation.remove(repo.id) }
        do {
            let result = try await store.client.setRepositoryEnabled(enabled, owner: repo.owner, name: repo.name)
            if let idx = store.sources.firstIndex(where: { $0.owner == result.owner && $0.name == result.name }) { store.sources[idx].enabled = result.enabled }
        } catch { store.errorMessage = error.localizedDescription }
    }

    @MainActor private func remove(_ repo: SkillRepository) async {
        pendingRemoval = nil
        guard !pendingMutation.contains(repo.id) else { return }
        pendingMutation.insert(repo.id); defer { pendingMutation.remove(repo.id) }
        do {
            let result = try await store.client.removeRepository(owner: repo.owner, name: repo.name)
            store.sources.removeAll { $0.owner == result.owner && $0.name == result.name }
        } catch { store.errorMessage = error.localizedDescription }
    }

    @MainActor private func exportDiagnostics() {
        guard !exportingDiagnostics else { return }
        exportingDiagnostics = true
        defer { exportingDiagnostics = false }
        do {
            _ = try store.exportDiagnosticsReport()
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct CardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.popSeparator, lineWidth: 1))
    }
}

enum SettingsTab: String, CaseIterable {
    case connect, sync, sources, install, quota, about
    var titleKey: String {
        switch self {
        case .connect: return "settings.tab.connect"
        case .sync:    return "settings.tab.sync"
        case .sources: return "settings.tab.sources"
        case .install: return "settings.tab.install"
        case .quota:   return "settings.tab.quota"
        case .about:   return "settings.tab.about"
        }
    }
}

enum SyncProvider: String, CaseIterable, Identifiable, Codable {
    case icloud, git, webdav, none

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .icloud: return "settings.sync.icloud.title"
        case .git:    return "settings.sync.git.title"
        case .webdav: return "settings.sync.webdav.title"
        case .none:   return "settings.sync.none.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .icloud: return "settings.sync.icloud.subtitle"
        case .git:    return "settings.sync.git.subtitle"
        case .webdav: return "settings.sync.webdav.subtitle"
        case .none:   return "settings.sync.none.subtitle"
        }
    }

    var symbol: String {
        switch self {
        case .icloud: return "icloud"
        case .git:    return "chevron.left.forwardslash.chevron.right"
        case .webdav: return "externaldrive.connected.to.line.below"
        case .none:   return "nosign"
        }
    }

    var implemented: Bool { self == .git || self == .icloud }
    var actionable: Bool { implemented }
}

enum SyncAction: String {
    case push, pull, status
}
