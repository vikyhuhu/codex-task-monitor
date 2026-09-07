import AppKit
import SwiftUI
import UserNotifications
import MonitorCore

final class MonitorModel: ObservableObject {
    @Published var tasks: [TaskRecord] = []
    @Published var error: String?
    @Published var refreshedAt: Date?
    @Published var notificationsEnabled = false
    @Published var notificationMessage = ""
    @Published var soundEnabled = true {
        didSet {
            defaults.set(soundEnabled, forKey: "soundEnabled")
            if !soundEnabled { soundPlayer.stop() }
        }
    }
    private let soundPlayer = ReminderSoundPlayer()
    private let home: URL
    private let store: TaskStore
    private let queue = DispatchQueue(label: "CodexTaskMonitor.reader", qos: .utility)
    private var scanning = false
    private var timer: Timer?
    private var alerts = AlertTracker()
    private var dismissed: Set<String>
    private var since: Date
    var onChange: (() -> Void)?
    private let defaults = UserDefaults.standard

    init(home: URL) {
        self.home = home
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        store = TaskStore(home: home)
        let saved = defaults.double(forKey: "monitorSince")
        since = saved > 0 ? Date(timeIntervalSince1970: saved) : Date()
        defaults.set(since.timeIntervalSince1970, forKey: "monitorSince")
        dismissed = Set(defaults.stringArray(forKey: "dismissed") ?? [])
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { self.notificationsEnabled = settings.authorizationStatus == .authorized }
        }
    }
    var running: Int { tasks.filter { $0.status == .running }.count }
    var attention: Int { tasks.filter { ![.running, .ended].contains($0.status) }.count }
    var ended: Int { tasks.filter { $0.status == .ended }.count }
    var waiting: Int { tasks.filter { $0.status == .needsInput }.count }
    var failed: Int { tasks.filter { $0.status == .failed }.count }
    var uncertain: Int { tasks.filter { [.interrupted, .uncertain].contains($0.status) }.count }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        guard !scanning else { return }
        scanning = true
        let cutoff = since
        queue.async {
            let result = Result { try self.store.snapshot(since: cutoff) }
            let receipts = ReadReceipts.load(home: self.home)
            DispatchQueue.main.async {
                self.scanning = false
                guard cutoff == self.since else { self.refresh(); return }
                switch result {
                case .success(let all):
                    self.error = nil; self.refreshedAt = Date()
                    if let receipts {
                        let readKeys = all.filter { receipts.isRead($0) }.map { $0.key }
                        if !Set(readKeys).isSubset(of: self.dismissed) {
                            self.dismissed.formUnion(readKeys)
                            self.defaults.set(Array(self.dismissed), forKey: "dismissed")
                        }
                    }
                    let visible = all.filter { !self.dismissed.contains($0.key) }
                    let changed = self.alerts.update(all, dismissed: self.dismissed)
                    self.tasks = visible
                    if !changed.isEmpty { self.notify(changed) }
                case .failure:
                    self.error = "无法更新任务状态。请检查 Codex 数据目录，稍后会自动重试。"
                }
                self.onChange?()
            }
        }
    }
    func dismiss(_ task: TaskRecord) {
        dismissed.insert(task.key)
        defaults.set(Array(dismissed), forKey: "dismissed")
        tasks.removeAll { $0.key == task.key }; onChange?()
    }
    func clearEnded() { for task in tasks where task.status == .ended { dismiss(task) } }
    func includeToday() {
        since = Calendar.current.startOfDay(for: Date())
        defaults.set(since.timeIntervalSince1970, forKey: "monitorSince")
        alerts.silenceNextUpdate(); refresh()
    }
    func open(_ task: TaskRecord) {
        guard let url = URL(string: "codex://threads/\(task.id)") else { return }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                if error == nil, task.status == .ended { self.dismiss(task) }
                else if error != nil { self.notificationMessage = "无法打开 Codex，任务仍保留在列表中" }
            }
        }
    }
    func enableNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                self.notificationMessage = granted ? "已开启，仅在状态变化时提醒" : "请到系统设置 → 通知中允许 Codex Task Monitor"
                if let error { self.notificationMessage = error.localizedDescription }
            }
        }
    }
    func previewSound(_ cue: SoundCue) {
        soundPlayer.play(cue) { [weak self] in
            self?.notificationMessage = "声音播放失败，请检查音频输出"
        }
    }
    private func notify(_ changed: [TaskRecord]) {
        // Local audio works without notification permission; one sound per batch.
        if soundEnabled, let cue = SoundCue.select(for: changed.map { $0.status }) { previewSound(cue) }
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = changed.count == 1 ? changed[0].status.label : "\(changed.count) 个任务有新状态"
        content.body = changed.prefix(3).map { String($0.title.prefix(60)) }.joined(separator: "\n")
        content.sound = nil // Audio is played above; avoid a second notification sound.
        if let first = changed.first { content.userInfo = ["threadID": first.id] }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if error != nil { DispatchQueue.main.async { self.notificationMessage = "通知发送失败，请检查系统通知权限" } }
        }
    }
}

extension TaskStatus {
    var color: Color {
        switch self {
        case .running: return .blue
        case .ended: return .green
        case .needsInput: return .orange
        case .failed: return .red
        case .interrupted, .uncertain: return .secondary
        }
    }
}

struct MonitorView: View {
    @ObservedObject var model: MonitorModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.secondary)
                Text("Codex 任务").font(.headline)
                Spacer()
                Text("\(model.tasks.count) 个").foregroundStyle(.secondary)
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("立即刷新")
            }.padding(18)
            HStack(spacing: 10) {
                stat("运行", model.running, .blue)
                stat("待处理", model.attention, .orange)
                stat("待查看", model.ended, .green)
            }.padding(.horizontal, 18).padding(.bottom, 16)
            Divider()
            if let error = model.error {
                Label(error + " 当前列表可能已过期。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(16)
            }
            ScrollView {
                if model.tasks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.seal").font(.system(size: 30)).foregroundStyle(.tertiary)
                        Text("暂时没有需要关注的任务").font(.headline)
                        Text("新运行的任务会自动出现在这里。\n历史任务默认不计入，可在下方查看今天的任务。")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.tasks) { task in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: task.status.symbol).foregroundStyle(task.status.color).frame(width: 20).padding(.top, 3)
                                Button { model.open(task) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                        HStack {
                                            Text(task.status.label).foregroundStyle(task.status.color)
                                            Spacer()
                                            if task.updatedAt > Date.distantPast { Text(task.updatedAt, style: .relative).foregroundStyle(.secondary) }
                                        }.font(.system(size: 11))
                                        Text(task.project).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                        if !task.detail.isEmpty { Text(task.detail).font(.caption2).foregroundStyle(.secondary) }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).help("打开 Codex 任务")
                                if task.status != .running {
                                    Button { model.dismiss(task) } label: { Image(systemName: "xmark").font(.caption) }
                                        .buttonStyle(.borderless).help("移出列表；下次运行会重新出现")
                                }
                            }.padding(.horizontal, 18).padding(.vertical, 13)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
            }.frame(minHeight: 160, maxHeight: 380)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("声音提醒", isOn: $model.soundEnabled).toggleStyle(.switch).controlSize(.mini)
                    Spacer()
                    Menu("试听") {
                        ForEach(SoundCue.allCases, id: \.rawValue) { cue in
                            Button(cue.label) { model.previewSound(cue) }
                        }
                    }.menuStyle(.borderlessButton).fixedSize()
                }.font(.caption)
                HStack {
                    Button("查看今天的任务", action: model.includeToday)
                    Spacer()
                    Button("清除已结束", action: model.clearEnded).disabled(model.ended == 0)
                }.buttonStyle(.borderless).font(.caption)
                HStack {
                    if model.notificationsEnabled {
                        Label("通知已开启", systemImage: "bell.badge").foregroundStyle(.secondary)
                    } else { Button("开启系统通知", action: model.enableNotifications).buttonStyle(.borderless) }
                    Spacer()
                    Text("本地只读 · 5 秒刷新").foregroundStyle(.tertiary)
                    Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
                }.font(.system(size: 11))
                if !model.notificationMessage.isEmpty { Text(model.notificationMessage).font(.caption2).foregroundStyle(.secondary) }
            }.padding(16)
        }.frame(width: 420)
    }
    func stat(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(count)").font(.system(size: 24, weight: .semibold, design: .rounded)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(10).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var model: MonitorModel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.codex-task-monitor").count > 1 {
            NSApplication.shared.terminate(nil); return
        }
        let homePath = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        model = MonitorModel(home: URL(fileURLWithPath: homePath))
        UNUserNotificationCenter.current().delegate = self
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self; item.button?.action = #selector(toggle)
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MonitorView(model: model))
        model.onChange = { [weak self] in self?.updateTitle() }
        updateTitle(); model.start()
        if CommandLine.arguments.contains("--show") { toggle() }
    }
    private func updateTitle() {
        guard model.error == nil else {
            item.button?.title = "⚪ 状态不可用"
            item.button?.toolTip = "无法读取最新状态，点开查看详情"
            return
        }
        // Emoji retain their colors in the menu bar; monochrome symbols do not.
        var title = "🔵 \(model.running)  🟠 \(model.waiting)  🔴 \(model.failed)  🟢 \(model.ended)"
        if model.uncertain > 0 { title += "  ⚪ \(model.uncertain)" }
        item.button?.title = title
        item.button?.toolTip = "Codex：共 \(model.tasks.count) 个任务；蓝：运行 \(model.running)，橙：等你处理 \(model.waiting)，红：失败 \(model.failed)，绿：本轮结束待查看 \(model.ended)，灰：中断或状态待确认 \(model.uncertain)"
    }
    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["threadID"] as? String,
           let url = URL(string: "codex://threads/\(id)") {
            DispatchQueue.main.async {
                if let task = self.model.tasks.first(where: { $0.id == id }) { self.model.open(task) }
                else { NSWorkspace.shared.open(url) }
            }
        }
        completionHandler()
    }
}

if CommandLine.arguments.contains("--snapshot") {
    let path = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
    do {
        let tasks = try TaskStore(home: URL(fileURLWithPath: path)).snapshot(since: Calendar.current.startOfDay(for: Date()))
        // Diagnostics intentionally omit prompts, titles, paths and IDs.
        for status in TaskStatus.allCases { print("\(status.rawValue): \(tasks.filter { $0.status == status }.count)") }
    } catch { fputs("Task data unavailable: \(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
