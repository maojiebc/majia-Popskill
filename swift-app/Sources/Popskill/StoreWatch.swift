import CoreServices
import Foundation

// store 与工具链接目录的 FSEvents 监听（v2.15）。
//
// 目标用户天天在终端直接动 ~/.agents（npx skills add / rm -rf / ln -s），
// 之前界面只有两条回家路：⌘R 手动重扫、切前台自动重扫——app 开在旁边屏幕时
// 就是脱节的。现在磁盘一动，秒级自动跟上，「文件系统就是数据库」补全最后一环。
//
// 边界刻意收窄：
// - 只监听 store 根 + 各工具的 skills/agents/mcp/bin 链接目录。不监听 ~/.claude
//   整棵树——projects/ 和 history 每个 Claude 会话都在写，噪音是信号的百倍。
// - kFSEventStreamCreateFlagIgnoreSelf 滤掉本进程自己的写（toggle/install 已各自
//   refresh）；git/npm 子进程的写不算 self，但它们都发生在临时目录，不在监听范围。
// - 回调只负责去抖后通知，扫描仍走 AppModel.refresh()（幂等、毫秒级）。
final class StoreWatcher {
    private var stream: FSEventStreamRef?
    private(set) var watchedPaths: [String] = []
    private let latency: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "popskill.fsevents")

    /// latency = FSEvents 侧的合并窗口：终端一串 mv/ln 只触发一次（测试注入小值）
    init(latency: TimeInterval = 1.0, onChange: @escaping () -> Void) {
        self.latency = latency
        self.onChange = onChange
    }

    deinit { stop() }

    /// 幂等对齐监听集：目标路径里实际存在的那部分没变就不动流；
    /// 变了（工具目录新出现/store 换根）才重建。refresh 每次都调，必须便宜。
    func sync(paths: [String]) {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }.sorted()
        guard existing != watchedPaths else { return }
        stop()
        guard !existing.isEmpty else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<StoreWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &ctx, existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf)
        ) else { return }
        stream = s
        watchedPaths = existing
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        watchedPaths = []
    }
}
