import CryptoKit
import Darwin
import Foundation

/// 同一 store 的跨进程写锁。
///
/// - `flock` 由内核持有，进程崩溃或 fd 关闭即自动释放，不产生陈旧锁。
/// - 锁文件放用户临时目录，不放 store 内；store 被删除/重建时仍只有同一把锁。
/// - 同进程按 store 路径复用 Gate，并支持同步调用栈内重入（install → mutateMeta）。
final class StoreProcessLock: @unchecked Sendable {
    private final class Gate {
        let local = NSRecursiveLock()
        var depth = 0
        var descriptor: Int32 = -1
    }

    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var gates: [String: Gate] = [:]

    let lockURL: URL
    private let timeout: TimeInterval
    private let gate: Gate

    init(storeRoot: URL, timeout: TimeInterval = 15) {
        let normalized = storeRoot.standardizedFileURL.path.lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.majia.popskill-store-\(digest).lock")
        self.timeout = max(0, timeout)

        StoreProcessLock.registryLock.lock()
        if let existing = StoreProcessLock.gates[lockURL.path] {
            gate = existing
        } else {
            let created = Gate()
            StoreProcessLock.gates[lockURL.path] = created
            gate = created
        }
        StoreProcessLock.registryLock.unlock()
    }

    func withLock<T>(_ body: () throws -> T) throws -> T {
        try lock()
        defer { unlock() }
        return try body()
    }

    func lock() throws {
        gate.local.lock()
        do {
            if gate.depth == 0 {
                gate.descriptor = try acquireFileLock()
            }
            gate.depth += 1
        } catch {
            gate.local.unlock()
            throw error
        }
    }

    func unlock() {
        precondition(gate.depth > 0, "unbalanced StoreProcessLock.unlock")
        gate.depth -= 1
        if gate.depth == 0 {
            _ = flock(gate.descriptor, LOCK_UN)
            _ = close(gate.descriptor)
            gate.descriptor = -1
        }
        gate.local.unlock()
    }

    private func acquireFileLock() throws -> Int32 {
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw StoreError.storeBusy
        }

        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            if code == EINTR { continue }
            guard code == EWOULDBLOCK || code == EAGAIN,
                ProcessInfo.processInfo.systemUptime < deadline
            else {
                _ = close(descriptor)
                throw StoreError.storeBusy
            }
            usleep(20_000)
        }
        return descriptor
    }
}
