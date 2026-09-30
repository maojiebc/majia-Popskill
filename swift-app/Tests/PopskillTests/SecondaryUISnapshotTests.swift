import AppKit
import SwiftUI
import XCTest
@testable import Popskill

/// Real SwiftUI/AppKit rendering, not a web mock. Opt-in in CI; all data stays in a sandbox.
@MainActor
final class SecondaryUISnapshotTests: XCTestCase {
    func testRenderSecondaryPages() throws {
        guard let destination = ProcessInfo.processInfo.environment["POPSKILL_UI_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set POPSKILL_UI_SNAPSHOT_DIR to capture native secondary-page fixtures")
        }
        let language = ProcessInfo.processInfo.environment["POPSKILL_UI_SNAPSHOT_LANG"] ?? "en"
        // SwiftPM keeps resources next to the xctest bundle. Embed that real build
        // artifact for this test so production bundle discovery does not fall back
        // to Chinese keys. Do not fake translations or change production lookup.
        let testBundle = Bundle(for: Self.self)
        let resources = testBundle.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Popskill_Popskill.bundle")
        let embedded = testBundle.bundleURL.appendingPathComponent("Popskill_Popskill.bundle")
        var embeddedByTest = false
        if !FileManager.default.fileExists(atPath: embedded.path) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: resources.path), resources.path)
            try FileManager.default.copyItem(at: resources, to: embedded)
            embeddedByTest = true
        }
        let previousLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        defer {
            if embeddedByTest { try? FileManager.default.removeItem(at: embedded) }
            UserDefaults.standard.set(previousLanguages, forKey: "AppleLanguages")
        }
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
        print("Snapshot resources: \(resources.path); test bundle: \(testBundle.bundleURL.path)")
        setenv("POPSKILL_NO_AUTOCHECK", "1", 1)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: .aqua)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-render-\(UUID())")
        let output = URL(fileURLWithPath: destination).appendingPathComponent(language)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "popskill-render-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let model = AppModel(env: StoreEnv(storeRoot: root, toolRoots: StoreEnv.toolRoots(at: root)), defaults: defaults)
        model.fake = true
        // Keep the About controls present, matching the app's Sparkle wiring.
        model.checkAppUpdate = {}
        model.sparkleAutoCheckGet = { false }
        model.sparkleAutoCheckSet = { _ in }
        (model.tools, model.entries) = Fixtures.make()
        // Match the user machine: three permanent rows plus discovered Grok and Pi.
        model.detectedOptionals = [
            DetectedOptional(id: "grok", name: "Grok", presence: .cli("/usr/local/bin/grok"), showOnHome: false),
            DetectedOptional(id: "pi", name: "Pi", presence: .cli("/usr/local/bin/pi"), showOnHome: false),
        ]
        model.maintenance.cliInventoryLoaded = true
        model.globalClis = [
            GlobalCli(name: "@openai/codex", installed: "1.0.0", latest: "1.1.0", prefix: "/opt/homebrew", pathHit: "/opt/homebrew/bin/codex", allowlisted: true),
            GlobalCli(name: "@anthropic-ai/claude-code", installed: "2.0.0", latest: "2.1.0", prefix: "/opt/homebrew", pathHit: "/usr/local/bin/claude", pathMatchesPrefix: false, allowlisted: true),
            GlobalCli(name: "@google/gemini-cli", installed: "1.0.0", prefix: "/opt/homebrew", allowlisted: true),
            GlobalCli(name: "@qwen-code/qwen-code", installed: "1.0.0", latest: "1.1.0", prefix: "/opt/homebrew", allowlisted: true),
        ]
        model.maintenance.cliChecks[model.globalClis[2].id] = CheckRecord(outcome: .failed, error: "Connection timed out. Check the network and try again.")
        for cli in [model.globalClis[0], model.globalClis[3]] {
            model.maintenance.report.enqueue(id: cli.id, name: cli.maintenanceName, kind: .cli)
        }
        model.maintenance.report.setPhase(model.globalClis[0].id, .running)
        model.upgradingClis = Set(model.maintenance.report.items.map(\.id))
        model.maintenance.showResults = true
        model.maintenance.tab = .clis
        try render(MaintenanceView().environment(model), size: CGSize(width: 1080, height: 680), to: output.appendingPathComponent("maintenance-clis.png"))
        model.maintenance.report = OperationReport()
        model.upgradingClis = []
        model.globalClis = [
            GlobalCli(name: "@anthropic-ai/claude-code", installed: "2.1.283", latest: "2.1.284", channel: .native,
                prefix: "/Users/example/.local/bin", pathHit: "/Users/example/.local/bin/claude", allowlisted: true,
                resolvedPath: "/Users/example/.local/share/claude/versions/2.1.283",
                updateCommand: CliUpdateCommand(executable: "/Users/example/.local/bin/claude", arguments: ["update"])),
            GlobalCli(name: "@openai/codex", installed: "0.155.0", latest: "0.155.1", channel: .bun,
                prefix: "/Users/example/.bun/install/global", pathHit: "/Users/example/.bun/bin/codex", allowlisted: true),
            GlobalCli(name: "@earendil-works/pi-coding-agent", installed: "0.99.0", latest: "0.99.1", channel: .pnpm,
                prefix: "/Users/example/Library/pnpm/global/5", pathHit: "/Users/example/Library/pnpm/pi", allowlisted: true),
        ]
        model.maintenance.expandedClis = [model.globalClis[0].id]
        try render(MaintenanceView().environment(model), size: CGSize(width: 1080, height: 680), to: output.appendingPathComponent("maintenance-native.png"))
        if let i = model.entries.firstIndex(where: { $0.isBundle && !$0.isManagedExternally }) {
            model.entries[i].latest = "2.0.0"
            model.entries[i].changedMembers = [model.entries[i].allCaps[0].name]
            model.entries[i].upstreamNew = ["new-upstream-skill"]
            model.maintenance.expandedSources = [model.entries[i].id]
        }
        model.maintenance.tab = .sources
        try render(MaintenanceView().environment(model), size: CGSize(width: 1080, height: 680), to: output.appendingPathComponent("maintenance-sources.png"))
        // Include the real command shapes that crashed the installed v2.22.0 app.
        let taskFixtures: [[String: Any]] = [
            ["Label": "com.example.proxy", "ProgramArguments": ["/bin/sh", "-c", "http://127.0.0.1:7897;"], "RunAtLoad": true],
            ["Label": "com.example.daily", "ProgramArguments": ["/usr/bin/python3", "/Users/example/Application Support/run_daily.py"], "StartCalendarInterval": ["Hour": 8]],
            ["Label": "com.example.worker", "ProgramArguments": ["/usr/local/bin/node", "./scripts/worker.mjs"], "KeepAlive": true],
        ]
        model.schedTasks = try taskFixtures.map {
            let data = try PropertyListSerialization.data(fromPropertyList: $0, format: .xml, options: 0)
            return try XCTUnwrap(SchedEngine.parsePlist(data, url: nil))
        }
        try render(SchedSheet().environment(model), size: CGSize(width: 760, height: 650), to: output.appendingPathComponent("system-background-tasks.png"))
        for i in 1...9 {
            let skill = root.appendingPathComponent("skills/backup-\(i)")
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            _ = try model.fs.moveToTrash(skill)
        }
        // One real same-name conflict; restore must remain unavailable for that row.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skills/backup-9"), withIntermediateDirectories: true)
        for section in SettingsSection.allCases {
            model.maintenance.settingsSection = section
            try render(SettingsView().environment(model), size: CGSize(width: 780, height: 660), to: output.appendingPathComponent("settings-\(section.rawValue).png"), toolIDs: section == .tools ? ["claude", "codex", "cursor", "grok", "pi"] : nil)
        }
        model.detectedOptionals = ToolDef.builtins.filter { !$0.alwaysShow }.map {
            DetectedOptional(id: $0.id, name: $0.name, presence: .cli("/usr/local/bin/" + $0.id), showOnHome: false)
        }
        model.maintenance.settingsSection = .tools
        try render(SettingsView().environment(model), size: CGSize(width: 780, height: 660),
                   to: output.appendingPathComponent("settings-tools-all.png"), toolIDs: ToolDef.builtins.map(\.id))
        let home = FileManager.default.homeDirectoryForCurrentUser
        model.tools = ToolDef.builtins.map { def in
            Tool(id: def.id, name: def.name, root: home.appendingPathComponent(def.rootRelative),
                 connected: true, defaultTarget: true)
        }
        try render(MainView().environment(model), size: CGSize(width: 1080, height: 720),
                   to: output.appendingPathComponent("main-all-tools.png"),
                   chromeIDs: ["hero:summary", "hero:actions"] + model.tools.map { "stat:\($0.id)" })
        XCTAssertEqual(l10nIsChinese, language.hasPrefix("zh"), "Render the actual requested localization")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.hasSuffix(".png") }.count, 10)
    }

    private func render<V: View>(_ view: V, size: CGSize, to url: URL, toolIDs: [String]? = nil, chromeIDs: [String]? = nil) throws {
        let capture = ToolBoundsCapture()
        let measured = view.preferredColorScheme(.light).tint(Ink.blue).environment(\.locale, l10nLocale)
            .overlayPreferenceValue(SettingsToolBoundsKey.self) { anchors in
                GeometryReader { proxy in
                    Color.clear.preference(key: ResolvedToolBoundsKey.self, value: anchors.mapValues { proxy[$0] })
                }.allowsHitTesting(false)
            }
            .onPreferenceChange(ResolvedToolBoundsKey.self) { capture.frames = $0 }
        let host = NSHostingView(rootView: measured)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        if let toolIDs {
            let frames = capture.frames.filter { !$0.key.contains(":") }
            XCTAssertEqual(Set(frames.keys), Set(toolIDs))
            XCTAssertEqual(capture.frames.keys.filter { $0.hasPrefix("default:") }.count, toolIDs.count)
            XCTAssertEqual(capture.frames.keys.filter { $0.hasPrefix("home:") }.count, toolIDs.count - 3)
            let contentFrame = host.bounds
            for (id, frame) in capture.frames {
                XCTAssertGreaterThanOrEqual(frame.minX, contentFrame.minX + 16, "\(id) title clips past the left edge")
                XCTAssertLessThanOrEqual(frame.maxX, contentFrame.maxX - 16, "\(id) title clips past the right edge")
                XCTAssertGreaterThan(frame.width, 10)
            }
            let centers = frames.values.map(\.midY).sorted()
            for (first, second) in zip(centers, centers.dropFirst()) {
                XCTAssertLessThanOrEqual(second - first, 100, "A tool row stretches instead of fitting its controls")
            }
        }
        if let chromeIDs {
            let contentFrame = host.bounds
            XCTAssertEqual(Set(chromeIDs).subtracting(capture.frames.keys), [])
            let summary = try XCTUnwrap(capture.frames["hero:summary"])
            let actions = try XCTUnwrap(capture.frames["hero:actions"])
            XCTAssertGreaterThanOrEqual(summary.minX, 16, "Hero summary clips past the left edge")
            XCTAssertLessThanOrEqual(summary.maxX, actions.minX + 1, "Hero summary overlaps the action buttons")
            XCTAssertGreaterThanOrEqual(actions.width, 360, "Action buttons were compressed: \(actions)")
            XCTAssertLessThanOrEqual(actions.maxX, contentFrame.maxX - 16, "Action buttons clip past the right edge")
            let statFrames = chromeIDs.filter { $0.hasPrefix("stat:") }.compactMap { capture.frames[$0] }
            XCTAssertEqual(statFrames.count, ToolDef.builtins.count)
            for id in chromeIDs where id.hasPrefix("stat:") {
                let frame = try XCTUnwrap(capture.frames[id])
                let toolID = String(id.dropFirst("stat:".count))
                let def = try XCTUnwrap(ToolDef.builtins.first { $0.id == toolID })
                let tool = Tool(id: def.id, name: def.name, root: URL(fileURLWithPath: "/"), connected: true, defaultTarget: true)
                XCTAssertGreaterThanOrEqual(frame.minX, 16, "\(toolID) label clips past the left edge")
                XCTAssertLessThanOrEqual(frame.maxX, contentFrame.maxX - 16, "\(toolID) label clips past the right edge")
                XCTAssertGreaterThanOrEqual(frame.width, statLabelWidth(toolColLabel(tool)) - 2,
                                            "\(toolID) label is truncated")
            }
            let centers = statFrames.map(\.midY)
            XCTAssertLessThanOrEqual((centers.max() ?? 0) - (centers.min() ?? 0), 6, "Stat labels wrap onto a second line")
            let bundleNames = capture.frames.filter { $0.key.hasPrefix("bundle-name:") }
            XCTAssertGreaterThanOrEqual(bundleNames.count, 3, "Folded bundle names were not measured")
            for (id, frame) in bundleNames {
                XCTAssertGreaterThanOrEqual(frame.width, 72, "\(id) name was crushed by the tool columns")
                XCTAssertLessThanOrEqual(frame.height, 26, "\(id) name wrapped vertically")
                let entryID = String(id.dropFirst("bundle-name:".count))
                let fractions = try XCTUnwrap(capture.frames["bundle-fractions:" + entryID])
                XCTAssertGreaterThan(fractions.minY, frame.maxY - 4, "\(entryID) fractions still sit beside a crushed name")
                XCTAssertLessThanOrEqual(fractions.maxX, contentFrame.maxX - 16, "\(entryID) tool columns overflow the window")
            }
        }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5_000, "A blank capture is not UI evidence")
        try data.write(to: url)
    }

    /// Matches the 9pt bold + 0.6 tracking used by the stat strip.
    private func statLabelWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 9, weight: .bold)
        return NSAttributedString(string: text, attributes: [.font: font, .kern: 0.6]).size().width
    }
}

private struct ResolvedToolBoundsKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, next in next }
    }
}
private final class ToolBoundsCapture {
    var frames: [String: CGRect] = [:]
}
