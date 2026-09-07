import AppKit

// Run as a standalone AppKit integration check, with the production TaskPopover source.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let content = NSViewController()
content.view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
let panel = TaskPopover(contentViewController: content)
panel.popover.animates = false
let item = NSStatusBar.system.statusItem(withLength: 20)
let button = item.button!
button.title = "T"
app.finishLaunching()
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
var failures = 0
func check(_ condition: Bool, _ name: String) {
    print("\(condition ? "PASS" : "FAIL") \(name)")
    if !condition { failures += 1 }
}
func openPanel() {
    if panel.popover.isShown { panel.close() }
    panel.toggle(from: button)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    if !panel.popover.isShown { print("FAIL could not open test popover"); exit(1) }
}
func mouseEvent(window: NSWindow, point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

openPanel()
NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: app)
check(!panel.popover.isShown, "app deactivation closes panel")

openPanel()
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: panel.popover.contentViewController!.view.window!.windowNumber, context: nil,
    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
check(panel.handleLocalEvent(escape) == nil && !panel.popover.isShown, "Escape closes and is consumed")

openPanel()
let popupWindow = panel.popover.contentViewController!.view.window!
let inside = mouseEvent(window: popupWindow, point: NSPoint(x: 10, y: 10))
check(panel.handleLocalEvent(inside) != nil && panel.popover.isShown, "inside clicks stay interactive")
let anchorBounds = button.convert(button.bounds, to: nil)
let anchorPoint = NSPoint(x: anchorBounds.midX, y: anchorBounds.midY)
let anchorClick = mouseEvent(window: button.window!, point: anchorPoint)
check(panel.handleLocalEvent(anchorClick) != nil && panel.popover.isShown, "anchor click is left for toggle")
panel.toggle(from: button)
check(!panel.popover.isShown, "second menu-bar toggle closes without reopening")

openPanel()
let otherWindow = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
let outside = mouseEvent(window: otherWindow, point: NSPoint(x: 5, y: 5))
check(panel.handleLocalEvent(outside) != nil && !panel.popover.isShown, "outside app-window click closes without consuming click")

openPanel()
let anchorScreen = button.window!.convertPoint(toScreen: anchorPoint)
panel.handleGlobalClick(at: anchorScreen)
check(panel.popover.isShown, "global anchor click does not preempt toggle")
panel.handleGlobalClick(at: NSPoint(x: -99999, y: -99999))
check(!panel.popover.isShown, "outside global click closes")

for _ in 0..<3 {
    openPanel()
    panel.close()
    panel.close()
    check(!panel.popover.isShown, "explicit close works after reopening and is idempotent")
}
NSStatusBar.system.removeStatusItem(item)
otherWindow.orderOut(nil)
exit(failures == 0 ? 0 : 1)
