import AppKit
import Foundation
import Testing
@testable import limit_bar

@Suite("IconRenderer")
struct IconRendererTests {

    private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)

    private func snapshot(
        windows: [LimitWindow],
        state: SnapshotState = .fresh,
        fetchedAt: Date? = Date(timeIntervalSince1970: 1_770_000_000)
    ) -> AccountSnapshot {
        AccountSnapshot(windows: windows, fetchedAt: fetchedAt, state: state)
    }

    private func window(_ kind: WindowKind, percent: Double, resetsAt: Date? = nil) -> LimitWindow {
        LimitWindow(kind: kind, usedPercent: percent, usedAbsolute: nil, resetsAt: resetsAt)
    }

    @Test("Usage below 70 percent decides green")
    func belowSeventyIsGreen() {
        for percent in [0.0, 50.0, 69.9] {
            let style = IconRenderer.style(
                for: snapshot(windows: [window(.fiveHour, percent: percent)]),
                window: .fiveHour,
                now: fixedNow
            )
            #expect(style.tint == .green, "percent \(percent)")
            #expect(style.fill == percent / 100)
        }
    }

    @Test("Usage from 70 through 89 percent decides amber")
    func seventyToEightyNineIsAmber() {
        for percent in [70.0, 70.5, 89.0] {
            let style = IconRenderer.style(
                for: snapshot(windows: [window(.fiveHour, percent: percent)]),
                window: .fiveHour,
                now: fixedNow
            )
            #expect(style.tint == .amber, "percent \(percent)")
        }
    }

    @Test("Usage at or above 90 percent decides red")
    func ninetyAndAboveIsRed() {
        for percent in [90.0, 95.0, 99.9] {
            let style = IconRenderer.style(
                for: snapshot(windows: [window(.fiveHour, percent: percent)]),
                window: .fiveHour,
                now: fixedNow
            )
            #expect(style.tint == .red, "percent \(percent)")
        }
    }

    @Test("A window at 100 percent shows the reset countdown instead of the percentage")
    func hundredPercentShowsCountdown() {
        let resetsAt = fixedNow.addingTimeInterval(2 * 3600 + 5 * 60)
        let style = IconRenderer.style(
            for: snapshot(windows: [window(.fiveHour, percent: 100, resetsAt: resetsAt)]),
            window: .fiveHour,
            now: fixedNow
        )
        #expect(style.tint == .red)
        #expect(style.fill == 1.0)
        #expect(style.text == "2h 5m")
    }

    @Test("Missing data renders the neutral gray state with the no-data-yet tooltip")
    func missingDataIsNeutral() {
        let nilStyle = IconRenderer.style(for: nil, window: .fiveHour, now: fixedNow)
        #expect(nilStyle.tint == .neutral)
        #expect(nilStyle.toolTip == "no data yet")

        let emptyStyle = IconRenderer.style(for: snapshot(windows: []), window: .fiveHour, now: fixedNow)
        #expect(emptyStyle.tint == .neutral)
        #expect(emptyStyle.toolTip == "no data yet")

        let unsupported = IconRenderer.style(
            for: snapshot(windows: [], state: .unsupported),
            window: .fiveHour,
            now: fixedNow
        )
        #expect(unsupported.tint == .neutral)

        let missingKind = IconRenderer.style(
            for: snapshot(windows: [window(.weekly, percent: 20)]),
            window: .fiveHour,
            now: fixedNow
        )
        #expect(missingKind.tint == .neutral)
    }

    @Test("Any plan window reaching 100 percent drives the countdown for the displayed window")
    func anyFullWindowDrivesCountdown() {
        let resetsAt = fixedNow.addingTimeInterval(45 * 60)
        let style = IconRenderer.style(
            for: snapshot(windows: [
                window(.fiveHour, percent: 64),
                window(.weekly, percent: 100, resetsAt: resetsAt),
            ]),
            window: .fiveHour,
            now: fixedNow
        )
        #expect(style.text == "45m")
        #expect(style.fill == 1.0)
    }

    @Test("Countdown formatting renders hours and minutes from resetsAt")
    func countdownFormatting() {
        #expect(IconRenderer.formatCountdown(until: fixedNow.addingTimeInterval(2 * 3600 + 5 * 60), now: fixedNow) == "2h 5m")
        #expect(IconRenderer.formatCountdown(until: fixedNow.addingTimeInterval(45 * 60), now: fixedNow) == "45m")
        #expect(IconRenderer.formatCountdown(until: fixedNow.addingTimeInterval(-30), now: fixedNow) == "0m")
        #expect(IconRenderer.formatCountdown(until: fixedNow.addingTimeInterval(59), now: fixedNow) == "0m")
    }

    @Test("Displayed window falls back to the highest-usage window when the kind is absent")
    func displayedWindowFallsBackToMaxUsage() {
        let style = IconRenderer.style(
            for: snapshot(windows: [window(.weekly, percent: 8)]),
            window: .fiveHour,
            now: fixedNow
        )

        #expect(style.text == "8%")
        #expect(style.fill == 0.08)
        #expect(style.tint == .green)
    }

    @Test("Rendered icon is a standard status-bar sized image, template only when neutral")
    func renderedImageProperties() {
        let neutral = IconRenderer.image(for: nil, window: .fiveHour, now: fixedNow)
        #expect(neutral.size.height == NSStatusBar.system.thickness)
        #expect(neutral.size.width > 0)
        #expect(neutral.isTemplate == true)

        let colored = IconRenderer.image(
            for: snapshot(windows: [window(.fiveHour, percent: 42)]),
            window: .fiveHour,
            now: fixedNow
        )
        #expect(colored.size.height == NSStatusBar.system.thickness)
        #expect(colored.size.width > 18)
        #expect(colored.isTemplate == false)
    }

    @Test("Multi-account icon draws one wide bar with its own percent per account")
    func multiAccountSegmentWidths() {
        let claude = ("Claude", snapshot(windows: [window(.fiveHour, percent: 42)]), WindowKind.fiveHour)
        let codex = ("Codex", snapshot(windows: [window(.weekly, percent: 8)]), WindowKind.weekly)
        let neutralA = ("A", nil as AccountSnapshot?, WindowKind.fiveHour)
        let neutralB = ("B", nil as AccountSnapshot?, WindowKind.weekly)

        let neutralPair = IconRenderer.image(for: [neutralA, neutralB], now: fixedNow)
        #expect(abs(neutralPair.size.width - 44) < 0.5)

        let coloredPair = IconRenderer.image(for: [claude, codex], now: fixedNow)
        #expect(coloredPair.size.width > neutralPair.size.width)
        #expect(coloredPair.isTemplate == false)
    }

    @Test("Icon tooltip composes every account label")
    func tooltipComposesLabels() {
        let image = IconRenderer.image(
            for: [
                ("Claude", snapshot(windows: [window(.fiveHour, percent: 42)]), .fiveHour),
                ("Codex", nil, .fiveHour),
            ],
            now: fixedNow
        )

        let description = image.accessibilityDescription ?? ""
        #expect(description.contains("Claude"))
        #expect(description.contains("Codex"))
        #expect(description.contains("no data yet"))
    }
}
