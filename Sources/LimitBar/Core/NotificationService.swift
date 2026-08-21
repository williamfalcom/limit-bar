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
        content.title = "Limit near cap"
        var body = "\(Self.windowName(window.kind)) limit at \(Int(window.usedPercent.rounded()))% used"
        if let resetsAt = window.resetsAt {
            body += ", resets in \(IconRenderer.formatCountdown(until: resetsAt, now: now))"
        }
        content.body = body

        let period = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
        let identifier = "limit-bar.\(accountID.uuidString).\(window.kind.rawValue).\(period)"
        return UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    }

    static func windowName(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }
}
