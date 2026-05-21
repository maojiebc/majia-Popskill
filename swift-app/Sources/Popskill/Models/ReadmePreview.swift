import Foundation

struct ReadmePreview: Equatable, Sendable {
    struct Excerpt: Equatable, Sendable {
        let text: String
        let truncated: Bool
    }

    let skillID: String
    let skillName: String
    let url: URL
    let excerpt: String
    let truncated: Bool

    static let maxBytes = 24 * 1024
    static let maxCharacters = 1_600
    static let maxLines = 26

    static func load(skillID: String, skillName: String, readmeURL: URL) throws -> ReadmePreview {
        guard FileManager.default.fileExists(atPath: readmeURL.path) else {
            throw ReadmePreviewError.missing
        }

        let handle = try FileHandle(forReadingFrom: readmeURL)
        defer { try? handle.close() }

        let data = try handle.read(upToCount: maxBytes) ?? Data()
        let content = String(decoding: data, as: UTF8.self)
        let excerpt = makeExcerpt(from: content)

        guard !excerpt.text.isEmpty else {
            throw ReadmePreviewError.empty
        }

        return ReadmePreview(
            skillID: skillID,
            skillName: skillName,
            url: readmeURL,
            excerpt: excerpt.text,
            truncated: excerpt.truncated || data.count >= maxBytes
        )
    }

    static func makeExcerpt(
        from content: String,
        maxCharacters: Int = Self.maxCharacters,
        maxLines: Int = Self.maxLines
    ) -> Excerpt {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let contentLines = dropYAMLFrontmatter(from: rawLines)
        let compactedLines = compactBlankRuns(in: contentLines)
            .drop { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var selected: [String] = []
        var currentCharacters = 0
        var truncated = false

        for line in compactedLines {
            let cleanLine = line.trimmingCharacters(in: .whitespaces)
            let additionalCharacters = cleanLine.count + (selected.isEmpty ? 0 : 1)

            guard selected.count < maxLines else {
                truncated = true
                break
            }
            guard currentCharacters + additionalCharacters <= maxCharacters else {
                truncated = true
                break
            }

            selected.append(cleanLine)
            currentCharacters += additionalCharacters
        }

        let excerpt = selected
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Excerpt(text: excerpt, truncated: truncated)
    }

    private static func dropYAMLFrontmatter(from lines: [String]) -> ArraySlice<String> {
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return ArraySlice(lines)
        }

        let searchRange = lines.dropFirst().prefix(40)
        guard let closingIndex = searchRange.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == "---" || trimmed == "..."
        }) else {
            return ArraySlice(lines)
        }

        let nextIndex = lines.index(after: closingIndex)
        guard nextIndex < lines.endIndex else {
            return []
        }
        return lines[nextIndex...]
    }

    private static func compactBlankRuns(in lines: ArraySlice<String>) -> [String] {
        var compacted: [String] = []
        var previousWasBlank = false

        for line in lines {
            let isBlank = line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isBlank {
                guard !previousWasBlank else { continue }
                compacted.append("")
            } else {
                compacted.append(line)
            }
            previousWasBlank = isBlank
        }

        while compacted.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            compacted.removeLast()
        }
        return compacted
    }
}

enum ReadmePreviewLoadState: Equatable {
    case loading
    case loaded(ReadmePreview)
    case failed(String)
}

enum ReadmePreviewError: LocalizedError {
    case missing
    case empty

    var errorDescription: String? {
        switch self {
        case .missing:
            "SKILL.md was not found."
        case .empty:
            "SKILL.md did not contain readable text."
        }
    }
}
