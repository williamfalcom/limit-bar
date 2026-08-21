import SwiftUI

@main
struct LimitBarApp: App {
    private let store: AccountStore
    private let engine: PollingEngine

    init() {
        let store = AccountStore(persistence: PersistenceController())
        let adapters: [ProviderKind: any ProviderAdapter] = [
            .claudeCode: ClaudeAdapter(credentials: KeychainStore(service: ClaudeAdapter.credentialService)),
            .codex: CodexAdapter(),
            .openCodeGo: GoAdapter(credentials: KeychainStore()),
        ]
        let engine = PollingEngine(
            store: store,
            adapters: adapters,
            notifications: NotificationService()
        )
        self.store = store
        self.engine = engine
        Task {
            await engine.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelContainer(store: store) {
                Task {
                    await engine.refreshAllNow()
                }
            }
        } label: {
            statusIcon
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store, keychain: KeychainStore())
        }
    }

    private var statusIcon: Image {
        let accountID = store.activeAccountID ?? store.accounts.first?.id
        let snapshot = accountID.flatMap { store.snapshot(for: $0) }
        let windowKind = store.accounts.first { $0.id == accountID }?.displayedWindow ?? .fiveHour
        return Image(nsImage: IconRenderer.image(for: snapshot, window: windowKind))
    }
}

private struct PanelContainer: View {
    @Environment(\.openSettings) private var openSettings

    var store: AccountStore
    var onRefresh: () -> Void

    var body: some View {
        PanelView(
            store: store,
            onRefresh: onRefresh,
            onOpenSettings: {
                openSettings()
            }
        )
        .id(panelKey)
    }

    private var panelKey: String {
        let id = store.activeAccountID ?? store.accounts.first?.id
        let fetchedAt = id.flatMap { store.snapshot(for: $0)?.fetchedAt }
        return "\(id?.uuidString ?? "none")-\(fetchedAt?.timeIntervalSince1970 ?? 0)"
    }
}
