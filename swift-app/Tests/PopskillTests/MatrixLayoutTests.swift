import XCTest
@testable import Popskill

final class MatrixLayoutTests: XCTestCase {
    func testWideThreshold() {
        XCTAssertFalse(MatrixLayout.wide(toolCount: 0))
        XCTAssertFalse(MatrixLayout.wide(toolCount: 2))
        XCTAssertTrue(MatrixLayout.wide(toolCount: 3))
        XCTAssertTrue(MatrixLayout.wide(toolCount: 6))
    }

    func testPackFoldedBundleMixesWithCaps() {
        let packed = MatrixLayout.pack([foldedBundle("b"), cap("a"), cap("c")], columns: 2)
        XCTAssertEqual(packed.map { $0.map(\.id) }, [["b-b", "c-a"], ["c-c"]])
        XCTAssertFalse(MatrixLayout.isFullWidthBundle(packed[0]))
    }

    func testPackExpandedBundleAlwaysSpans() {
        let packed = MatrixLayout.pack([expandedBundle("e"), cap("a")], columns: 2)
        XCTAssertEqual(packed.map { $0.map(\.id) }, [["b-e"], ["c-a"]])
        XCTAssertTrue(MatrixLayout.isFullWidthBundle(packed[0]))
    }

    private func cap(_ name: String) -> DisplayItem {
        let c = Capability(
            id: name, name: name, type: .skill, desc: "",
            version: nil, author: nil, tokens: 0,
            dirURL: URL(fileURLWithPath: "/tmp/\(name)"))
        return .cap(c, entry: Entry(id: name, cap: c, children: nil), fromBundle: nil)
    }

    private func foldedBundle(_ name: String) -> DisplayItem {
        let kid = Capability(
            id: "\(name)-k", name: "\(name)-k", type: .skill, desc: "",
            version: nil, author: nil, tokens: 0,
            dirURL: URL(fileURLWithPath: "/tmp/\(name)-k"))
        let head = Capability(
            id: name, name: name, type: .bundle, desc: "",
            version: nil, author: nil, tokens: 0,
            dirURL: URL(fileURLWithPath: "/tmp/\(name)"))
        return .bundle(Entry(id: name, cap: head, children: [kid]), kids: nil)
    }

    private func expandedBundle(_ name: String) -> DisplayItem {
        let kid = Capability(
            id: "\(name)-k", name: "\(name)-k", type: .skill, desc: "",
            version: nil, author: nil, tokens: 0,
            dirURL: URL(fileURLWithPath: "/tmp/\(name)-k"))
        let head = Capability(
            id: name, name: name, type: .bundle, desc: "",
            version: nil, author: nil, tokens: 0,
            dirURL: URL(fileURLWithPath: "/tmp/\(name)"))
        return .bundle(Entry(id: name, cap: head, children: [kid]), kids: [kid])
    }
}
