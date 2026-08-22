import Foundation
import UserNotifications

protocol NotificationCentering: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func add(_ request: UNNotificationRequest) async throws
}

struct SystemNotificationCenter: NotificationCentering, @unchecked Sendable {
    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request, withCompletionHandler: { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

enum ThresholdNotification {
    static let thresholdPercent = 80.0

    /// One notification per window per reset period. The period is identified by the
    /// window's resetsAt timestamp; windows without a reset time are never notified.
    static func shouldNotify(percent: Double, resetsAt: Date?, lastNotifiedResetsAt: Date?) -> Bool {
        guard percent >= thresholdPercent, let resetsAt else { return false }
        return lastNotifiedResetsAt != resetsAt
    }
}

actor NotificationService {
    private let center: any NotificationCentering
    private var markers: [UUID: [WindowKind: Date]] = [:]

    init(center: any NotificationCentering = SystemNotificationCenter()) {
        self.center = center
    }

    func process(success windows: [LimitWindow], accountID: UUID) async {
        for window in windows {
            let last = markers[accountID]?[window.kind]
            guard ThresholdNotification.shouldNotify(
                percent: window.usedPercent,
                resetsAt: window.resetsAt,
                lastNotifiedResetsAt: last
            ), let resetsAt = window.resetsAt else { continue }

            markers[accountID, default: [:]][window.kind] = resetsAt

            let status = await center.authorizationStatus()
            guard status == .authorized else { continue }

            let request = Self.request(accountID: accountID, window: window, now: Date())
            try? await center.add(request)
        }
    }

    static func request(accountID: UUID, window: LimitWindow, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Limit near cap", comment: "notification title")
        var body = String(
            format: NSLocalizedString("%1$@ limit at %2$d%% used, resets in %3$@", comment: "notification body"),
            Self.windowName(window.kind),
            Int(window.usedPercent.rounded()),
            window.resetsAt.map { IconRenderer.formatCountdown(until: $0, now: now) } ?? "—"
        )
        content.body = body

        let period = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
        let identifier = "limit-bar.\(accountID.uuidString).\(window.kind.identifierValue).\(period)"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    static func windowName(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: NSLocalizedString("5-hour", comment: "window name")
        case .weekly: NSLocalizedString("Weekly", comment: "window name")
        case .monthly: NSLocalizedString("Monthly", comment: "window name")
        case .weeklyModel(let model):
            String(format: NSLocalizedString("Weekly · %@", comment: "per-model weekly window name"), model)
        }
    }
}

private extension WindowKind {
    var identifierValue: String {
        switch self {
        case .fiveHour: "fiveHour"
        case .weekly: "weekly"
        case .monthly: "monthly"
        case .weeklyModel(let model): "weeklyModel:\(model)"
        }
    }
}
