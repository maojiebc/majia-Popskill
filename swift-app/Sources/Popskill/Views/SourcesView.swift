import SwiftUI

/// 获取 / 更新中心 — install new capabilities and update installed ones whose
/// upstream moved. Layout follows the prototype: hero + URL-add · source tabs ·
/// 可更新 section · 浏览 section.
///
/// Real wiring: 可更新 = `store.updates` (pending upstream updates); 浏览 · GitHub
/// = `store.sources` (the repos you've added); the URL-add calls the real
/// `addRepository`. Live registry crawl (search brand-new items on
/// ClawHub/npm) has no sidecar backend yet — those tabs show a soon state.
@MainActor
struct SourcesView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var tab: SourceTab = .github
    @State private var query = ""
    @State private var addURL = ""
    @State private var adding = false
    @State private var updatedIDs: Set<String> = []
    @State private var pendingMutation: Set<String> = []
    @State private var pendingRemoval: SkillRepository?

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    private var updates: [SkillUpdateInfo] {
        store.updates.filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }
    private var pendingUpdates: [SkillUpdateInfo] { updates.filter { !updatedIDs.contains($0.id) } }

    private var githubSources: [SkillRepository] {
        store.sources.filter { q.isEmpty || $0.label.lowercased().contains(q) }
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
            await store.refreshUpdates(force: false)
        }
        .confirmationDialog(
            localization.string("sources.row.remove.confirm.title"),
            isPresented: removalDialogPresented,
            titleVisibility: .visible
        ) {
            if let pendingRemoval {
                Button(localization.string("sources.row.remove.confirm.button"), role: .destructive) {
                    Task { await remove(pendingRemoval) }
                }
            }
            Button(localization.string("sources.add.cancel"), role: .cancel) { pendingRemoval = nil }
        } message: {
            if let pendingRemoval {
                Text(localization.string("sources.row.remove.confirm.message", pendingRemoval.label))
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
        let count = t == .github ? store.sources.count : 0
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
                Button { for u in pendingUpdates { updatedIDs.insert(u.id) } } label: {
                    Text(pendingUpdates.isEmpty ? localization.string("sources.allLatest") : localization.string("sources.updateAll", pendingUpdates.count))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(pendingUpdates.isEmpty ? Color(hex: 0xB8B3A3) : .white)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(pendingUpdates.isEmpty ? Color(hex: 0xECE9E0) : Color(hex: 0x1F8A4C), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }.buttonStyle(.plain).disabled(pendingUpdates.isEmpty)
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
        let done = updatedIDs.contains(u.id)
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
            Group {
                if done {
                    Text("\(shortHash(u.remoteHash)) ✓").foregroundStyle(Color.popSecondaryLabel)
                } else {
                    HStack(spacing: 6) {
                        Text(shortHash(u.currentHash ?? "—")).foregroundStyle(Color.popTertiaryLabel)
                        Text(verbatim: "→").foregroundStyle(Color.popLinkOff)
                        Text(shortHash(u.remoteHash)).fontWeight(.bold).foregroundStyle(Color(hex: 0x1F8A4C))
                    }
                }
            }
            .font(.system(size: 11.5, design: .monospaced))
            Button { updatedIDs.insert(u.id) } label: {
                Text(done ? localization.string("sources.updated") : localization.string("sources.update"))
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(done ? Color(hex: 0x1A7A3E) : .white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(done ? Color(hex: 0xF3F8F4) : Color(hex: 0x1F8A4C), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(done ? Color(hex: 0xCFE0D2) : Color.clear, lineWidth: 1))
            }.buttonStyle(.plain).disabled(done)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .opacity(done ? 0.55 : 1)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    // MARK: Browse

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(localization.string("sources.browse", tab.title)).font(.system(size: 10.5, weight: .bold)).tracking(0.7).textCase(.uppercase).foregroundStyle(Color.popTertiaryLabel)
                Text("· \(tab == .github ? githubSources.count : 0)").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.popLinkOff)
                Spacer()
            }
            .padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 8)

            if tab == .github {
                if githubSources.isEmpty {
                    emptyCard("sources.empty.body")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(githubSources.enumerated()), id: \.element.id) { i, repo in
                            sourceRow(repo, last: i == githubSources.count - 1)
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

    private func sourceRow(_ repo: SkillRepository, last: Bool) -> some View {
        HStack(spacing: 12) {
            sourceMark(.github, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.label).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Color.popLabel).lineLimit(1).truncationMode(.middle)
                Text(localization.string("sources.row.branch", repo.branch)).font(.system(size: 11)).foregroundStyle(Color.popSecondaryLabel)
            }
            Spacer(minLength: 8)
            if pendingMutation.contains(repo.id) {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(get: { repo.enabled }, set: { v in Task { await setEnabled(repo, enabled: v) } }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Menu {
                if let url = URL(string: "https://github.com/\(repo.owner)/\(repo.name)") {
                    Link(destination: url) { Label(localization.string("sources.row.openGithub"), systemImage: "arrow.up.right.square") }
                }
                Button(role: .destructive) { pendingRemoval = repo } label: { Label(localization.string("sources.row.remove"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popSecondaryLabel).frame(width: 26)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Color.popRowDivider).frame(height: 1) } }
    }

    // MARK: Bits

    private func sourceMark(_ t: SourceTab, size: CGFloat) -> some View {
        Text(t.mark).font(.system(size: size > 24 ? 10 : 8, weight: .heavy, design: .monospaced)).foregroundStyle(.white)
            .frame(width: size, height: size).background(t.markColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func emptyCard(_ key: String) -> some View {
        LocalizedText(key).font(.system(size: 12.5)).foregroundStyle(Color.popTertiaryLabel).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 36)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(Color.popControlStroke))
            .padding(.horizontal, 28)
    }

    private func kind(forName name: String) -> CapabilityKind? {
        store.capabilities.first { $0.name == name }?.kind
    }
    private func shortHash(_ h: String) -> String {
        h.count > 7 ? String(h.prefix(7)) : h
    }

    private var removalDialogPresented: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
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
            addURL = ""
        } catch { store.errorMessage = error.localizedDescription }
    }

    @MainActor private func setEnabled(_ repo: SkillRepository, enabled: Bool) async {
        guard !pendingMutation.contains(repo.id) else { return }
        pendingMutation.insert(repo.id)
        defer { pendingMutation.remove(repo.id) }
        do {
            let result = try await store.client.setRepositoryEnabled(enabled, owner: repo.owner, name: repo.name)
            if let idx = store.sources.firstIndex(where: { $0.owner == result.owner && $0.name == result.name }) {
                store.sources[idx].enabled = result.enabled
            }
        } catch { store.errorMessage = error.localizedDescription }
    }

    @MainActor private func remove(_ repo: SkillRepository) async {
        guard !pendingMutation.contains(repo.id) else { return }
        pendingRemoval = nil
        pendingMutation.insert(repo.id)
        defer { pendingMutation.remove(repo.id) }
        do {
            let result = try await store.client.removeRepository(owner: repo.owner, name: repo.name)
            store.sources.removeAll { $0.owner == result.owner && $0.name == result.name }
        } catch { store.errorMessage = error.localizedDescription }
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
