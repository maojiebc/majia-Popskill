import Foundation

/// 从 SKILL.md / README.md 提炼给普通用户看的结构化说明。
///
/// 不调用模型、不联网：优先尊重 frontmatter / Catalog 的 description，再从 Markdown
/// 的首段与「适用场景 / 能力」章节提取。解析失败时只降级，不影响技能扫描与挂载。
struct SkillInsight: Equatable, Sendable {
    var summary: String
    var useCases: [String]
    var capabilities: [String]
    var keywords: [String]

    static func load(for cap: Capability) -> SkillInsight {
        let names = cap.linkKind == .cli
            ? ["README.md", "SKILL.md"]
            : ["SKILL.md", "README.md"]
        let url = names
            .map { cap.dirURL.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        let markdown: String
        if let url, let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
            // 详情 peek 只需要说明区，限制读入避免异常大文档拖慢主线程。
            markdown = String(decoding: data.prefix(96 * 1024), as: UTF8.self)
        } else {
            markdown = ""
        }
        return parse(markdown: markdown, name: cap.name, fallbackDescription: cap.desc)
    }

    static func parse(markdown: String, name: String, fallbackDescription: String) -> SkillInsight {
        let body = bodyLines(markdown)
        var useCases: [String] = []
        var capabilities: [String] = []
        var generalBullets: [String] = []
        var headingKeywords: [String] = []
        var section: Section = .other
        var inFence = false

        for raw in body {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence, !trimmed.isEmpty else { continue }
            if let heading = headingText(trimmed) {
                section = classify(heading)
                let clean = cleanMarkdown(heading)
                if !clean.isEmpty { headingKeywords.append(clean) }
                continue
            }
            guard let item = listItem(trimmed) else { continue }
            let clean = normalizedItem(item)
            guard isUsefulLine(clean) else { continue }
            switch section {
            case .useCases: appendUnique(clean, to: &useCases, limit: 4)
            case .capabilities: appendUnique(clean, to: &capabilities, limit: 4)
            case .other: appendUnique(clean, to: &generalBullets, limit: 5)
            }
        }

        // 很多 Skill 没写标准章节，但开头会直接列“支持什么”。只在明确能力段缺失时
        // 拿通用 bullet 兜底，避免同一批内容同时出现在两个区块。
        if capabilities.isEmpty {
            capabilities = Array(generalBullets.prefix(3))
        }

        let fallback = cleanMarkdown(fallbackDescription)
        let first = firstParagraph(body)
        let summary: String
        if usefulDescription(fallback, name: name) {
            summary = clipped(fallback, limit: 220)
        } else if !first.isEmpty {
            summary = clipped(first, limit: 220)
        } else {
            summary = maintenanceText("\(name) 的本地能力说明暂不完整，可打开原始文档查看。",
                                      "The local description for \(name) is incomplete; open the source document for details.")
        }

        var keywords: [String] = []
        for heading in headingKeywords {
            let lower = heading.lowercased()
            guard classify(heading) == .other,
                  !["overview", "introduction", "简介", "概述", "说明"].contains(lower),
                  heading.count <= 28 else { continue }
            appendUnique(heading, to: &keywords, limit: 4)
        }

        return SkillInsight(
            summary: summary,
            useCases: useCases,
            capabilities: capabilities,
            keywords: keywords
        )
    }

    private enum Section {
        case useCases, capabilities, other
    }

    private static func bodyLines(_ markdown: String) -> [String] {
        var lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return lines
        }
        if let end = lines.dropFirst().firstIndex(where: {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return value == "---" || value == "..."
        }) {
            lines.removeSubrange(lines.startIndex...end)
        }
        return lines
    }

    private static func headingText(_ line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let text = line.drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
        return text.isEmpty ? nil : String(text)
    }

    private static func classify(_ heading: String) -> Section {
        let value = cleanMarkdown(heading).lowercased()
        let useTokens = [
            "when to use", "use cases", "use case", "recommended for", "适用场景",
            "使用场景", "何时使用", "什么时候用", "什么时候使用", "适合", "推荐场景",
        ]
        if useTokens.contains(where: value.contains) { return .useCases }
        let capabilityTokens = [
            "capabilities", "features", "what it does", "what this skill does",
            "核心能力", "主要能力", "能做什么", "功能", "能力", "支持内容",
        ]
        if capabilityTokens.contains(where: value.contains) { return .capabilities }
        return .other
    }

    private static func listItem(_ line: String) -> String? {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return String(line.dropFirst(2))
        }
        let pattern = #"^\d+[\.)]\s+"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        return String(line[range.upperBound...])
    }

    private static func firstParagraph(_ lines: [String]) -> String {
        var out: [String] = []
        var inFence = false
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            if line.isEmpty {
                if !out.isEmpty { break }
                continue
            }
            if headingText(line) != nil || listItem(line) != nil || line.hasPrefix("|")
                || line.hasPrefix("<") || line.contains("shields.io") || line.hasPrefix("![") {
                if !out.isEmpty { break }
                continue
            }
            let clean = cleanMarkdown(line)
            if isUsefulLine(clean) { out.append(clean) }
            if out.joined(separator: " ").count >= 220 { break }
        }
        return out.joined(separator: " ")
    }

    private static func cleanMarkdown(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^\)]*\)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(
            of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for token in ["**", "__", "`", "~~"] {
            value = value.replacingOccurrences(of: token, with: "")
        }
        value = value.replacingOccurrences(
            of: #"\s+"#, with: " ", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedItem(_ raw: String) -> String {
        var value = cleanMarkdown(raw)
        if let range = value.range(of: #"^\[[ xX]\]\s*"#, options: .regularExpression) {
            value.removeSubrange(range)
        }
        return clipped(value, limit: 150)
    }

    private static func usefulDescription(_ value: String, name: String) -> Bool {
        guard isUsefulLine(value), value.count >= 8 else { return false }
        let lower = value.lowercased()
        let generic = [
            name.lowercased(), "skill", "agent skill", "a skill", "暂无描述", "无描述",
            "no description", "description", "todo",
        ]
        return !generic.contains(lower)
    }

    private static func isUsefulLine(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 3 else { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return false }
        if trimmed.allSatisfy({ $0 == "-" || $0 == "=" || $0 == "_" }) { return false }
        return true
    }

    private static func appendUnique(_ value: String, to list: inout [String], limit: Int) {
        guard list.count < limit else { return }
        let key = value.lowercased()
        guard !list.contains(where: { $0.lowercased() == key }) else { return }
        list.append(value)
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
