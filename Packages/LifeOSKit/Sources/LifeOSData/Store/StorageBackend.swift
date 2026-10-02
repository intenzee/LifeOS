import Foundation
import LifeOSCore

/// Byte storage under a root, addressed by relative paths like `food/2026-10.json`.
/// Implementations are thread-safe. Callers (store actors) never use them on the main thread.
public protocol StorageBackend: Sendable {
    func read(_ path: String) throws -> Data?
    /// Atomic replace.
    func write(_ data: Data, to path: String) throws
    func remove(_ path: String) throws
    func move(_ path: String, to newPath: String) throws
    /// File names (not paths) directly inside `directory`. Empty if it doesn't exist.
    func list(_ directory: String) throws -> [String]
}

/// Files under a root directory, protected with
/// `.completeUntilFirstUserAuthentication` (SEC-01). Not `.complete`: HealthKit
/// background delivery and BG tasks must write while the phone is locked
/// (doc 09 §3.1).
public final class FileStorageBackend: StorageBackend {
    public let root: URL

    public init(root: URL) throws {
        self.root = root
        try Self.createDirectory(root)
    }

    /// `Application Support/LifeOSStore/v1`. Included in the encrypted device backup.
    public static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appendingPathComponent("LifeOSStore/v1", isDirectory: true)
    }

    public func read(_ path: String) throws -> Data? {
        let url = url(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, to path: String) throws {
        let url = url(for: path)
        try Self.createDirectory(url.deletingLastPathComponent())
        try data.write(to: url, options: Self.writeOptions)
    }

    public func remove(_ path: String) throws {
        let url = url(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func move(_ path: String, to newPath: String) throws {
        let destination = url(for: newPath)
        try Self.createDirectory(destination.deletingLastPathComponent())
        try FileManager.default.moveItem(at: url(for: path), to: destination)
    }

    public func list(_ directory: String) throws -> [String] {
        let url = url(for: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    private func url(for path: String) -> URL {
        root.appendingPathComponent(path, isDirectory: false)
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS) || os(watchOS) || os(visionOS)
        return [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        return [.atomic]
        #endif
    }

    private static func createDirectory(_ url: URL) throws {
        #if os(iOS) || os(watchOS) || os(visionOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
    }
}

/// In-memory backend for tests, previews and fixture personas.
public final class InMemoryStorageBackend: StorageBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    /// Counts writes, so tests can assert batching (e.g. one write per shard).
    public private(set) var writeCount = 0

    public init() {}

    public func read(_ path: String) throws -> Data? {
        lock.withLock { files[path] }
    }

    public func write(_ data: Data, to path: String) throws {
        lock.withLock {
            files[path] = data
            writeCount += 1
        }
    }

    public func remove(_ path: String) throws {
        _ = lock.withLock { files.removeValue(forKey: path) }
    }

    public func move(_ path: String, to newPath: String) throws {
        try lock.withLock {
            guard let data = files.removeValue(forKey: path) else {
                throw StringError("No file at \(path)")
            }
            files[newPath] = data
        }
    }

    public func list(_ directory: String) throws -> [String] {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return lock.withLock {
            files.keys
                .filter { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
                .filter { !$0.contains("/") }
        }
    }
}
