import Foundation

enum MatrixVersionFormatter {
    static func value(manifestVersion: String?, contentHash: String?, updatedAt: Int?) -> String? {
        if let version = semanticVersion(manifestVersion) {
            return version
        }
        return value(contentHash: contentHash, updatedAt: updatedAt)
    }

    static func value(contentHash: String?, updatedAt: Int?) -> String? {
        if let hash = shortHash(contentHash) {
            return hash
        }
        if let updatedAt, updatedAt > 0 {
            return dateString(updatedAt)
        }
        return nil
    }

    static func shortHash(_ hash: String?) -> String? {
        guard let hash = hash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !hash.isEmpty else {
            return nil
        }
        return String(hash.prefix(7))
    }

    static func semanticVersion(_ version: String?) -> String? {
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else {
            return nil
        }
        return version.hasPrefix("v") ? version : "v\(version)"
    }

    private static func dateString(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
