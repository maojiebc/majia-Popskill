import XCTest
@testable import Popskill

final class CapabilityMaintenanceTests: XCTestCase {
    func testStableReleaseUpdatesPrereleaseButNeverDowngradesToPrerelease() {
        XCTAssertTrue(cliVersionIsNewer("1.2.3", than: "1.2.3-beta.10"))
        XCTAssertTrue(cliVersionIsNewer("1.2.3-beta.10", than: "1.2.3-beta.9"))
        XCTAssertFalse(cliVersionIsNewer("1.2.3-beta.1", than: "1.2.3"))
        XCTAssertFalse(cliVersionIsNewer("unavailable", than: "1.2.3"))
    }

    func testPackageNamesCannotBorrowAnAgentIdentityFromTheirDisplayName() {
        let impostor = GlobalCli(name: "untrusted-helper", installed: "1.0.0", latest: "2.0.0",
                                 displayName: "codex", allowlisted: true)
        XCTAssertFalse(impostor.safeRecognizedAgentUpdate)
    }

    func testMissingUpstreamSkillIsFailureAndPreservesInstalledContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-missing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let local = root.appendingPathComponent("store/skills/demo")
        let upstream = root.appendingPathComponent("upstream")
        for dir in [local, upstream.appendingPathComponent("skills/other")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: \(dir.lastPathComponent)\n---\nKeep this skill\n".write(
                to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        let fs = StoreFS(env: StoreEnv(storeRoot: root.appendingPathComponent("store"), toolRoots: [:]))
        var cap = Capability(id: "demo", name: "demo", type: .skill, desc: "", version: nil,
                             author: nil, tokens: 0, dirURL: local)
        cap.repoSubdir = "skills/demo"
        let lock = root.appendingPathComponent("store/.skill-lock.json")
        try JSONSerialization.data(withJSONObject: ["skills": ["demo": ["source": upstream.path, "skillPath": "skills/demo/SKILL.md"]]]).write(to: lock)
        let entry = Entry(id: "demo", cap: cap, children: nil, sourceUrl: upstream.path)
        XCTAssertThrowsError(try fs.checkUpdate(entry))
        XCTAssertThrowsError(try fs.applyUpdate(entry))
        cap.repoSubdir = nil
        try JSONSerialization.data(withJSONObject: ["skills": ["demo": ["source": upstream.path]]]).write(to: lock)
        let withoutLockPath = Entry(id: "demo", cap: cap, children: nil, sourceUrl: upstream.path)
        XCTAssertThrowsError(try fs.checkUpdate(withoutLockPath))
        XCTAssertThrowsError(try fs.applyUpdate(withoutLockPath))
        XCTAssertTrue(try String(contentsOf: local.appendingPathComponent("SKILL.md")).contains("Keep this skill"))
        XCTAssertTrue(fs.listTrash().isEmpty)
    }

    func testDownloadSnapshotRejectsLocalEditOrSameContentReinstallation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-snapshot-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("skills/demo")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("SKILL.md")
        let original = "---\nname: demo\n---\nOriginal\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let fs = StoreFS(env: StoreEnv(storeRoot: root, toolRoots: [:]))
        let cap = Capability(id: "demo", name: "demo", type: .skill, desc: "", version: nil,
                             author: nil, tokens: 0, dirURL: dir)
        let entry = Entry(id: "demo", cap: cap, children: nil, sourceUrl: "/upstream")
        fs.mutateMeta { $0.entries[typedId(.skill, "demo")] = StoreMeta.EntryMeta(sourceUrl: "/upstream") }
        let snapshot = try fs.snapshotForUpdate(entry)
        try "New local edit".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try fs.assertUpdateSnapshot(entry, snapshot: snapshot))
        try original.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try fs.assertUpdateSnapshot(entry, snapshot: snapshot))
        try FileManager.default.moveItem(at: dir, to: root.appendingPathComponent("previous-installation"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try original.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try fs.assertUpdateSnapshot(entry, snapshot: snapshot))
    }

    func testAdditionalAgentsMountSkillsInTheirOwnDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-tools-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("store")
        let skill = store.appendingPathComponent("skills/demo")
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: demo\n---\n".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let expectedRoots = ["copilot": ".copilot", "crush": ".config/crush", "hermes": ".hermes"]
        let fs = StoreFS(env: StoreEnv(storeRoot: store, toolRoots: StoreEnv.toolRoots(at: root)))
        for (id, relative) in expectedRoots {
            let toolRoot = try XCTUnwrap(fs.env.toolRoots[id])
            let tool = Tool(id: id, name: id, root: toolRoot, connected: true, defaultTarget: false)
            try FileManager.default.createDirectory(at: toolRoot, withIntermediateDirectories: true)
            try fs.setLink(tool: tool, kind: .skill, name: "demo", storeDir: skill, on: true)
            let link = root.appendingPathComponent(relative + "/skills/demo")
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), skill.path)
            try fs.setLink(tool: tool, kind: .skill, name: "demo", storeDir: skill, on: false)
            XCTAssertTrue(FileManager.default.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path))
        }
    }

    func testDownloadSnapshotRejectsChangedMemberSourcePathAndBundleMembership() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-provenance-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let fs = StoreFS(env: StoreEnv(storeRoot: root, toolRoots: [:]))
        func install(_ name: String) throws {
            let dir = root.appendingPathComponent("skills/" + name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "---\nname: \(name)\n---\nOriginal\n".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        }
        func writeLock(_ names: [String], source: String = "owner/repo", subdir: String = "skills/a") throws {
            let skills = Dictionary(uniqueKeysWithValues: names.map { name in
                (name, ["source": source, "skillPath": (name == "a" ? subdir : "skills/" + name) + "/SKILL.md"])
            })
            try JSONSerialization.data(withJSONObject: ["skills": skills]).write(to: root.appendingPathComponent(".skill-lock.json"))
        }
        for name in ["a", "b"] { try install(name) }
        try writeLock(["a", "b"])
        let entry = try XCTUnwrap(fs.scanEntries(tools: [], meta: fs.loadMeta()).first)
        XCTAssertEqual(entry.bundleKind, .source)
        let snapshot = try fs.snapshotForUpdate(entry)
        let first = try XCTUnwrap(entry.allCaps.first { $0.name == "a" })
        let second = try XCTUnwrap(entry.allCaps.first { $0.name == "b" })
        let firstFile = first.dirURL.appendingPathComponent("SKILL.md")
        let original = try String(contentsOf: firstFile)
        try "Earlier member already updated".write(to: firstFile, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try fs.assertUpdateMember(second, snapshot: snapshot), "Each commit guard must remain valid after an earlier member updates")
        let secondFile = second.dirURL.appendingPathComponent("SKILL.md")
        let secondOriginal = try String(contentsOf: secondFile)
        try "Local edit during incoming copy".write(to: secondFile, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try fs.assertUpdateMember(second, snapshot: snapshot))
        try original.write(to: firstFile, atomically: true, encoding: .utf8)
        try secondOriginal.write(to: secondFile, atomically: true, encoding: .utf8)
        try writeLock(["a", "b"], subdir: "renamed/a")
        XCTAssertThrowsError(try fs.assertUpdateSnapshot(entry, snapshot: snapshot))
        XCTAssertThrowsError(try fs.snapshotForUpdate(entry), "A stale UI entry must not start a new download")
        try writeLock(["a", "b"])
        fs.mutateMeta { meta in meta.entries[typedId(.skill, "a")] = StoreMeta.EntryMeta(sourceUrl: "https://github.com/other/repo") }
        XCTAssertThrowsError(try fs.assertUpdateSnapshot(entry, snapshot: snapshot))
        fs.mutateMeta { $0.entries.removeValue(forKey: typedId(.skill, "a")) }
        try install("c")
        try writeLock(["a", "b", "c"])
        XCTAssertThrowsError(try fs.assertUpdateSnapshot(entry, snapshot: snapshot))
        XCTAssertThrowsError(try fs.snapshotForUpdate(entry), "A changed bundle must be rescanned before updating")
    }

    func testStandaloneLosingItsRecordedSourceCannotUseTheCachedUpdatePlan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("popskill-orphan-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("skills/unique-orphan")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: unique-orphan\n---\nLocal content\n".write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let fs = StoreFS(env: StoreEnv(storeRoot: root, toolRoots: [:]))
        let lock = root.appendingPathComponent(".skill-lock.json")
        try JSONSerialization.data(withJSONObject: ["skills": ["unique-orphan": ["source": "owner/repo"]]]).write(to: lock)
        let entry = try XCTUnwrap(fs.scanEntries(tools: [], meta: fs.loadMeta()).first)
        XCTAssertNoThrow(try fs.snapshotForUpdate(entry))
        try FileManager.default.removeItem(at: lock)
        XCTAssertThrowsError(try fs.snapshotForUpdate(entry))
        XCTAssertThrowsError(try fs.applyUpdate(entry, force: true), "Force allows replacing local edits, never updating an unverified installation")
        XCTAssertTrue(try String(contentsOf: dir.appendingPathComponent("SKILL.md")).contains("Local content"))
        XCTAssertTrue(fs.listTrash().isEmpty)
    }
}
