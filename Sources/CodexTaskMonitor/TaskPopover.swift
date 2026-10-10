import AppKit

/// Owns presentation and dismissal for the menu-bar panel.
private final class TaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class TaskPopover: NSObject {
    let window: NSPanel
    var isShown: Bool { window.isVisible }
    static let menuBarGap: CGFloat = 12
    private let contentViewController: NSViewController
    private weak var button: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?

    init(contentViewController: NSViewController) {
        self.contentViewController = contentViewController
        window = TaskPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.title = "Codex 任务"
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        let content = contentViewController.view
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        window.contentView = background
    }

    func toggle(from button: NSView) {
        self.button = button
        if isShown { close() }
        else {
            guard let anchorWindow = button.window else { return }
            let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
            // Status-bar windows can report no screen; resolve it from their screen coordinates.
            guard let screen = anchorWindow.screen ?? NSScreen.screens.min(by: {
                Self.distance(from: anchor, to: $0.frame) < Self.distance(from: anchor, to: $1.frame)
            }) else { return }
            let size = window.contentView?.fittingSize ?? NSSize(width: 420, height: 480)
            window.setFrame(Self.frame(contentSize: size, anchor: anchor, visibleFrame: screen.visibleFrame), display: true)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            installMonitors()
        }
    }

    /// Place the panel below the menu bar, using the anchor's display (including negative origins).
    static func frame(contentSize: NSSize, anchor: NSRect, visibleFrame: NSRect) -> NSRect {
        let available = visibleFrame.insetBy(dx: 12, dy: 12)
        // Before AppKit lays out an overflow item, its window may still be at the origin.
        let anchorTop = anchor.maxY <= visibleFrame.minY ? visibleFrame.maxY : anchor.minY
        let top = min(anchorTop, visibleFrame.maxY) - menuBarGap
        let width = min(contentSize.width, available.width)
        let height = min(contentSize.height, max(0, top - available.minY))
        let x = min(max(anchor.midX - width / 2, available.minX), available.maxX - width)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    private static func distance(from anchor: NSRect, to screen: NSRect) -> CGFloat {
        // Overflow status items can sit just outside the display until clicked.
        let dx = max(screen.minX - anchor.midX, 0, anchor.midX - screen.maxX)
        let dy = max(screen.minY - anchor.midY, 0, anchor.midY - screen.maxY)
        return hypot(dx, dy)
    }

    func close() {
        removeMonitors()
        window.orderOut(nil)
    }

    private func installMonitors() {
        removeMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalEvent(event)
        }
        // Mouse-only global monitoring does not require keyboard/accessibility access.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.handleGlobalClick(at: NSEvent.mouseLocation)
        }
        deactivationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            self?.close()
        }
    }

    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard isShown else { return event }
        if event.type == .keyDown {
            if event.keyCode == 53 { close(); return nil }
            return event
        }
        guard let window = event.window else { return event } // Preserve native menu tracking.
        if window === self.window || window.level == .popUpMenu { return event }
        if let button, window === button.window,
           button.convert(button.bounds, to: nil).contains(event.locationInWindow) { return event }
        close()
        return event // Do not consume the click intended for the other control.
    }

    func handleGlobalClick(at point: NSPoint) {
        guard isShown else { return }
        if let button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        if window.frame.contains(point) { return }
        close()
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let deactivationObserver { NotificationCenter.default.removeObserver(deactivationObserver) }
        localMonitor = nil; globalMonitor = nil; deactivationObserver = nil
    }

    deinit { removeMonitors() }
}
