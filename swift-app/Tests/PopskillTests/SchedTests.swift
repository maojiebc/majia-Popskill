import XCTest
@testable import Popskill

/// SchedEngine 纯解析层测试——fixture 取自真机数据形状，不碰真 launchctl/crontab
final class SchedTests: XCTestCase {

    // ── plist 解析 ────────────────────────────────────────

    private func plistData(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    func testParsePlistCalendarDaily() throws {
        // com.majia.update-skills 形状：每天 06:00 + 日志路径
        let data = try plistData([
            "Label": "com.majia.update-skills",
            "ProgramArguments": ["/bin/bash", "/Users/majia/.local/bin/update-skills.sh"],
            "StartCalendarInterval": ["Hour": 6, "Minute": 0],
            "StandardOutPath": "/Users/majia/.local/log/update-skills.log",
        ])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil))
        XCTAssertEqual(t.label, "com.majia.update-skills")
        XCTAssertEqual(t.schedule, "每天 06:00")
        XCTAssertEqual(t.command, "/bin/bash /Users/majia/.local/bin/update-skills.sh")
        XCTAssertEqual(t.logPath, "/Users/majia/.local/log/update-skills.log")
        XCTAssertFalse(t.vendor)
        XCTAssertFalse(t.loaded, "loaded 由 launchctl 比对回填，解析层默认 false")
    }

    func testParsePlistWeekly() throws {
        // com.agents.skills-sync 形状：每周一 10:17
        let data = try plistData([
            "Label": "com.agents.skills-sync",
            "ProgramArguments": ["/Users/majia/.agents/sync.sh"],
            "StartCalendarInterval": ["Weekday": 1, "Hour": 10, "Minute": 17],
        ])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil))
        XCTAssertEqual(t.schedule, "每周一 10:17")
        XCTAssertNil(t.logPath)
    }

    func testParsePlistKeepAliveDaemon() throws {
        // claude-to-im 形状：KeepAlive 常驻
        let data = try plistData([
            "Label": "com.claude-to-im.bridge",
            "ProgramArguments": ["/usr/local/bin/node", "daemon.mjs"],
            "KeepAlive": true, "RunAtLoad": true,
        ])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil))
        XCTAssertEqual(t.schedule, "常驻 daemon", "KeepAlive 优先于 RunAtLoad")
    }

    func testParsePlistRunAtLoadOnly() throws {
        let data = try plistData(["Label": "Nowledge Mem", "Program": "/Applications/Mem.app/Contents/MacOS/Mem", "RunAtLoad": true])
        let t = try XCTUnwrap(SchedEngine.parsePlist(data, url: nil))
        XCTAssertEqual(t.schedule, "登录自启")
        XCTAssertEqual(t.command, "/Applications/Mem.app/Contents/MacOS/Mem", "Program 单字段也要认")
    }

    func testParsePlistNoLabelRejected() throws {
        let data = try plistData(["ProgramArguments": ["/bin/true"]])
        XCTAssertNil(SchedEngine.parsePlist(data, url: nil))
    }

    // ── 调度人话化 ────────────────────────────────────────

    func testDescribeCalendarVariants() {
        XCTAssertEqual(SchedEngine.describeCalendar(["Hour": 6, "Minute": 0]), "每天 06:00")
        XCTAssertEqual(SchedEngine.describeCalendar(["Weekday": 0, "Hour": 9, "Minute": 30]), "每周日 09:30")
        XCTAssertEqual(SchedEngine.describeCalendar(["Day": 1, "Hour": 3, "Minute": 0]), "每月 1 日 03:00")
        XCTAssertEqual(SchedEngine.describeCalendar(["Minute": 17]), "每小时第 17 分")
        XCTAssertEqual(SchedEngine.describeCalendar(["Hour": 5]), "每天 05:00", "缺 Minute 按 0")
    }

    func testDescribeCalendarArray() {
        let sched = SchedEngine.describeSchedule([
            "StartCalendarInterval": [["Hour": 6, "Minute": 0], ["Hour": 18, "Minute": 0]],
        ])
        XCTAssertEqual(sched, "每天 06:00 / 每天 18:00")
    }

    func testDescribeInterval() {
        XCTAssertEqual(SchedEngine.describeInterval(7200), "每 2 小时")
        XCTAssertEqual(SchedEngine.describeInterval(300), "每 5 分钟")
        XCTAssertEqual(SchedEngine.describeInterval(45), "每 45 秒")
    }

    // ── crontab 解析 ──────────────────────────────────────

    func testParseCrontabRealLines() {
        // 真机 crontab 三条
        let text = """
        17 */6 * * * /Users/majia/.openclaw/workspace/scripts/track_mediacrawler.sh >/tmp/track_mediacrawler.log 2>&1
        0 4 * * * /Users/majia/scripts/openclaw-maintenance.sh >> /Users/majia/.openclaw/logs/maintenance.log 2>&1
        41 23 * * * /opt/homebrew/Cellar/acme.sh/3.1.3/libexec/acme.sh --cron --home "/Users/majia/.acme.sh" > /dev/null
        """
        let tasks = SchedEngine.parseCrontab(text)
        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].schedule, "每 6 小时的第 17 分")
        XCTAssertEqual(tasks[0].label, "track_mediacrawler.sh")
        XCTAssertEqual(tasks[0].logPath, "/tmp/track_mediacrawler.log")
        XCTAssertEqual(tasks[1].schedule, "每天 04:00")
        XCTAssertEqual(tasks[1].logPath, "/Users/majia/.openclaw/logs/maintenance.log", ">> 追加重定向也要认")
        XCTAssertEqual(tasks[2].schedule, "每天 23:41")
        XCTAssertNil(tasks[2].logPath, "/dev/null 不算日志")
        XCTAssertTrue(tasks.allSatisfy { $0.loaded }, "cron 在 crontab 里即生效")
        XCTAssertTrue(tasks.allSatisfy { $0.kind == .cron && !$0.canOperate })
    }

    func testParseCrontabSkipsCommentsAndEnv() {
        let text = """
        # 注释行
        MAILTO=""

        30 2 * * 1 /Users/majia/backup.sh
        """
        let tasks = SchedEngine.parseCrontab(text)
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
        XCTAssertEqual(map["com.claude-to-im.bridge"] ?? nil, 1, "退出码非 0 要保留——这就是「上次结果」")
        XCTAssertEqual(map["com.agents.skills-sync"] ?? nil, 0)
        XCTAssertFalse(map.keys.contains("PID"), "表头不是任务")
    }

    func testScanMergesLoadedState() throws {
        // 沙盘 LaunchAgents + 注入 launchctl/crontab 输出，验证 loaded/lastExit 回填
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
            crontabOut: "0 4 * * * /Users/majia/scripts/m.sh\n"
        )
        XCTAssertEqual(tasks.count, 3)
        let mine = try XCTUnwrap(tasks.first { $0.label == "com.majia.update-skills" })
        XCTAssertTrue(mine.loaded)
        XCTAssertEqual(mine.lastExit, 0)
        let google = try XCTUnwrap(tasks.first { $0.label == "com.google.keystone.agent" })
        XCTAssertTrue(google.vendor, "Google 任务标 vendor（默认隐藏）")
        XCTAssertFalse(google.loaded, "不在 launchctl list 里 = 未加载")
        XCTAssertEqual(tasks.filter { $0.kind == .cron }.count, 1)
    }

    func testVendorFilter() {
        XCTAssertTrue(SchedEngine.isVendor("com.google.keystone.agent"))
        XCTAssertTrue(SchedEngine.isVendor("io.github.clash-verge-rev.clash-verge-rev"))
        XCTAssertTrue(SchedEngine.isVendor("com.apple.anything"))
        XCTAssertFalse(SchedEngine.isVendor("com.majia.update-skills"))
        XCTAssertFalse(SchedEngine.isVendor("Nowledge Mem"))
        XCTAssertFalse(SchedEngine.isVendor("com.agents.skills-sync"))
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
