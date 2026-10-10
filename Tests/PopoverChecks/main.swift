import AppKit

// Run as a standalone AppKit integration check, with the production TaskPopover source.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let content = NSViewController()
content.view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 100))
content.view.widthAnchor.constraint(equalToConstant: 220).isActive = true
content.view.heightAnchor.constraint(equalToConstant: 100).isActive = true
let panel = TaskPopover(contentViewController: content)
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
    if panel.isShown { panel.close() }
    panel.toggle(from: button)
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    if !panel.isShown {
        print("Screens: \(NSScreen.screens.map { $0.frame }), anchor rect: \(String(describing: button.window?.convertToScreen(button.convert(button.bounds, to: nil))))")
        print("FAIL could not open test panel: anchor=\(String(describing: button.window?.frame)), panel=\(panel.window.frame)")
        exit(1)
    }
}
func mouseEvent(window: NSWindow, point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}

openPanel()
let screen = NSScreen.screens.first { $0.frame.contains(panel.window.frame) }!
let anchor = button.window!.convertToScreen(button.convert(button.bounds, to: nil))
check(abs(panel.window.frame.maxY - (min(anchor.minY, screen.visibleFrame.maxY) - 12)) < 0.5,
      "panel leaves 12 points below menu bar")
check(panel.window.frame.width == 220 && panel.window.frame.height == 100, "panel uses content fitting size")
let pendingAnchor = TaskPopover.frame(contentSize: NSSize(width: 420, height: 450),
    anchor: NSRect(x: 0, y: -26, width: 118, height: 22),
    visibleFrame: NSRect(x: 0, y: 93, width: 1440, height: 777))
check(pendingAnchor.height == 450 && pendingAnchor.maxY == 858, "unpositioned startup anchor does not collapse panel")
for display in [NSRect(x: 0, y: 0, width: 1440, height: 875), NSRect(x: -1920, y: 200, width: 1920, height: 1055)] {
    for x in [display.minX, display.maxX] {
        let rect = TaskPopover.frame(contentSize: NSSize(width: 420, height: 2000),
            anchor: NSRect(x: x, y: display.maxY, width: 30, height: 24), visibleFrame: display)
        check(display.contains(rect) && abs(rect.maxY - display.maxY + 12) < 0.5,
            "panel stays on anchor display at screen edges and limits height")
    }
}
NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: app)
check(!panel.isShown, "app deactivation closes panel")

openPanel()
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: panel.window.windowNumber, context: nil,
    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
check(panel.handleLocalEvent(escape) == nil && !panel.isShown, "Escape closes and is consumed")

openPanel()
let popupWindow = panel.window
let inside = mouseEvent(window: popupWindow, point: NSPoint(x: 10, y: 10))
check(panel.handleLocalEvent(inside) != nil && panel.isShown, "inside clicks stay interactive")
let anchorBounds = button.convert(button.bounds, to: nil)
let anchorPoint = NSPoint(x: anchorBounds.midX, y: anchorBounds.midY)
let anchorClick = mouseEvent(window: button.window!, point: anchorPoint)
check(panel.handleLocalEvent(anchorClick) != nil && panel.isShown, "anchor click is left for toggle")
panel.toggle(from: button)
check(!panel.isShown, "second menu-bar toggle closes without reopening")

openPanel()
let otherWindow = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
let outside = mouseEvent(window: otherWindow, point: NSPoint(x: 5, y: 5))
check(panel.handleLocalEvent(outside) != nil && !panel.isShown, "outside app-window click closes without consuming click")

openPanel()
let anchorScreen = button.window!.convertPoint(toScreen: anchorPoint)
panel.handleGlobalClick(at: anchorScreen)
check(panel.isShown, "global anchor click does not preempt toggle")
panel.handleGlobalClick(at: NSPoint(x: -99999, y: -99999))
check(!panel.isShown, "outside global click closes")

for _ in 0..<3 {
    openPanel()
    panel.close()
    panel.close()
    check(!panel.isShown, "explicit close works after reopening and is idempotent")
}
NSStatusBar.system.removeStatusItem(item)
otherWindow.orderOut(nil)
exit(failures == 0 ? 0 : 1)
