import Foundation

/// Optional read state from the local desktop app. Missing data is never “all read”.
public struct ReadReceipts {
    public let unread: Set<String>
    public let modifiedAt: Date
    public init?(data: Data, modifiedAt: Date) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let current = root["electron-thread-read-state-v1"] {
            // The desktop now persists read state outside the legacy atom store.
            // Never fall back to stale legacy data if a new-format key is present.
            guard let encoded = try? JSONSerialization.data(withJSONObject: current, options: [.fragmentsAllowed]),
                  let state = try? JSONDecoder().decode(CurrentState.self, from: encoded),
                  state.version == 1,
                  state.unreadByIdentity.count == 1,
                  let hosts = state.unreadByIdentity.values.first else { return nil }
            // Do not guess the active account or execution host when ambiguous.
            // Resolving those identities would require additional app/auth data.
            let local = hosts.filter { $0.key.hasPrefix("local:") && $0.key.count > "local:".count }
            guard local.count == 1, let ids = local.values.first else { return nil }
            self.unread = Set(ids)
        } else {
            guard let atoms = root["electron-persisted-atom-state"] as? [String: Any],
                  let hosts = atoms["unread-thread-ids-by-host-v1"] as? [String: Any],
                  let local = hosts["local"] as? [String] else { return nil }
            self.unread = Set(local)
        }
        self.modifiedAt = modifiedAt
    }
    private struct CurrentState: Decodable {
        let version: Int
        let unreadByIdentity: [String: [String: [String]]]
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
