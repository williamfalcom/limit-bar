import AppKit
import Testing
import SwiftUI
@testable import limit_bar

@Suite("ProviderTheme")
struct ProviderThemeTests {

    private func srgbComponents(_ color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let srgb = color.usingColorSpace(.sRGB)!
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }

    @Test("Claude Code accent is #FF8C00")
    func claudeCodeIsDarkOrange() {
        let (r, g, b) = srgbComponents(ProviderKind.claudeCode.barNSColor)
        #expect(abs(r - 255 / 255) < 0.001)
        #expect(abs(g - 140 / 255) < 0.001)
        #expect(abs(b - 0 / 255) < 0.001)
    }

    @Test("Codex accent is #4169E1")
    func codexIsRoyalBlue() {
        let (r, g, b) = srgbComponents(ProviderKind.codex.barNSColor)
        #expect(abs(r - 65 / 255) < 0.001)
        #expect(abs(g - 105 / 255) < 0.001)
        #expect(abs(b - 225 / 255) < 0.001)
    }

    @Test("OpenCode Go accent is #C0C0C0")
    func openCodeGoIsSilver() {
        let (r, g, b) = srgbComponents(ProviderKind.openCodeGo.barNSColor)
        #expect(abs(r - 192 / 255) < 0.001)
        #expect(abs(g - 192 / 255) < 0.001)
        #expect(abs(b - 192 / 255) < 0.001)
    }

    @Test("GitHub Copilot accent is #6A5ACD")
    func githubCopilotIsSlateBlue() {
        let (r, g, b) = srgbComponents(ProviderKind.githubCopilot.barNSColor)
        #expect(abs(r - 106 / 255) < 0.001)
        #expect(abs(g - 90 / 255) < 0.001)
        #expect(abs(b - 205 / 255) < 0.001)
    }

    @Test("SwiftUI barColor bridges from barNSColor")
    func barColorBridgesFromNSColor() {
        for kind in [ProviderKind.claudeCode, .codex, .openCodeGo, .githubCopilot] {
            #expect(kind.barColor == Color(nsColor: kind.barNSColor))
        }
    }
}
