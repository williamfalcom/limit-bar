import SwiftUI

struct PanelView: View {
    var store: AccountStore
    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                emptyState
            } else {
                tabs
            }
        }
        .frame(width: 420)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var tabs: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.accounts) { account in
                        tabButton(account)
                    }
                }
                .padding(.horizontal, 2)
            }
            activeTabContent
        }
    }

    private func tabButton(_ account: Account) -> some View {
        let activeID = store.activeAccountID ?? store.accounts.first?.id
        let isActive = activeID == account.id
        return Button {
            store.selectActive(account.id)
        } label: {
            Text(account.label)
                .font(.system(size: 16, weight: isActive ? .semibold : .medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.10)),
                    in: Capsule()
                )
                .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(account.label)
    }

    private var activeSnapshot: AccountSnapshot? {
        guard let id = store.activeAccountID ?? store.accounts.first?.id else { return nil }
        return store.snapshot(for: id)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        let snapshot = activeSnapshot
        switch snapshot?.state {
        case .fresh, .stale, .error:
            if let account = activeProvider {
                VStack(spacing: 8) {
                    if case .error(let message) = snapshot?.state {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array((snapshot?.windows ?? []).enumerated()), id: \.element.kind) { _, window in
                        WindowRow(window: window, fetchedAt: snapshot?.fetchedAt, now: Date(), provider: account.provider)
                    }
                    footer(fetchedAt: snapshot?.fetchedAt, isStale: snapshot?.state == .stale)
                }
            }
        case .unauthorized:
            if let provider = activeProvider {
                ReauthInstructions(providerID: provider.provider)
            }
        case .unsupported:
            VStack(spacing: 6) {
                Label(NSLocalizedString(NSLocalizedString("OpenCode Go usage API not available yet", comment: ""), comment: ""), systemImage: "hourglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString(NSLocalizedString("Limits will appear here once the provider exposes a usage endpoint.", comment: ""), comment: ""))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        case nil:
            ContentUnavailableView("No data", systemImage: "gauge", description: Text("Select an account"))
        }
    }

    private var activeProvider: Account? {
        guard let id = store.activeAccountID ?? store.accounts.first?.id else { return nil }
        return store.accounts.first { $0.id == id }
    }
    private func footer(fetchedAt: Date?, isStale: Bool) -> some View {
        HStack {
            Text(Self.updatedText(fetchedAt: fetchedAt, now: Date(), stale: isStale))
                .font(.system(size: 15, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Open Settings")
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Refresh all accounts now")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "gauge")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No accounts configured")
                .font(.headline)
            Button("Add your first account") {
                onOpenSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    static func updatedText(fetchedAt: Date?, now: Date, stale: Bool = false) -> String {
        guard let fetchedAt else { return "" }
        let minutes = max(1, Int(now.timeIntervalSince(fetchedAt) / 60))
        let suffix = stale ? " " + NSLocalizedString("(stale)", comment: "stale data marker") : ""
        if minutes >= 60 {
            let hours = minutes / 60
            return String(
                format: NSLocalizedString("%dh %dm ago", comment: "updated hours and minutes ago"),
                hours, minutes % 60
            ) + suffix
        }
        return String(format: NSLocalizedString("%dm ago", comment: "updated minutes ago"), minutes) + suffix
    }
}

private struct WindowRow: View {
    let window: LimitWindow
    let fetchedAt: Date?
    let now: Date
    let provider: ProviderKind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if let absolute = window.usedAbsolute {
                    Text(absolute)
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            LimitProgressBar(percent: window.usedPercent, tint: provider.barColor)
            if let resetsAt = window.resetsAt {
                Text("resets in \(IconRenderer.formatCountdown(until: resetsAt, now: now))")
                    .font(.system(size: 15, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(Int(window.usedPercent))% used")
    }

    private var title: String {
        switch window.kind {
        case .fiveHour: NSLocalizedString("5-hour", comment: "window title")
        case .weekly: NSLocalizedString("Weekly", comment: "window title")
        case .monthly: NSLocalizedString("Monthly", comment: "window title")
        case .weeklyModel(let model):
            String(format: NSLocalizedString("Weekly · %@", comment: "per-model weekly window title"), model)
        }
    }
}

private struct LimitProgressBar: View {
    let percent: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(10, geo.size.width * min(max(percent, 0), 100) / 100))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private struct ReauthInstructions: View {
    let providerID: ProviderKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sign-in required", systemImage: "lock")
                .font(.headline)
            Text(instructionText)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var instructionText: String {
        switch providerID {
        case .claudeCode:
            NSLocalizedString("The Claude Code credential was rejected, missing, or Keychain access was denied. Log in with the Claude Code CLI and allow limit-bar to read \"Claude Code-credentials\" when macOS asks.", comment: "Claude reauth instructions")
        case .codex:
            NSLocalizedString("Codex authentication failed or auth.json is missing. Log in again with the Codex CLI, then refresh.", comment: "Codex reauth instructions")
        case .openCodeGo:
            NSLocalizedString("Your OpenCode Go API key was rejected. Paste a valid key in Settings.", comment: "Go reauth instructions")
        }
    }

    private var command: String {
        switch providerID {
        case .claudeCode: "claude login"
        case .codex: "codex login"
        case .openCodeGo: "# Settings → Accounts → Go API key"
        }
    }
}
