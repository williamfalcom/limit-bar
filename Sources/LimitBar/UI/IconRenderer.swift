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
    static var noDataToolTip: String { NSLocalizedString("no data yet", comment: "no data tooltip") }

    static func style(for snapshot: AccountSnapshot?, window: WindowKind, now: Date) -> Style {
        guard let snapshot, snapshot.fetchedAt != nil, !snapshot.windows.isEmpty else {
            return Style(tint: .neutral, text: nil, fill: nil, toolTip: noDataToolTip)
        }
        if let full = snapshot.windows.first(where: { $0.usedPercent >= 100 }) {
            let countdown = full.resetsAt.map { formatCountdown(until: $0, now: now) }
            return Style(tint: .red, text: countdown, fill: 1.0, toolTip: nil)
        }
        let usage = snapshot.windows.first { $0.kind == window }?.usedPercent
            ?? snapshot.windows.map(\.usedPercent).max()
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
        image(for: [(label: "account", snapshot: snapshot, window: window)], now: now)
    }

    /// One wide progress bar plus its own percentage per account.
    static func image(
        for entries: [(label: String, snapshot: AccountSnapshot?, window: WindowKind)],
        now: Date = Date()
    ) -> NSImage {
        let height = NSStatusBar.system.thickness
        let barWidth: CGFloat = 18
        let barHeight: CGFloat = 6
        let textGap: CGFloat = 3
        let entryGap: CGFloat = 8
        let styles = entries.map { Self.style(for: $0.snapshot, window: $0.window, now: now) }

        var textSizes: [CGSize] = []
        var width: CGFloat = 0
        for style in styles {
            width += barWidth
            if let text = style.text {
                let size = (text as NSString).size(withAttributes: textAttributes)
                textSizes.append(size)
                width += textGap + ceil(size.width)
            } else {
                textSizes.append(.zero)
            }
            width += entryGap
        }
        width -= entryGap

        let image = NSImage(size: NSSize(width: max(width, barWidth), height: height))
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }

        var xOffset: CGFloat = 0.5
        for (index, style) in styles.enumerated() {
            drawBar(style: style, x: xOffset, width: barWidth, y: (height - barHeight) / 2, height: barHeight)
            xOffset += barWidth
            if let text = style.text {
                let attributed = NSAttributedString(string: text, attributes: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.foregroundColor: color(for: style.tint),
                ])
                attributed.draw(at: NSPoint(x: xOffset + textGap, y: (height - textSizes[index].height) / 2))
                xOffset += textGap + textSizes[index].width
            }
            xOffset += entryGap
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
        NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [NSAttributedString.Key.font: font]
    }
}
