import Foundation
import MonitorCore
import CSQLite


private var failures = 0
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { failures += 1; print("FAIL \(file):\(line): \(actual) != \(expected)") }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(value, false, file: file, line: line) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); failures += 1; print("FAIL \(file):\(line): expected error") } catch {}
}

final class LifecycleTests {
    let base = Date(timeIntervalSince1970: 1_788_800_000)
    func line(_ type: String, _ fields: [String: Any] = [:], outer: String = "event_msg", offset: Double = 0) -> Data {
        var payload = fields; payload["type"] = type
        return try! JSONSerialization.data(withJSONObject: ["type": outer, "timestamp": ISO8601DateFormatter().string(from: base.addingTimeInterval(offset)), "payload": payload])
    }
    func started() -> Lifecycle {
        var s = Lifecycle(); s.consume(line("task_started", ["turn_id": "one"])); return s
    }
    func testOnlyExplicitCompletionEndsTurn() {
        var s = started()
        s.consume(line("message", ["role": "assistant", "phase": "final"], outer: "response_item", offset: 1))
        XCTAssertEqual(s.status, .running)
        s.consume(line("task_complete", ["turn_id": "one"], offset: 2))
        XCTAssertEqual(s.status, .ended)
    }
    func testOldCompletionDoesNotEndNewTurn() {
        var s = started(); s.consume(line("task_started", ["turn_id": "two"], offset: 1))
        s.consume(line("task_complete", ["turn_id": "one"], offset: 2))
        XCTAssertEqual(s.status, .running)
    }
    func testQuestionRemainsVisibleAtEndAndClearsNextTurn() {
        var s = started()
        s.consume(line("function_call", ["name": "request_user_input_async"], outer: "response_item", offset: 1))
        s.consume(line("task_complete", ["turn_id": "one"], offset: 2))
        XCTAssertEqual(s.status, .needsInput)
        s.consume(line("task_started", ["turn_id": "two"], offset: 3))
        XCTAssertEqual(s.status, .running)
        s.consume(line("task_complete", ["turn_id": "two"], offset: 4))
        XCTAssertEqual(s.status, .ended)
    }
    func testQuotedExecCodeDoesNotTriggerQuestion() {
        var s = started()
        s.consume(line("custom_tool_call", ["name": "exec", "input": "await tools.request_user_input_async({questions: []});"], outer: "response_item", offset: 1))
        XCTAssertEqual(s.status, .running)
        s.consume(line("message", ["role": "user"], outer: "response_item", offset: 2))
        XCTAssertEqual(s.status, .running)
    }
    func testProseDoesNotTriggerQuestion() {
        var s = started()
        s.consume(line("message", ["role": "assistant", "content": "request_user_input"], outer: "response_item"))
        XCTAssertEqual(s.status, .running)
    }
    func testAbortAndStaleAreNotSuccess() {
        var s = started()
        XCTAssertEqual(s.displayStatus(now: base.addingTimeInterval(901)), .uncertain)
        s.consume(line("turn_aborted", ["turn_id": "one"], offset: 1000))
        XCTAssertEqual(s.status, .interrupted)
    }
    func testToolFailureIsNotTaskFailure() {
        var s = started()
        s.consume(line("function_call_output", ["output": "Error: connection failed"], outer: "response_item"))
        XCTAssertEqual(s.status, .running)
        s.consume(line("task_failed", ["turn_id": "one"]))
        XCTAssertEqual(s.status, .failed)
    }
    func testUnstartedLogIsUnknown() {
        var s = Lifecycle(); s.consume(line("task_complete", ["turn_id": "one"]))
        XCTAssertFalse(s.hasStarted); XCTAssertEqual(s.status, .uncertain)
    }
    func testReaderPartialWriteMalformedLineAndTruncation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var data = line("task_started", ["turn_id": "one"]); data.append(10)
        let complete = line("task_complete", ["turn_id": "one"], offset: 1)
        data.append(complete.prefix(20)); try data.write(to: url)
        let reader = RolloutReader(); try reader.read(url)
        XCTAssertEqual(reader.lifecycle.status, .running)
        let file = try FileHandle(forWritingTo: url); try file.seekToEnd()
        try file.write(contentsOf: complete.dropFirst(20)); try file.write(contentsOf: Data("\nnot-json\n".utf8)); try file.close()
        try reader.read(url); XCTAssertEqual(reader.lifecycle.status, .ended)
        try reader.read(url); XCTAssertEqual(reader.lifecycle.status, .ended)
        var replacement = line("task_started", ["turn_id": "two"]); replacement.append(10)
        try replacement.write(to: url); try reader.read(url)
        XCTAssertEqual(reader.lifecycle.status, .running); XCTAssertEqual(reader.lifecycle.turnID, "two")
    }
    func testSQLiteIntegrationFiltersArchiveSubagentsAndHistoricalCompleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE threads(id TEXT, name TEXT, title TEXT, cwd TEXT, rollout_path TEXT, archived INTEGER, source TEXT, updated_at INTEGER)", nil, nil, nil), SQLITE_OK)
        for (id, archived, source, end) in [("live", 0, "vscode", false), ("old", 0, "vscode", true), ("archived", 1, "vscode", false), ("child", 0, "subagent", false)] {
            let path = root.appendingPathComponent(id + ".jsonl")
            var data = line("task_started", ["turn_id": id]); data.append(10)
            if end { data.append(line("task_complete", ["turn_id": id])); data.append(10) }
            try data.write(to: path)
            XCTAssertEqual(sqlite3_exec(db, "INSERT INTO threads VALUES ('\(id)', 'UI title', 'raw prompt', '/project', '\(path.path)', \(archived), '\(source)', \(Int(base.timeIntervalSince1970)))", nil, nil, nil), SQLITE_OK)
        }
        let store = TaskStore(home: root)
        let snapshot = try store.snapshot(since: base.addingTimeInterval(1), now: base.addingTimeInterval(2))
        XCTAssertEqual(snapshot.count, 1); XCTAssertEqual(snapshot.first?.id, "live"); XCTAssertEqual(snapshot.first?.title, "UI title")
        // Monitor never writes the source database.
        XCTAssertEqual(try store.snapshot(since: base, now: base.addingTimeInterval(2)).count, 2)
    }
    func testNotificationTransitionsDedupDismissalAndRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var db: OpaquePointer?; sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE threads(id TEXT, name TEXT, title TEXT, cwd TEXT, rollout_path TEXT, archived INTEGER, source TEXT, updated_at INTEGER)", nil, nil, nil)
        let url = root.appendingPathComponent("task.jsonl")
        var data = line("task_started", ["turn_id": "one"]); data.append(10); try data.write(to: url)
        sqlite3_exec(db, "INSERT INTO threads VALUES ('task', 'Test', '', '/test', '\(url.path)', 0, 'vscode', \(Int(base.timeIntervalSince1970)))", nil, nil, nil)
        let store = TaskStore(home: root)
        let live = try store.snapshot(since: base, now: base)
        var tracker = AlertTracker()
        XCTAssertEqual(tracker.update(live).count, 0)
        let file = try FileHandle(forWritingTo: url); try file.seekToEnd()
        try file.write(contentsOf: line("task_complete", ["turn_id": "one"], offset: 1)); try file.write(contentsOf: Data([10])); try file.close()
        let ended = try store.snapshot(since: base, now: base.addingTimeInterval(2))
        XCTAssertEqual(tracker.update(ended).count, 1)
        XCTAssertEqual(tracker.update(ended).count, 0)
        _ = tracker.update([])
        XCTAssertEqual(tracker.update(ended).count, 0)
        var restarted = AlertTracker(); XCTAssertEqual(restarted.update(ended).count, 0)
        _ = tracker.update(live)
        XCTAssertEqual(tracker.update(ended, dismissed: Set(ended.map { $0.key })).count, 0)
        tracker.silenceNextUpdate(); XCTAssertEqual(tracker.update(ended).count, 0)
    }
    func testMissingDatabaseThrowsInsteadOfEmptySuccess() {
        XCTAssertThrowsError(try TaskStore(home: URL(fileURLWithPath: "/does-not-exist")).snapshot(since: base))
    }
}

let suite = LifecycleTests()
suite.testOnlyExplicitCompletionEndsTurn(); print("CHECK testOnlyExplicitCompletionEndsTurn")
suite.testOldCompletionDoesNotEndNewTurn(); print("CHECK testOldCompletionDoesNotEndNewTurn")
suite.testQuestionRemainsVisibleAtEndAndClearsNextTurn(); print("CHECK testQuestionRemainsVisibleAtEndAndClearsNextTurn")
suite.testQuotedExecCodeDoesNotTriggerQuestion(); print("CHECK testQuotedExecCodeDoesNotTriggerQuestion")
suite.testProseDoesNotTriggerQuestion(); print("CHECK testProseDoesNotTriggerQuestion")
suite.testAbortAndStaleAreNotSuccess(); print("CHECK testAbortAndStaleAreNotSuccess")
suite.testToolFailureIsNotTaskFailure(); print("CHECK testToolFailureIsNotTaskFailure")
suite.testUnstartedLogIsUnknown(); print("CHECK testUnstartedLogIsUnknown")
do { try suite.testReaderPartialWriteMalformedLineAndTruncation(); print("CHECK testReaderPartialWriteMalformedLineAndTruncation") } catch { failures += 1; print("FAIL testReaderPartialWriteMalformedLineAndTruncation: \(error)") }
do { try suite.testSQLiteIntegrationFiltersArchiveSubagentsAndHistoricalCompleted(); print("CHECK testSQLiteIntegrationFiltersArchiveSubagentsAndHistoricalCompleted") } catch { failures += 1; print("FAIL testSQLiteIntegrationFiltersArchiveSubagentsAndHistoricalCompleted: \(error)") }
suite.testMissingDatabaseThrowsInsteadOfEmptySuccess(); print("CHECK testMissingDatabaseThrowsInsteadOfEmptySuccess")
if failures > 0 { exit(1) }
do { try suite.testNotificationTransitionsDedupDismissalAndRestart(); print("CHECK notification transitions, dedup, dismissal and restart") } catch { failures += 1; print("FAIL notification checks: \(error)") }
if failures > 0 { exit(1) }
print("Passed 12 checks")
