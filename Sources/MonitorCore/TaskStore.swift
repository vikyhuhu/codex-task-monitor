import Foundation
import CSQLite

public enum StoreError: LocalizedError {
    case unavailable(String)
    public var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

public final class TaskStore {
    private let home: URL
    private var readers: [String: RolloutReader] = [:]
    public init(home: URL) { self.home = home }
    public func snapshot(since: Date, now: Date = Date()) throws -> [TaskRecord] {
        let files = try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)
        let databases = files.filter { $0.lastPathComponent.range(of: #"^state_\d+\.sqlite$"#, options: .regularExpression) != nil }
        guard let dbURL = databases.sorted(by: {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
        }).first else { throw StoreError.unavailable("找不到 Codex 本地任务库。请先在 Codex 中运行一个任务。") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw StoreError.unavailable("无法只读打开 Codex 任务库。")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1000)
        var stmt: OpaquePointer?
        // Root tasks only. Name is the UI title; title can contain the full first prompt.
        let sql = "SELECT id, COALESCE(NULLIF(name, ''), title), cwd, rollout_path FROM threads WHERE archived = 0 AND source NOT LIKE '%subagent%' AND updated_at >= ? ORDER BY updated_at DESC"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.unavailable("Codex 数据格式不兼容；未将任务误报为完成。")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(min(since.timeIntervalSince1970, now.addingTimeInterval(-86400).timeIntervalSince1970)))
        func field(_ index: Int32) -> String {
            sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? ""
        }
        var records: [TaskRecord] = []
        var retained = Set<String>()
        var result = sqlite3_step(stmt)
        while result == SQLITE_ROW {
            let id = field(0), title = field(1), cwd = field(2), path = field(3)
            retained.insert(path)
            let reader = readers[path] ?? RolloutReader()
            readers[path] = reader
            do {
                try reader.read(URL(fileURLWithPath: path))
                let state = reader.lifecycle
                if state.hasStarted && (state.startedAt >= since || state.status == .running || state.status == .needsInput) {
                    let status = state.displayStatus(now: now)
                    records.append(TaskRecord(id: id, title: title, project: URL(fileURLWithPath: cwd).lastPathComponent,
                        status: status, turnID: state.turnID, startedAt: state.startedAt, updatedAt: state.updatedAt,
                        detail: status == .uncertain ? "15 分钟没有新日志；可能仍在执行，请查看任务" : ""))
                }
            } catch {
                records.append(TaskRecord(id: id, title: title, project: URL(fileURLWithPath: cwd).lastPathComponent,
                    status: .uncertain, turnID: reader.lifecycle.turnID, startedAt: reader.lifecycle.startedAt,
                    updatedAt: reader.lifecycle.updatedAt, detail: "任务日志暂时不可读"))
            }
            result = sqlite3_step(stmt)
        }
        guard result == SQLITE_DONE else { throw StoreError.unavailable("任务库正在更新，稍后重试。") }
        readers = readers.filter { retained.contains($0.key) }
        return records.sorted { a, b in
            a.status.order == b.status.order ? a.updatedAt > b.updatedAt : a.status.order < b.status.order
        }
    }
}
