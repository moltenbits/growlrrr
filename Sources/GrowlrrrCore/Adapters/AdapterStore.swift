import Foundation

/// Small values an adapter keeps between runs of growlrrr, such
/// as something noted when a prompt was submitted and needed when the turn
/// ends. Those are separate processes, so each key is a file of its own.
///
/// Get one from `AdapterContext.store(for:)`; each adapter has its own.
public struct AdapterStore {
    public enum StoreError: Error {
        case invalidKey(String)
    }

    /// A key becomes a file name, so it is limited to plain names.
    private static let keyCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    public func value(forKey key: String) -> String? {
        guard let file = file(forKey: key),
              let value = try? String(contentsOf: file, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    public func set(_ value: String, forKey key: String) throws {
        guard let file = file(forKey: key) else {
            throw StoreError.invalidKey(key)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try value.write(to: file, atomically: true, encoding: .utf8)
    }

    public func removeValue(forKey key: String) {
        guard let file = file(forKey: key) else {
            return
        }
        try? FileManager.default.removeItem(at: file)
    }

    private func file(forKey key: String) -> URL? {
        guard !key.isEmpty, key.unicodeScalars.allSatisfy(Self.keyCharacters.contains) else {
            return nil
        }
        return directory.appendingPathComponent(key)
    }
}
