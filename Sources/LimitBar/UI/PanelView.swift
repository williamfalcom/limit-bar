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
        .frame(width: 300)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var tabs: some View {
        VStack(spacing: 10) {
            Picker("Account", selection: selection) {
                ForEach(store.accounts) { account in
                    Text(account.label).tag(Optional(account.id))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            activeTabContent
        }
    }

    private var selection: Binding<UUID?> {
        Binding(
            get: { store.activeAccountID ?? store.accounts.first?.id },
            set: { newValue in
                if let newValue {
                    store.selectActive(newValue)
                }
            }
        )
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
            VStack(spacing: 8) {
                if case .error(let message) = snapshot?.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array((snapshot?.windows ?? []).enumerated()), id: \.element.kind) { _, window in
                    WindowRow(window: window, fetchedAt: snapshot?.fetchedAt, now: Date())
                }
                footer(fetchedAt: snapshot?.fetchedAt, isStale: snapshot?.state == .stale)
            }
        case .unauthorized:
            if let provider = activeProvider {
                ReauthInstructions(providerID: provider.provider)
            }
        case .unsupported:
            VStack(spacing: 6) {
                Label("OpenCode Go usage API not available yet", systemImage: "hourglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Limits will appear here once the provider exposes a usage endpoint.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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
                .font(.caption2)
                .foregroundStyle(isStale ? .secondary : .tertiary)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
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
        let suffix = stale ? " (stale)" : ""
        if minutes >= 60 {
            let hours = minutes / 60
            return "updated \(hours)h \(minutes % 60)m ago\(suffix)"
        }
        return "updated \(minutes)m ago\(suffix)"
    }
}

private struct WindowRow: View {
    let window: LimitWindow
    let fetchedAt: Date?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                if let absolute = window.usedAbsolute {
                    Text(absolute)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: min(max(window.usedPercent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
            if let resetsAt = window.resetsAt {
                Text("resets in \(IconRenderer.formatCountdown(until: resetsAt, now: now))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(Int(window.usedPercent))% used")
    }

    private var title: String {
        switch window.kind {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    private var tint: Color {
        if window.usedPercent >= IconRenderer.redThreshold { return .red }
        if window.usedPercent >= IconRenderer.amberThreshold { return .orange }
        return .green
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
            "The Claude Code credential was rejected, missing, or Keychain access was denied. Log in with the Claude Code CLI and allow limit-bar to read \"Claude Code-credentials\" when macOS asks."
        case .codex:
            "Codex authentication failed or auth.json is missing. Log in again with the Codex CLI, then refresh."
        case .openCodeGo:
            "Your OpenCode Go API key was rejected. Paste a valid key in Settings."
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
