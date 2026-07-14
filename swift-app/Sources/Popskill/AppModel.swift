import AppKit
import Observation
import SwiftUI
import os

/// 关键写路径留痕（Console.app 按 subsystem 过滤可见）——
/// toast 2.6 秒即逝，出问题后这是唯一能回看的证据链。
let plog = Logger(subsystem: "com.majia.popskill", category: "store")

// 打包后以 Info.plist 为准（发版脚本写入），裸二进制显示 dev（常量版本号必腐，不再写死）
let popskillVersion: String =
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"

/// 修复弹层的目标：哪个能力 × 哪个工具 × 锚点在哪
struct FixTarget: Equatable {
    let issueKind: LinkStatus        // .broken / .stub
    let cap: Capability
    let entry: Entry
    let tool: Tool
    let anchor: CGPoint              // 窗口坐标系（左上原点）：单元格底边中心
    let flip: Bool                   // 下半屏向上翻
}

/// 详情 peek 的目标（PATCH-01）
struct PeekTarget: Equatable {
    let cap: Capability
    let entry: Entry
    let anchor: CGPoint
    let flip: Bool
}

struct FixOption: Identifiable {
    enum Kind { case relink, repull, adopt, unlink, trashCopy, keep, update }
    let id = UUID()
    let kind: Kind
    let label: String
    let desc: String
    let rec: Bool
    let toast: String
}

enum SheetKind { case add, settings, sched, cli }

/// 环境探测警告（v2.17）：git / npm 不在 PATH 时横幅提示，避免「无法识别仓库」黑洞
struct EnvWarning: Identifiable, Equatable {
    let id: String
    let message: String
}

/// 键盘导航焦点项（PATCH-02）：与可见顺序一致的扁平序列
struct KbItem: Equatable, Identifiable {
    let id: String          // 行 id（套装=entry.id，能力=cap.id）
    let isBundle: Bool
    let entryId: String
    let capId: String?      // 套装行为 nil
}

@MainActor
@Observable
final class AppModel {
    var fs: StoreFS
    var fake = false

    var tools: [Tool] = []
    var entries: [Entry] = []
    var syncInfo = SyncInfo()

    // UI 态
    var sheet: SheetKind?
    var toast: String?
    var toastIsError = false
    var flashId: String?
    var query = ""
    var typeFilter: CapType?         // nil = 全部
    var viewMode: ViewMode = .grid   // 卡片矩阵 / 账本表格（v2.13）
    var expanded: Set<String> = []
    var fixTarget: FixTarget?
    var peekTarget: PeekTarget?
    var searchFocused = false
    var checkingUpdates = false
    var updatingIds: Set<String> = []
    var installing = false           // 添加弹层安装忙态（v2.16：曾在主线程同步 copy，大仓直接卡死 UI）
    var installError: String?        // 添加弹层驻留错误（v2.16：曾只有 6 秒 toast，消失后计划页零线索）

    // 全局 CLI 巡检（v2.14）：npm -g 装的 AI CLI 进更新雷达
    var globalClis: [GlobalCli] = []
    var checkingClis = false
    var upgradingClis: Set<String> = []
    var cliUpdates: [GlobalCli] { globalClis.filter(\.hasUpdate) }

    // 定时任务面板（v2.9）
    var schedTasks: [SchedTask] = []
    var schedShowVendor = false
    var schedLoading = false
    var schedBusy: Set<String> = []

    // 键盘导航（PATCH-02）
    var kbFocusId: String?
    var kbToolIdx = 0
    var fixKbIdx = 0                 // 修复弹层内的键盘选中项（v2.16：键盘能开弹层却按不动）
    var kbFocusList: [KbItem] = []           // MainView 按可见顺序回填
    var kbFocusFrame: CGRect = .zero         // 聚焦行的窗口坐标（修复弹层锚点用）
    var winSize: CGSize = .zero

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    // store 实时监听（v2.15）：终端动了 ~/.agents / 工具链接目录，秒级自动跟上
    @ObservationIgnored private var watcher: StoreWatcher?
    @ObservationIgnored private var watchDebounce: Task<Void, Never>?
    // v2.16 打磨批新增：
    @ObservationIgnored private var warnedMetaCorrupt = false          // meta 损坏告警只发一次
    @ObservationIgnored private var pendingRecheck: Set<String> = []   // 全量检查中收到的定向重查请求，收尾后追跑
    @ObservationIgnored private var updateBatch: UpdateBatch?          // 「全部更新」的收工账本
    @ObservationIgnored private var cliQueue: [String] = []            // npm 升级串行队列（并发 npm i -g 会互相咬全局目录）
    @ObservationIgnored private var cliPumping = false
    @ObservationIgnored private var cliBatch: (ok: Int, fail: [String])?

    struct UpdateBatch {
        var remaining: Set<String>
        var ok: [String] = []
        var failed: [String] = []
    }

    /// 环境探测的进程级单飞标志（v2.17，见 init 注释）
    private static var envProbeLaunched = false
    /// Sparkle 手动检查入口（PopskillApp 注入；裸二进制为 nil）
    @ObservationIgnored var checkAppUpdate: (() -> Void)?
    /// Sparkle 自动检查读/写（PopskillApp 注入）——设置页开关用，AppModel 不直接依赖 Sparkle
    @ObservationIgnored var sparkleAutoCheckGet: (() -> Bool)?
    @ObservationIgnored var sparkleAutoCheckSet: ((Bool) -> Void)?

    // 派生
    var stats: Stats { deriveStats(entries, tools: tools) }
    var issues: [Issue] { deriveIssues(entries, tools: tools) }
    var updates: [Entry] { deriveUpdates(entries) }
    /// 待更新技能总数（用户视角）：套装逐成员计——横幅与「全部更新」按钮都用它
    var updateItemCount: Int { updates.reduce(0) { $0 + $1.updateCount } }
    /// 上游 monorepo 新增未装技能总数（v2.17 横幅）
    var upstreamNewItemCount: Int { entries.reduce(0) { $0 + $1.upstreamNewCount } }
    var entriesWithUpstreamNew: [Entry] { entries.filter(\.hasUpstreamNew) }
    var isEmpty: Bool { entries.isEmpty }

    // v2.17 环境探测 / 深链接
    var envWarnings: [EnvWarning] = []
    var pendingAddURL: String?          // popskill://install?src=… 预填添加框
    @ObservationIgnored private var envProbed = false

    init(env: StoreEnv = .real()) {
        fs = StoreFS(env: env)
        let pe = ProcessInfo.processInfo.environment
        if pe["POPSKILL_FAKE_DATA"] == "1" {
            fake = true
            (tools, entries) = Fixtures.make()
            entries = fs.sortEntries(entries)
            syncInfo = SyncInfo(isGitRepo: true, clean: true, lastSync: Date().addingTimeInterval(-120), storeSizeMB: 482)
        } else {
            refresh()
        }
        if pe["POPSKILL_EMPTY"] == "1" { entries = [] }
        if pe["POPSKILL_VIEW"] == "list" { viewMode = .list }   // 截图/E2E：直开表格视图
        switch pe["POPSKILL_SHEET"] {
        case "add": sheet = .add
        case "settings": sheet = .settings
        case "sched": sheet = .sched; reloadSched()
        case "cli": sheet = .cli; checkCliUpdates()
        default: break
        }
        // PATCH-02：套装默认全折叠（首屏密度），不再自动展开第一个
        // 调试钩子：POPSKILL_EXPAND=id1,id2 启动即展开指定套装（截图用）
        if let ids = pe["POPSKILL_EXPAND"]?.split(separator: ",") {
            ids.forEach { expanded.insert(String($0)) }
        }
        // 启动后台检查更新；开了自动更新的源直接更（v2.1）
        if !fake && pe["POPSKILL_NO_AUTOCHECK"] != "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))   // 不抢首屏
                await MainActor.run { self?.checkUpdates(auto: true) }
            }
        }
        // 环境探测（v2.17）见 launchEnvProbeOnce()——RootView onAppear 启动，
        // 不放 init：detached task 在 init 里捕获构造中的 self 是 Swift 6 错误
        // 调试钩子：POPSKILL_ONBOARD_SCAN=1 启动后自动触发空态扫描（新用户旅程 E2E）
        if pe["POPSKILL_ONBOARD_SCAN"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run { self?.scanLocalForOnboarding() }
            }
        }
        // 调试钩子：POPSKILL_KB_SIM=d,d,u,l,r,space 启动后模拟键盘导航（E2E 截图用）
        if let sim = pe["POPSKILL_KB_SIM"] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                await MainActor.run {
                    guard let self else { return }
                    for step in sim.split(separator: ",") {
                        switch step {
                        case "d": self.kbMove(1)
                        case "u": self.kbMove(-1)
                        case "l": self.kbSetTool(self.kbToolIdx - 1)
                        case "r": self.kbSetTool(self.kbToolIdx + 1)
                        case "space": self.kbActivate()
                        default: break
                        }
                    }
                }
            }
        }
        // 调试钩子：POPSKILL_PEEK=capId 启动即开详情 peek（截图验证用）
        if let capId = pe["POPSKILL_PEEK"] {
            for e in entries {
                if let c = e.allCaps.first(where: { $0.id == capId }) {
                    expanded.insert(e.id)
                    peekTarget = PeekTarget(cap: c, entry: e, anchor: CGPoint(x: 300, y: 420), flip: false)
                }
            }
        }
        // 调试钩子：POPSKILL_FIXPOP=capId:toolId 启动即开修复弹层（截图验证用）
        if let spec = pe["POPSKILL_FIXPOP"]?.split(separator: ":"), spec.count == 2 {
            let capId = String(spec[0]), toolId = String(spec[1])
            for e in entries {
                if let c = e.allCaps.first(where: { $0.id == capId }), let t = tools.first(where: { $0.id == toolId }) {
                    expanded.insert(e.id)
                    fixTarget = FixTarget(issueKind: c.status(toolId), cap: c, entry: e, tool: t,
                                          anchor: CGPoint(x: 1100, y: 360), flip: false)
                }
            }
        }
    }

    func refresh() {
        guard !fake else { return }
        // v2.18 身份类型化的一次性 meta 键迁移（幂等，快速路径零写盘）。
        // 必须在 scanEntries 之前：扫描按新键读来源/自动更新/跳过状态；
        // 也必须在 gcMeta 之前：旧格式键不迁就会被当孤儿清掉
        fs.migrateMetaKeys()
        let meta = fs.loadMeta()
        tools = fs.scanTools(meta: meta)
        entries = fs.scanEntries(tools: tools, meta: meta)
        revalidateOverlays()
        syncWatchPaths()
        // meta 曾损坏（loadMeta 已备份第一现场）：告警一次，别静默装无事发生
        if !warnedMetaCorrupt, fs.metaCorruptBackupExists {
            warnedMetaCorrupt = true
            sayError(L("store 元数据曾损坏，已备份为 .popskill.json.corrupt——来源与自动更新设置可能需要重新配置"))
        }
        // 孤儿 meta 键随手清（终端删掉的条目残留的 sourceUrl/autoUpdate 会祸害重装的同名技能）
        let keep = Set(entries.flatMap { e in [e.id] + e.allCaps.map { typedId($0.layoutKind, $0.name) } })
        let fsCopy = fs
        Task.detached { @Sendable [weak self] in
            fsCopy.gcMeta(keep: keep)
            let info = fsCopy.syncInfo()
            await MainActor.run { [weak self] in self?.syncInfo = info }
        }
    }

    // ── store 实时监听（v2.15）──────────────────────────────

    /// FSEvents 监听启动（RootView onAppear 调一次）。⌘R 与切前台重扫保留——
    /// 睡眠/权限等极端情况下事件可能丢，多一条兜底回家路不冲突。
    func startWatching() {
        guard !fake, watcher == nil,
              ProcessInfo.processInfo.environment["POPSKILL_NO_WATCH"] != "1" else { return }
        watcher = StoreWatcher { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleWatchRefresh() }
        }
        syncWatchPaths()
    }

    /// FSEvents 侧已有秒级合并窗口，这里再补一层尾去抖：一批回调只落一次重扫。
    /// 换版进行中让位（applyUpdate 收尾自带 refresh，中途重扫只会看到换到一半的盘面）。
    private func scheduleWatchRefresh() {
        watchDebounce?.cancel()
        watchDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled, self.updatingIds.isEmpty else { return }
            plog.info("FSEvents：store/工具目录有外部变更，自动重扫")
            self.refresh()
        }
    }

    /// 监听集跟着盘面走：工具链接目录（~/.codex/skills 等）挂载后才存在——
    /// 每次 refresh 后对齐一次。StoreWatcher.sync 幂等，集合没变就是 no-op。
    /// 刻意不监听 ~/.claude 整棵树：projects/ 每个 Claude 会话都在写，噪音是信号的百倍。
    /// v2.17：store 根被删时改听父目录——重建后 sync 自动换回只听 store（曾靠切前台兜底）。
    private func syncWatchPaths() {
        guard let watcher else { return }
        var paths: [String] = []
        let store = fs.env.storeRoot
        if FileManager.default.fileExists(atPath: store.path) {
            paths.append(store.path)
        } else {
            // 根没了：听父目录等它被重建；父目录事件多，scheduleWatchRefresh 仍去抖+幂等 refresh
            paths.append(store.deletingLastPathComponent().path)
        }
        for t in tools where t.connected {
            for dir in ["skills", "agents", "mcp", "bin"] {
                paths.append(t.root.appendingPathComponent(dir).path)
            }
        }
        watcher.sync(paths: paths)
    }

    /// 环境探测启动（v2.17，RootView onAppear 调）。进程探测（ensureGit / zsh -lc 找 npm）
    /// 整个在后台线程做——login shell 可能 1-3 秒（nvm 用户常见），放 MainActor 会冻窗口。
    /// 进程级单飞：环境是机器属性，一个进程探测一次就够——测试套件会构造十几个 AppModel，
    /// 若各起一个 detached 探测会并行卡在 NpmEnv 的 NSLock 上，把 Swift 协作线程池
    /// 占满饿死其它 async 工作（watcher 集成测试实测被饿挂）
    func launchEnvProbeOnce() {
        guard !fake, !Self.envProbeLaunched else { return }
        Self.envProbeLaunched = true
        Task.detached(priority: .utility) { @Sendable [weak self] in
            try? await Task.sleep(for: .seconds(1))
            let gitOK = (try? StoreFS.ensureGit()) != nil
            let npmOK = NpmEnv.npmBin() != nil
            await MainActor.run { [weak self] in self?.applyEnvProbe(gitOK: gitOK, npmOK: npmOK) }
        }
    }

    /// 环境探测结果装配（v2.17）：git 影响 GitHub 安装，npm 影响 CLI 巡检 / npm 源更新。
    /// 探测本体（起进程）在 launchEnvProbeOnce 的 detached Task 里做，这里只在主线程装配状态
    func applyEnvProbe(gitOK: Bool, npmOK: Bool) {
        guard !fake else { return }
        var warnings: [EnvWarning] = []
        if !gitOK {
            warnings.append(EnvWarning(
                id: "git",
                message: L("未检测到 git——安装 GitHub 技能需要它。在「终端」运行：xcode-select --install")))
        }
        if !npmOK {
            warnings.append(EnvWarning(
                id: "npm",
                message: L("未检测到 npm——CLI 巡检与 npm 源更新不可用。请安装 Node.js 或把 npm 加入 PATH。")))
        }
        envWarnings = warnings
        envProbed = true
    }

    func dismissEnvWarning(_ id: String) {
        envWarnings.removeAll { $0.id == id }
        UserDefaults.standard.set(true, forKey: "dismissedEnvWarning.\(id)")
    }

    /// 过滤已点「知道了」的警告（会话外持久）
    func activeEnvWarnings() -> [EnvWarning] {
        envWarnings.filter { !UserDefaults.standard.bool(forKey: "dismissedEnvWarning.\($0.id)") }
    }

    /// 深链接（v2.17）：`popskill://install?src=github.com/owner/repo`
    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "popskill" else { return }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let isInstall = host == "install" || path == "/install" || path.hasSuffix("/install")
            || (host.isEmpty && path.contains("install"))
        guard isInstall else {
            say(L("无法识别的 Popskill 链接"))
            return
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let src = comps?.queryItems?.first(where: { ["src", "url", "source"].contains($0.name.lowercased()) })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let src, !src.isEmpty else {
            sheet = .add
            say(L("已打开添加面板——请粘贴仓库地址"))
            return
        }
        pendingAddURL = src
        sheet = .add
        plog.info("深链接进入添加流程：\(src, privacy: .public)")
        say(L("已从链接打开添加流程"))
    }

    /// refresh 换掉 entries 后，开着的修复弹层 / 详情 peek 持有的是旧快照——
    /// 按 id 重新解析：还在且状态没变就原位续上，否则关掉（盘面已变，别对着幻影操作）
    private func revalidateOverlays() {
        if let t = fixTarget {
            if let entry = entries.first(where: { $0.id == t.entry.id }),
               let cap = entry.allCaps.first(where: { $0.id == t.cap.id }),
               cap.status(t.tool.id) == t.issueKind {
                fixTarget = FixTarget(issueKind: t.issueKind, cap: cap, entry: entry,
                                      tool: t.tool, anchor: t.anchor, flip: t.flip)
            } else {
                fixTarget = nil
            }
        }
        if let pk = peekTarget {
            if let entry = entries.first(where: { $0.id == pk.entry.id }),
               let cap = entry.allCaps.first(where: { $0.id == pk.cap.id }) {
                peekTarget = PeekTarget(cap: cap, entry: entry, anchor: pk.anchor, flip: pk.flip)
            } else {
                peekTarget = nil
            }
        }
    }

    // ── toast / flash ────────────────────────────────────

    func say(_ msg: String, error: Bool = false) {
        toast = msg
        toastIsError = error
        toastTask?.cancel()
        toastTask = Task {
            // 错误必须比成功提示活得久——它是用户唯一的现场证据
            try? await Task.sleep(for: .seconds(error ? 6 : 2.6))
            if !Task.isCancelled { toast = nil }
        }
    }

    func sayError(_ msg: String) {
        plog.error("\(msg, privacy: .public)")
        say(msg, error: true)
    }

    func flash(_ id: String) {
        flashId = id
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if flashId == id { flashId = nil }
        }
    }

    // ── 键盘导航（PATCH-02）───────────────────────────────

    private var kbIdx: Int? {
        guard let id = kbFocusId else { return nil }
        return kbFocusList.firstIndex { $0.id == id }
    }

    func kbMove(_ delta: Int) {
        guard !kbFocusList.isEmpty else { return }
        if let i = kbIdx {
            kbFocusId = kbFocusList[max(0, min(kbFocusList.count - 1, i + delta))].id
        } else {
            kbFocusId = (delta > 0 ? kbFocusList.first : kbFocusList.last)?.id
        }
    }

    func kbSetTool(_ idx: Int) {
        guard kbFocusId != nil else { return }
        kbToolIdx = max(0, min(tools.count - 1, idx))
    }

    /// 空格/回车：套装行折叠/展开；能力行 on/off 切换、stub/broken 开修复弹层
    func kbActivate() {
        guard let i = kbIdx else { return }
        let item = kbFocusList[i]
        if item.isBundle {
            // Bundle chip 下强制展开——空格折叠是暗改状态、界面无反应（与点击守卫一致，v2.16）
            guard query.trimmingCharacters(in: .whitespaces).isEmpty, typeFilter != .bundle else { return }
            if expanded.contains(item.entryId) { expanded.remove(item.entryId) }
            else { expanded.insert(item.entryId) }
            return
        }
        guard let entry = entries.first(where: { $0.id == item.entryId }),
              let cap = entry.allCaps.first(where: { $0.id == item.capId }),
              kbToolIdx < tools.count else { return }
        let tool = tools[kbToolIdx]
        let st = cap.status(tool.id)
        if st == .on || st == .off {
            toggle(cap: cap, entry: entry, tool: tool)
        } else {
            let anchor = CGPoint(x: kbFocusFrame.midX, y: kbFocusFrame.maxY)
            let flip = winSize.height > 0 && kbFocusFrame.maxY > winSize.height * 0.63
            openFix(FixTarget(issueKind: st, cap: cap, entry: entry, tool: tool, anchor: anchor, flip: flip))
        }
    }

    /// 焦点列表更新后校验：当前焦点已不可见则清除
    func kbValidate() {
        if let id = kbFocusId, !kbFocusList.contains(where: { $0.id == id }) {
            kbFocusId = nil
        }
    }

    // ── 浮层互斥（peek 与修复弹层只存在一个）──────────────

    func openFix(_ target: FixTarget) {
        peekTarget = nil
        fixTarget = target
        // 键盘选中项落在推荐方案上（v2.16）
        fixKbIdx = fixOptions(for: target).firstIndex(where: \.rec) ?? 0
    }

    func openPeek(cap: Capability, entry: Entry, anchor: CGPoint, flip: Bool) {
        fixTarget = nil
        peekTarget = PeekTarget(cap: cap, entry: entry, anchor: anchor, flip: flip)
    }

    // ── 开关 ─────────────────────────────────────────────

    func toggle(cap: Capability, entry: Entry, tool: Tool) {
        guard !entry.isManagedExternally else {
            say(L("Marketplace 插件由 Claude Code 管理——在 Claude Code 里用 /plugin 操作"))
            return
        }
        guard !updatingIds.contains(entry.id) else {
            say(L("\(entry.name) 正在更新中，稍候再操作"))
            return
        }
        let from = cap.status(tool.id)
        guard from == .on || from == .off else { return }   // stub/broken 走修复弹层
        // 工具没装（~/.claude / ~/.codex 不存在）时挂载会凭空建出该目录——先确认
        if from == .off, !fake, !tool.connected, !confirmMountUnconnected(tool) { return }
        let to: LinkStatus = from == .on ? .off : .on
        if fake {
            mutateFake(capId: cap.id, toolId: tool.id, to: to)
        } else {
            do {
                if entry.bundleKind == .directory && cap.id != entry.cap.id {
                    try fs.setBundleChildLink(
                        tool: tool, bundleName: entry.name, bundleDir: entry.cap.dirURL,
                        childName: cap.name, allChildren: (entry.children ?? []).map(\.name), on: to == .on)
                } else {
                    // 独立条目 / 源式套装成员：都是平铺 symlink
                    try fs.setLink(tool: tool, kind: cap.layoutKind, name: cap.name, storeDir: cap.dirURL, on: to == .on)
                }
                refresh()
            } catch {
                sayError(to == .on
                    ? L("链接 \(cap.name) 失败：\(error.localizedDescription)")
                    : L("断开 \(cap.name) 失败：\(error.localizedDescription)"))
                return
            }
        }
        say(to == .on ? L("已链接 \(cap.name) → \(tool.name)") : L("已断开 \(cap.name) → \(tool.name)"))
    }

    /// 未装工具的挂载确认——矩阵格与添加流程共用（v2.16：添加流程曾绕过这道防线，
    /// 静默建出 ~/.codex）。v2.15 的「不再询问」（系统原生 suppression）在这里：
    /// 批量往新工具挂十几个技能时十几连弹是折磨；只在点了「仍然挂载」时才记住勾选。
    func confirmMountUnconnected(_ tool: Tool) -> Bool {
        if ProcessInfo.processInfo.environment["POPSKILL_AUTOCONFIRM"] == "1" { return true }
        if UserDefaults.standard.bool(forKey: "suppressMountConfirm") { return true }
        let alert = NSAlert()
        alert.messageText = L("\(tool.name) 似乎还没安装")
        alert.informativeText = L("挂载会在 \(tool.rootDisplay) 创建目录。如果你还没用这个工具，可以先不挂。确定要创建并挂载吗？")
        alert.addButton(withTitle: L("仍然挂载"))
        alert.addButton(withTitle: L("取消"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("不再询问")
        let resp = alert.runModal()
        guard resp == .alertFirstButtonReturn else { return false }
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: "suppressMountConfirm")
        }
        return true
    }

    // ── 修复 ─────────────────────────────────────────────

    func fixOptions(for t: FixTarget) -> [FixOption] {
        var opts: [FixOption] = []
        if t.issueKind == .stub {
            // 真实世界的 stub = 本地副本（真实目录占着链接位）
            opts.append(FixOption(kind: .adopt, label: L("改用 store 链接"), desc: L("原目录移入 store 回收站，换成指向 store 的 symlink"), rec: true,
                                  toast: L("已把 \(t.cap.name) · \(t.tool.name) 换成 store 链接")))
            opts.append(FixOption(kind: .trashCopy, label: L("移除该侧副本"), desc: L("目录移入 store 回收站，不建链接"), rec: false,
                                  toast: L("已移除 \(t.cap.name) 在 \(t.tool.name) 侧的副本")))
            opts.append(FixOption(kind: .keep, label: L("保持现状"), desc: L("保留本地副本，popskill 不接管"), rec: false, toast: ""))
        } else {
            let storeExists = FileManager.default.fileExists(atPath: t.cap.dirURL.path)
            if t.entry.hasUpdate, let latest = t.entry.latest {
                opts.append(FixOption(kind: .update, label: L("更新到 \(latest) 并修复"), desc: L("从 \(t.entry.sourceUrl ?? L("源")) 拉取新版，重链 symlink"), rec: true,
                                      toast: L("已更新 \(t.entry.name) 并修复链接")))
            }
            if storeExists {
                opts.append(FixOption(kind: .relink, label: L("重链到 store 中本地版本"), desc: L("指回 store 中现存的目录"), rec: !t.entry.hasUpdate,
                                      toast: L("已重链 \(t.cap.name) · \(t.tool.name)")))
            }
            if let url = t.entry.sourceUrl, SourceKind.of(url) == .github {
                // 推荐唯一：有更新推更新，store 健在推重链，都没有才推重拉
                opts.append(FixOption(kind: .repull, label: L("从源重新拉取"), desc: L("从 \(url) 重新获取该项"),
                                      rec: !t.entry.hasUpdate && !storeExists,
                                      toast: L("已从源重新拉取 \(t.cap.name)")))
            }
            opts.append(FixOption(kind: .unlink, label: L("移除该侧链接"), desc: L("撤掉这条 symlink，其他工具不受影响"), rec: false,
                                  toast: L("已移除 \(t.cap.name) 在 \(t.tool.name) 侧的链接")))
        }
        return opts
    }

    func applyFix(_ opt: FixOption, target t: FixTarget) {
        defer { fixTarget = nil }
        if fake {
            let to: LinkStatus = (opt.kind == .unlink || opt.kind == .trashCopy) ? .off : .on
            if opt.kind != .keep { mutateFake(capId: t.cap.id, toolId: t.tool.id, to: to) }
            if opt.kind == .update { runUpdate(t.entry.id, quiet: true) }
            if !opt.toast.isEmpty { say(opt.toast) }
            return
        }
        do {
            let link = linkPath(cap: t.cap, entry: t.entry, tool: t.tool)
            switch opt.kind {
            case .keep:
                return
            case .relink:
                try relink(cap: t.cap, entry: t.entry, tool: t.tool)
            case .adopt:
                try fs.replaceCopyWithLink(at: link, target: t.cap.dirURL)
            case .trashCopy:
                if fs.isSymlink(link) { try fs.removeLink(at: link) } else { try fs.moveToTrash(link) }
            case .unlink:
                try fs.removeLink(at: link)
            case .repull:
                guard let url = t.entry.sourceUrl else { return }
                repull(entry: t.entry, primaryToolId: t.tool.id, url: url, toast: opt.toast)
                return   // 网络在后台跑，toast 由 repull 收尾时发
            case .update:
                try? relink(cap: t.cap, entry: t.entry, tool: t.tool)   // 先把这格链上，更新落盘后自动生效
                runUpdate(t.entry.id)
                refresh()
                return   // 收尾 toast 由 runUpdate 发——曾在这抢跑说「已更新」，失败时前后矛盾（v2.16）
            }
            refresh()
            if !opt.toast.isEmpty { say(opt.toast) }
        } catch {
            sayError(L("修复 \(t.cap.name) 失败：\(error.localizedDescription)"))
        }
    }

    /// 从源重拉：曾在 @MainActor 上同步跑 git clone，网络慢时整个 UI 冻死。
    /// 现照 resolveSource/runUpdate 的模式下放后台，期间条目置 updating 态。
    /// 顺序不变：先 resolve（clone 失败时本地分毫未动）→ removeEntry → install。
    private func repull(entry: Entry, primaryToolId: String, url: String, toast toastMsg: String) {
        guard !updatingIds.contains(entry.id) else { return }
        updatingIds.insert(entry.id)
        say(L("正在从源重新拉取 \(entry.name)…"))
        let fsCopy = fs
        let allTools = tools
        Task { [weak self] in
            let result: Result<Void, Error> = await Task.detached {
                do {
                    let resolved = try fsCopy.resolve(url)
                    do {
                        try fsCopy.removeEntry(entry, tools: allTools)
                        let relinkTools = allTools.filter { tool in
                            tool.id == primaryToolId || entry.allCaps.contains { $0.status(tool.id) != .off }
                        }
                        try fsCopy.install(resolved, linkTools: relinkTools)
                    } catch {
                        // SECURITY.md 承诺临时 clone「用完即删，失败也删」——失败路径必须兜底
                        fsCopy.discardStaging(resolved)
                        throw error
                    }
                    return .success(())
                } catch { return .failure(error) }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updatingIds.remove(entry.id)
                self.refresh()
                switch result {
                case .success:
                    plog.info("repull \(entry.name, privacy: .public) ← \(url, privacy: .public) 完成")
                    if !toastMsg.isEmpty { self.say(toastMsg) }
                case .failure(let err):
                    self.sayError(L("重新拉取 \(entry.name) 失败：\(err.localizedDescription)"))
                }
            }
        }
    }

    private func linkPath(cap: Capability, entry: Entry, tool: Tool) -> URL {
        if entry.bundleKind == .directory && cap.id != entry.cap.id {
            return fs.toolLinkPath(tool, kind: .bundle, name: entry.name).appendingPathComponent(cap.name)
        }
        return fs.toolLinkPath(tool, kind: cap.layoutKind, name: cap.name)
    }

    private func relink(cap: Capability, entry: Entry, tool: Tool) throws {
        if entry.bundleKind == .directory && cap.id != entry.cap.id {
            try fs.setBundleChildLink(tool: tool, bundleName: entry.name, bundleDir: entry.cap.dirURL,
                                      childName: cap.name, allChildren: (entry.children ?? []).map(\.name), on: true)
        } else {
            try fs.setLink(tool: tool, kind: cap.layoutKind, name: cap.name, storeDir: cap.dirURL, on: true)
        }
    }

    /// 全部修复：对每个问题执行其推荐方案
    func fixAll() {
        let list = issues
        var fixed = 0
        var skipped = 0
        var firstError: String?
        for issue in list {
            guard let entry = entries.first(where: { $0.id == issue.entryId }),
                  let cap = entry.allCaps.first(where: { $0.id == issue.capId }),
                  let tool = tools.first(where: { $0.id == issue.toolId }),
                  !updatingIds.contains(entry.id) else {
                skipped += 1   // 条目消失或正在后台换版——是跳过，不是失败
                continue
            }
            if fake {
                mutateFake(capId: cap.id, toolId: tool.id, to: .on)
                fixed += 1
            } else {
                let storeExists = FileManager.default.fileExists(atPath: cap.dirURL.path)
                do {
                    if storeExists {
                        try relink(cap: cap, entry: entry, tool: tool)
                    } else {
                        try fs.removeLink(at: linkPath(cap: cap, entry: entry, tool: tool))
                    }
                    fixed += 1
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                    plog.error("fixAll \(cap.name, privacy: .public) · \(tool.id, privacy: .public) 失败: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        if !fake { refresh() }
        // 成功/失败/跳过三态分开——红色错误只留给真出错的
        let failedCount = list.count - fixed - skipped
        if failedCount > 0 {
            sayError(firstError.map { L("修复 \(fixed) 个，\(failedCount) 个失败：\($0)") }
                ?? L("修复 \(fixed) 个，\(failedCount) 个失败"))
        } else if skipped > 0 {
            say(L("已修复 \(fixed) 个，跳过 \(skipped) 个（正在更新中）"))
        } else {
            say(L("已修复 \(fixed) 个链接问题"))
        }
    }

    // ── 更新（v2.1：内容哈希比对，吸收自 cc-switch）────────

    /// 检查全部可检查的源；auto=true 时对开了自动更新的源直接执行更新。
    /// only 非空 = 定向重查那几个源（恢复更新提醒后用，不扫全部不碰 CLI 巡检）
    func checkUpdates(auto: Bool = false, only: Set<String>? = nil) {
        guard !fake else { say(L("原型数据模式不检查更新")); return }
        guard !checkingUpdates else { return }
        // v2.14：npm 源进检查范围（比对全局 CLI 版本）；全局 CLI 巡检顺带跑
        let candidates = entries.filter {
            $0.sourceUrl != nil && !$0.isManagedExternally && (only?.contains($0.id) ?? true)
        }
        guard !candidates.isEmpty else { say(L("没有可检查的源（需要 GitHub 或本地路径来源）")); return }
        checkingUpdates = true
        if only == nil { checkCliUpdates() }
        let fsCopy = fs
        Task { [weak self] in
            var found: [StoreFS.UpdateCheck] = []
            var fresh: [String] = []   // 检查成功且确认无更新的 entryId（用于熄灭残留徽标）
            var failed = 0
            // 失败和「确实最新」必须是两个态——曾用 try? 把断网/源被删压成 nil，
            // 然后对用户谎报「全部源已是最新」
            await withTaskGroup(of: (String, Result<StoreFS.UpdateCheck?, Error>).self) { group in
                var pending = candidates.makeIterator()
                var running = 0
                func enqueue() {
                    while running < 4, let e = pending.next() {
                        running += 1
                        group.addTask {
                            do { return (e.id, .success(try fsCopy.checkUpdate(e))) }
                            catch {
                                plog.error("检查更新失败 \(e.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                                return (e.id, .failure(error))
                            }
                        }
                    }
                }
                enqueue()
                for await (id, result) in group {
                    running -= 1
                    switch result {
                    case .success(let check): if let check { found.append(check) } else { fresh.append(id) }
                    case .failure: failed += 1
                    }
                    enqueue()
                }
            }
            let failedCount = failed
            let freshIds = fresh
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.checkingUpdates = false
                for check in found {
                    if let i = self.entries.firstIndex(where: { $0.id == check.entryId }) {
                        // contentUnchanged = 仅上游新增，不亮更新徽标
                        if check.contentUnchanged {
                            self.entries[i].upstreamNew = check.upstreamNew.isEmpty ? nil : check.upstreamNew
                        } else {
                            self.entries[i].latest = check.latest
                            self.entries[i].changedMembers = check.changedMembers
                            self.entries[i].skippedUpdate = false
                            self.entries[i].upstreamNew = check.upstreamNew.isEmpty ? nil : check.upstreamNew
                            self.fs.saveLatest(self.entries[i].id, latest: check.latest,
                                               changed: check.changedMembers, fingerprint: check.fingerprint)
                        }
                    }
                }
                // 确认一致的熄灭残留徽标（如终端手动同步后；meta 由 checkUpdate 清，这里同步内存镜像）。
                // 检查失败的不在 freshIds 里——失败 ≠ 最新
                for id in freshIds {
                    if let i = self.entries.firstIndex(where: { $0.id == id }) {
                        if self.entries[i].latest != nil {
                            self.entries[i].latest = nil
                            self.entries[i].changedMembers = nil
                        }
                        // 完整比对无更新也无 upstreamNew 时 meta 已清；同步内存
                        let metaNew = self.fs.loadMeta().entries[self.entries[i].id]?.upstreamNew
                        self.entries[i].upstreamNew = metaNew
                    }
                }
                // found 里 contentUnchanged 的 upstreamNew 已写；全量再从 meta 对齐一次防漏
                let metaAll = self.fs.loadMeta()
                for e in candidates {
                    if let i = self.entries.firstIndex(where: { $0.id == e.id }) {
                        if let u = metaAll.entries[self.entries[i].id]?.upstreamNew {
                            self.entries[i].upstreamNew = u
                        }
                    }
                }
                // well-known 部分成员没查成时如实透出（v2.16——「1 项可更新」背后可能还有 5 个状态未知）
                let partial = found.reduce(0) { $0 + $1.partialFailures }
                let partialNote = partial > 0 ? L("；另有 \(partial) 个套装成员没查成（网络抖动）") : ""
                let contentFound = found.filter { !$0.contentUnchanged }
                let newOnlyCount = found.filter(\.contentUnchanged).reduce(0) { $0 + $1.upstreamNew.count }
                let newOnlyNote = newOnlyCount > 0 ? L("；上游新增 \(newOnlyCount) 个未装技能") : ""
                let autoTargets = auto ? self.entries.filter { $0.hasUpdate && $0.autoUpdate } : []
                if !autoTargets.isEmpty {
                    for e in autoTargets { self.runUpdate(e.id, quiet: true) }
                    self.say(L("自动更新 \(autoTargets.count) 个源"))
                } else if failedCount > 0 {
                    // 启动自动检查的失败不弹 toast 打扰（断网开机最常见），日志已留痕；手动检查必须如实报
                    if !auto {
                        self.sayError((contentFound.isEmpty
                            ? L("\(failedCount) 个源检查失败（网络或源不可达）")
                            : L("发现 \(contentFound.count) 个源可更新；\(failedCount) 个源检查失败（网络或源不可达）")) + partialNote + newOnlyNote)
                    } else if !contentFound.isEmpty {
                        self.say(L("发现 \(contentFound.count) 个源可更新（另有 \(failedCount) 个检查失败）") + partialNote + newOnlyNote)
                    }
                } else if !auto || !contentFound.isEmpty || newOnlyCount > 0 {
                    if contentFound.isEmpty && newOnlyCount == 0 {
                        self.say(L("全部源已是最新") + partialNote)
                    } else if contentFound.isEmpty {
                        self.say(L("内容已是最新") + newOnlyNote + partialNote)
                    } else {
                        self.say(L("发现 \(contentFound.count) 个源可更新") + newOnlyNote + partialNote)
                    }
                }
                // 全量检查期间收到的「恢复更新提醒」定向重查，此刻追跑（v2.16：曾被 guard 静默吞掉）
                if !self.pendingRecheck.isEmpty {
                    let ids = self.pendingRecheck
                    self.pendingRecheck = []
                    self.checkUpdates(only: ids)
                }
            }
        }
    }

    /// 一步更新：备份 → 拉上游 → 落盘（symlink 路径不变自动延续）
    func runUpdate(_ entryId: String, quiet: Bool = false) {
        guard let entry = entries.first(where: { $0.id == entryId }) else { return }
        if fake {
            if let i = entries.firstIndex(where: { $0.id == entryId }) {
                let latest = entries[i].latest ?? L("新版")
                entries[i].cap.version = entries[i].latest
                entries[i].latest = nil
                say(L("已更新 \(entry.name) → \(latest)"))
            }
            return
        }
        guard !updatingIds.contains(entryId) else { return }
        updatingIds.insert(entryId)
        let fsCopy = fs
        Task { [weak self] in
            let result: Result<(updated: [String], upstreamNew: [String]), Error> = await Task.detached {
                do { return .success(try fsCopy.applyUpdate(entry)) }
                catch { return .failure(error) }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updatingIds.remove(entryId)
                switch result {
                case .success(let r):
                    plog.info("更新 \(entry.name, privacy: .public) 完成：\(r.updated.joined(separator: ","), privacy: .public)")
                    self.refresh()
                    let inBatch = self.batchNote(entryId, name: entry.name, ok: true)
                    if !quiet && !inBatch {
                        // npm 源的「更新」= npm i -g 全局 CLI，全程不碰回收站——
                        // 曾统一说「旧版已入回收站」，谎报可回滚（v2.16 审计）
                        if SourceKind.of(entry.sourceUrl) == .npm {
                            self.say(L("已升级全局 CLI \(r.updated.first ?? entry.name)（npm i -g）"))
                        } else {
                            let names = r.updated.count <= 3 ? r.updated.joined(separator: L("、"))
                                : L("\(r.updated.prefix(3).joined(separator: L("、"))) 等")
                            var msg = r.updated.count == 1 && !entry.isBundle
                                ? L("已更新 \(entry.name)（旧版已入回收站）")
                                : L("已更新 \(entry.name)：\(names)（旧版已入回收站）")
                            if !r.upstreamNew.isEmpty {
                                msg += L(" · 上游另有 \(r.upstreamNew.count) 个未安装技能")
                                // 内存镜像跟上（meta 已由 applyUpdate 写入）
                                if let i = self.entries.firstIndex(where: { $0.id == entryId }) {
                                    self.entries[i].upstreamNew = r.upstreamNew
                                }
                            }
                            self.say(msg)
                        }
                    }
                case .failure(let err):
                    plog.error("更新 \(entry.name, privacy: .public) 失败：\(err.localizedDescription, privacy: .public)")
                    if !self.batchNote(entryId, name: entry.name, ok: false) {
                        self.sayError(L("更新 \(entry.name) 失败：\(err.localizedDescription)"))
                    }
                }
            }
        }
    }

    /// 「全部更新」的收工账本（v2.16：曾只报开工不报收工——成功零反馈、
    /// 部分失败的 toast 互相覆盖只剩最后一条）。返回是否记入了批次。
    private func batchNote(_ entryId: String, name: String, ok: Bool) -> Bool {
        guard updateBatch?.remaining.contains(entryId) == true else { return false }
        updateBatch?.remaining.remove(entryId)
        if ok { updateBatch?.ok.append(name) } else { updateBatch?.failed.append(name) }
        if let b = updateBatch, b.remaining.isEmpty {
            updateBatch = nil
            if b.failed.isEmpty {
                say(L("已更新 \(b.ok.count) 个源"))
            } else {
                sayError(L("更新收工：\(b.ok.count) 个成功，\(b.failed.count) 个失败（\(b.failed.joined(separator: L("、")))）"))
            }
        }
        return true
    }

    func updateAll() {
        // 已在更新中的条目 runUpdate 会直接跳过——不入账本，否则批次永远等不齐
        let targets = updates.filter { !updatingIds.contains($0.id) }
        guard !targets.isEmpty else { return }
        updateBatch = UpdateBatch(remaining: Set(targets.map(\.id)))
        for e in targets { runUpdate(e.id, quiet: true) }
        say(L("正在更新 \(targets.count) 个源…"))
    }

    /// 「跳过此版本」（v2.15，吸收 cc-switch dismissedVersion）：徽标熄灭，
    /// 该上游状态不再提醒；上游再出新东西时 checkUpdate 里指纹不匹配自动重亮。
    func skipUpdate(_ entry: Entry) {
        guard entry.hasUpdate else { return }
        if !fake { fs.skipLatest(entry.id) }
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i].latest = nil
            entries[i].changedMembers = nil
            entries[i].skippedUpdate = true
        }
        plog.info("跳过版本 \(entry.name, privacy: .public)")
        say(L("已跳过 \(entry.name) 的这个版本——上游再出新版会重新提醒"))
    }

    /// 恢复更新提醒：清跳过标记，并定向重查这一个源让徽标从真相重新推导。
    /// 全量检查进行中时排队等收尾追跑——曾直接调 checkUpdates 被 guard 吞掉，
    /// toast 说「正在重新检查」实际什么都没发生（v2.16 审计）
    func unskipUpdate(_ entry: Entry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i].skippedUpdate = false }
        guard !fake else { return }
        fs.unskipLatest(entry.id)
        if checkingUpdates {
            pendingRecheck.insert(entry.id)
            say(L("已恢复 \(entry.name) 的更新提醒——当前检查结束后将复查此源"))
        } else {
            say(L("已恢复 \(entry.name) 的更新提醒，正在重新检查…"))
            checkUpdates(only: [entry.id])
        }
    }

    // ── 全局 CLI 巡检（v2.14）────────────────────────────

    /// npm ls -g 全量 → 逐包比 registry。entries 里 npm 源对应的包走 entry 更新链，
    /// 这里排除掉——同一个更新在横幅出现两处计数比漏报更糟。
    func checkCliUpdates() {
        guard !fake, !checkingClis else { return }
        checkingClis = true
        let fsCopy = fs
        let entryPkgs = Set(entries.compactMap { npmPkgName($0.sourceUrl) })
        Task { [weak self] in
            let clis: [GlobalCli] = await Task.detached {
                let installed = fsCopy.npmGlobalList().filter { !entryPkgs.contains($0.key) }
                return installed.sorted { $0.key < $1.key }.map { pkg, ver in
                    GlobalCli(name: pkg, installed: ver, latest: try? fsCopy.npmLatestVersion(pkg))
                }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.globalClis = clis
                self.checkingClis = false
            }
        }
    }

    /// 升级单个全局 CLI 到 registry 最新版（实际执行走串行队列）
    func upgradeCli(_ pkg: String) {
        enqueueCliUpgrades([pkg])
    }

    /// 「全部升级」：批量入队 + 收工汇总（v2.16：曾并发喷 N 个 npm i -g——
    /// 同一全局前缀无锁并发写会互相咬，且成功/失败 toast 互相覆盖只剩最后一条）
    func upgradeAllClis() {
        let targets = cliUpdates.map(\.name)
        guard !targets.isEmpty else { return }
        if cliBatch == nil { cliBatch = (0, []) }
        enqueueCliUpgrades(targets)
    }

    private func enqueueCliUpgrades(_ pkgs: [String]) {
        let fresh = pkgs.filter { p in
            globalClis.first(where: { $0.name == p })?.hasUpdate == true
                && !upgradingClis.contains(p) && !cliQueue.contains(p)
        }
        guard !fresh.isEmpty else { return }
        upgradingClis.formUnion(fresh)   // 排队即转 spinner——「点了没反应」是最迷惑的失败模式
        cliQueue.append(contentsOf: fresh)
        pumpCliQueue()
    }

    private func pumpCliQueue() {
        guard !cliPumping, !cliQueue.isEmpty else {
            // 队列干了才结账
            if cliQueue.isEmpty, !cliPumping, let b = cliBatch {
                cliBatch = nil
                if b.fail.isEmpty {
                    say(L("已升级 \(b.ok) 个 CLI"))
                } else {
                    sayError(L("CLI 升级收工：\(b.ok) 个成功，\(b.fail.count) 个失败（\(b.fail.joined(separator: L("、")))）"))
                }
            }
            return
        }
        cliPumping = true
        let pkg = cliQueue.removeFirst()
        guard let cli = globalClis.first(where: { $0.name == pkg }), let latest = cli.latest else {
            upgradingClis.remove(pkg)
            cliPumping = false
            pumpCliQueue()
            return
        }
        let fsCopy = fs
        Task { [weak self] in
            let result: Result<Void, Error> = await Task.detached {
                do { try fsCopy.npmGlobalInstall(pkg, version: latest); return .success(()) }
                catch { return .failure(error) }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.upgradingClis.remove(pkg)
                switch result {
                case .success:
                    if let i = self.globalClis.firstIndex(where: { $0.name == pkg }) {
                        self.globalClis[i] = GlobalCli(name: pkg, installed: latest, latest: latest)
                    }
                    if self.cliBatch != nil { self.cliBatch!.ok += 1 } else { self.say(L("已升级 \(pkg) → v\(latest)")) }
                case .failure(let e):
                    plog.error("升级 CLI \(pkg, privacy: .public) 失败：\(e.localizedDescription, privacy: .public)")
                    if self.cliBatch != nil { self.cliBatch!.fail.append(pkg) } else { self.sayError(L("升级 \(pkg) 失败：\(e.localizedDescription)")) }
                }
                self.cliPumping = false
                self.pumpCliQueue()
            }
        }
    }

    /// 横幅「N 个技能可更新」点击：跳到下一个待更新条目并闪烁定位，多个时循环。
    /// 跳转意图优先于过滤——目标被搜索词/类型筛选挡住时直接清掉过滤，
    /// 否则「点了没反应」是最迷惑的失败模式。滚动由 kbFocusId 的 onChange 联动。
    func jumpToNextUpdate() {
        let ids = updates.map(\.id)
        guard !ids.isEmpty else { return }
        let cur = kbFocusId.flatMap { ids.firstIndex(of: $0) }
        let targetId = ids[((cur ?? -1) + 1) % ids.count]
        guard let e = entries.first(where: { $0.id == targetId }) else { return }
        query = ""
        typeFilter = nil
        if e.isBundle { expanded.insert(e.id) }
        kbFocusId = e.id
        flash(e.id)
    }

    /// 横幅「上游新增」循环定位（v2.17）
    func jumpToNextUpstreamNew() {
        let ids = entriesWithUpstreamNew.map(\.id)
        guard !ids.isEmpty else { return }
        let cur = kbFocusId.flatMap { ids.firstIndex(of: $0) }
        let targetId = ids[((cur ?? -1) + 1) % ids.count]
        guard let e = entries.first(where: { $0.id == targetId }) else { return }
        query = ""
        typeFilter = nil
        if e.isBundle { expanded.insert(e.id) }
        kbFocusId = e.id
        flash(e.id)
    }

    /// 安装某个源的上游新增技能（默认装名单全部；可传子集）
    func installUpstreamNew(_ entry: Entry, names: [String]? = nil, skipConfirm: Bool = false) {
        guard !entry.isManagedExternally else { return }
        let list = names ?? entry.upstreamNew ?? []
        guard !list.isEmpty else { return }
        if fake {
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[i].upstreamNew = nil
            }
            say(L("已安装上游新增 \(list.count) 个（原型）"))
            return
        }
        if !skipConfirm, !confirmInstallUpstream(entry.name, names: list) { return }
        // 只挂 connected 的默认工具——未装的工具不因批量安装被静默建目录
        let linkTools = tools.filter { $0.defaultTarget && $0.connected }
        guard !updatingIds.contains(entry.id) else {
            say(L("\(entry.name) 正在更新中，稍候再操作")); return
        }
        updatingIds.insert(entry.id)
        let fsCopy = fs
        Task { [weak self] in
            let result: Result<[String], Error> = await Task.detached {
                do { return .success(try fsCopy.installUpstreamMembers(entry, names: list, linkTools: linkTools)) }
                catch { return .failure(error) }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.updatingIds.remove(entry.id)
                switch result {
                case .success(let installed):
                    plog.info("安装上游新增 \(entry.name, privacy: .public)：\(installed.joined(separator: ","), privacy: .public)")
                    self.refresh()
                    if installed.isEmpty {
                        self.say(L("未能安装任何上游新增技能——检查源是否仍包含这些目录"))
                    } else {
                        let tail = installed.count > 4 ? "…" : ""
                        let head = installed.prefix(4).joined(separator: L("、"))
                        self.say(L("已安装上游新增 \(installed.count) 个：\(head)\(tail)"))
                        // flash 按条目 id 定位；上游新增装进 skills/（v2.18 起 id 类型化）
                        if let first = installed.first { self.flash(typedId(.skill, first)) }
                    }
                case .failure(let err):
                    self.sayError(L("安装上游新增失败：\(err.localizedDescription)"))
                }
            }
        }
    }

    /// 横幅「全部安装上游新增」：一次确认后逐源装
    func installAllUpstreamNew() {
        let targets = entriesWithUpstreamNew
        guard !targets.isEmpty else { return }
        let allNames = targets.flatMap { $0.upstreamNew ?? [] }
        if !confirmInstallUpstream(L("全部源"), names: allNames, totalHint: allNames.count) {
            return
        }
        for e in targets {
            installUpstreamNew(e, skipConfirm: true)
        }
    }

    private func confirmInstallUpstream(_ source: String, names: [String], totalHint: Int? = nil) -> Bool {
        if ProcessInfo.processInfo.environment["POPSKILL_AUTOCONFIRM"] == "1" { return true }
        let alert = NSAlert()
        let n = totalHint ?? names.count
        alert.messageText = L("安装上游新增的 \(n) 个技能？")
        let preview = names.sorted().prefix(6).joined(separator: L("、"))
        let more = names.count > 6 ? "…" : ""
        alert.informativeText = L("来自 \(source)：\(preview)\(more)。将写入 store 并按默认工具挂载。")
        alert.addButton(withTitle: L("安装"))
        alert.addButton(withTitle: L("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // ── 未托管目录导入（v2.1）─────────────────────────────

    func importUnmanaged() {
        guard !fake else { say(L("原型数据模式不可导入")); return }
        // 已知集合按类型化 id：skills/x 已托管不遮蔽未托管的 agents/x（v2.18）
        let known = Set(entries.flatMap { e in [e.id] + e.allCaps.map { typedId($0.layoutKind, $0.name) } })
        let found = fs.scanUnmanaged(tools: tools, knownIds: known)
        guard !found.isEmpty else { say(L("没有发现未托管的能力目录")); return }
        // 批量搬运是破坏性操作（原目录移进回收站），必须先让用户看清清单再确认——
        // 不能像过去那样点一下就静默把人家手装的技能都搬走
        guard confirmImport(Set(found.map(\.name)), kinds: Set(found.map(\.kind))) else { return }
        do {
            let r = try fs.importUnmanaged(found)
            plog.info("导入未托管目录 \(r.imported.joined(separator: ","), privacy: .public)（同名跳过 \(r.skippedSameName.count)）")
            refresh()
            // 分账如实报（v2.16：曾「发现 6 个、导入 4 个」，差的 2 个无解释）
            var msg = L("已导入 \(r.imported.count) 个未托管目录进 store（原目录已入回收站）")
            if !r.skippedSameName.isEmpty { msg += L("；\(r.skippedSameName.count) 个因同名跳过") }
            say(msg)
        } catch {
            sayError(L("导入中断：\(error.localizedDescription)——已导入的保留，重开设置页可续导剩余项"))
        }
    }

    /// 收编确认弹窗（onboarding 与设置页导入共用）：列清单 + 说清后果，POPSKILL_AUTOCONFIRM=1 跳过（E2E）
    private func confirmImport(_ names: Set<String>, kinds: Set<CapType> = [.skill]) -> Bool {
        if ProcessInfo.processInfo.environment["POPSKILL_AUTOCONFIRM"] == "1" { return true }
        let alert = NSAlert()
        let kindHint = kinds.count > 1
            ? L("技能 / Agent / MCP / CLI")
            : (kinds.first.map { $0.rawValue } ?? "Skill")
        alert.messageText = L("发现 \(names.count) 个未托管的能力目录")
        alert.informativeText = L("在 Claude / Codex 的 \(kindHint) 目录里发现现有能力（如 \(names.sorted().prefix(3).joined(separator: L("、")))…）。导入 store 统一管理，原位替换为 symlink？原目录会进 store 回收站，可恢复。")
        alert.addButton(withTitle: L("导入 \(names.count) 个"))
        alert.addButton(withTitle: L("暂不"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 空态「扫描本地目录」= 新用户引导（v2.4.1）：
    /// ① 重扫 store；② store 仍为空则扫工具目录里的未托管技能，确认后收编建链。
    func scanLocalForOnboarding() {
        refresh()
        guard entries.isEmpty else {
            say(L("扫描完成：发现 \(stats.total) 项能力"))
            return
        }
        let found = fs.scanUnmanaged(tools: tools, knownIds: [])
        guard !found.isEmpty else {
            say(L("store 为空，工具目录里也没有发现技能——点「+ 添加」装第一个"))
            return
        }
        guard confirmImport(Set(found.map(\.name)), kinds: Set(found.map(\.kind))) else { return }
        do {
            let r = try fs.importUnmanaged(found)
            plog.info("空态收编 \(r.imported.joined(separator: ","), privacy: .public)")
            refresh()
            say(L("已导入 \(r.imported.count) 个技能进 store 并建链——这就是你的能力矩阵"))
        } catch {
            sayError(L("导入中断：\(error.localizedDescription)——已导入的保留，重试可续导剩余项"))
        }
    }

    // ── 安装 / 移除 ───────────────────────────────────────

    func resolveSource(_ url: String) async throws -> StoreFS.ResolvedSource {
        if fake {
            // 原型行为：任意 URL → 单项 Skill 假数据
            let name = url.split(separator: "/").last.map(String.init) ?? "new-skill"
            return StoreFS.ResolvedSource(
                url: url, kind: SourceKind.of(url), entryName: name, isBundle: false,
                items: [StoreFS.PlanItem(name: name, type: .skill, desc: "从源 manifest 读取的描述", version: "1.0.0", tokens: 9200)],
                stagingDir: URL(fileURLWithPath: "/tmp"), version: "1.0.0")
        }
        let fsCopy = fs
        return try await Task.detached { try fsCopy.resolve(url) }.value
    }

    func install(_ src: StoreFS.ResolvedSource, targets: [String: Bool]) {
        let linkTools = tools.filter { targets[$0.id] == true }
        if fake {
            var cap = Capability(id: src.entryName, name: src.entryName, type: .skill,
                                 desc: src.items.first?.desc ?? "", version: src.version, author: nil,
                                 tokens: src.items.first?.tokens ?? 0, dirURL: URL(fileURLWithPath: "/tmp"))
            for t in tools { cap.links[t.id] = targets[t.id] == true ? .on : .off }
            entries.insert(Entry(id: src.entryName, cap: cap, children: nil, sourceUrl: src.url), at: 0)
            sheet = nil
            flash(src.entryName)
            say(linkTools.isEmpty ? L("已保存 \(src.entryName) 到 store") : L("已安装 \(src.entryName) 并链接到 \(linkTools.count) 个工具"))
            return
        }
        // 未装工具确认（v2.16：添加流程曾绕过矩阵格的同款防线，静默建出 ~/.codex）
        for t in linkTools where !t.connected {
            guard confirmMountUnconnected(t) else { return }
        }
        guard !installing else { return }
        installing = true
        installError = nil
        let fsCopy = fs
        // 后台执行（v2.16：曾在主线程同步 copyItem，大仓安装期间整个 UI 卡死）
        Task { [weak self] in
            let result: Result<Void, Error> = await Task.detached {
                do { try fsCopy.install(src, linkTools: linkTools); return .success(()) }
                catch { return .failure(error) }
            }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.installing = false
                switch result {
                case .success:
                    plog.info("安装 \(src.entryName, privacy: .public) ← \(src.url, privacy: .public)，链 \(linkTools.count) 个工具")
                    self.refresh()
                    self.sheet = nil
                    self.flash(typedId(src.isBundle ? .bundle : .skill, src.entryName))
                    self.say(linkTools.isEmpty ? L("已保存 \(src.entryName) 到 store") : L("已安装 \(src.entryName) 并链接到 \(linkTools.count) 个工具"))
                case .failure(let error):
                    // 驻留在计划页（v2.16：曾只有 6 秒 toast，消失后零线索）；同名冲突给出路
                    if case StoreError.alreadyExists = error {
                        self.installError = L("store 已有同名条目「\(src.entryName)」。想换新版：回主界面对它「检查更新」；确要重装：先移除旧的（会进回收站）再回来安装。")
                    } else {
                        self.installError = L("安装 \(src.entryName) 失败：\(error.localizedDescription)")
                    }
                    self.sayError(self.installError!)
                }
            }
        }
    }

    func removeEntry(_ entry: Entry) {
        guard !entry.isManagedExternally else {
            say(L("Marketplace 插件由 Claude Code 管理——在 Claude Code 里用 /plugin 卸载"))
            return
        }
        guard !updatingIds.contains(entry.id) else {
            say(L("\(entry.name) 正在更新中，稍候再操作"))
            return
        }
        let alert = NSAlert()
        alert.messageText = L("移除 \(entry.name)？")
        alert.informativeText = entry.isBundle
            ? L("套装连同 \(entry.children?.count ?? 0) 个子项的 store 副本与全部 symlink 都会清理（store 副本进回收站，可恢复）。")
            : L("store 副本与全部 symlink 都会清理（store 副本进回收站，可恢复）。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("移除"))
        alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if fake {
            entries.removeAll { $0.id == entry.id }
        } else {
            do {
                try fs.removeEntry(entry, tools: tools)
                plog.info("移除 \(entry.name, privacy: .public)（store 副本入回收站）")
                refresh()
            } catch {
                sayError(L("移除 \(entry.name) 失败：\(error.localizedDescription)"))
                return
            }
        }
        say(L("store 副本与全部 symlink 已清理"))
    }

    // ── 设置 ─────────────────────────────────────────────

    func toggleAutoUpdate(_ entryId: String) {
        guard let i = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[i].autoUpdate.toggle()
        guard !fake else { return }
        let on = entries[i].autoUpdate
        // meta 键一律 entry.id（v2.18）：v2.16 曾因「写 id 读 repoName」两头不一致
        // 让套装自动更新从未生效，当时统一到 name；类型化身份后 id 成为唯一读写键，
        // 源式套装头键即 "src:<归拢键>"，扫描回读同键，歧义根除
        let id = entries[i].id
        fs.mutateMeta { meta in
            var m = meta.entries[id] ?? StoreMeta.EntryMeta()
            m.autoUpdate = on
            meta.entries[id] = m
        }
    }

    func toggleDefaultTarget(_ toolId: String) {
        guard let i = tools.firstIndex(where: { $0.id == toolId }) else { return }
        tools[i].defaultTarget.toggle()
        guard !fake else { return }
        let on = tools[i].defaultTarget
        fs.mutateMeta { meta in
            var m = meta.tools[toolId] ?? StoreMeta.ToolMeta()
            m.defaultTarget = on
            meta.tools[toolId] = m
        }
    }

    // ── 回收站（v2.8）─────────────────────────────────────

    func restoreTrashItem(_ item: StoreFS.TrashItem) {
        do {
            try fs.restoreFromTrash(item)
            plog.info("回收站恢复 \(item.name, privacy: .public)")
            refresh()
            say(L("已恢复 \(item.name) 到 store——按需重新链接工具"))
        } catch {
            sayError(L("恢复 \(item.name) 失败：\(error.localizedDescription)"))
        }
    }

    func openTrash() {
        let t = fs.trashURL
        if !FileManager.default.fileExists(atPath: t.path) {
            try? FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(t)
    }

    /// 打开来源链接——按类型规范成真网址，别再把 `npm:@x/y` 直接拼成
    /// `https://npm:@x/y` 这种畸形 URL 点了跳不动（用户实测发现）。
    func openSourceLink(_ raw: String) {
        let url = raw.trimmingCharacters(in: .whitespaces)
        if SourceKind.of(url) == .local {
            // 本地源：在访达里定位目录，而不是当网址打开
            let dir = URL(fileURLWithPath: NSString(string: url).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: dir.path) {
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            }
            return
        }
        if let web = StoreFS.sourceWebURL(url) { NSWorkspace.shared.open(web) }
        else { say(L("无法打开来源链接：\(url)")) }
    }

    // ── 反馈渠道（v2.8：崩了/错了至少有条路找到作者）───────

    func reportIssue() {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var comps = URLComponents(string: "https://github.com/maojiebc/majia-Popskill/issues/new")!
        comps.queryItems = [URLQueryItem(name: "body", value: L("""
        App: Popskill v\(popskillVersion)
        macOS: \(os)

        <!-- 描述问题。若 app 崩溃过，请附上 ~/Library/Logs/DiagnosticReports 里最新的 Popskill-*.ips 文件 -->

        """))]
        if let u = comps.url { NSWorkspace.shared.open(u) }
    }

    // ── 打开 ─────────────────────────────────────────────

    func openInEditor(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openStore() {
        NSWorkspace.shared.activateFileViewerSelecting([fs.env.storeRoot])
    }

    // ── 定时任务面板（v2.9）────────────────────────────────
    // 只读解析 launchd/crontab；写操作仅 launchctl kickstart/unload/load，全部先确认。

    private let sched = SchedEngine()

    func reloadSched() {
        guard !schedLoading else { return }
        schedLoading = true
        let engine = sched
        let notes = fs.loadMeta().schedNotes ?? [:]
        Task.detached { [weak self] in
            let tasks = engine.scan(notes: notes)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.schedTasks = tasks
                self.schedLoading = false
            }
        }
    }

    /// 保存任务人话备注（空串 = 清除），立即回写内存镜像
    func schedSaveNote(_ task: SchedTask, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        fs.saveSchedNote(task.label, note: trimmed)
        if let i = schedTasks.firstIndex(where: { $0.id == task.id }) {
            schedTasks[i].note = trimmed.isEmpty ? nil : trimmed
        }
    }

    func schedOpenLog(_ task: SchedTask) {
        guard let path = task.logPath else { return }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            // 日志可能按天滚动（update-skills-YYYYMMDD.log）：plist 写的固定名不在时开所在目录
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    func schedKickstart(_ task: SchedTask) {
        let restart = task.behavior == .daemon
        guard schedConfirm(
            title: restart ? L("重启 \(task.displayName)？") : L("立刻运行 \(task.displayName)？"),
            info: restart ? L("等价于 launchctl kickstart -k——杀掉旧进程重新拉起。任务输出看它自己的日志。")
                          : L("等价于 launchctl kickstart -k——不等下次调度时间，现在就跑一遍。任务输出看它自己的日志。"),
            button: restart ? L("重启") : L("跑一次")
        ) else { return }
        schedRun(task, doneToast: L("已触发 \(task.displayName)")) { try $0.kickstart($1) }
    }

    func schedSetLoaded(_ task: SchedTask, to on: Bool) {
        guard schedConfirm(
            title: on ? L("启用 \(task.displayName)？") : L("停用 \(task.displayName)？"),
            info: on ? L("launchctl load——按 plist 里的调度恢复运行。")
                     : L("launchctl unload——不再按时执行，plist 文件原样保留，随时可重新启用。"),
            button: on ? L("启用") : L("停用")
        ) else { return }
        schedRun(task, doneToast: on ? L("已启用 \(task.displayName)") : L("已停用 \(task.displayName)")) { try $0.setLoaded($1, to: on) }
    }

    private func schedRun(_ task: SchedTask, doneToast: String, _ op: @escaping (SchedEngine, SchedTask) throws -> Void) {
        guard !schedBusy.contains(task.id) else { return }
        schedBusy.insert(task.id)
        let engine = sched
        let notes = fs.loadMeta().schedNotes ?? [:]
        Task.detached { [weak self] in
            let result = Result { try op(engine, task) }
            // launchctl 状态变化（尤其 kickstart 的退出码）要一拍后才稳定
            try? await Task.sleep(for: .milliseconds(600))
            let tasks = engine.scan(notes: notes)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.schedBusy.remove(task.id)
                self.schedTasks = tasks
                switch result {
                case .success: self.say(doneToast)
                case .failure(let e): self.sayError(e.localizedDescription)
                }
            }
        }
    }

    private func schedConfirm(title: String, info: String, button: String) -> Bool {
        if ProcessInfo.processInfo.environment["POPSKILL_AUTOCONFIRM"] == "1" { return true }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: L("取消"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // ── fake 模式的内存变更（原型语义）─────────────────────

    private func mutateFake(capId: String, toolId: String, to: LinkStatus) {
        for (ei, e) in entries.enumerated() {
            if e.isBundle {
                for (ci, c) in (e.children ?? []).enumerated() where c.id == capId {
                    entries[ei].children?[ci].links[toolId] = to
                    return
                }
            } else if e.cap.id == capId {
                entries[ei].cap.links[toolId] = to
                return
            }
        }
    }
}
