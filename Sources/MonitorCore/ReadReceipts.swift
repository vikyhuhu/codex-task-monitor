import Foundation

/// Optional read state from the local desktop app. Missing data is never “all read”.
public struct ReadReceipts {
    public let unread: Set<String>
    public let modifiedAt: Date
    public init?(data: Data, modifiedAt: Date) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atoms = root["electron-persisted-atom-state"] as? [String: Any],
              let hosts = atoms["unread-thread-ids-by-host-v1"] as? [String: Any],
              let local = hosts["local"] as? [String] else { return nil }
        self.unread = Set(local); self.modifiedAt = modifiedAt
    }
    public func isRead(_ task: TaskRecord, now: Date = Date()) -> Bool {
        // Allow the desktop app to persist its end-of-turn unread update first.
        task.status == .ended && now.timeIntervalSince(task.updatedAt) >= 10 &&
            modifiedAt >= task.updatedAt && !unread.contains(task.id)
    }
    public static func load(home: URL) -> ReadReceipts? {
        let url = home.appendingPathComponent(".codex-global-state.json")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              let data = try? Data(contentsOf: url) else { return nil }
        return ReadReceipts(data: data, modifiedAt: modified)
    }
}
