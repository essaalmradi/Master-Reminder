import Foundation

public final class StorageManager {
    public let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    public init(url: URL) {
        self.url = url
        encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    }
    public func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppData() }
        return try decode(Data(contentsOf: url))
    }
    public func decode(_ bytes: Data) throws -> AppData {
        guard bytes.count <= 10_000_000 else { throw DataError.fileTooLarge }
        var result = try decoder.decode(AppData.self, from: bytes)
        try result.validate()
        return result
    }
    public func encoded(_ data: AppData) throws -> Data {
        var checked = data
        checked.reminders.removeAll { $0.isTemporary }
        checked.snoozes.removeAll { $0.reminder.isTemporary }
        try checked.validate()
        return try encoder.encode(checked)
    }
    public func save(_ data: AppData) throws {
        let bytes = try encoded(data)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try bytes.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
