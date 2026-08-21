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
        let style = Self.style(for: snapshot, window: window, now: now)
        let height = NSStatusBar.system.thickness
        let barWidth: CGFloat = 18
        let barHeight: CGFloat = 6
        let gap: CGFloat = 4

        var width = barWidth
        var textSize: CGSize = .zero
        if let text = style.text {
            textSize = (text as NSString).size(withAttributes: textAttributes)
            width += gap + ceil(textSize.width)
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocusFlipped(false)
        defer { image.unlockFocus() }

        let color: NSColor
        switch style.tint {
        case .green: color = .systemGreen
        case .amber: color = .systemOrange
        case .red: color = .systemRed
        case .neutral: color = .tertiaryLabelColor
        }

        let barY = (height - barHeight) / 2
        if let fill = style.fill {
            let track = NSRect(x: 0.5, y: barY, width: barWidth - 1, height: barHeight)
            NSColor.tertiaryLabelColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            let filledWidth = max(barHeight, (barWidth - 1) * CGFloat(fill))
            let filled = NSRect(x: 0.5, y: barY, width: filledWidth, height: barHeight)
            color.setFill()
            NSBezierPath(roundedRect: filled, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }

        if let text = style.text {
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.foregroundColor: color,
            ])
            attributed.draw(at: NSPoint(x: barWidth + gap, y: (height - textSize.height) / 2))
        }

        image.isTemplate = style.tint == .neutral
        image.accessibilityDescription = style.toolTip
        return image
    }

    private static var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [NSAttributedString.Key.font: font]
    }
}
