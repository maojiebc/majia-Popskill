import Combine
import SwiftUI
import Sparkle

/// 退出保护：后台换版（applyUpdate/repull）进行中时延迟退出，等收尾再走——
/// 原子换版保证中断也不丢数据，但没必要把一次更新切成「备份完成、新版没落盘」。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.updatingIds.isEmpty else { return .terminateNow }
        Task { @MainActor in
            let deadline = ContinuousClock.now + .seconds(30)
            while let m = self.model, !m.updatingIds.isEmpty, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(200))
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct PopskillApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // 裸二进制（无 Info.plist feed）下不启动 updater，避免 debug 弹错
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
        updaterDelegate: nil, userDriverDelegate: nil
    )

    init() {
        // 产品决策是全亮色账本视觉。只靠 preferredColorScheme 锁不住 AppKit 层——
        // 深色模式下 NSAlert/Sparkle 弹窗/菜单会保持深色，与暖纸白主窗割裂
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        // 单窗口产品用 Window 而非 WindowGroup：系统自动去掉「新建窗口 ⌘N」。
        // 曾经 ⌘N 能开出第二个共享同一 model 的窗口，弹层在所有窗口重复渲染
        Window("Popskill", id: "main") {
            RootView()
                .environment(model)
                .onAppear {
                    appDelegate.model = model
                    if updaterController.updater.canCheckForUpdates || Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
                        model.checkAppUpdate = { [weak updaterController = updaterController] in
                            updaterController?.checkForUpdates(nil)
                        }
                        // Sparkle 把该偏好写进 user defaults，覆盖 Info.plist 烤入值
                        model.sparkleAutoCheckGet = { [weak updaterController = updaterController] in
                            updaterController?.updater.automaticallyChecksForUpdates ?? false
                        }
                        model.sparkleAutoCheckSet = { [weak updaterController = updaterController] in
                            updaterController?.updater.automaticallyChecksForUpdates = $0
                        }
                    }
                }
                .preferredColorScheme(.light)
                .tint(Ink.blue)
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("检查更新…") { updaterController.checkForUpdates(nil) }
            }
            // 标准 ⌘, ——设置一直在标题栏 ⚙ 里，但 mac 用户的手指头先去按 ⌘,
            // 添加弹层开着时不抢（已解析的安装计划不能被静默销毁）
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { if model.sheet == nil { model.sheet = .settings } }
                    .keyboardShortcut(",", modifiers: .command)
                Button("定时任务…") { if model.sheet == nil { model.sheet = .sched; model.reloadSched() } }
                    .keyboardShortcut("j", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Popskill 帮助") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/maojiebc/majia-Popskill#readme")!)
                }
            }
            // CLI 用户在终端动了 ~/.agents 后需要一条不重启的回家路。
            // 修复弹层/peek 先关——它们持有的快照在重扫后就过期了
            CommandGroup(after: .toolbar) {
                Button("刷新") {
                    model.fixTarget = nil
                    model.peekTarget = nil
                    model.refresh()
                    model.say("已重新扫描 store 与工具目录")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            // 弹层开着时不偷焦点给背后的搜索框
            CommandGroup(after: .textEditing) {
                Button("查找") { if model.sheet == nil { model.searchFocused = true } }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var keyMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Titlebar()
                    if model.isEmpty {
                        EmptyPane()
                    } else {
                        MainView()
                    }
                    StatusBar()
                }
                .background(Ink.window)

                // 修复弹层（带透明遮罩捕获关闭点击）
                if let target = model.fixTarget {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { model.fixTarget = nil }
                    ZStack(alignment: target.flip ? .bottomLeading : .topLeading) {
                        Color.clear
                        FixPopoverView(target: target, winSize: geo.size)
                    }
                }

                // 详情 peek（与修复弹层互斥，model.openFix/openPeek 保证）
                if let peek = model.peekTarget {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture { model.peekTarget = nil }
                    ZStack(alignment: peek.flip ? .bottomLeading : .topLeading) {
                        Color.clear
                        DetailPeekView(target: peek, winSize: geo.size)
                    }
                }

                // 弹层
                if model.sheet == .add {
                    AddSheet().transition(.opacity)
                } else if model.sheet == .settings {
                    SettingsSheet().transition(.opacity)
                } else if model.sheet == .sched {
                    SchedSheet().transition(.opacity)
                }

                // toast：底部居中
                if let toast = model.toast {
                    VStack {
                        Spacer()
                        ToastView(msg: toast, isError: model.toastIsError).padding(.bottom, 44)
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .animation(.easeOut(duration: 0.12), value: model.toast)
        .onGeometryChange(for: CGSize.self, of: \.size) { model.winSize = $0 }
        .onAppear { installKeyMonitor() }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m) }
        }
        // 回到前台自动重扫——目标用户天天在终端直接动 ~/.agents，
        // 「文件系统即数据库」的界面不能和磁盘脱节到要重启 app
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    /// `/` 聚焦搜索；Esc 关闭弹层/浮层
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {   // Esc
                if model.peekTarget != nil { model.peekTarget = nil; return nil }
                if model.fixTarget != nil { model.fixTarget = nil; return nil }
                if model.sheet != nil { model.sheet = nil; return nil }
                if model.kbFocusId != nil { model.kbFocusId = nil; return nil }
                return event
            }
            // 带 ⌘/⌥/⌃ 的组合键一律放行给系统/菜单——曾经 ⌘↑、⌥↓、⌘/ 全被吞掉
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.charactersIgnoringModifiers == "/",
               mods.subtracting(.shift).isEmpty,   // 德语等布局 / 在 ⇧7 上，shift 要留
               model.sheet == nil,
               !(NSApp.keyWindow?.firstResponder is NSTextView) {
                model.searchFocused = true
                return nil
            }
            // 键盘导航（PATCH-02）：弹层/浮层/输入框打开时不响应
            if mods.isEmpty, model.sheet == nil, model.fixTarget == nil, model.peekTarget == nil,
               !(NSApp.keyWindow?.firstResponder is NSTextView) {
                switch event.keyCode {
                case 125: model.kbMove(1); return nil          // ↓
                case 126: model.kbMove(-1); return nil         // ↑
                case 123: model.kbSetTool(model.kbToolIdx - 1); return model.kbFocusId == nil ? event : nil  // ←
                case 124: model.kbSetTool(model.kbToolIdx + 1); return model.kbFocusId == nil ? event : nil  // →
                case 49, 36:                                   // 空格 / 回车
                    if model.kbFocusId != nil { model.kbActivate(); return nil }
                    return event
                default: break
                }
            }
            return event
        }
    }
}
