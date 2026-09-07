import Foundation

public enum TaskStatus: String, Codable, CaseIterable {
    case running, needsInput, ended, interrupted, failed, uncertain
    public var label: String {
        switch self {
        case .running: return "运行中"
        case .needsInput: return "等你处理"
        case .ended: return "本轮结束 · 待查看"
        case .interrupted: return "已中断"
        case .failed: return "执行失败"
        case .uncertain: return "状态待确认"
        }
    }
    public var symbol: String {
        switch self {
        case .running: return "arrow.triangle.2.circlepath"
        case .needsInput: return "hand.raised.fill"
        case .ended: return "checkmark.circle.fill"
        case .interrupted: return "pause.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .uncertain: return "questionmark.circle"
        }
    }
    public var order: Int {
        switch self {
        case .needsInput: return 0
        case .failed: return 1
        case .interrupted: return 2
        case .uncertain: return 3
        case .ended: return 4
        case .running: return 5
        }
    }
}

public struct TaskRecord: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var project: String
    public var status: TaskStatus
    public var turnID: String
    public var startedAt: Date
    public var updatedAt: Date
    public var detail: String
    public var key: String { id + ":" + turnID }
}

/// A reducer over explicit lifecycle events. No prose-based completion inference.
public struct Lifecycle {
    public private(set) var status: TaskStatus = .uncertain
    public private(set) var turnID = ""
    public private(set) var startedAt = Date.distantPast
    public private(set) var updatedAt = Date.distantPast
    public private(set) var hasStarted = false
    private var pendingQuestion = false
    public init() {}

    public mutating func consume(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let p = root["payload"] as? [String: Any] else { return }
        let outer = root["type"] as? String ?? ""
        let type = p["type"] as? String ?? ""
        let timestamp = Self.date(root["timestamp"]) ?? updatedAt
        // Token records and tool output count as activity, not task completion.
        if hasStarted { updatedAt = max(updatedAt, timestamp) }
        if outer == "event_msg" {
            switch type {
            case "task_started":
                let newID = p["turn_id"] as? String ?? String(timestamp.timeIntervalSince1970)
                if newID != turnID { pendingQuestion = false }
                turnID = newID; startedAt = timestamp; updatedAt = timestamp
                hasStarted = true; status = .running
            case "task_complete":
                guard matches(p) else { return }
                status = pendingQuestion ? .needsInput : .ended
            case "turn_aborted":
                guard matches(p) else { return }
                pendingQuestion = false; status = .interrupted
            case "task_failed":
                guard matches(p) else { return }
                pendingQuestion = false; status = .failed
            case "user_message":
                pendingQuestion = false
                if hasStarted { status = .running }
            default: break
            }
        }
        if outer == "response_item" {
            if type == "message", p["role"] as? String == "user" {
                pendingQuestion = false
                if hasStarted { status = .running }
            }
            let name = p["name"] as? String ?? ""
            if ["function_call", "custom_tool_call"].contains(type) {
                let directName = name.split(separator: ".").last.map(String.init) ?? name
                // Do not inspect exec source: quoted fixtures or documentation may
                // contain request calls that were never executed.
                if directName == "request_user_input" || directName == "request_user_input_async" {
                    pendingQuestion = true; status = .needsInput
                }
            }
        }
    }
    private func matches(_ p: [String: Any]) -> Bool {
        guard hasStarted else { return false }
        return (p["turn_id"] as? String).map { $0 == turnID } ?? true
    }
    public func displayStatus(now: Date, staleAfter: TimeInterval = 900) -> TaskStatus {
        status == .running && now.timeIntervalSince(updatedAt) > staleAfter ? .uncertain : status
    }
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let plain = ISO8601DateFormatter()
    private static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return fractional.date(from: s) ?? plain.date(from: s)
    }
}

/// Incremental JSONL reader. Incomplete writes are retained until the next poll.
public final class RolloutReader {
    public private(set) var lifecycle = Lifecycle()
    private var offset: UInt64 = 0
    private var pending = Data()
    private var identity: UInt64?
    private var droppingOversizedLine = false
    public init() {}
    public func read(_ url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
        if size < offset || (identity != nil && identity != inode) {
            offset = 0; pending.removeAll(); lifecycle = Lifecycle(); droppingOversizedLine = false
        }
        identity = inode
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        try file.seek(toOffset: offset)
        while let chunk = try file.read(upToCount: 65536), !chunk.isEmpty {
            offset += UInt64(chunk.count)
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                if !droppingOversizedLine { lifecycle.consume(Data(line)) }
                pending.removeSubrange(...newline)
                droppingOversizedLine = false
            }
            // Giant tool outputs are irrelevant to lifecycle. Bound memory usage.
            if pending.count > 2_097_152 { pending.removeAll(keepingCapacity: false); droppingOversizedLine = true }
        }
    }
}
