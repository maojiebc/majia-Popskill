import SwiftUI

/// 获取 / 更新中心 — install new capabilities and update installed ones whose
/// upstream moved. Layout follows the prototype: hero + URL-add · source tabs ·
/// 可更新 section · 浏览 section.
///
/// Real wiring: 可更新 = `store.updates`; 浏览 · GitHub = `store.catalogSkills`
/// returned by sidecar `discover`; install buttons call the real sidecar
/// installer using Settings' default targets. ClawHub/npm/local still show a
/// soon state because sidecar has no registry adapter for them yet.
@MainActor
struct SourcesView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var tab: SourceTab = .github
    @State private var query = ""
    @State private var addURL = ""
    @State private var adding = false
    @State private var pendingMutation: Set<String> = []
    @State private var installPlanSheet: CatalogInstallPlanSheetState?

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var updates: [SkillUpdateInfo] {
        store.updates.filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }
    private var pendingUpdates: [SkillUpdateInfo] { updates }

    private var catalogItems: [CatalogSkill] {
        store.catalogSkills.filter { catalogMatches($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            tabsBand
            ScrollView {
                VStack(spacing: 0) {
                    updatesSection
                    browseSection
                    Color.clear.frame(height: 28)
                }
            }
            .background(Color.popMainBackground)
        }
        .popPageBackground()
        .task {
            await store.refreshSources(force: false)
            await store.refreshCatalog(force: false)
            await store.refreshUpdates(force: false)
        }
        .sheet(item: $installPlanSheet) { sheet in
            CatalogInstallPlanSheetView(state: sheet) { apps in
                await store.installCatalogSkill(sheet.catalog, targetApps: apps)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                LocalizedText("sources.title").font(.system(size: 25, weight: .bold)).tracking(-0.6).foregroundStyle(Color.popLabel)
                LocalizedText("sources.subtitle2").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x6F6B5E)).frame(maxWidth: 560, alignment: .leading)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Text(verbatim: "↗").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color.popTertiaryLabel)
                    TextField(localization.string("sources.urlPlaceholder"), text: $addURL)
                        .textFieldStyle(.plain).font(.system(size: 11.5, design: .monospaced))
                        .onSubmit { Task { await addSource() } }
                }
                .padding(.horizontal, 10).frame(width: 250, height: 30)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.popControlStroke, lineWidth: 1))
                Button { Task { await addSource() } } label: {
                    Group {
                        if adding { ProgressView().controlSize(.small) }
                        else { LocalizedText("matrix.add").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white) }
                    }
                    .padding(.horizontal, 13).frame(height: 30)
                    .background(Color.popLabel, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain).disabled(adding || AddSourceInput.parse(addURL) == nil)
            }
        }
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    // MARK: Tabs

    private var tabsBand: some View {
        HStack(spacing: 8) {
            ForEach(SourceTab.allCases, id: \.self) { t in
                tabButton(t)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.popTertiaryLabel)
                TextField(localization.string("sources.searchInSource"), text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 10).frame(width: 200, height: 30)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.popControlStroke, lineWidth: 1))
            Button { store.currentSelection = .settings } label: {
                Text(localization.string("sources.manage")).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: 0x5E5A4E))
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.popControlStroke, lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .background(Color.popMainBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    private func tabButton(_ t: SourceTab) -> some View {
        let active = tab == t
        let count = t == .github ? store.catalogSkills.count : 0
        return Button { tab = t } label: {
            HStack(spacing: 7) {
                Text(t.mark).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(t.markColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(t.title).font(.system(size: 12.5, weight: active ? .semibold : .medium)).foregroundStyle(active ? Color.popLabel : Color(hex: 0x5E5A4E))
                Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(active ? Color.popTertiaryLabel : Color(hex: 0xB8B3A3))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(active ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(active ? Color.popControlStroke : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LocalizedText("sources.updatable").font(.system(size: 10.5, weight: .bold)).tracking(0.7).textCase(.uppercase).foregroundStyle(Color.popTertiaryLabel)
                Text("· \(pendingUpdates.count) / \(updates.count)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.popLinkOff)
                Spacer()
                Button { Task { await updateAll() } } label: {
                    Text(pendingUpdates.isEmpty ? localization.string("sources.allLatest") : localization.string("sources.updateAll", pendingUpdates.count))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(pendingUpdates.isEmpty ? Color(hex: 0xB8B3A3) : .white)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(pendingUpdates.isEmpty ? Color(hex: 0xECE9E0) : Color(hex: 0x1F8A4C), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }.buttonStyle(.plain).disabled(pendingUpdates.isEmpty || hasPendingUpdates)
            }
            .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 8)

            if updates.isEmpty {
                emptyCard("sources.noUpdates")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(updates.enumerated()), id: \.element.id) { i, u in
                        updateRow(u, last: i == updates.count - 1)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
                .padding(.horizontal, 28)
            }
        }
    }

    private func updateRow(_ u: SkillUpdateInfo, last: Bool) -> some View {
        let pending = pendingMutation.contains(updateMutationKey(u.id))
        return HStack(spacing: 12) {
            sourceMark(.github, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(u.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popLabel)
                    if let kind = kind(forName: u.name) { LedgerTypeTag(kind: kind) }
                }
                Text(localization.string("sources.updateDesc")).font(.system(size: 11)).foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text(shortHash(u.currentHash ?? "—")).foregroundStyle(Color.popTertiaryLabel)
                Text(verbatim: "→").foregroundStyle(Color.popLinkOff)
                Text(shortHash(u.remoteHash)).fontWeight(.bold).foregroundStyle(Color(hex: 0x1F8A4C))
            }
            .font(.system(size: 11.5, design: .monospaced))
            Button { Task { await update(u) } } label: {
                Group {
                    if pending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(localization.string("sources.update"))
                    }
                }
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color(hex: 0x1F8A4C), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }.buttonStyle(.plain).disabled(pending)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .opacity(pending ? 0.75 : 1)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    // MARK: Browse

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(localization.string("sources.browse", tab.title)).font(.system(size: 10.5, weight: .bold)).tracking(0.7).textCase(.uppercase).foregroundStyle(Color.popTertiaryLabel)
                Text("· \(tab == .github ? catalogItems.count : 0)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.popLinkOff)
                Spacer()
            }
            .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 8)

            if tab == .github {
                if store.catalogRefreshInFlight {
                    loadingCard("sources.catalog.loading")
                } else if let error = store.catalogError {
                    emptyCardText(localization.string("sources.catalog.error", error))
                } else if catalogItems.isEmpty {
                    if store.catalogSkills.isEmpty {
                        emptyCard("discover.empty.noSkills")
                    } else {
                        emptyCardText(localization.string("discover.empty.noMatch", query))
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(catalogItems.enumerated()), id: \.element.id) { i, catalog in
                            catalogRow(catalog, last: i == catalogItems.count - 1)
                        }
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
                    .padding(.horizontal, 28)
                }
            } else {
                emptyCard("sources.registrySoon")
            }
        }
    }

    private func catalogRow(_ catalog: CatalogSkill, last: Bool) -> some View {
        let installed = isCatalogInstalled(catalog)
        let planning = pendingMutation.contains(planMutationKey(catalog.key))
        let pending = store.catalogInstallInFlight.contains(catalog.key) || planning
        let canInstall = !installed && !pending && !store.defaultInstallTargets.isEmpty
        return HStack(spacing: 12) {
            sourceMark(.github, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(catalog.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popLabel).lineLimit(1)
                    LedgerTypeTag(kind: .skill)
                }
                Text("\(catalog.description) · \(catalog.sourceLabel)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Text(catalog.directory)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.popTertiaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120, alignment: .trailing)
            if let url = catalog.sourceURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.popSecondaryLabel)
                        .frame(width: 22)
                }
                .buttonStyle(.plain)
            }
            Button { Task { await prepareInstall(catalog) } } label: {
                Group {
                    if pending {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(installed ? localization.string("sources.installed") : localization.string("sources.install"))
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(installed ? Color(hex: 0x1A7A3E) : .white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(installed ? Color(hex: 0xF3F8F4) : Color.popLabel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(installed ? Color(hex: 0xCFE0D2) : Color.popLabel, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!canInstall)
            .opacity(store.defaultInstallTargets.isEmpty && !installed ? 0.45 : 1)
            .help(store.defaultInstallTargets.isEmpty ? localization.string("sources.install.noTargets") : "")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .opacity(pending ? 0.75 : 1)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    // MARK: Bits

    private func sourceMark(_ t: SourceTab, size: CGFloat) -> some View {
        Text(t.mark).font(.system(size: size > 24 ? 10 : 8, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
            .frame(width: size, height: size).background(t.markColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func emptyCard(_ key: String) -> some View {
        emptyCardText(localization.string(key))
    }

    private func emptyCardText(_ text: String) -> some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(Color.popTertiaryLabel).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 36)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.popControlStroke))
            .padding(.horizontal, 28)
    }

    private func loadingCard(_ key: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            LocalizedText(key).font(.system(size: 12.5)).foregroundStyle(Color.popSecondaryLabel)
            Spacer()
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 24)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
        .padding(.horizontal, 28)
    }

    private func kind(forName name: String) -> CapabilityKind? {
        store.capabilities.first { $0.name == name }?.kind
    }
    private func shortHash(_ h: String) -> String {
        h.count > 7 ? String(h.prefix(7)) : h
    }
    private func updateMutationKey(_ id: String) -> String { "update:\(id)" }
    private func planMutationKey(_ id: String) -> String { "plan:\(id)" }
    private var hasPendingUpdates: Bool { pendingMutation.contains { $0.hasPrefix("update:") } }

    private func catalogMatches(_ catalog: CatalogSkill) -> Bool {
        q.isEmpty
            || catalog.name.lowercased().contains(q)
            || catalog.description.lowercased().contains(q)
            || catalog.directory.lowercased().contains(q)
            || catalog.sourceLabel.lowercased().contains(q)
    }

    private func isCatalogInstalled(_ catalog: CatalogSkill) -> Bool {
        catalog.installed || store.skills.contains { skill in
            skill.directory.caseInsensitiveCompare(catalog.directory) == .orderedSame
                || skill.id.caseInsensitiveCompare(catalog.key) == .orderedSame
        }
    }

    // MARK: Actions

    @MainActor private func addSource() async {
        guard let parsed = AddSourceInput.parse(addURL), !adding else { return }
        adding = true
        defer { adding = false }
        do {
            let repo = try await store.client.addRepository(owner: parsed.owner, name: parsed.name, branch: parsed.branch, enabled: true)
            if let idx = store.sources.firstIndex(where: { $0.id == repo.id }) { store.sources[idx] = repo }
            else { store.sources.append(repo) }
            await store.refreshCatalog(force: true)
            addURL = ""
        } catch { store.errorMessage = error.localizedDescription }
    }

    @MainActor private func update(_ update: SkillUpdateInfo) async {
        let key = updateMutationKey(update.id)
        guard !pendingMutation.contains(key) else { return }
        pendingMutation.insert(key)
        defer { pendingMutation.remove(key) }
        _ = await store.updateInstalledSkill(update)
    }

    @MainActor private func updateAll() async {
        for update in pendingUpdates where !pendingMutation.contains(updateMutationKey(update.id)) {
            await self.update(update)
        }
    }

    @MainActor private func prepareInstall(_ catalog: CatalogSkill) async {
        let apps = store.defaultInstallTargets
        guard !apps.isEmpty else {
            store.errorMessage = CatalogInstallError.noDefaultTarget.localizedDescription
            return
        }

        let key = planMutationKey(catalog.key)
        guard !pendingMutation.contains(key) else { return }
        pendingMutation.insert(key)
        defer { pendingMutation.remove(key) }

        do {
            let plans = try await store.catalogInstallPlans(catalog, targetApps: apps)
            let targetPlans = zip(apps, plans).map { app, plan in
                CatalogInstallTargetPlan(app: app, plan: plan)
            }
            installPlanSheet = CatalogInstallPlanSheetState(catalog: catalog, targetPlans: targetPlans)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

}

struct CatalogInstallPlanSheetState: Identifiable, Equatable {
    var id: String { catalog.key }

    let catalog: CatalogSkill
    let targetPlans: [CatalogInstallTargetPlan]
}

struct CatalogInstallTargetPlan: Identifiable, Equatable {
    var id: String { app.rawValue }

    let app: TargetApp
    let plan: InstallPlan
}

private struct CatalogInstallPlanSheetView: View {
    let state: CatalogInstallPlanSheetState
    let onConfirm: ([TargetApp]) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.popskillLocalization) private var localization
    @State private var selectedTargets: Set<TargetApp>
    @State private var installing = false

    init(
        state: CatalogInstallPlanSheetState,
        onConfirm: @escaping ([TargetApp]) async -> Bool
    ) {
        self.state = state
        self.onConfirm = onConfirm
        _selectedTargets = State(initialValue: Set(state.targetPlans.map(\.app)))
    }

    private var selectedPlans: [CatalogInstallTargetPlan] {
        state.targetPlans.filter { selectedTargets.contains($0.app) }
    }

    private var uniqueSteps: [String] {
        var seen = Set<String>()
        return state.targetPlans.flatMap(\.plan.steps).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    HStack(alignment: .top, spacing: 18) {
                        planColumn
                        previewColumn
                    }
                }
                .padding(22)
            }
            footer
        }
        .frame(width: 900)
        .frame(minHeight: 560)
        .background(Color.popMainBackground)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(localization.string("sources.installPlan.crumb"))
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
            Text(localization.string("sources.installPlan.title"))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color.popLabel)
            Spacer()
            Text("esc")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.popTertiaryLabel)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .frame(width: 22, height: 22)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.popControlStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(hex: 0xF4F2EC))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            PackageAvatar(name: state.catalog.name, identifier: state.catalog.key, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                Text(state.catalog.name)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.popLabel)
                Text(state.catalog.sourceLabel)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Color.popSecondaryLabel)
                Text(state.catalog.description)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.popSecondaryLabel)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                sheetMetric("sources.installPlan.targets", "\(selectedPlans.count)/\(state.targetPlans.count)")
                sheetMetric("sources.installPlan.branch", state.catalog.repoBranch ?? "main")
            }
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
    }

    private var planColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetSection("sources.installPlan.targets") {
                VStack(spacing: 0) {
                    ForEach(Array(state.targetPlans.enumerated()), id: \.element.id) { index, targetPlan in
                        targetPlanRow(targetPlan, last: index == state.targetPlans.count - 1)
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.popSeparator, lineWidth: 1))
            }

            sheetSection("sources.installPlan.writes") {
                VStack(spacing: 10) {
                    pathRow(titleKey: "sources.installPlan.store", value: state.targetPlans.first?.plan.writes.ssotPath ?? "—")
                    ForEach(selectedPlans) { targetPlan in
                        pathRow(
                            title: targetPlan.app.title,
                            value: targetPlan.plan.writes.appSkillPath ?? localization.string("sources.installPlan.noAppPath")
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            sheetSection("sources.installPlan.steps") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(uniqueSteps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.popLabel, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Text(step)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Color.popSecondaryLabel)
                        }
                    }
                }
            }

            sheetSection("sources.installPlan.preview") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(selectedPlans) { targetPlan in
                        commandBlock(targetPlan)
                    }
                    if selectedPlans.isEmpty {
                        Text(localization.string("sources.installPlan.noSelection"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.popTertiaryLabel)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x15161A), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            if let existing = state.targetPlans.compactMap(\.plan.existingSkillId).first {
                Label(localization.string("sources.installPlan.existing", existing), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.popStatusWarning)
            }
        }
        .frame(width: 360, alignment: .topLeading)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text(localization.string("sources.installPlan.summary", selectedPlans.count, state.catalog.directory))
                .font(.system(size: 12))
                .foregroundStyle(Color.popSecondaryLabel)
            Spacer()
            Button(localization.string("sources.installPlan.cancel")) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.popLabel)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.popControlStroke, lineWidth: 1))
            Button { Task { await confirm() } } label: {
                Group {
                    if installing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(localization.string("sources.installPlan.confirm", selectedPlans.count))
                    }
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Color.popLabel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(installing || selectedPlans.isEmpty)
            .opacity(selectedPlans.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(hex: 0xF4F2EC))
        .overlay(alignment: .top) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    private func confirm() async {
        guard !selectedPlans.isEmpty, !installing else { return }
        installing = true
        let ok = await onConfirm(selectedPlans.map(\.app))
        installing = false
        if ok {
            dismiss()
        }
    }

    private func targetPlanRow(_ targetPlan: CatalogInstallTargetPlan, last: Bool) -> some View {
        let selected = selectedTargets.contains(targetPlan.app)
        return Button {
            if selected {
                selectedTargets.remove(targetPlan.app)
            } else {
                selectedTargets.insert(targetPlan.app)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? targetPlan.app.sourcesAccentColor : Color.popTertiaryLabel)
                Image(systemName: targetPlan.app.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(targetPlan.app.sourcesAccentColor)
                    .frame(width: 22, height: 22)
                    .background(targetPlan.app.sourcesAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(targetPlan.app.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.popLabel)
                    Text(targetPlan.plan.writes.appSkillPath ?? localization.string("sources.installPlan.noAppPath"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.popTertiaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) }
        }
    }

    private func pathRow(titleKey: String, value: String) -> some View {
        pathRow(title: localization.string(titleKey), value: value)
    }

    private func pathRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.popSecondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.popSeparator, lineWidth: 1))
    }

    private func commandBlock(_ targetPlan: CatalogInstallTargetPlan) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("$ skill-cli install \(state.catalog.key) --app \(targetPlan.app.rawValue) --json")
                .foregroundStyle(Color(hex: 0xE6E9EC))
            Text("# store \(targetPlan.plan.writes.ssotPath)")
                .foregroundStyle(Color(hex: 0x6B7280))
            if let appPath = targetPlan.plan.writes.appSkillPath {
                Text("# link  \(appPath)")
                    .foregroundStyle(Color(hex: 0x7FAACD))
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }

    private func sheetSection<Content: View>(_ titleKey: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string(titleKey))
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
            content()
        }
    }

    private func sheetMetric(_ titleKey: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(localization.string(titleKey))
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.popLabel)
        }
    }
}

enum SourceTab: String, CaseIterable {
    case github, clawhub, npm, local

    var title: String {
        switch self {
        case .github: return "GitHub"
        case .clawhub: return "ClawHub"
        case .npm: return "npm"
        case .local: return "本地"
        }
    }
    var mark: String {
        switch self {
        case .github: return "GH"
        case .clawhub: return "Cw"
        case .npm: return "npm"
        case .local: return "~/"
        }
    }
    var markColor: Color {
        switch self {
        case .github: return Color(hex: 0x111111)
        case .clawhub: return Color(hex: 0x1F7A6E)
        case .npm: return Color(hex: 0xCB3837)
        case .local: return Color(hex: 0x8A8676)
        }
    }
}

private extension TargetApp {
    var sourcesAccentColor: Color {
        switch self {
        case .claude: .orange
        case .codex: .green
        case .gemini: .blue
        case .opencode: .mint
        case .hermes: .purple
        }
    }
}

/// Inline `owner/name@branch` parser.
struct AddSourceInput: Equatable {
    let owner: String
    let name: String
    let branch: String

    static func parse(_ raw: String) -> AddSourceInput? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let stripped = trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")

        let (path, branch): (String, String) = {
            if let atIndex = stripped.firstIndex(of: "@") {
                let p = String(stripped[..<atIndex])
                let b = String(stripped[stripped.index(after: atIndex)...])
                return (p, b.isEmpty ? "main" : b)
            }
            return (stripped, "main")
        }()

        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }

        return AddSourceInput(owner: String(parts[0]), name: String(parts[1]), branch: branch)
    }
}
