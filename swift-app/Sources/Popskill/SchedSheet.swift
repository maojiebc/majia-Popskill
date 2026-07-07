import AppKit
import SwiftUI

// 定时任务弹层（v2.9 引入，v2.10 人性化重做）。
// 视角翻转：分组按行为（定时跑/常驻/自启）不按 launchd/cron；每行主信息是
// 「下次什么时候跑」倒计时（按它排序）和「上次结果」；reverse-DNS label 换成
// 人话名 + 可编辑备注。只读解析为主；写操作全部走 AppModel 的确认弹窗。

struct SchedSheet: View {
    @Environment(AppModel.self) private var model
    @State private var editingId: String?
    @State private var noteDraft = ""
    @State private var hoverId: String?
    @FocusState private var noteFocus: Bool

    private var visible: [SchedTask] {
        model.schedTasks.filter { model.schedShowVendor || !$0.vendor }
    }
    private var timed: [SchedTask] {
        visible.filter { $0.behavior == .timed }
            .sorted { ($0.nextFire ?? .distantFuture, $0.label) < ($1.nextFire ?? .distantFuture, $1.label) }
    }
    private var daemons: [SchedTask] { visible.filter { $0.behavior == .daemon } }
    private var loginItems: [SchedTask] { visible.filter { $0.behavior == .loginItem || $0.behavior == .manual } }
    private var vendorCount: Int { model.schedTasks.filter(\.vendor).count }

    var body: some View {
        SheetShell(width: 660, onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                head
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        todayStrip
                        if !timed.isEmpty { section(L("按时间跑（\(timed.count)）· 按下次运行排序"), timed) }
                        if !daemons.isEmpty { section(L("常驻后台（\(daemons.count)）"), daemons) }
                        if !loginItems.isEmpty { section(L("登录自启（\(loginItems.count)）"), loginItems) }
                        if visible.isEmpty {
                            Text(model.schedLoading ? L("扫描中…") : L("没有可显示的任务"))
                                .font(.ui(11.5)).foregroundStyle(Ink.tertiary).padding(.vertical, 10)
                        }
                        if !timed.filter({ $0.kind == .cron }).isEmpty {
                            Text(L("cron 条目在终端用 crontab -e 管理，这里只看不动。"))
                                .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                        }
                    }
                    .padding(EdgeInsets(top: 14, leading: 20, bottom: 16, trailing: 20))
                }
                .frame(maxHeight: 560)
                foot
            }
        }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("定时任务")).font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
                Text(L("谁在跑、下次什么时候跑、上次结果如何。点名字旁的 ✎ 加人话备注。"))
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

    /// 今天还会跑什么——打开面板第一眼的答案
    @ViewBuilder
    private var todayStrip: some View {
        let cal = Calendar.current
        let today = timed.filter { $0.nextFire.map { cal.isDateInToday($0) } ?? false }
        if !today.isEmpty {
            // 名单是数据（时刻 + 任务名），只有前缀句要本地化
            let list = today.prefix(3).map {
                "\(shortTime($0.nextFire!)) \($0.displayName)"
            }.joined(separator: " · ") + (today.count > 3 ? " …" : "")
            HStack(spacing: 6) {
                Text("◷").font(.ui(11)).foregroundStyle(Ink.amberText)
                Text(L("今天还会跑 \(today.count) 个：\(list)"))
                    .font(.ui(11)).foregroundStyle(Ink.amberText)
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Ink.amberBadgeBg.opacity(0.5)))
        }
    }

    private func shortTime(_ d: Date) -> String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: d), c.component(.minute, from: d))
    }

    private func section(_ title: String, _ tasks: [SchedTask]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: title)
            VStack(spacing: 6) {
                ForEach(tasks) { t in row(t) }
            }
        }
    }

    // ── 行 ───────────────────────────────────────────────

    private func row(_ t: SchedTask) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor(t)).frame(width: 7, height: 7)
                .help(dotHelp(t))
            VStack(alignment: .leading, spacing: 1) {
                if editingId == t.id {
                    TextField(L("人话备注，留空恢复默认"), text: $noteDraft)
                        .textFieldStyle(.plain)
                        .font(.ui(12, .semibold)).foregroundStyle(Ink.ink)
                        .focused($noteFocus)
                        .onSubmit { commitNote(t) }
                        .onExitCommand { editingId = nil }
                } else {
                    HStack(spacing: 5) {
                        Text(t.displayName)
                            .font(.ui(12, .semibold)).foregroundStyle(Ink.ink)
                            .lineLimit(1).truncationMode(.middle)
                        if t.kind == .cron {
                            Text("cron").font(.mono(9))
                                .foregroundStyle(Ink.tertiary)
                                .padding(.horizontal, 4)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Ink.control2, lineWidth: 1))
                        }
                        if t.kind == .launchd && !t.loaded {
                            Text(L("已停用")).font(.ui(9.5)).foregroundStyle(Ink.tertiary)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
                        }
                        if hoverId == t.id {
                            Button {
                                noteDraft = t.note ?? ""
                                editingId = t.id
                                noteFocus = true
                            } label: {
                                Text("✎").font(.ui(11)).foregroundStyle(Ink.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help(L("编辑人话备注（存在 Popskill，不动 plist）"))
                        }
                    }
                }
                Text(commandShort(t))
                    .font(.mono(10)).foregroundStyle(Ink.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 10)
            rightInfo(t)
            actions(t)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(t.stalled ? Ink.red.opacity(0.4) : Ink.hairline, lineWidth: 1))
        .opacity(t.kind == .launchd && !t.loaded ? 0.62 : 1)
        .onHover { hoverId = $0 ? t.id : (hoverId == t.id ? nil : hoverId) }
    }

    /// 右侧主信息：定时任务 = 下次倒计时；daemon = 活着/停摆；自启 = 状态
    @ViewBuilder
    private func rightInfo(_ t: SchedTask) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            switch t.behavior {
            case .timed:
                if let next = t.nextFire, t.loaded {
                    // TimelineView 让倒计时每 30s 重算（v2.16：曾冻结在面板打开那一刻，
                    // 「3 分钟后」挂一小时还是「3 分钟后」）；到点后的过期值靠右下「刷新」重扫
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(SchedEngine.humanNext(next))
                            .font(.ui(11.5, .semibold)).foregroundStyle(Ink.blue)
                    }
                } else {
                    Text(t.loaded ? t.schedule : L("不会再跑"))
                        .font(.ui(11.5, .medium)).foregroundStyle(Ink.secondary)
                }
                Text(subLine(t)).font(.ui(10)).foregroundStyle(Ink.tertiary)
            case .daemon:
                if t.stalled {
                    Text(L("已停摆")).font(.ui(11.5, .semibold)).foregroundStyle(Ink.red)
                    Text(L("上次退出码 \(t.lastExit ?? -1)")).font(.ui(10)).foregroundStyle(Ink.red.opacity(0.8))
                } else if t.pid != nil {
                    Text(L("运行中")).font(.ui(11.5, .semibold)).foregroundStyle(Ink.greenText)
                    Text(L("PID \(t.pid!)")).font(.mono(9.5)).foregroundStyle(Ink.tertiary)
                } else {
                    Text(L("已停用")).font(.ui(11.5, .medium)).foregroundStyle(Ink.tertiary)
                    Text(L("常驻 daemon")).font(.ui(10)).foregroundStyle(Ink.tertiary)
                }
            case .loginItem, .manual:
                Text(t.pid != nil ? L("运行中") : (t.loaded ? L("已就绪") : L("已停用")))
                    .font(.ui(11.5, .medium))
                    .foregroundStyle(t.pid != nil ? Ink.greenText : Ink.secondary)
                Text(t.behavior == .manual ? L("未配置调度") : L("登录自启")).font(.ui(10)).foregroundStyle(Ink.tertiary)
            }
        }
        .lineLimit(1)
        .layoutPriority(1)
    }

    /// 定时行副行："每天 05:00 · 上次 今天 05:00 ✓"
    private func subLine(_ t: SchedTask) -> String {
        var parts = [t.schedule]
        if let last = t.lastRun {
            let mark = (t.lastExit ?? 0) == 0 ? "✓" : L("✗ 码 \(t.lastExit!)")
            parts.append(L("上次 \(SchedEngine.humanLast(last)) \(mark)"))
        } else if let exit = t.lastExit, exit != 0 {
            parts.append(L("上次退出码 \(exit)"))
        }
        return parts.joined(separator: " · ")
    }

    private func commandShort(_ t: SchedTask) -> String {
        // 副行展示脚本本体的 basename，整行命令太长没人读。
        // 跳过解释器、flag、env 赋值和引号碎片（zsh -lc 'export HOME="…"; python3 x.py' 这种）；
        // 优先认有脚本扩展名的 token，找不到再退回第一个干净路径。
        let interpreters = ["/bin/bash", "/bin/zsh", "/bin/sh", "/usr/bin/env", "/usr/bin/python3"]
        let parts = t.command.split(separator: " ").map(String.init)
            .filter { $0.contains("/") && !$0.hasPrefix("-") && !$0.contains("=") && !$0.contains("\"") && !$0.contains("'") && !interpreters.contains($0) }
        let exts = ["sh", "py", "mjs", "js", "rb", "pl", "swift"]
        let script = parts.first { exts.contains(URL(fileURLWithPath: $0).pathExtension) } ?? parts.first
        if let script {
            let name = URL(fileURLWithPath: script).lastPathComponent
            if !name.isEmpty { return name }
        }
        return t.command
    }

    @ViewBuilder
    private func actions(_ t: SchedTask) -> some View {
        let busy = model.schedBusy.contains(t.id)
        HStack(spacing: 2) {
            if t.logPath != nil {
                HoverAction(symbol: "≡", danger: false, help: L("打开日志")) { model.schedOpenLog(t) }
            }
            if t.canOperate {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 22, height: 22)
                } else if t.stalled {
                    Button { model.schedKickstart(t) } label: {
                        Text(L("重启"))
                            .font(.ui(10.5, .semibold)).foregroundStyle(Ink.red)
                            .padding(.horizontal, 8).frame(height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.red.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else if t.loaded {
                    HoverAction(symbol: "▶", danger: false,
                                help: t.behavior == .daemon ? L("重启（launchctl kickstart -k）") : L("立刻跑一次（launchctl kickstart）")) { model.schedKickstart(t) }
                    HoverAction(symbol: "⏸", danger: true, help: L("停用（launchctl unload，不删文件）")) { model.schedSetLoaded(t, to: false) }
                } else {
                    HoverAction(symbol: "⏻", danger: false, help: L("启用（launchctl load）")) { model.schedSetLoaded(t, to: true) }
                }
            }
        }
    }

    private func commitNote(_ t: SchedTask) {
        model.schedSaveNote(t, note: noteDraft)
        editingId = nil
    }

    private func dotColor(_ t: SchedTask) -> Color {
        if t.stalled { return Ink.red }
        if t.kind == .launchd && !t.loaded { return Ink.offDot }
        return (t.lastExit ?? 0) == 0 ? Ink.green : Ink.red
    }

    private func dotHelp(_ t: SchedTask) -> String {
        if t.stalled { return L("常驻任务在册但没有进程——停摆了") }
        if t.kind == .cron { return L("crontab 在册即生效") }
        if !t.loaded { return L("未加载（已停用）") }
        return (t.lastExit ?? 0) == 0 ? L("已加载，上次运行正常") : L("已加载，上次运行失败（退出码 \(t.lastExit ?? -1)）")
    }

    // ── 底栏 ─────────────────────────────────────────────

    private var foot: some View {
        HStack(spacing: 10) {
            if vendorCount > 0 {
                HStack(spacing: 6) {
                    PsSwitch(on: model.schedShowVendor) { model.schedShowVendor.toggle() }
                    Text(L("显示系统/第三方任务（\(vendorCount)）"))
                        .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                }
            }
            Spacer()
            Button { model.reloadSched() } label: {
                Text(model.schedLoading ? L("扫描中…") : L("刷新"))
                    .font(.ui(11, .semibold)).foregroundStyle(Color(hex: 0x444444))
                    .padding(.horizontal, 10).frame(height: 24)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.schedLoading)
        }
        .padding(EdgeInsets(top: 9, leading: 20, bottom: 11, trailing: 20))
        .background(Ink.window)
        .overlay(alignment: .top) { Ink.hairline2.frame(height: 1) }
    }
}
