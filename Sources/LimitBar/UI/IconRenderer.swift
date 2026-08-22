import AppKit
import Foundation

enum IconRenderer {
    struct Style: Equatable, Sendable {
        enum Tint: Equatable, Sendable {
            case green, amber, red, neutral
        }

        var tint: Tint
        var text: String?
        var fill: Double?
        var toolTip: String?
    }

    static let amberThreshold = 70.0
    static let redThreshold = 90.0
    static let noDataToolTip = "no data yet"

    static func style(for snapshot: AccountSnapshot?, window: WindowKind, now: Date) -> Style {
        guard let snapshot, snapshot.fetchedAt != nil, !snapshot.windows.isEmpty else {
            return Style(tint: .neutral, text: nil, fill: nil, toolTip: noDataToolTip)
        }
        if let full = snapshot.windows.first(where: { $0.usedPercent >= 100 }) {
            let countdown = full.resetsAt.map { formatCountdown(until: $0, now: now) }
            return Style(tint: .red, text: countdown, fill: 1.0, toolTip: nil)
        }
        let usage = snapshot.windows.first { $0.kind == window }?.usedPercent
        guard let usage else {
            return Style(tint: .neutral, text: nil, fill: nil, toolTip: noDataToolTip)
        }
        let tint: Style.Tint = usage < amberThreshold ? .green : (usage < redThreshold ? .amber : .red)
        return Style(
            tint: tint,
            text: "\(Int(usage.rounded()))%",
            fill: min(max(usage / 100, 0), 1),
            toolTip: nil
        )
    }

    static func formatCountdown(until resetsAt: Date, now: Date) -> String {
        let totalMinutes = Int(resetsAt.timeIntervalSince(now) / 60)
        let clamped = max(0, totalMinutes)
        let hours = clamped / 60
        let minutes = clamped % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func image(for snapshot: AccountSnapshot?, window: WindowKind, now: Date = Date()) -> NSImage {
        image(
            for: [(label: "account", snapshot: snapshot, window: window)],
            activeIndex: 0,
            now: now
        )
    }

    /// One mini progress bar per account; the active account may append its %/countdown text.
    static func image(
        for entries: [(label: String, snapshot: AccountSnapshot?, window: WindowKind)],
        activeIndex: Int?,
        now: Date = Date()
    ) -> NSImage {
        let height = NSStatusBar.system.thickness
        let barWidth: CGFloat = 12
        let barHeight: CGFloat = 6
        let barGap: CGFloat = 4
        let styles = entries.map { Self.style(for: $0.snapshot, window: $0.window, now: now) }

        var width = max(0, CGFloat(entries.count) * barWidth + CGFloat(max(0, entries.count - 1)) * barGap)
        var textSize: CGSize = .zero
        var trailingText: String?
        if let activeIndex, entries.indices.contains(activeIndex) {
            trailingText = styles[activeIndex].text
        }
        if let text = trailingText {
            textSize = (text as NSString).size(withAttributes: textAttributes)
            width += barGap + ceil(textSize.width)
        }

        let image = NSImage(size: NSSize(width: max(width, barWidth), height: height))
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }

        var xOffset: CGFloat = 0.5
        for style in styles {
            drawBar(style: style, x: xOffset, width: barWidth, y: (height - barHeight) / 2, height: barHeight)
            xOffset += barWidth + barGap
        }

        if let text = trailingText {
            let tint = color(for: styles[activeIndex!].tint)
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: tint,
            ])
            attributed.draw(at: NSPoint(x: xOffset - barGap + 0.5 - 1, y: (height - textSize.height) / 2))
        }

        image.isTemplate = styles.allSatisfy { $0.tint == .neutral }
        let tooltipParts = zip(entries, styles).map { entry, style in
            "\(entry.label): \(style.toolTip ?? style.text ?? "ok")"
        }
        image.accessibilityDescription = tooltipParts.joined(separator: " · ")
        return image
    }

    private static func color(for tint: Style.Tint) -> NSColor {
        switch tint {
        case .green: .systemGreen
        case .amber: .systemOrange
        case .red: .systemRed
        case .neutral: .tertiaryLabelColor
        }
    }

    private static func drawBar(style: Style, x: CGFloat, width: CGFloat, y: CGFloat, height: CGFloat) {
        NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: width, height: height),
            xRadius: height / 2,
            yRadius: height / 2
        ).fill()
        guard let fill = style.fill else { return }
        let filledWidth = max(height, width * CGFloat(fill))
        let filled = NSRect(x: x, y: y, width: filledWidth, height: height)
        color(for: style.tint).setFill()
        NSBezierPath(roundedRect: filled, xRadius: height / 2, yRadius: height / 2).fill()
    }

    private static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [NSAttributedString.Key.font: font]
    }
}
