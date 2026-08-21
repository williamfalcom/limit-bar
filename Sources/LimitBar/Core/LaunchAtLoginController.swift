import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = Self.statusEnabled(SMAppService.mainApp.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // State below re-reads the authoritative status; registration can also be pending approval.
        }
        isEnabled = Self.statusEnabled(SMAppService.mainApp.status)
    }

    private static func statusEnabled(_ status: SMAppService.Status) -> Bool {
        status == .enabled
    }
}
