import SwiftUI
import Sparkle

@main
struct PopskillApp: App {
    @State private var model = AppModel()
    // 裸二进制（无 Info.plist feed）下不启动 updater，避免 debug 弹错
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
        updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear {
                    if updaterController.updater.canCheckForUpdates || Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
                        model.checkAppUpdate = { [weak updaterController = updaterController] in
                            updaterController?.checkForUpdates(nil)
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
                }

                // toast：底部居中
                if let toast = model.toast {
                    VStack {
                        Spacer()
                        ToastView(msg: toast).padding(.bottom, 44)
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
            if event.charactersIgnoringModifiers == "/",
               model.sheet == nil,
               !(NSApp.keyWindow?.firstResponder is NSTextView) {
                model.searchFocused = true
                return nil
            }
            // 键盘导航（PATCH-02）：弹层/浮层/输入框打开时不响应
            if model.sheet == nil, model.fixTarget == nil, model.peekTarget == nil,
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
