import Foundation

// 定时任务面板引擎（v2.9）：launchd 用户级任务 + crontab 的只读解析。
// 缘起：majia-guanyuan 被 com.majia.update-skills 用旧缓存回滚（2026-06-12），
// 排查时发现「本机有哪些定时任务、什么时候跑、上次结果如何」没有可视化入口。
// 边界：plist 内容绝不写；写操作只有 launchctl load/unload/kickstart，UI 层确认后才到这。

struct SchedTask: Identifiable, Equatable {
    enum Kind: Equatable { case launchd, cron }
    let id: String              // launchd = Label；cron = "cron:<行号>"
    let kind: Kind
    let label: String           // launchd Label / cron 取脚本名
    let schedule: String        // 人话调度（"每天 06:00" / "常驻 daemon"…）
    let command: String         // 执行什么（完整命令行）
    let plistURL: URL?          // launchd plist 文件
    let logPath: String?        // StandardOutPath / cron 重定向目标
    var loaded: Bool            // launchctl 在册（cron 恒 true：在 crontab 里即生效）
    var lastExit: Int?          // launchctl list 第二列；非 0 = 上次失败
    var vendor: Bool            // 系统/第三方（默认折叠隐藏）

    var canOperate: Bool { kind == .launchd }
}

struct SchedEngine {
    let agentsDir: URL
    private let fm = FileManager.default

    init(agentsDir: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")) {
        self.agentsDir = agentsDir
    }

    /// 系统/第三方 app 自带任务的 Label 前缀——不是用户手工创建的，默认隐藏
    static let vendorPrefixes = [
        "com.apple.", "com.google.", "com.microsoft.", "com.adobe.",
        "io.github.clash", "com.tuxera.", "org.gpgtools.", "com.dropbox.",
        "com.oracle.", "us.zoom.", "com.tencent.",
    ]

    static func isVendor(_ label: String) -> Bool {
        let l = label.lowercased()
        return vendorPrefixes.contains { l.hasPrefix($0) }
    }

    // ── 扫描 ─────────────────────────────────────────────

    /// 全量扫描。launchctl/crontab 输出可注入（测试不碰真系统）。
    func scan(launchctlOut: String? = nil, crontabOut: String? = nil) -> [SchedTask] {
        let lcOut = launchctlOut ?? runProcess("/bin/launchctl", ["list"], timeout: 30).out
        let loadedMap = Self.parseLaunchctlList(lcOut)
        var tasks: [SchedTask] = []

        let plists = ((try? fm.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in plists {
            guard let data = try? Data(contentsOf: url),
                  var task = Self.parsePlist(data, url: url) else { continue }
            if let exit = loadedMap[task.label] {
                task.loaded = true
                task.lastExit = exit
            }
            tasks.append(task)
        }

        let cronText = crontabOut ?? runProcess("/usr/bin/crontab", ["-l"], timeout: 30).out
        tasks.append(contentsOf: Self.parseCrontab(cronText))
        return tasks
    }

    /// launchctl list 输出 → Label: 上次退出码。
    /// 行形如 "PID\tStatus\tLabel"，PID "-" 表示当前没在跑（但在册）。
    static func parseLaunchctlList(_ out: String) -> [String: Int?] {
        var map: [String: Int?] = [:]
        for line in out.split(separator: "\n").dropFirst() {   // 首行表头
            let cols = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard cols.count == 3 else { continue }
            map[String(cols[2])] = Int(cols[1])
        }
        return map
    }

    // ── plist 解析（只读） ─────────────────────────────────

    static func parsePlist(_ data: Data, url: URL?) -> SchedTask? {
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let label = dict["Label"] as? String else { return nil }
        let command = commandLine(dict)
        return SchedTask(
            id: label, kind: .launchd, label: label,
            schedule: describeSchedule(dict),
            command: command.isEmpty ? "—" : command,
            plistURL: url,
            logPath: dict["StandardOutPath"] as? String,
            loaded: false, lastExit: nil,
            vendor: isVendor(label)
        )
    }

    private static func commandLine(_ dict: [String: Any]) -> String {
        if let args = dict["ProgramArguments"] as? [String] { return args.joined(separator: " ") }
        if let prog = dict["Program"] as? String { return prog }
        return ""
    }

    /// 调度配置 → 人话。优先级：StartCalendarInterval > StartInterval > KeepAlive > RunAtLoad
    static func describeSchedule(_ dict: [String: Any]) -> String {
        if let cal = dict["StartCalendarInterval"] {
            let items: [[String: Int]]
            if let one = cal as? [String: Int] { items = [one] }
            else if let many = cal as? [[String: Int]] { items = many }
            else { items = [] }
            if !items.isEmpty {
                let parts = items.prefix(3).map(describeCalendar)
                let suffix = items.count > 3 ? " 等 \(items.count) 个时间点" : ""
                return parts.joined(separator: " / ") + suffix
            }
        }
        if let sec = dict["StartInterval"] as? Int, sec > 0 { return describeInterval(sec) }
        if let keep = dict["KeepAlive"] {
            if (keep as? Bool) == true || keep is [String: Any] { return "常驻 daemon" }
        }
        if (dict["RunAtLoad"] as? Bool) == true { return "登录自启" }
        return "未配置调度（手动）"
    }

    static func describeCalendar(_ c: [String: Int]) -> String {
        let weekdays = ["日", "一", "二", "三", "四", "五", "六", "日"]   // launchd: 0 和 7 都是周日
        var when = ""
        if let m = c["Month"] { when += "每年 \(m) 月" }
        if let d = c["Day"] { when += when.isEmpty ? "每月 \(d) 日" : " \(d) 日" }
        if let w = c["Weekday"], w >= 0, w <= 7 { when += "每周\(weekdays[w])" }
        if when.isEmpty { when = c["Hour"] != nil ? "每天" : "" }
        if let h = c["Hour"] {
            when += String(format: " %02d:%02d", h, c["Minute"] ?? 0)
        } else if let min = c["Minute"] {
            when += when.isEmpty ? "每小时第 \(min) 分" : " 每小时第 \(min) 分"
        }
        return when.trimmingCharacters(in: .whitespaces)
    }

    static func describeInterval(_ sec: Int) -> String {
        if sec % 3600 == 0 { return "每 \(sec / 3600) 小时" }
        if sec % 60 == 0 { return "每 \(sec / 60) 分钟" }
        return "每 \(sec) 秒"
    }

    // ── crontab 解析（只读） ───────────────────────────────

    static func parseCrontab(_ text: String) -> [SchedTask] {
        var tasks: [SchedTask] = []
        for (n, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 6 else { continue }   // 环境变量行（FOO=bar）等跳过
            guard fields[0].first.map({ "0123456789*/,-".contains($0) }) == true else { continue }
            let timing = Array(fields[0..<5])
            let rawCmd = fields[5...].joined(separator: " ")
            let (cmd, log) = splitRedirect(rawCmd)
            let name = cmd.split(separator: " ").first.map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? cmd
            tasks.append(SchedTask(
                id: "cron:\(n)", kind: .cron, label: name,
                schedule: describeCron(timing),
                command: cmd, plistURL: nil, logPath: log,
                loaded: true, lastExit: nil, vendor: false
            ))
        }
        return tasks
    }

    /// 剥掉重定向：命令本体 + 日志目标（/dev/null 不算日志）
    static func splitRedirect(_ raw: String) -> (cmd: String, log: String?) {
        guard let r = raw.range(of: #"\s*>>?\s*"#, options: .regularExpression) else { return (raw, nil) }
        let cmd = String(raw[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
        var rest = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let sp = rest.firstIndex(of: " ") { rest = String(rest[..<sp]) }   // 去掉尾随 2>&1 等
        return (cmd, rest.isEmpty || rest == "/dev/null" ? nil : rest)
    }

    /// cron 5 字段 → 人话；翻不动的原样返回
    static func describeCron(_ f: [String]) -> String {
        guard f.count == 5 else { return f.joined(separator: " ") }
        let (min, hour, dom, mon, dow) = (f[0], f[1], f[2], f[3], f[4])
        let weekdays = ["日", "一", "二", "三", "四", "五", "六", "日"]
        func t(_ h: String, _ m: String) -> String? {
            guard let hi = Int(h), let mi = Int(m) else { return nil }
            return String(format: "%02d:%02d", hi, mi)
        }
        if dom == "*", mon == "*" {
            if dow == "*" {
                if let time = t(hour, min) { return "每天 \(time)" }
                if hour.hasPrefix("*/"), let step = Int(hour.dropFirst(2)), let mi = Int(min) {
                    return "每 \(step) 小时的第 \(mi) 分"
                }
                if hour == "*", let mi = Int(min) { return "每小时第 \(mi) 分" }
                if hour == "*", min.hasPrefix("*/"), let step = Int(min.dropFirst(2)) { return "每 \(step) 分钟" }
            } else if let w = Int(dow), w >= 0, w <= 7, let time = t(hour, min) {
                return "每周\(weekdays[w]) \(time)"
            }
        }
        if mon == "*", dow == "*", let d = Int(dom), let time = t(hour, min) { return "每月 \(d) 日 \(time)" }
        return f.joined(separator: " ")
    }

    // ── 操作（仅 launchd；调用方负责确认） ──────────────────

    enum SchedError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let s) = self { return s }; return nil }
    }

    func kickstart(_ task: SchedTask) throws {
        guard task.kind == .launchd else { throw SchedError.failed("cron 任务请在终端手动执行") }
        let r = runProcess("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(task.label)"], timeout: 30)
        guard r.status == 0 else { throw SchedError.failed(r.err.isEmpty ? "launchctl kickstart 退出码 \(r.status)" : r.err) }
    }

    func setLoaded(_ task: SchedTask, to on: Bool) throws {
        guard let plist = task.plistURL else { throw SchedError.failed("没有 plist 路径") }
        let r = runProcess("/bin/launchctl", [on ? "load" : "unload", plist.path], timeout: 30)
        guard r.status == 0 else { throw SchedError.failed(r.err.isEmpty ? "launchctl 退出码 \(r.status)" : r.err) }
    }
}
