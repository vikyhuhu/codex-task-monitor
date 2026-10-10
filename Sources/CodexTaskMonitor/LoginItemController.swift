import Combine
import ServiceManagement

protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// System registration is the source of truth; never store a separate enabled preference.
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var message = ""
    private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
        refresh()
    }

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = service.status
        switch status {
        case .requiresApproval: message = "请在系统登录项中允许此应用启动"
        case .notFound: message = "系统暂未找到登录项，可开启自启动或在系统登录项中设置"
        default: message = ""
        }
    }

    func setEnabled(_ enabled: Bool) {
        refresh()
        // A registered but blocked item needs system consent, not another registration.
        if enabled && needsApproval { return }
        if enabled == isEnabled && !needsApproval { return }
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
            refresh()
        } catch {
            refresh()
            if !needsApproval {
                message = "自启动设置失败，请检查应用是否已安装，或到系统登录项中设置"
            }
        }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
