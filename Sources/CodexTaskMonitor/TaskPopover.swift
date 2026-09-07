import AppKit

/// Owns presentation and dismissal for the menu-bar panel.
final class TaskPopover: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    private weak var button: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?

    init(contentViewController: NSViewController) {
        super.init()
        popover.behavior = .applicationDefined
        popover.contentViewController = contentViewController
        popover.delegate = self
    }

    func toggle(from button: NSView) {
        self.button = button
        if popover.isShown { close() }
        else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() {
        removeMonitors()
        popover.close()
    }

    func popoverDidShow(_ notification: Notification) {
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

    func popoverDidClose(_ notification: Notification) { removeMonitors() }

    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard popover.isShown else { return event }
        if event.type == .keyDown {
            if event.keyCode == 53 { close(); return nil }
            return event
        }
        guard let window = event.window else { return event } // Preserve native menu tracking.
        if window === popover.contentViewController?.view.window || window.level == .popUpMenu { return event }
        if let button, window === button.window,
           button.convert(button.bounds, to: nil).contains(event.locationInWindow) { return event }
        close()
        return event // Do not consume the click intended for the other control.
    }

    func handleGlobalClick(at point: NSPoint) {
        guard popover.isShown else { return }
        if let button, let window = button.window,
           window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return }
        if popover.contentViewController?.view.window?.frame.contains(point) == true { return }
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
