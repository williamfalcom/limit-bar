import AppKit
import SwiftUI

extension ProviderKind {
    var barNSColor: NSColor {
        switch self {
        case .claudeCode: NSColor(srgbRed: 255 / 255, green: 140 / 255, blue: 0 / 255, alpha: 1)
        case .codex: NSColor(srgbRed: 65 / 255, green: 105 / 255, blue: 225 / 255, alpha: 1)
        case .openCodeGo: NSColor(srgbRed: 192 / 255, green: 192 / 255, blue: 192 / 255, alpha: 1)
        case .githubCopilot: NSColor(srgbRed: 106 / 255, green: 90 / 255, blue: 205 / 255, alpha: 1)
        }
    }

    var barColor: Color {
        Color(nsColor: barNSColor)
    }
}
