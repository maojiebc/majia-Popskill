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
        (model.tools, model.entries) = Fixtures.make()
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
        model.maintenance.tab = .sources
        try render(MaintenanceView().environment(model), size: CGSize(width: 1080, height: 680), to: output.appendingPathComponent("maintenance-sources.png"))
        for i in 1...9 {
            let skill = root.appendingPathComponent("skills/backup-\(i)")
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            _ = try model.fs.moveToTrash(skill)
        }
        // One real same-name conflict; restore must remain unavailable for that row.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("skills/backup-9"), withIntermediateDirectories: true)
        for section in SettingsSection.allCases {
            model.maintenance.settingsSection = section
            try render(SettingsView().environment(model), size: CGSize(width: 780, height: 660), to: output.appendingPathComponent("settings-\(section.rawValue).png"))
        }
        XCTAssertEqual(l10nIsChinese, language.hasPrefix("zh"), "Render the actual requested localization")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).filter { $0.hasSuffix(".png") }.count, 6)
    }

    private func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let host = NSHostingView(rootView: view.preferredColorScheme(.light).environment(\.locale, l10nLocale))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(data.count, 5_000, "A blank capture is not UI evidence")
        try data.write(to: url)
    }
}
