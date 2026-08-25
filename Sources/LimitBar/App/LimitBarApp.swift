import SwiftUI
import AppKit

// AD-001 fallback path: NSStatusItem + NSPopover replaces MenuBarExtra so the
// status item supports left-click (panel) and right-click (menu with Quit).
@main
struct LimitBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings live in an AppKit window managed by AppDelegate; this scene
        // only satisfies the SwiftUI lifecycle requirement.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: AccountStore
    let engine: PollingEngine

    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var escMonitor: Any?

    override init() {
        let store = AccountStore(persistence: PersistenceController())
        let adapters: [ProviderKind: any ProviderAdapter] = [
            .claudeCode: ClaudeAdapter(),
            .codex: CodexAdapter(),
            .openCodeGo: GoAdapter(credentials: KeychainStore()),
        ]
        let engine = PollingEngine(store: store, adapters: adapters, notifications: NotificationService())
        self.store = store
        self.engine = engine
        super.init()
        store.onAccountsChanged = { [weak self] in
            Task { await self?.engine.interruptSleep() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await engine.start() }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 372)
        popover.contentViewController = NSHostingController(
            rootView: PanelHost(
                store: store,
                onRefresh: { [weak self] in
                    guard let self else { return }
                    Task { await self.engine.refreshAllNow() }
                },
                onOpenSettings: { [weak self] in self?.openSettings() }
            )
        )

        redrawIcon()
        observeIconChanges()
    }

    // MARK: - Icon

    private func observeIconChanges() {
        withObservationTracking { [weak self] in
            self?.redrawIcon()
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeIconChanges() }
        }
    }

    private func redrawIcon() {
        let entries = store.accounts.map { account in
            (
                label: account.label,
                snapshot: store.snapshot(for: account.id),
                window: account.displayedWindow,
                provider: account.provider
            )
        }
        statusItem?.button?.image = IconRenderer.image(for: entries)
    }

    // MARK: - Click handling

    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) else {
            togglePopover()
            return
        }
        showContextMenu()
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            installEscMonitor()
        }
    }

    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()
        let refresh = NSMenuItem(title: NSLocalizedString("Refresh all accounts now", comment: ""),
                                 action: #selector(refreshNow(_:)), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let settings = NSMenuItem(title: NSLocalizedString("Settings…", comment: "context menu"),
                                  action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: NSLocalizedString("Quit limit-bar", comment: "context menu"),
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func refreshNow(_ sender: AnyObject?) {
        Task { await engine.refreshAllNow() }
    }

    @objc private func openSettingsFromMenu(_ sender: AnyObject?) {
        openSettings()
    }

    private var settingsWindow: NSWindow?

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let root = SettingsView(store: store, keychain: KeychainStore())
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = NSLocalizedString("Settings…", comment: "settings window title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 540))
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Esc dismissal

    private func installEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.popover.performClose(nil)
                self?.removeEscMonitor()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitor() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }
}

private struct PanelHost: View {
    var store: AccountStore
    var onRefresh: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        PanelView(
            store: store,
            onRefresh: onRefresh,
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                onOpenSettings()
            }
        )
        .id(panelKey)
        .transition(.identity)
        .animation(nil, value: panelKey)
    }

    private var panelKey: String {
        let id = store.activeAccountID ?? store.accounts.first?.id
        let fetchedAt = id.flatMap { store.snapshot(for: $0)?.fetchedAt }
        return "\(id?.uuidString ?? "none")-\(fetchedAt?.timeIntervalSince1970 ?? 0)"
    }
}
