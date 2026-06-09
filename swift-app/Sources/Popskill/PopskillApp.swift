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
                if model.fixTarget != nil { model.fixTarget = nil; return nil }
                if model.sheet != nil { model.sheet = nil; return nil }
                return event
            }
            if event.charactersIgnoringModifiers == "/",
               model.sheet == nil,
               !(NSApp.keyWindow?.firstResponder is NSTextView) {
                model.searchFocused = true
                return nil
            }
            return event
        }
    }
}
