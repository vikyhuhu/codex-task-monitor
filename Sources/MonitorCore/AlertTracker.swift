import Foundation

/// Only observed transitions produce alerts. Starting/restarting never replays history.
public struct AlertTracker {
    private var previous: [String: TaskStatus] = [:]
    private var baselineEstablished = false
    private var delivered = Set<String>()
    public init() {}
    public mutating func silenceNextUpdate() { baselineEstablished = false }
    public mutating func update(_ records: [TaskRecord], dismissed: Set<String> = []) -> [TaskRecord] {
        let alerts = records.filter {
            baselineEstablished && !dismissed.contains($0.key) && previous[$0.key] != $0.status && !delivered.contains($0.key + ":" + $0.status.rawValue) &&
                [.ended, .needsInput, .failed, .interrupted].contains($0.status)
        }
        for record in (baselineEstablished ? alerts : records) {
            delivered.insert(record.key + ":" + record.status.rawValue)
        }
        previous = Dictionary(records.map { ($0.key, $0.status) }, uniquingKeysWith: { _, new in new })
        baselineEstablished = true
        return alerts
    }
}
