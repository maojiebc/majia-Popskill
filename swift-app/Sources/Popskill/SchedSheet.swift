import AppKit
import SwiftUI

// 定时任务弹层（v2.9）—— launchd 用户级任务 + crontab 的可视化。
// 只读解析为主；写操作（跑一次 / 停用 / 启用）全部走 AppModel 的确认弹窗。

struct SchedSheet: View {
    @Environment(AppModel.self) private var model

    private var launchdTasks: [SchedTask] {
        model.schedTasks.filter { $0.kind == .launchd && (model.schedShowVendor || !$0.vendor) }
    }
    private var cronTasks: [SchedTask] { model.schedTasks.filter { $0.kind == .cron } }
    private var vendorCount: Int { model.schedTasks.filter { $0.kind == .launchd && $0.vendor }.count }

    var body: some View {
        SheetShell(width: 660, onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                head
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        launchdSection
                        cronSection
                    }
                    .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
                }
                .frame(maxHeight: 560)
                foot
            }
        }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("定时任务").font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
                Text("launchd 用户级任务与 crontab — 谁在跑、什么时候跑、上次结果如何。")
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

    // ── launchd ──────────────────────────────────────────

    private var launchdSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "LAUNCHD · ~/Library/LaunchAgents（\(launchdTasks.count)）")
            if launchdTasks.isEmpty {
                Text(model.schedLoading ? "扫描中…" : "没有用户级 launchd 任务")
                    .font(.ui(11.5)).foregroundStyle(Ink.tertiary).padding(.vertical, 10)
            }
            VStack(spacing: 6) {
                ForEach(launchdTasks) { t in row(t) }
            }
        }
    }

    private var cronSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "CRONTAB（\(cronTasks.count)）")
            if cronTasks.isEmpty {
                Text(model.schedLoading ? "扫描中…" : "crontab 为空")
                    .font(.ui(11.5)).foregroundStyle(Ink.tertiary).padding(.vertical, 10)
            }
            VStack(spacing: 6) {
                ForEach(cronTasks) { t in row(t) }
            }
            if !cronTasks.isEmpty {
                Text("cron 条目在终端用 crontab -e 管理，这里只看不动。")
                    .font(.ui(10.5)).foregroundStyle(Ink.tertiary).padding(.top, 8)
            }
        }
    }

    // ── 行 ───────────────────────────────────────────────

    private func row(_ t: SchedTask) -> some View {
        SheetRow {
            Circle().fill(dotColor(t)).frame(width: 7, height: 7)
                .help(dotHelp(t))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(t.label)
                        .font(.ui(12, .semibold)).foregroundStyle(Ink.ink)
                        .lineLimit(1).truncationMode(.middle)
                    if let exit = t.lastExit, exit != 0 {
                        Text("上次退出 \(exit)")
                            .font(.mono(9.5)).foregroundStyle(Ink.red)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.red.opacity(0.45), lineWidth: 1))
                    }
                    if t.kind == .launchd && !t.loaded {
                        Text("已停用").font(.ui(9.5)).foregroundStyle(Ink.tertiary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.control2, lineWidth: 1))
                    }
                }
                Text(t.command)
                    .font(.mono(10.5)).foregroundStyle(Ink.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 10)
            Text(t.schedule)
                .font(.ui(11, .medium)).foregroundStyle(Ink.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            actions(t)
        }
        .opacity(t.kind == .launchd && !t.loaded ? 0.62 : 1)
    }

    @ViewBuilder
    private func actions(_ t: SchedTask) -> some View {
        let busy = model.schedBusy.contains(t.id)
        HStack(spacing: 2) {
            if t.logPath != nil {
                HoverAction(symbol: "≡", danger: false, help: "打开日志") { model.schedOpenLog(t) }
            }
            if t.canOperate {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 22, height: 22)
                } else {
                    if t.loaded {
                        HoverAction(symbol: "▶", danger: false, help: "立刻跑一次（launchctl kickstart）") { model.schedKickstart(t) }
                        HoverAction(symbol: "⏸", danger: true, help: "停用（launchctl unload，不删文件）") { model.schedSetLoaded(t, to: false) }
                    } else {
                        HoverAction(symbol: "⏻", danger: false, help: "启用（launchctl load）") { model.schedSetLoaded(t, to: true) }
                    }
                }
            }
        }
    }

    private func dotColor(_ t: SchedTask) -> Color {
        if t.kind == .cron { return Ink.green }
        if !t.loaded { return Ink.offDot }
        return (t.lastExit ?? 0) == 0 ? Ink.green : Ink.red
    }

    private func dotHelp(_ t: SchedTask) -> String {
        if t.kind == .cron { return "crontab 在册即生效" }
        if !t.loaded { return "未加载（已停用）" }
        return (t.lastExit ?? 0) == 0 ? "已加载，上次运行正常" : "已加载，上次运行失败（退出码 \(t.lastExit ?? -1)）"
    }

    // ── 底栏 ─────────────────────────────────────────────

    private var foot: some View {
        HStack(spacing: 10) {
            if vendorCount > 0 {
                HStack(spacing: 6) {
                    PsSwitch(on: model.schedShowVendor) { model.schedShowVendor.toggle() }
                    Text("显示系统/第三方任务（\(vendorCount)）")
                        .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
                }
            }
            Spacer()
            Button { model.reloadSched() } label: {
                Text(model.schedLoading ? "扫描中…" : "刷新")
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
