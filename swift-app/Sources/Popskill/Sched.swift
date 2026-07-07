import Foundation

// 定时任务面板引擎（v2.9 引入，v2.10 人性化重做）：launchd 用户级任务 + crontab 的只读解析。
// 缘起：majia-guanyuan 被 com.majia.update-skills 用旧缓存回滚（2026-06-12），
// 排查时发现「本机有哪些定时任务、什么时候跑、上次结果如何」没有可视化入口。
// v2.10 视角翻转：按行为分组（定时跑/常驻/自启）、下次运行倒计时排序、人话名 + 备注、
// 上次运行时间从日志 mtime 推断——面板主角是「人关心的三件事」，不是 plist 字段。
// 边界：plist 内容绝不写；写操作只有 launchctl load/unload/kickstart，UI 层确认后才到这。

struct SchedTask: Identifiable, Equatable {
    enum Kind: Equatable { case launchd, cron }
    /// 行为分组——人的心智模型，不是实现细节
    enum Behavior: Equatable {
        case timed       // 按时间跑（StartCalendarInterval / StartInterval / cron）
        case daemon      // 常驻后台（KeepAlive）
        case loginItem   // 登录自启（仅 RunAtLoad）
        case manual      // 没配调度
    }
    let id: String              // launchd = Label；cron = "cron:<行号>"
    let kind: Kind
    let label: String           // launchd Label / cron 取脚本名
    let behavior: Behavior
    let schedule: String        // 人话调度规则（"每天 05:00" / "每 6 小时的第 17 分"…）
    let command: String         // 完整命令行（详情/副行截断展示）
    let plistURL: URL?
    let logPath: String?        // StandardOutPath / cron 重定向目标
    var loaded: Bool
    var lastExit: Int?          // launchctl list 第二列；非 0 = 上次失败
    var pid: Int?               // 在跑的进程；daemon 活着的标志
    var nextFire: Date?         // 下次触发（timed 才有；StartInterval 无锚点为 nil）
    var lastRun: Date?          // 上次运行（日志 mtime 推断，没有日志为 nil）
    var note: String?           // 用户人话备注（存 .popskill.json，不动 plist）
    var vendor: Bool

    var canOperate: Bool { kind == .launchd }
    /// 展示名：备注 > 美化 label
    var displayName: String { note ?? SchedEngine.prettyLabel(label) }
    /// daemon 应活未活（KeepAlive 在册但没有进程）= 停摆
    var stalled: Bool { behavior == .daemon && loaded && pid == nil }
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

    /// label 美化：去 reverse-DNS 噪音段（com.majia.update-skills → update-skills）。
    /// 第二段是短 vendor 名（majia/agents/github ≤ 6 字符）才一起去；像 claude-to-im
    /// 这种产品名当段名的保留——裁成光杆 "bridge" 反而没人认识。备注可覆盖一切。
    static func prettyLabel(_ label: String) -> String {
        guard label.contains("."), !label.contains(" ") else { return label }
        let parts = label.split(separator: ".")
        guard parts.count >= 3, ["com", "org", "io", "net", "us", "cn", "dev", "app"].contains(parts[0].lowercased()) else {
            return label
        }
        let drop = parts[1].count <= 6 ? 2 : 1
        return String(parts.dropFirst(drop).joined(separator: "."))
    }

    // ── 扫描 ─────────────────────────────────────────────

    /// 全量扫描。launchctl/crontab 输出与备注可注入（测试不碰真系统）。
    func scan(launchctlOut: String? = nil, crontabOut: String? = nil,
              notes: [String: String] = [:], now: Date = Date()) -> [SchedTask] {
        let lcOut = launchctlOut ?? runProcess("/bin/launchctl", ["list"], timeout: 30).out
        let loadedMap = Self.parseLaunchctlList(lcOut)
        var tasks: [SchedTask] = []

        let plists = ((try? fm.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "plist" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in plists {
            guard let data = try? Data(contentsOf: url),
                  var task = Self.parsePlist(data, url: url, now: now) else { continue }
            if let st = loadedMap[task.label] {
                task.loaded = true
                task.lastExit = st.exit
                task.pid = st.pid
            }
            task.note = notes[task.label]
            task.lastRun = Self.logMTime(task.logPath)
            tasks.append(task)
        }

        let cronText = crontabOut ?? runProcess("/usr/bin/crontab", ["-l"], timeout: 30).out
        var crons = Self.parseCrontab(cronText, now: now)
        for i in crons.indices {
            crons[i].note = notes[crons[i].label]
            crons[i].lastRun = Self.logMTime(crons[i].logPath)
        }
        tasks.append(contentsOf: crons)
        return tasks
    }

    /// launchctl list 输出 → Label: (pid, 上次退出码)。
    /// 行形如 "PID\tStatus\tLabel"，PID "-" 表示当前没在跑（但在册）。
    static func parseLaunchctlList(_ out: String) -> [String: (pid: Int?, exit: Int?)] {
        var map: [String: (pid: Int?, exit: Int?)] = [:]
        for line in out.split(separator: "\n").dropFirst() {   // 首行表头
            let cols = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard cols.count == 3 else { continue }
            map[String(cols[2])] = (Int(cols[0]), Int(cols[1]))
        }
        return map
    }

    /// 上次运行时间：日志文件 mtime（launchd/cron 都不直接提供 last run，这是最实用的代理）
    static func logMTime(_ path: String?) -> Date? {
        guard let path else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        return (try? FileManager.default.attributesOfItem(atPath: expanded))?[.modificationDate] as? Date
    }

    // ── plist 解析（只读） ─────────────────────────────────

    static func parsePlist(_ data: Data, url: URL?, now: Date = Date()) -> SchedTask? {
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let label = dict["Label"] as? String else { return nil }
        let command = commandLine(dict)
        let behavior = classify(dict)
        return SchedTask(
            id: label, kind: .launchd, label: label,
            behavior: behavior,
            schedule: describeSchedule(dict),
            command: command.isEmpty ? "—" : command,
            plistURL: url,
            logPath: dict["StandardOutPath"] as? String,
            loaded: false, lastExit: nil, pid: nil,
            nextFire: behavior == .timed ? nextFire(dict, after: now) : nil,
            lastRun: nil, note: nil,
            vendor: isVendor(label)
        )
    }

    /// 行为归组。优先级与 describeSchedule 一致：时间调度 > KeepAlive > RunAtLoad
    static func classify(_ dict: [String: Any]) -> SchedTask.Behavior {
        if dict["StartCalendarInterval"] != nil { return .timed }
        if let sec = dict["StartInterval"] as? Int, sec > 0 { return .timed }
        if let keep = dict["KeepAlive"], (keep as? Bool) == true || keep is [String: Any] { return .daemon }
        if (dict["RunAtLoad"] as? Bool) == true { return .loginItem }
        return .manual
    }

    private static func commandLine(_ dict: [String: Any]) -> String {
        if let args = dict["ProgramArguments"] as? [String] { return args.joined(separator: " ") }
        if let prog = dict["Program"] as? String { return prog }
        return ""
    }

    /// 调度配置 → 人话规则。优先级：StartCalendarInterval > StartInterval > KeepAlive > RunAtLoad
    static func describeSchedule(_ dict: [String: Any]) -> String {
        if let cal = dict["StartCalendarInterval"] {
            let items = calendarItems(cal)
            if !items.isEmpty {
                let parts = items.prefix(3).map(describeCalendar)
                let suffix = items.count > 3 ? L(" 等 \(items.count) 个时间点") : ""
                return parts.joined(separator: " / ") + suffix
            }
        }
        if let sec = dict["StartInterval"] as? Int, sec > 0 { return describeInterval(sec) }
        if let keep = dict["KeepAlive"] {
            if (keep as? Bool) == true || keep is [String: Any] { return L("常驻 daemon") }
        }
        if (dict["RunAtLoad"] as? Bool) == true { return L("登录自启") }
        return L("未配置调度（手动）")
    }

    private static func calendarItems(_ cal: Any) -> [[String: Int]] {
        if let one = cal as? [String: Int] { return [one] }
        if let many = cal as? [[String: Int]] { return many }
        return []
    }

    /// 整词取词（"每周一" 而非 "每周"+"一"），翻译才有完整语序；launchd: 0 和 7 都是周日
    static let weeklyWords = [L("每周日"), L("每周一"), L("每周二"), L("每周三"),
                              L("每周四"), L("每周五"), L("每周六"), L("每周日")]

    static func describeCalendar(_ c: [String: Int]) -> String {
        var when = ""
        if let m = c["Month"] { when += L("每年 \(m) 月") }
        if let d = c["Day"] { when += when.isEmpty ? L("每月 \(d) 日") : " " + L("\(d) 日") }
        if let w = c["Weekday"], w >= 0, w <= 7 { when += weeklyWords[w] }
        if when.isEmpty { when = c["Hour"] != nil ? L("每天") : "" }
        if let h = c["Hour"] {
            when += String(format: " %02d:%02d", h, c["Minute"] ?? 0)
        } else if let min = c["Minute"] {
            let part = L("每小时第 \(min) 分")
            when += when.isEmpty ? part : " " + part
        }
        return when.trimmingCharacters(in: .whitespaces)
    }

    static func describeInterval(_ sec: Int) -> String {
        if sec % 3600 == 0 { return L("每 \(sec / 3600) 小时") }
        if sec % 60 == 0 { return L("每 \(sec / 60) 分钟") }
        return L("每 \(sec) 秒")
    }

    // ── 下次触发计算（纯函数，注入 now） ────────────────────

    /// launchd plist 的下次触发。StartCalendarInterval 逐分钟扫描匹配（launchd 语义：
    /// 缺省字段=通配）；StartInterval 没有公开锚点，返回 nil（UI 退回显示调度规则）。
    static func nextFire(_ dict: [String: Any], after now: Date) -> Date? {
        guard let cal = dict["StartCalendarInterval"] else { return nil }   // 没有 calendar 不能给空字典兜底——空字典=全通配=每分钟
        let items = calendarItems(cal)
        guard !items.isEmpty else { return nil }
        return items.compactMap { nextCalendarFire($0, after: now) }.min()
    }

    static func nextCalendarFire(_ c: [String: Int], after now: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        // 从下一整分起逐分钟找第一个全字段匹配，封顶 366 天
        var t = cal.date(bySetting: .second, value: 0, of: now.addingTimeInterval(60)) ?? now
        // bySetting 可能进位到下一分钟边界以外，统一拉回整分
        t = cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute], from: t)) ?? t
        let limit = now.addingTimeInterval(366 * 86400)
        while t <= limit {
            let comp = cal.dateComponents([.month, .day, .weekday, .hour, .minute], from: t)
            let weekday = (comp.weekday! - 1)   // Calendar: 1=周日 → launchd: 0=周日
            if (c["Month"].map { $0 == comp.month } ?? true),
               (c["Day"].map { $0 == comp.day } ?? true),
               (c["Weekday"].map { $0 % 7 == weekday } ?? true),   // launchd 0/7 都是周日
               (c["Hour"].map { $0 == comp.hour } ?? true),
               (c["Minute"].map { $0 == comp.minute } ?? true) {
                return t
            }
            // 跳跃优化：时分都不匹配时按小时/天推进，避免 53 万次逐分钟迭代
            if let h = c["Hour"], h != comp.hour {
                t = cal.date(byAdding: .hour, value: 1, to: t)!
                t = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: t))!
            } else {
                t = cal.date(byAdding: .minute, value: 1, to: t)!
            }
        }
        return nil
    }

    /// cron 5 字段的下次触发。支持 * 、*/n、单值、逗号列表、a-b 范围；
    /// 标准语义：day-of-month 与 day-of-week 都受限时取 OR。
    static func nextCronFire(_ f: [String], after now: Date) -> Date? {
        guard f.count == 5 else { return nil }
        func match(_ field: String, _ v: Int) -> Bool {
            if field == "*" { return true }
            for part in field.split(separator: ",") {
                let p = String(part)
                if p.hasPrefix("*/"), let step = Int(p.dropFirst(2)), step > 0 { if v % step == 0 { return true } }
                else if p.contains("-") {
                    let ab = p.split(separator: "-").compactMap { Int($0) }
                    if ab.count == 2, v >= ab[0], v <= ab[1] { return true }
                } else if Int(p) == v { return true }
                else if p == "7", v == 0 { return true }   // cron 周日 0/7 等价
            }
            return false
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var t = cal.date(from: cal.dateComponents([.year, .month, .day, .hour, .minute],
                                                  from: now.addingTimeInterval(60))) ?? now
        let limit = now.addingTimeInterval(366 * 86400)
        let domAny = f[2] == "*", dowAny = f[4] == "*"
        while t <= limit {
            let comp = cal.dateComponents([.month, .day, .weekday, .hour, .minute], from: t)
            let dow = comp.weekday! - 1
            let domOk = match(f[2], comp.day!), dowOk = match(f[4], dow)
            // 标准 cron：dom 与 dow 都受限 → OR；否则 AND（受限的那个生效）
            let dayOk = (!domAny && !dowAny) ? (domOk || dowOk) : (domOk && dowOk)
            if match(f[0], comp.minute!), match(f[1], comp.hour!), dayOk, match(f[3], comp.month!) {
                return t
            }
            if !match(f[1], comp.hour!) {
                t = cal.date(byAdding: .hour, value: 1, to: t)!
                t = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: t))!
            } else {
                t = cal.date(byAdding: .minute, value: 1, to: t)!
            }
        }
        return nil
    }

    // ── 人话时间格式化（注入 now，UI 与测试共用） ─────────────

    /// 单日历日名（humanNext 用，"周一 10:17"），launchd weekly 全词另存 weeklyWords
    static let weekdayWords = [L("周日"), L("周一"), L("周二"), L("周三"), L("周四"), L("周五"), L("周六")]

    /// 下次触发 → "32 分钟后 · 23:41" / "7 小时后 · 明天 05:00" / "周一 10:17"
    static func humanNext(_ date: Date, now: Date = Date()) -> String {
        let sec = date.timeIntervalSince(now)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let hm = String(format: "%02d:%02d", cal.component(.hour, from: date), cal.component(.minute, from: date))
        let dayWord: String
        if cal.isDate(date, inSameDayAs: now) { dayWord = "" }
        else if let tm = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tm) { dayWord = L("明天") + " " }
        else if let at = cal.date(byAdding: .day, value: 2, to: now), cal.isDate(date, inSameDayAs: at) { dayWord = L("后天") + " " }
        else {
            let wd = weekdayWords[cal.component(.weekday, from: date) - 1]
            dayWord = sec < 7 * 86400 ? wd + " " : "\(cal.component(.month, from: date))/\(cal.component(.day, from: date)) "
        }
        let rel: String
        if sec < 90 * 60 { rel = L("\(max(1, Int(sec / 60))) 分钟后") }
        else if sec < 48 * 3600 { rel = L("\(Int(sec / 3600)) 小时后") }
        else { rel = L("\(Int(sec / 86400)) 天后") }
        return "\(rel) · \(dayWord)\(hm)"
    }

    /// 上次运行 → "今天 05:00" / "昨天 23:41" / "6/10 14:00"
    static func humanLast(_ date: Date, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let hm = String(format: "%02d:%02d", cal.component(.hour, from: date), cal.component(.minute, from: date))
        if cal.isDate(date, inSameDayAs: now) { return L("今天 \(hm)") }
        if let yd = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(date, inSameDayAs: yd) { return L("昨天 \(hm)") }
        return "\(cal.component(.month, from: date))/\(cal.component(.day, from: date)) \(hm)"
    }

    // ── crontab 解析（只读） ───────────────────────────────

    static func parseCrontab(_ text: String, now: Date = Date()) -> [SchedTask] {
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
                behavior: .timed,
                schedule: describeCron(timing),
                command: cmd, plistURL: nil, logPath: log,
                loaded: true, lastExit: nil, pid: nil,
                nextFire: nextCronFire(timing, after: now),
                lastRun: nil, note: nil, vendor: false
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

    /// cron 5 字段 → 人话规则；翻不动的原样返回
    static func describeCron(_ f: [String]) -> String {
        guard f.count == 5 else { return f.joined(separator: " ") }
        let (min, hour, dom, mon, dow) = (f[0], f[1], f[2], f[3], f[4])
        func t(_ h: String, _ m: String) -> String? {
            guard let hi = Int(h), let mi = Int(m) else { return nil }
            return String(format: "%02d:%02d", hi, mi)
        }
        if dom == "*", mon == "*" {
            if dow == "*" {
                if let time = t(hour, min) { return L("每天 \(time)") }
                if hour.hasPrefix("*/"), let step = Int(hour.dropFirst(2)), let mi = Int(min) {
                    return L("每 \(step) 小时的第 \(mi) 分")
                }
                if hour == "*", let mi = Int(min) { return L("每小时第 \(mi) 分") }
                if hour == "*", min.hasPrefix("*/"), let step = Int(min.dropFirst(2)) { return L("每 \(step) 分钟") }
            } else if let w = Int(dow), w >= 0, w <= 7, let time = t(hour, min) {
                return weeklyWords[w] + " " + time   // cron 周日 0/7 等价
            }
        }
        if mon == "*", dow == "*", let d = Int(dom), let time = t(hour, min) { return L("每月 \(d) 日 \(time)") }
        return f.joined(separator: " ")
    }

    // ── 操作（仅 launchd；调用方负责确认） ──────────────────

    enum SchedError: LocalizedError {
        case failed(String)
        var errorDescription: String? { if case .failed(let s) = self { return s }; return nil }
    }

    func kickstart(_ task: SchedTask) throws {
        guard task.kind == .launchd else { throw SchedError.failed(L("cron 任务请在终端手动执行")) }
        let r = runProcess("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(task.label)"], timeout: 30)
        guard r.status == 0 else { throw SchedError.failed(r.err.isEmpty ? L("launchctl kickstart 退出码 \(Int(r.status))") : r.err) }
    }

    func setLoaded(_ task: SchedTask, to on: Bool) throws {
        guard let plist = task.plistURL else { throw SchedError.failed(L("没有 plist 路径")) }
        let target = "gui/\(getuid())/\(task.label)"
        if on {
            // enable 先清掉 disable override（没有 override 时是 no-op），bootstrap 真正拉起
            _ = runProcess("/bin/launchctl", ["enable", target], timeout: 30)
            let r = runProcess("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plist.path], timeout: 30)
            guard r.status == 0 else { throw SchedError.failed(r.err.isEmpty ? L("launchctl 退出码 \(Int(r.status))") : r.err) }
        } else {
            // v2.16 修复：旧版 `unload`（无 -w、无 override）——plist 留在 LaunchAgents，
            // 下次登录 launchd 自动重载，「停用」的任务重启电脑就复活。
            // bootout 卸载当次 + disable 写 override 才是真停用；plist 本身仍原样保留。
            // bootout 对「本来就没加载」的任务会报错，以 disable 的结果为准
            let out = runProcess("/bin/launchctl", ["bootout", target], timeout: 30)
            let dis = runProcess("/bin/launchctl", ["disable", target], timeout: 30)
            guard dis.status == 0 else {
                let msg = [out.err, dis.err].filter { !$0.isEmpty }.joined(separator: "; ")
                throw SchedError.failed(msg.isEmpty ? L("launchctl 退出码 \(Int(dis.status))") : msg)
            }
        }
    }
}
