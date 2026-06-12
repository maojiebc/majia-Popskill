import XCTest
@testable import Popskill

/// SchedEngine 纯解析层测试——fixture 取自真机数据形状，不碰真 launchctl/crontab
final class SchedTests: XCTestCase {

    // 固定基准时刻：2026-06-12（周五）22:00 本地时区
    private var now: Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        return cal.date(from: DateComponents(year: 2026, month: 6, day: 12, hour: 22, minute: 0))!
    }
    private func comps(_ d: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d)
    }

    private func plistData(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    // ── plist 解析 ────────────────────────────────────────

    func testParsePlistCalendarDaily() throws {
        // com.majia.update-skills 形状：每天 06:00 + 日志路径
        let data = try plistData([
            "Label": "com.majia.update-skills",
            "ProgramArguments": ["/bin/bash", "/Users/majia/.local/bin/update-skills.sh"],
            "StartCalendarInterval": ["Hour": 6, "Minute": 0],
            "StandardOutPath": "/Users/majia/.local/log/update-skills.log",
        ])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil, now: now))
        XCTAssertEqual(t.label, "com.majia.update-skills")
        XCTAssertEqual(t.displayName, "update-skills", "无备注时用美化 label")
        XCTAssertEqual(t.behavior, .timed)
        XCTAssertEqual(t.schedule, "每天 06:00")
        XCTAssertEqual(t.command, "/bin/bash /Users/majia/.local/bin/update-skills.sh")
        XCTAssertEqual(t.logPath, "/Users/majia/.local/log/update-skills.log")
        XCTAssertFalse(t.vendor)
        XCTAssertFalse(t.loaded, "loaded 由 launchctl 比对回填，解析层默认 false")
        // 22:00 → 明天 06:00
        let next = try XCTUnwrap(t.nextFire)
        let c = comps(next)
        XCTAssertEqual([c.day, c.hour, c.minute], [13, 6, 0])
    }

    func testParsePlistWeekly() throws {
        let data = try plistData([
            "Label": "com.agents.skills-sync",
            "ProgramArguments": ["/Users/majia/.agents/sync.sh"],
            "StartCalendarInterval": ["Weekday": 1, "Hour": 10, "Minute": 17],
        ])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil, now: now))
        XCTAssertEqual(t.schedule, "每周一 10:17")
        // 6/12 是周五 → 下周一 6/15 10:17
        let c = comps(try XCTUnwrap(t.nextFire))
        XCTAssertEqual([c.day, c.hour, c.minute, c.weekday], [15, 10, 17, 2])
    }

    func testParsePlistKeepAliveDaemon() throws {
        let data = try plistData([
            "Label": "com.claude-to-im.bridge",
            "ProgramArguments": ["/usr/local/bin/node", "daemon.mjs"],
            "KeepAlive": true, "RunAtLoad": true,
        ])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil, now: now))
        XCTAssertEqual(t.behavior, .daemon, "KeepAlive 优先于 RunAtLoad")
        XCTAssertEqual(t.schedule, "常驻 daemon")
        XCTAssertNil(t.nextFire, "daemon 没有下次触发")
        XCTAssertEqual(t.displayName, "claude-to-im.bridge", "去 reverse-DNS 前缀")
    }

    func testParsePlistRunAtLoadOnly() throws {
        let data = try plistData(["Label": "Nowledge Mem", "Program": "/Applications/Mem.app/Contents/MacOS/Mem", "RunAtLoad": true])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil, now: now))
        XCTAssertEqual(t.behavior, .loginItem)
        XCTAssertEqual(t.displayName, "Nowledge Mem", "带空格的非 reverse-DNS 名不动")
        XCTAssertEqual(t.command, "/Applications/Mem.app/Contents/MacOS/Mem", "Program 单字段也要认")
    }

    func testParsePlistNoLabelRejected() throws {
        let data = try plistData(["ProgramArguments": ["/bin/true"]])
        XCTAssertNil(SchedEngine.parsePlist(data, url: nil, now: now))
    }

    // ── 行为归组 / 美化名 ──────────────────────────────────

    func testClassify() {
        XCTAssertEqual(SchedEngine.classify(["StartCalendarInterval": ["Hour": 6]]), .timed)
        XCTAssertEqual(SchedEngine.classify(["StartInterval": 3600]), .timed)
        XCTAssertEqual(SchedEngine.classify(["KeepAlive": true]), .daemon)
        XCTAssertEqual(SchedEngine.classify(["RunAtLoad": true]), .loginItem)
        XCTAssertEqual(SchedEngine.classify([:]), .manual)
        XCTAssertEqual(SchedEngine.classify(["StartInterval": 3600, "KeepAlive": true]), .timed, "时间调度优先")
    }

    func testPrettyLabel() {
        XCTAssertEqual(SchedEngine.prettyLabel("com.majia.update-skills"), "update-skills")
        XCTAssertEqual(SchedEngine.prettyLabel("io.github.clash-verge-rev.clash-verge-rev"), "clash-verge-rev.clash-verge-rev")
        XCTAssertEqual(SchedEngine.prettyLabel("Nowledge Mem"), "Nowledge Mem")
        XCTAssertEqual(SchedEngine.prettyLabel("update-skills.sh"), "update-skills.sh", "两段的不裁")
    }

    // ── 下次触发：launchd calendar ─────────────────────────

    func testNextCalendarFireDaily() throws {
        // 22:00，每天 05:00 → 明天 05:00
        let c = comps(try XCTUnwrap(SchedEngine.nextCalendarFire(["Hour": 5, "Minute": 0], after: now)))
        XCTAssertEqual([c.day, c.hour, c.minute], [13, 5, 0])
        // 22:00，每天 23:41 → 今天 23:41
        let c2 = comps(try XCTUnwrap(SchedEngine.nextCalendarFire(["Hour": 23, "Minute": 41], after: now)))
        XCTAssertEqual([c2.day, c2.hour, c2.minute], [12, 23, 41])
    }

    func testNextCalendarFireHourly() throws {
        // 22:00，每小时第 17 分 → 22:17
        let c = comps(try XCTUnwrap(SchedEngine.nextCalendarFire(["Minute": 17], after: now)))
        XCTAssertEqual([c.day, c.hour, c.minute], [12, 22, 17])
    }

    func testNextCalendarFireMonthly() throws {
        // 6/12，每月 1 日 03:00 → 7/1 03:00
        let c = comps(try XCTUnwrap(SchedEngine.nextCalendarFire(["Day": 1, "Hour": 3, "Minute": 0], after: now)))
        XCTAssertEqual([c.month, c.day, c.hour], [7, 1, 3])
    }

    func testNextCalendarFireWeekday7IsSunday() throws {
        // launchd 0 和 7 都是周日：6/12 周五 → 6/14 周日
        let c = comps(try XCTUnwrap(SchedEngine.nextCalendarFire(["Weekday": 7, "Hour": 9, "Minute": 0], after: now)))
        XCTAssertEqual([c.day, c.weekday], [14, 1])
    }

    // ── 下次触发：cron ────────────────────────────────────

    func testNextCronFireRealLines() throws {
        // 22:00，"17 */6 * * *"（0/6/12/18 点的第 17 分）→ 明天 00:17
        let c = comps(try XCTUnwrap(SchedEngine.nextCronFire(["17", "*/6", "*", "*", "*"], after: now)))
        XCTAssertEqual([c.day, c.hour, c.minute], [13, 0, 17])
        // "41 23 * * *" → 今晚 23:41
        let c2 = comps(try XCTUnwrap(SchedEngine.nextCronFire(["41", "23", "*", "*", "*"], after: now)))
        XCTAssertEqual([c2.day, c2.hour, c2.minute], [12, 23, 41])
        // "30 2 * * 1"（周一 02:30）→ 6/15 周一
        let c3 = comps(try XCTUnwrap(SchedEngine.nextCronFire(["30", "2", "*", "*", "1"], after: now)))
        XCTAssertEqual([c3.day, c3.hour, c3.minute], [15, 2, 30])
    }

    func testNextCronFireDomDowUnion() throws {
        // 标准 cron：dom 和 dow 都受限 → OR。"0 0 20 * 1"：20 号或周一，先到周一 6/15
        let c = comps(try XCTUnwrap(SchedEngine.nextCronFire(["0", "0", "20", "*", "1"], after: now)))
        XCTAssertEqual(c.day, 15, "周一 (6/15) 比 20 号先到")
    }

    // ── 人话时间 ──────────────────────────────────────────

    func testHumanNext() {
        XCTAssertEqual(SchedEngine.humanNext(now.addingTimeInterval(101 * 60), now: now), "1 小时后 · 23:41")
        XCTAssertEqual(SchedEngine.humanNext(now.addingTimeInterval(32 * 60), now: now), "32 分钟后 · 22:32")
        XCTAssertEqual(SchedEngine.humanNext(now.addingTimeInterval(7 * 3600), now: now), "7 小时后 · 明天 05:00")
        XCTAssertTrue(SchedEngine.humanNext(now.addingTimeInterval(62 * 3600), now: now).hasPrefix("2 天后 · 周一"))
    }

    func testHumanLast() {
        XCTAssertEqual(SchedEngine.humanLast(now.addingTimeInterval(-17 * 3600), now: now), "今天 05:00")
        XCTAssertEqual(SchedEngine.humanLast(now.addingTimeInterval(-23 * 3600), now: now), "昨天 23:00")
        XCTAssertEqual(SchedEngine.humanLast(now.addingTimeInterval(-72 * 3600), now: now), "6/9 22:00")
    }

    // ── crontab 解析 ──────────────────────────────────────

    func testParseCrontabRealLines() {
        let text = """
        17 */6 * * * /Users/majia/.openclaw/workspace/scripts/track_mediacrawler.sh >/tmp/track_mediacrawler.log 2>&1
        0 4 * * * /Users/majia/scripts/openclaw-maintenance.sh >> /Users/majia/.openclaw/logs/maintenance.log 2>&1
        41 23 * * * /opt/homebrew/Cellar/acme.sh/3.1.3/libexec/acme.sh --cron --home "/Users/majia/.acme.sh" > /dev/null
        """
        let tasks = SchedEngine.parseCrontab(text, now: now)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].schedule, "每 6 小时的第 17 分")
        XCTAssertEqual(tasks[0].label, "track_mediacrawler.sh")
        XCTAssertEqual(tasks[0].logPath, "/tmp/track_mediacrawler.log")
        XCTAssertEqual(tasks[1].schedule, "每天 04:00")
        XCTAssertEqual(tasks[1].logPath, "/Users/majia/.openclaw/logs/maintenance.log", ">> 追加重定向也要认")
        XCTAssertEqual(tasks[2].schedule, "每天 23:41")
        XCTAssertNil(tasks[2].logPath, "/dev/null 不算日志")
        XCTAssertTrue(tasks.allSatisfy { $0.loaded }, "cron 在 crontab 里即生效")
        XCTAssertTrue(tasks.allSatisfy { $0.kind == .cron && !$0.canOperate && $0.behavior == .timed })
        XCTAssertTrue(tasks.allSatisfy { $0.nextFire != nil }, "cron 都能算出下次触发")
    }

    func testParseCrontabSkipsCommentsAndEnv() {
        let text = """
        # 注释行
        MAILTO=""

        30 2 * * 1 /Users/majia/backup.sh
        """
        let tasks = SchedEngine.parseCrontab(text, now: now)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].schedule, "每周一 02:30")
    }

    func testDescribeCronVariants() {
        XCTAssertEqual(SchedEngine.describeCron(["*/10", "*", "*", "*", "*"]), "每 10 分钟")
        XCTAssertEqual(SchedEngine.describeCron(["5", "*", "*", "*", "*"]), "每小时第 5 分")
        XCTAssertEqual(SchedEngine.describeCron(["0", "0", "15", "*", "*"]), "每月 15 日 00:00")
        XCTAssertEqual(SchedEngine.describeCron(["1", "2", "3", "4", "5"]), "1 2 3 4 5", "翻不动的原样返回")
    }

    // ── launchctl list 比对 ───────────────────────────────

    func testParseLaunchctlList() {
        let out = """
        PID\tStatus\tLabel
        729\t0\tcom.tuxera.ntfs.agent
        -\t1\tcom.claude-to-im.bridge
        -\t0\tcom.agents.skills-sync
        """
        let map = SchedEngine.parseLaunchctlList(out)
        XCTAssertEqual(map.count, 3)
        XCTAssertEqual(map["com.tuxera.ntfs.agent"]?.pid, 729, "在跑的进程要拿到 PID")
        XCTAssertEqual(map["com.claude-to-im.bridge"]?.exit, 1, "退出码非 0 要保留——这就是「上次结果」")
        XCTAssertNil(map["com.claude-to-im.bridge"]?.pid ?? nil, "PID '-' = 没在跑")
        XCTAssertFalse(map.keys.contains("PID"), "表头不是任务")
    }

    func testScanMergesLoadedStateAndNotes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sched-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try plistData([
            "Label": "com.majia.update-skills",
            "ProgramArguments": ["/bin/bash", "u.sh"],
            "StartCalendarInterval": ["Hour": 6, "Minute": 0],
        ]).write(to: dir.appendingPathComponent("com.majia.update-skills.plist"))
        try plistData([
            "Label": "com.google.keystone.agent",
            "ProgramArguments": ["/g"],
            "StartInterval": 3600,
        ]).write(to: dir.appendingPathComponent("com.google.keystone.agent.plist"))

        let engine = SchedEngine(agentsDir: dir)
        let tasks = engine.scan(
            launchctlOut: "PID\tStatus\tLabel\n-\t0\tcom.majia.update-skills\n",
            crontabOut: "0 4 * * * /Users/majia/scripts/m.sh\n",
            notes: ["com.majia.update-skills": "自动更新 AI 技能"],
            now: now
        )
        XCTAssertEqual(tasks.count, 3)
        let mine = try XCTUnwrap(tasks.first { $0.label == "com.majia.update-skills" })
        XCTAssertTrue(mine.loaded)
        XCTAssertEqual(mine.lastExit, 0)
        XCTAssertEqual(mine.displayName, "自动更新 AI 技能", "有备注时备注是展示名")
        let google = try XCTUnwrap(tasks.first { $0.label == "com.google.keystone.agent" })
        XCTAssertTrue(google.vendor, "Google 任务标 vendor（默认隐藏）")
        XCTAssertFalse(google.loaded)
        XCTAssertNil(google.nextFire, "StartInterval 没有公开锚点，不给倒计时")
        XCTAssertEqual(tasks.filter { $0.kind == .cron }.count, 1)
    }

    func testDaemonStalled() throws {
        let data = try plistData(["Label": "d", "ProgramArguments": ["/d"], "KeepAlive": true])
        var t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil, now: now))
        t.loaded = true; t.pid = nil
        XCTAssertTrue(t.stalled, "KeepAlive 在册但没进程 = 停摆")
        t.pid = 4242
        XCTAssertFalse(t.stalled)
    }

    // ── 备注存储（meta 往返） ──────────────────────────────

    func testSchedNotePersistence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sched-note-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skills"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fs = StoreFS(env: StoreEnv(storeRoot: root, toolRoots: [:]))
        fs.saveSchedNote("com.majia.update-skills", note: "自动更新 AI 技能")
        XCTAssertEqual(fs.loadMeta().schedNotes?["com.majia.update-skills"], "自动更新 AI 技能")
        fs.saveSchedNote("com.majia.update-skills", note: "  ")
        XCTAssertNil(fs.loadMeta().schedNotes?["com.majia.update-skills"] ?? nil, "空白 = 清除备注")
    }

    // ── 重定向剥离 ────────────────────────────────────────

    func testSplitRedirect() {
        let (c1, l1) = SchedEngine.splitRedirect("/a/b.sh --flag >/tmp/x.log 2>&1")
        XCTAssertEqual(c1, "/a/b.sh --flag")
        XCTAssertEqual(l1, "/tmp/x.log")
        let (c2, l2) = SchedEngine.splitRedirect("/a/b.sh")
        XCTAssertEqual(c2, "/a/b.sh")
        XCTAssertNil(l2)
        let (_, l3) = SchedEngine.splitRedirect("/a/b.sh > /dev/null")
        XCTAssertNil(l3)
    }
}
