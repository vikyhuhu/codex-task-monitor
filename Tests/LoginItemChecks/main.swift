import ServiceManagement

final class FakeService: LoginItemService {
    var status: SMAppService.Status = .notRegistered
    var registrations = 0
    var removals = 0
    var shouldFail = false
    var requiresApproval = false
    func register() throws {
        registrations += 1
        if shouldFail { throw Failure.denied }
        status = requiresApproval ? .requiresApproval : .enabled
    }
    func unregister() throws {
        removals += 1
        if shouldFail { throw Failure.denied }
        status = .notRegistered
    }
    enum Failure: Error { case denied }
}

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print("\(condition ? "PASS" : "FAIL") \(name)")
    if !condition { failures += 1 }
}
let service = FakeService()
let controller = LoginItemController(service: service)
check(!controller.isEnabled && service.registrations == 0, "startup does not register without user choice")
controller.setEnabled(true)
check(controller.isEnabled && service.registrations == 1, "enable reflects successful system registration")
controller.setEnabled(true)
check(service.registrations == 1, "repeated enable does not register twice")
controller.setEnabled(false)
check(!controller.isEnabled && service.removals == 1, "disable unregisters")
service.shouldFail = true
controller.setEnabled(true)
check(!controller.isEnabled && !controller.message.isEmpty, "failed enable stays off and explains failure")
service.status = .enabled
controller.setEnabled(false)
check(controller.isEnabled && !controller.message.isEmpty, "failed disable keeps actual system state")
service.shouldFail = false
service.status = .requiresApproval
controller.refresh()
check(!controller.isEnabled && controller.needsApproval && !controller.message.isEmpty, "external revocation refreshes into approval state")
let registrations = service.registrations
controller.setEnabled(true)
check(service.registrations == registrations && controller.needsApproval, "approval state does not falsely register or claim enabled")
controller.setEnabled(false)
check(service.status == .notRegistered && !controller.needsApproval, "pending registration can be removed")
service.requiresApproval = true
controller.setEnabled(true)
check(controller.needsApproval && !controller.isEnabled, "registration requiring consent stays pending")
service.status = .enabled
controller.refresh()
check(controller.isEnabled && controller.message.isEmpty, "approval granted externally clears message")
service.status = .notFound
controller.refresh()
check(!controller.isEnabled && !controller.message.isEmpty, "missing app is surfaced")
exit(failures == 0 ? 0 : 1)
