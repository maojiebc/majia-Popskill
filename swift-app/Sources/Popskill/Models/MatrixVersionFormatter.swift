import Foundation

enum MatrixVersionFormatter {
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

    private static func dateString(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
