import SwiftUI

/// 修复中心 — health / repair. Left: a problem list of broken-link rows; right:
/// the selected issue's source line, symlink-path diff, remediation options, and
/// a diagnostic log. When nothing is broken it shows an all-clear state.
///
/// Real data: `store.linkHealth.rows` give the broken symlinks (name / ssot path
/// / per-app status). The prototype's cause/remediation/log are derived here —
/// applying a fix marks it resolved locally (a real repair needs sidecar support).
@MainActor
struct FixView: View {
    @Bindable var store: PopskillStore
    @Environment(\.popskillLocalization) private var localization

    @State private var loading = false
    @State private var selectedID: String?
    @State private var resolved: Set<String> = []

    private var brokenRows: [LinkHealthRow] {
        (store.linkHealth?.rows ?? []).filter { row in
            (row.deployment?.appLinks ?? [:]).values.contains { $0.status.lowercased() == "broken" }
        }
    }
    private var pending: [LinkHealthRow] { brokenRows.filter { !resolved.contains($0.skillId) } }
    private var allClear: Bool { pending.isEmpty }
    private var selectedRow: LinkHealthRow? {
        brokenRows.first { $0.skillId == selectedID } ?? brokenRows.first
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
            if loading && store.linkHealth == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if brokenRows.isEmpty {
                allClearState
            } else {
                HStack(spacing: 0) {
                    problemList
                    detail
                }
                .frame(maxHeight: .infinity)
            }
        }
        .popPageBackground()
        .task { if store.linkHealth == nil { await reload() } }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    LocalizedText("sidebar.fix")
                        .font(.system(size: 25, weight: .bold)).tracking(-0.6)
                        .foregroundStyle(Color.popLabel)
                    countPill
                }
                LocalizedText("fix.subtitle")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(hex: 0x6F6B5E))
                    .frame(maxWidth: 560, alignment: .leading)
            }
            Spacer(minLength: 8)
            autofixButton
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(Color(hex: 0xFFFAF4))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popSeparator).frame(height: 1) }
    }

    private var countPill: some View {
        let ok = allClear
        return Text(ok ? localization.string("fix.allClear") : localization.string("fix.pendingCount", pending.count))
            .font(.system(size: 11, weight: .bold)).tracking(0.6).textCase(.uppercase)
            .foregroundStyle(ok ? Color(hex: 0x1A7A3E) : Color.popLinkBroken)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(ok ? Color(hex: 0xF3F8F4) : Color.white, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ok ? Color(hex: 0xCFE0D2) : Color(hex: 0xEBC4C4), lineWidth: 1))
    }

    private var autofixButton: some View {
        let disabled = allClear
        return Button {
            for row in pending { resolved.insert(row.skillId) }
        } label: {
            Text(disabled ? localization.string("fix.allFixed") : localization.string("fix.autofixAll", pending.count))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(disabled ? Color(hex: 0xB8B3A3) : .white)
                .padding(.horizontal, 14).frame(height: 30)
                .background(disabled ? Color(hex: 0xECE9E0) : Color(hex: 0x1F8A4C), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: All-clear

    private var allClearState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: 0x1F8A4C).opacity(0.12)).frame(width: 60, height: 60)
                Image(systemName: "checkmark").font(.system(size: 26, weight: .bold)).foregroundStyle(Color(hex: 0x1F8A4C))
            }
            LocalizedText("fix.empty.title").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.popLabel)
            Text(localization.string("fix.empty.body", store.okLinkCount))
                .font(.system(size: 12.5)).foregroundStyle(Color.popSecondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Problem list

    private var problemList: some View {
        VStack(spacing: 0) {
            LocalizedText("fix.problemList")
                .font(.system(size: 10, weight: .bold)).tracking(0.6).textCase(.uppercase)
                .foregroundStyle(Color.popTertiaryLabel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(brokenRows, id: \.skillId) { row in
                        listItem(row)
                    }
                }
            }
        }
        .frame(width: 308)
        .background(Color.popMainBackground)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.popSeparator).frame(width: 1) }
    }

    private func listItem(_ row: LinkHealthRow) -> some View {
        let isSel = (selectedRow?.skillId == row.skillId)
        let done = resolved.contains(row.skillId)
        return Button { selectedID = row.skillId } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(row.skillName).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.popLabel).lineLimit(1)
                    Spacer(minLength: 6)
                    if done {
                        Text(localization.string("fix.done")).font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0x1A7A3E))
                    } else {
                        Text(brokenSide(row)).font(.system(size: 9.5, weight: .bold)).tracking(0.4).textCase(.uppercase)
                            .foregroundStyle(Color.popSecondaryLabel)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(hex: 0xDDD9CD), lineWidth: 1))
                    }
                }
                HStack(spacing: 7) {
                    causeTag
                    Text(sourceLabel(row)).font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Color.popSecondaryLabel).lineLimit(1).truncationMode(.middle)
                }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSel ? (done ? Color(hex: 0xF2F8F3) : Color(hex: 0xFFF5F0)) : Color.clear)
            .overlay(alignment: .leading) {
                Rectangle().fill(isSel ? (done ? Color(hex: 0x1A7A3E) : Color.popLinkBroken) : Color.clear).frame(width: 3)
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Color.popRowDivider).frame(height: 1) }
            .opacity(done ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var causeTag: some View {
        Text(localization.string("fix.cause.broken"))
            .font(.system(size: 9.5, weight: .bold)).tracking(0.3)
            .foregroundStyle(Color.popLinkBroken)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color(hex: 0xEBC4C4), lineWidth: 1))
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let row = selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detailHeader(row)
                    if resolved.contains(row.skillId) {
                        successCard(row)
                    } else {
                        diffSection(row)
                        remediationSection(row)
                        logSection(row)
                    }
                    Color.clear.frame(height: 28)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear
        }
    }

    private func detailHeader(_ row: LinkHealthRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(row.skillName).font(.system(size: 18, weight: .bold)).tracking(-0.2).foregroundStyle(Color.popLabel)
                causeTag
            }
            HStack(spacing: 9) {
                Image(systemName: "shippingbox.fill").font(.system(size: 9)).foregroundStyle(Color.popTertiaryLabel)
                Text(sourceLabel(row)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.popLabel)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                Button { store.currentSelection = .settings } label: {
                    Text(localization.string("fix.manageSource")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.popAccent)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .background(Color.popMainBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.popSeparator, lineWidth: 1))
            .padding(.top, 12)
        }
        .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.popRowDivider).frame(height: 1) }
    }

    private func successCard(_ row: LinkHealthRow) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: 0x1F8A4C)).frame(width: 34, height: 34)
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string("fix.resolved", row.skillName)).font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: 0x15602F))
                Text(localization.string("fix.relinkCmd", row.skillName)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(hex: 0x3F7A55))
            }
            Spacer()
        }
        .padding(20)
        .background(Color(hex: 0xF2F9F4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0xCFE0D2), lineWidth: 1))
        .padding(.horizontal, 28).padding(.top, 22)
    }

    private func diffSection(_ row: LinkHealthRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("fix.symlinkPath")
            VStack(spacing: 0) {
                ForEach(Array(diffRows(row).enumerated()), id: \.offset) { _, d in
                    HStack(spacing: 8) {
                        Text(d.arrow).foregroundStyle(Color.popTertiaryLabel).frame(width: 12)
                        Text(d.path).foregroundStyle(Color.popLabel).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        Text(d.status).font(.system(size: 10.5, weight: .bold)).tracking(0.3).textCase(.uppercase)
                            .foregroundStyle(d.bad ? Color.popLinkBroken : (d.ok ? Color(hex: 0x1A7A3E) : Color.popAccent))
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(d.bad ? Color(hex: 0xFFF0ED) : Color.clear)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.popSeparator, lineWidth: 1))
        }
        .padding(.horizontal, 28).padding(.top, 16)
    }

    private func remediationSection(_ row: LinkHealthRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("fix.options")
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(remediations(row).enumerated()), id: \.offset) { _, r in
                    remCard(r, row: row)
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 22)
    }

    private func remCard(_ r: Remediation, row: LinkHealthRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(r.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.popLabel)
            }
            Text(r.desc).font(.system(size: 11.5)).foregroundStyle(Color(hex: 0x666666)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            Text(r.cmd).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Color(hex: 0x444444)).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.popSurface, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.popSeparator, lineWidth: 1))
            Button { resolved.insert(row.skillId) } label: {
                Text(localization.string("fix.apply"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(r.rec ? .white : Color.popLabel)
                    .padding(.horizontal, 11).padding(.vertical, 5)
                    .background(r.rec ? Color.popLabel : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(r.rec ? Color.popLabel : Color.popControlStroke, lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(r.rec ? Color(hex: 0xF2F9F4) : Color.white, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(r.rec ? Color(hex: 0x1F8A4C) : Color(hex: 0xE2DFD3), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            if r.rec {
                Text(localization.string("fix.recommended"))
                    .font(.system(size: 9.5, weight: .bold)).tracking(0.4).textCase(.uppercase).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(hex: 0x1F8A4C), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .offset(x: 12, y: -8)
            }
        }
    }

    private func logSection(_ row: LinkHealthRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("fix.log")
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(logLines(row).enumerated()), id: \.offset) { _, l in
                    HStack(spacing: 10) {
                        Text(l.time).foregroundStyle(Color(hex: 0x6B7280))
                        Text(l.text).foregroundStyle(l.bad ? Color(hex: 0xFF8A7A) : (l.ok ? Color(hex: 0x5FD29C) : Color(hex: 0xCBD0D6)))
                    }
                    .font(.system(size: 11.5, design: .monospaced))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x15161A), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 28).padding(.top, 22)
    }

    private func sectionLabel(_ key: String) -> some View {
        LocalizedText(key).font(.system(size: 10, weight: .bold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Color.popTertiaryLabel)
    }

    // MARK: Derivations

    private func skill(_ row: LinkHealthRow) -> Skill? { store.skills.first { $0.id == row.skillId } }

    private func sourceLabel(_ row: LinkHealthRow) -> String {
        if let s = skill(row), !s.sourceLabel.isEmpty { return s.sourceLabel }
        if let path = row.deployment?.ssotPath, !path.isEmpty { return (path as NSString).abbreviatingWithTildeInPath }
        return row.skillName
    }

    private func brokenApps(_ row: LinkHealthRow) -> [String] {
        (row.deployment?.appLinks ?? [:]).filter { $0.value.status.lowercased() == "broken" }
            .keys.sorted { ($0 == "claude" ? 0 : 1) < ($1 == "claude" ? 0 : 1) }
    }

    private func brokenSide(_ row: LinkHealthRow) -> String {
        brokenApps(row).map { $0 == "claude" ? "Claude" : ($0 == "codex" ? "Codex" : $0.capitalized) }.joined(separator: " / ")
    }

    private struct DiffLine { let arrow: String; let path: String; let status: String; var bad = false; var ok = false }
    private func diffRows(_ row: LinkHealthRow) -> [DiffLine] {
        var out: [DiffLine] = []
        for app in brokenApps(row) {
            out.append(DiffLine(arrow: "●", path: "~/.\(app)/skills/\(row.skillName)", status: "symlink"))
            out.append(DiffLine(arrow: "↳", path: "store/skills/\(row.skillName)/", status: localization.string("fix.diff.targetMissing"), bad: true))
        }
        if let path = row.deployment?.ssotPath, !path.isEmpty {
            out.append(DiffLine(arrow: "✓", path: (path as NSString).abbreviatingWithTildeInPath, status: localization.string("fix.diff.ssotExists"), ok: true))
        }
        return out
    }

    private struct Remediation { let rec: Bool; let title: String; let desc: String; let cmd: String }
    private func remediations(_ row: LinkHealthRow) -> [Remediation] {
        [
            Remediation(rec: true, title: localization.string("fix.rem.relink.title"), desc: localization.string("fix.rem.relink.desc"), cmd: "popskill relink \(row.skillName)"),
            Remediation(rec: false, title: localization.string("fix.rem.repull.title"), desc: localization.string("fix.rem.repull.desc"), cmd: "popskill repull \(row.skillName)"),
            Remediation(rec: false, title: localization.string("fix.rem.remove.title"), desc: localization.string("fix.rem.remove.desc"), cmd: "popskill unlink \(row.skillName)")
        ]
    }

    private struct LogLine { let time: String; let text: String; var bad = false; var ok = false }
    private func logLines(_ row: LinkHealthRow) -> [LogLine] {
        let app = brokenApps(row).first ?? "claude"
        return [
            LogLine(time: "·", text: "readlink ~/.\(app)/skills/\(row.skillName)"),
            LogLine(time: "·", text: "stat: ENOENT — store/skills/\(row.skillName)/", bad: true),
            LogLine(time: "·", text: localization.string("fix.log.ready"), ok: true)
        ]
    }

    @MainActor
    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do { store.linkHealth = try await store.client.linkHealth() }
        catch { store.errorMessage = error.localizedDescription }
    }
}
