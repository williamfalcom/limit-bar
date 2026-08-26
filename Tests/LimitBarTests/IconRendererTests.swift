import AppKit
import Foundation
import Testing
@testable import limit_bar

@Suite("IconRenderer")
struct IconRendererTests {

    private let fixedNow = Date(timeIntervalSince1970: 1_770_000_000)
    private let allProviders = [ProviderKind.claudeCode, .codex, .openCodeGo]

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

    @Test("Every data-bearing usage level tints with the account provider, not usage thresholds")
    func providerTintAtEveryUsageLevel() {
        for provider in allProviders {
            for percent in [0.0, 42.0, 69.9, 70.0, 89.0, 90.0, 99.9] {
                let style = IconRenderer.style(
                    for: snapshot(windows: [window(.fiveHour, percent: percent)]),
                    window: .fiveHour,
                    provider: provider,
                    now: fixedNow
                )
                #expect(style.tint == .provider(provider), "provider \(provider), percent \(percent)")
            }
        }
    }

    @Test("Fill and text keep encoding the usage level while tint stays provider-fixed")
    func fillAndTextTrackUsageRegardlessOfTint() {
        let style = IconRenderer.style(
            for: snapshot(windows: [window(.fiveHour, percent: 93)]),
            window: .fiveHour,
            provider: .codex,
            now: fixedNow
        )
        #expect(style.tint == .provider(.codex))
        #expect(style.text == "93%")
        #expect(style.fill == 0.93)
    }

    @Test("A window at 100 percent shows the reset countdown in the provider color")
    func hundredPercentCountdownKeepsProviderTint() {
        for provider in allProviders {
            let resetsAt = fixedNow.addingTimeInterval(2 * 3600 + 5 * 60)
            let style = IconRenderer.style(
                for: snapshot(windows: [window(.fiveHour, percent: 100, resetsAt: resetsAt)]),
                window: .fiveHour,
                provider: provider,
                now: fixedNow
            )
            #expect(style.tint == .provider(provider))
            #expect(style.fill == 1.0)
            #expect(style.text == "2h 5m")
        }
    }

    @Test("Nil snapshot, empty windows, and unsupported state render neutral")
    func missingDataIsNeutral() {
        for provider in allProviders {
            let nilStyle = IconRenderer.style(for: nil, window: .fiveHour, provider: provider, now: fixedNow)
            #expect(nilStyle.tint == .neutral)
            #expect(nilStyle.toolTip == IconRenderer.noDataToolTip)

            let emptyStyle = IconRenderer.style(for: snapshot(windows: []), window: .fiveHour, provider: provider, now: fixedNow)
            #expect(emptyStyle.tint == .neutral)
            #expect(emptyStyle.toolTip == IconRenderer.noDataToolTip)

            let unsupported = IconRenderer.style(
                for: snapshot(windows: [], state: .unsupported),
                window: .fiveHour,
                provider: provider,
                now: fixedNow
            )
            #expect(unsupported.tint == .neutral)
        }
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
            provider: .claudeCode,
            now: fixedNow
        )
        #expect(style.text == "45m")
        #expect(style.fill == 1.0)
        #expect(style.tint == .provider(.claudeCode))
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
            provider: .openCodeGo,
            now: fixedNow
        )

        #expect(style.text == "8%")
        #expect(style.fill == 0.08)
        #expect(style.tint == .provider(.openCodeGo))
    }

    @Test("Rendered icon is a standard status-bar sized image, non-template when colored")
    func renderedImageProperties() {
        let neutral = IconRenderer.image(
            for: nil, window: .fiveHour, provider: .claudeCode, now: fixedNow
        )
        #expect(neutral.size.height == NSStatusBar.system.thickness)
        #expect(neutral.size.width > 0)
        #expect(neutral.isTemplate == true)

        let colored = IconRenderer.image(
            for: snapshot(windows: [window(.fiveHour, percent: 42)]),
            window: .fiveHour,
            provider: .codex,
            now: fixedNow
        )
        #expect(colored.size.height == NSStatusBar.system.thickness)
        #expect(colored.size.width > 18)
        #expect(colored.isTemplate == false)
    }

    @Test("Icon is template only when every rendered account is neutral")
    func templateOnlyWhenAllNeutral() {
        let mixed = IconRenderer.image(
            for: [
                ("Claude", snapshot(windows: [window(.fiveHour, percent: 42)]), WindowKind.fiveHour, ProviderKind.claudeCode),
                ("Codex", nil as AccountSnapshot?, WindowKind.fiveHour, ProviderKind.codex),
            ],
            now: fixedNow
        )
        #expect(mixed.isTemplate == false)

        let allNeutral = IconRenderer.image(
            for: [
                ("A", nil as AccountSnapshot?, WindowKind.fiveHour, ProviderKind.claudeCode),
                ("B", nil as AccountSnapshot?, WindowKind.weekly, ProviderKind.codex),
            ],
            now: fixedNow
        )
        #expect(allNeutral.isTemplate == true)
    }

    @Test("Multi-account icon draws one wide bar per account with its own provider")
    func multiAccountSegmentWidths() {
        let claude = ("Claude", snapshot(windows: [window(.fiveHour, percent: 42)]), WindowKind.fiveHour, ProviderKind.claudeCode)
        let codex = ("Codex", snapshot(windows: [window(.weekly, percent: 8)]), WindowKind.weekly, ProviderKind.codex)
        let neutralA = ("A", nil as AccountSnapshot?, WindowKind.fiveHour, ProviderKind.openCodeGo)
        let neutralB = ("B", nil as AccountSnapshot?, WindowKind.weekly, ProviderKind.openCodeGo)

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
                ("Claude", snapshot(windows: [window(.fiveHour, percent: 42)]), .fiveHour, ProviderKind.claudeCode),
                ("Codex", nil as AccountSnapshot?, .fiveHour, ProviderKind.codex),
            ],
            now: fixedNow
        )

        let description = image.accessibilityDescription ?? ""
        #expect(description.contains("Claude"))
        #expect(description.contains("Codex"))
        #expect(description.contains(IconRenderer.noDataToolTip))
    }
}
