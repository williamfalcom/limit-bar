import Foundation
import Testing
import UserNotifications
@testable import limit_bar

private final class FakeNotificationCenter: NotificationCentering, @unchecked Sendable {
    private let lock = NSLock()
    private var _status: UNAuthorizationStatus
    private var _requests: [UNNotificationRequest] = []

    init(status: UNAuthorizationStatus) {
        _status = status
    }

    var requests: [UNNotificationRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        status()
    }

    func add(_ request: UNNotificationRequest) async throws {
        append(request)
    }

    private func status() -> UNAuthorizationStatus {
        lock.lock()
        defer { lock.unlock() }
        return _status
    }

    private func append(_ request: UNNotificationRequest) {
        lock.lock()
        defer { lock.unlock() }
        _requests.append(request)
    }
}

@Suite("NotificationService")
struct NotificationServiceTests {

    private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)
    private let accountID = UUID()

    private func window(_ percent: Double, resetsAt: Date?) -> LimitWindow {
        LimitWindow(kind: .weekly, usedPercent: percent, usedAbsolute: nil, resetsAt: resetsAt)
    }

    private func makeService(status: UNAuthorizationStatus) -> (NotificationService, FakeNotificationCenter) {
        let center = FakeNotificationCenter(status: status)
        return (NotificationService(center: center), center)
    }

    @Test("A window crossing 80 percent posts exactly one notification")
    func crossingPostsOnce() async {
        let periodEnd = fixedNow.addingTimeInterval(3600)
        let (service, center) = makeService(status: .authorized)

        await service.process(success: [window(79.9, resetsAt: periodEnd)], accountID: accountID)
        #expect(center.requests.isEmpty)

        await service.process(success: [window(80.1, resetsAt: periodEnd)], accountID: accountID)
        #expect(center.requests.count == 1)

        await service.process(success: [window(80.5, resetsAt: periodEnd)], accountID: accountID)
        await service.process(success: [window(90, resetsAt: periodEnd)], accountID: accountID)
        #expect(center.requests.count == 1)
    }

    @Test("Repeated crossings inside one reset period stay suppressed")
    func reCrossSamePeriodSuppressed() async {
        let periodEnd = fixedNow.addingTimeInterval(3600)
        let (service, center) = makeService(status: .authorized)

        await service.process(success: [window(81, resetsAt: periodEnd)], accountID: accountID)
        await service.process(success: [window(50, resetsAt: periodEnd)], accountID: accountID)
        await service.process(success: [window(81, resetsAt: periodEnd)], accountID: accountID)

        #expect(center.requests.count == 1)
    }

    @Test("Reset-period rollover re-arms the notification")
    func rolloverRearms() async {
        let firstPeriod = fixedNow.addingTimeInterval(3600)
        let secondPeriod = fixedNow.addingTimeInterval(7 * 86_400)
        let (service, center) = makeService(status: .authorized)

        await service.process(success: [window(81, resetsAt: firstPeriod)], accountID: accountID)
        #expect(center.requests.count == 1)

        await service.process(success: [window(40, resetsAt: secondPeriod)], accountID: accountID)
        await service.process(success: [window(82, resetsAt: secondPeriod)], accountID: accountID)

        #expect(center.requests.count == 2)
        #expect(center.requests[1].identifier.contains(String(Int(secondPeriod.timeIntervalSince1970))))
    }

    @Test("Denied authorization skips silently without posting or erroring")
    func deniedSkipsSilently() async throws {
        let periodEnd = fixedNow.addingTimeInterval(3600)
        let (service, center) = makeService(status: .denied)

        await service.process(success: [window(85, resetsAt: periodEnd)], accountID: accountID)

        #expect(center.requests.isEmpty)

        await service.process(success: [window(85, resetsAt: periodEnd)], accountID: accountID)
        #expect(center.requests.isEmpty)
    }

    @Test("Windows below threshold or without a reset time never notify")
    func belowThresholdOrMissingPeriodNeverNotify() async {
        let (service, center) = makeService(status: .authorized)

        await service.process(success: [window(79.99, resetsAt: fixedNow.addingTimeInterval(3600))], accountID: accountID)
        await service.process(success: [window(95, resetsAt: nil)], accountID: accountID)
        #expect(center.requests.isEmpty)

        await service.process(success: [window(81, resetsAt: fixedNow.addingTimeInterval(3600))], accountID: accountID)
        #expect(center.requests.count == 1)
    }
}
