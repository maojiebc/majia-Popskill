import SwiftUI

// CLI 巡检弹层（v2.14，吸收 cc-switch 的工具版本矩阵）。
// npm -g 装的全局 CLI（claude-code / lark-cli / getnote…）从此进 Popskill 的更新雷达：
// 每行 包名 | 已装 | 最新 | 升级。entries 里 npm 源对应的包走能力矩阵的更新链，不在这里。

struct CliSheet: View {
    @Environment(AppModel.self) private var model
    @State private var hoverRow: String?

    var body: some View {
        SheetShell(width: 560, onDismiss: { model.sheet = nil }) {
            VStack(spacing: 0) {
                head
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.globalClis.isEmpty {
                            Text(model.checkingClis ? L("正在扫描全局 npm 包…")
                                 : L("没有发现全局 npm 包（或未安装 Node.js/npm）"))
                                .font(.ui(11.5)).foregroundStyle(Ink.tertiary)
                                .padding(.vertical, 24)
                                .frame(maxWidth: .infinity)
                        } else {
                            tableHead
                            ForEach(model.globalClis) { cli in row(cli) }
                        }
                    }
                    .padding(EdgeInsets(top: 10, leading: 20, bottom: 14, trailing: 20))
                }
                .frame(maxHeight: 480)
                foot
            }
        }
    }

    private var head: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("CLI 巡检")).font(.ui(15.5, .bold)).foregroundStyle(Ink.ink)
                Text(L("npm 全局安装的命令行工具——已装版本对比 registry 最新版，一键升级。"))
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

    private var tableHead: some View {
        HStack(spacing: 10) {
            Text(L("包名")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("已装")).frame(width: 84, alignment: .trailing)
            Text(L("最新")).frame(width: 84, alignment: .trailing)
            Color.clear.frame(width: 74)
        }
        .font(.ui(9.5, .bold)).tracking(0.5)
        .foregroundStyle(Ink.tertiary)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Ink.hairline.frame(height: 1) }
    }

    private func row(_ cli: GlobalCli) -> some View {
        HStack(spacing: 10) {
            Text(cli.name)
                .font(.mono(11.5))
                .foregroundStyle(Ink.ink)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("v\(cli.installed)")
                .font(.mono(11)).foregroundStyle(Ink.secondary2).monospacedDigit()
                .frame(width: 84, alignment: .trailing)
            Text(cli.latest.map { "v\($0)" } ?? "—")
                .font(.mono(11)).monospacedDigit()
                .foregroundStyle(cli.hasUpdate ? Ink.amberText : Ink.tertiary)
                .frame(width: 84, alignment: .trailing)
                .help(cli.latest == nil ? L("registry 查询失败（网络）——点右下重新扫描") : "")
            Group {
                if model.upgradingClis.contains(cli.name) {
                    UpdatingDot()
                } else if cli.hasUpdate {
                    Button { model.upgradeCli(cli.name) } label: {
                        Text(L("升级"))
                            .font(.ui(10.5, .semibold)).foregroundStyle(Color(hex: 0x5A4A14))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Ink.amberBadgeBg))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.amberBadgeBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(L("npm i -g \(cli.name)@\(cli.latest ?? "")"))
                } else {
                    // 状态词与表头「最新」刻意分 key：英文一个是 Latest 一个是 Up to date
                    Text(cli.latest == nil ? "" : L("已最新"))
                        .font(.ui(10.5)).foregroundStyle(Ink.green)
                }
            }
            .frame(width: 74, alignment: .trailing)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(hoverRow == cli.name ? Ink.chrome : .clear))
        .onHover { hoverRow = $0 ? cli.name : (hoverRow == cli.name ? nil : hoverRow) }
        .overlay(alignment: .bottom) { Ink.tableHairline.frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(cli.name)，已装 \(cli.installed)") + (cli.hasUpdate ? L("，可升级到 \(cli.latest ?? "")") : ""))
    }

    private var foot: some View {
        HStack {
            Text(L("升级即在后台执行 npm i -g，与终端手动升级完全等价。"))
                .font(.ui(10.5)).foregroundStyle(Ink.tertiary)
            Spacer()
            Button { model.checkCliUpdates() } label: {
                Text(model.checkingClis ? L("扫描中…") : L("重新扫描"))
                    .font(.ui(11.5, .semibold)).foregroundStyle(Ink.secondary2)
                    .padding(.horizontal, 11).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ink.control2, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(model.checkingClis)
            if !model.cliUpdates.isEmpty {
                Button { model.upgradeAllClis() } label: {
                    Text(L("全部升级 (\(model.cliUpdates.count))"))
                        .font(.ui(11.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Ink.ink))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 20, bottom: 13, trailing: 20))
        .background(Ink.chrome)
        .overlay(alignment: .top) { Ink.hairline.frame(height: 1) }
    }
}
