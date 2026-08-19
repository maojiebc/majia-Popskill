import Foundation

/// 工作模式（v2.20，吸收 CC Switch Profile）。
/// 套装描述「这批技能从哪来」；工作模式描述「此刻这个任务场景该挂哪些」。
///
/// 快照语义：
/// - 缺某个 toolId 键 = 从未为该工具保存，切换时不动它
/// - 键在、数组空 = 明确要求该工具全部断开
struct WorkProfile: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var note: String?
    var tools: [String: [String]]
}

struct ProfileChange: Equatable {
    var toolId: String
    var toolName: String
    var turnOn: [String]
    var turnOff: [String]
    var missing: [String]
    var blocked: [String]

    var isNoop: Bool {
        turnOn.isEmpty && turnOff.isEmpty && missing.isEmpty && blocked.isEmpty
    }
}

func captureWorkSnapshot(entries: [Entry], tools: [Tool]) -> [String: [String]] {
    let caps = entries.filter { !$0.isManagedExternally }.flatMap(\.allCaps)
    var out: [String: [String]] = [:]
    for t in tools {
        out[t.id] = caps.filter { $0.status(t.id) == .on }.map(\.id).sorted()
    }
    return out
}

func diffWorkSnapshot(
    desired: [String: [String]],
    entries: [Entry],
    tools: [Tool]
) -> [ProfileChange] {
    let caps = entries.filter { !$0.isManagedExternally }.flatMap(\.allCaps)
    let byId = Dictionary(uniqueKeysWithValues: caps.map { ($0.id, $0) })
    var changes: [ProfileChange] = []
    for (toolId, wantIds) in desired {
        guard let tool = tools.first(where: { $0.id == toolId }) else { continue }
        let want = Set(wantIds)
        var turnOn: [String] = []
        var turnOff: [String] = []
        var blocked: [String] = []
        let missing = wantIds.filter { byId[$0] == nil }.sorted()
        for c in caps {
            let st = c.status(toolId)
            let should = want.contains(c.id)
            switch (should, st) {
            case (true, .off): turnOn.append(c.name)
            case (false, .on): turnOff.append(c.name)
            case (true, .on), (false, .off): break
            default: blocked.append(c.name)
            }
        }
        let change = ProfileChange(
            toolId: toolId, toolName: tool.name,
            turnOn: turnOn.sorted(), turnOff: turnOff.sorted(),
            missing: missing, blocked: blocked.sorted()
        )
        if !change.isNoop { changes.append(change) }
    }
    return changes.sorted { $0.toolName.localizedStandardCompare($1.toolName) == .orderedAscending }
}

func workSnapshotMatches(desired: [String: [String]], current: [String: [String]]) -> Bool {
    let keys = Set(desired.keys).intersection(current.keys)
    return keys.allSatisfy { Set(desired[$0] ?? []) == Set(current[$0] ?? []) }
}

func formatProfilePlan(_ changes: [ProfileChange]) -> String {
    guard !changes.isEmpty else { return "" }
    let sep = L("、")
    let semi = L("；")
    return changes.map { c in
        var parts: [String] = []
        if !c.turnOn.isEmpty { parts.append(L("将挂载 \(c.turnOn.joined(separator: sep))")) }
        if !c.turnOff.isEmpty { parts.append(L("将断开 \(c.turnOff.joined(separator: sep))")) }
        if !c.missing.isEmpty { parts.append(L("已删除 \(c.missing.count) 项，跳过")) }
        if !c.blocked.isEmpty { parts.append(L("断链/本地副本 \(c.blocked.joined(separator: sep))，需先修复")) }
        return "\(c.toolName)：\(parts.joined(separator: semi))"
    }.joined(separator: "\n")
}
