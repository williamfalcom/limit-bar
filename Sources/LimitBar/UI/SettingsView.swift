import SwiftUI

enum IntervalValidator {
    struct ValidationError: Error, Equatable {
        let message: String
    }

    static let allowedRangeMessage = NSLocalizedString("Allowed range: 60–3600 seconds", comment: "interval validation")
    static let floor: TimeInterval = 60
    static let ceiling: TimeInterval = 3600

    typealias Result = Swift.Result<TimeInterval, ValidationError>

    static func validate(_ raw: String) -> Result {
        guard let value = TimeInterval(raw.trimmingCharacters(in: .whitespaces)), value > 0 else {
            return .failure(ValidationError(message: allowedRangeMessage))
        }
        guard value >= floor else {
            return .failure(ValidationError(message: allowedRangeMessage))
        }
        guard value <= ceiling else {
            return .failure(ValidationError(message: allowedRangeMessage))
        }
        return .success(value)
    }
}

struct SettingsView: View {
    var store: AccountStore
    var authManager: GoAuthManager
    var keychain: any CredentialStore = KeychainStore()

    @State private var showingAddSheet = false
    @State private var showingRemovalError = false
    @State private var removalError: String?
    @State private var intervalText: String
    @State private var intervalError: String?
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLogin = LaunchAtLoginController()

    init(
        store: AccountStore,
        authManager: GoAuthManager,
        keychain: any CredentialStore = KeychainStore()
    ) {
        self.store = store
        self.authManager = authManager
        self.keychain = keychain
        _intervalText = State(initialValue: String(Int(store.pollInterval)))
    }

    var body: some View {
        VStack(spacing: 0) {
            accountList
            Divider()
            intervalSection
        }
        .padding()
        .frame(width: 420, height: 360)
        .onAppear {
            launchAtLoginEnabled = launchAtLogin.isEnabled
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAccountSheet(authManager: authManager) { account in
                add(account: account)
            }
        }
        .alert("Could not remove account", isPresented: $showingRemovalError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalError ?? "Local credential cleanup did not complete. The account is still configured.")
        }
    }

    private var accountList: some View {
        List {
            Section("Accounts") {
                ForEach(store.accounts) { account in
                    AccountRow(
                        account: account,
                        onRename: { store.update(account: $0) },
                        onUpdate: { store.update(account: $0) },
                        onDelete: { remove(account: account) }
                    )
                }
            }
            Button("Add Account…") {
                showingAddSheet = true
            }
        }
        .listStyle(.inset)
        .frame(maxHeight: .infinity)
    }

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Refresh every")
                TextField("Seconds", text: $intervalText)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commitInterval)
                Text("seconds")
                Spacer()
                if let intervalError {
                    Text(intervalError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 180, alignment: .leading)
                } else {
                    EmptyView()
                }
            }
            Toggle("Start at Login", isOn: $launchAtLoginEnabled)
                .onChange(of: launchAtLoginEnabled) { _, newValue in
                    launchAtLogin.setEnabled(newValue)
                    launchAtLoginEnabled = launchAtLogin.isEnabled
                }
        }
        .padding(.top, 8)
    }

    private func commitInterval() {
        switch IntervalValidator.validate(intervalText) {
        case .success(let value):
            store.setPollInterval(value)
            intervalError = nil
            intervalText = String(Int(value))
        case .failure(let error):
            intervalError = error.message
        }
    }

    private func add(account: Account) {
        store.add(account: account)
        if store.activeAccountID == nil {
            store.selectActive(account.id)
        }
    }

    private func remove(account: Account) {
        Task {
            do {
                if account.provider == .openCodeGo {
                    try await authManager.deleteCredentials(for: account.id)
                } else {
                    do {
                        try keychain.deleteSecret(forKey: account.id.uuidString)
                    } catch KeychainStore.KeychainError.itemNotFound {
                        // Removing an account with no local credential is still safe.
                    }
                }
                store.remove(account: account)
            } catch {
                removalError = NSLocalizedString(
                    "Local credential cleanup did not complete. The account is still configured. Try again; some credentials may already have been removed.",
                    comment: "local account removal failure"
                )
                showingRemovalError = true
            }
        }
    }
}

private struct AccountRow: View {
    let account: Account
    let onRename: (Account) -> Void
    let onUpdate: (Account) -> Void
    let onDelete: () -> Void
    @State private var showingRemovalConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                TextField("Label", text: labelBinding)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Picker("Displayed window", selection: windowBinding) {
                        Text("5-hour").tag(WindowKind.fiveHour)
                        Text("Weekly").tag(WindowKind.weekly)
                        Text("Monthly").tag(WindowKind.monthly)
                    }
                    .labelsHidden()
                    .fixedSize()
                    if account.provider == .codex {
                        TextField("CODEX_HOME override", text: codexHomeBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                    }
                }
            }
            Spacer()
            Button(role: .destructive) {
                showingRemovalConfirmation = true
            } label: {
                Label("Remove account", systemImage: "minus.circle")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Remove account")
        }
        .padding(.vertical, 2)
        .confirmationDialog(
            isOAuthAccount ? "Remove OpenCode account?" : "Remove account?",
            isPresented: $showingRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            if isOAuthAccount {
                Text("Removing this account deletes its credentials from this Mac, but does not revoke the OpenCode Console session.")
            } else {
                Text("Remove this account and its locally stored credentials?")
            }
        }
    }

    private var iconName: String {
        switch account.provider {
        case .claudeCode: "c.circle.fill"
        case .codex: "x.square.fill"
        case .openCodeGo: "g.circle.fill"
        case .githubCopilot: "chevron.left.forwardslash.chevron.right"
        }
    }

    private var isOAuthAccount: Bool {
        account.provider == .openCodeGo && account.effectiveGoAuthMethod == .consoleOAuth
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { account.label },
            set: { newValue in
                var updated = account
                updated.label = newValue
                onRename(updated)
            }
        )
    }

    private var windowBinding: Binding<WindowKind> {
        Binding(
            get: { account.displayedWindow },
            set: { newValue in
                var updated = account
                updated.displayedWindow = newValue
                onUpdate(updated)
            }
        )
    }

    private var codexHomeBinding: Binding<String> {
        Binding(
            get: { account.codexHomeOverride ?? "" },
            set: { newValue in
                var updated = account
                updated.codexHomeOverride = newValue.isEmpty ? nil : newValue
                onUpdate(updated)
            }
        )
    }
}

private struct AddAccountSheet: View {
    let authManager: GoAuthManager
    let onAdd: (Account) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var label = ""
    @State private var provider: ProviderKind = .claudeCode
    @State private var codexHomeOverride = ""
    @State private var goAPIKey = ""
    @State private var goAuthMethodRawValue = GoAuthMethod.consoleOAuth.rawValue
    @State private var userCode: String?
    @State private var connectionError: String?
    @State private var isConnecting = false
    @State private var connectionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Account")
                .font(.headline)
            Form {
                Picker("Provider", selection: $provider) {
                    Text("Claude Code").tag(ProviderKind.claudeCode)
                    Text("Codex").tag(ProviderKind.codex)
                    Text("OpenCode").tag(ProviderKind.openCodeGo)
                    Text("GitHub Copilot").tag(ProviderKind.githubCopilot)
                }
                .disabled(isConnecting)
                TextField("Label", text: $label, prompt: Text(promptForDefaultLabel))
                    .disabled(isConnecting)
                if provider == .codex {
                    TextField("CODEX_HOME override (optional)", text: $codexHomeOverride)
                        .disabled(isConnecting)
                }
                if provider == .openCodeGo {
                    Picker("OpenCode sign-in method", selection: $goAuthMethodRawValue) {
                        Text("Browser login (recommended)").tag(GoAuthMethod.consoleOAuth.rawValue)
                        Text("API key").tag(GoAuthMethod.apiKey.rawValue)
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(isConnecting)
                    if selectedGoAuthMethod == .apiKey {
                        SecureField("API key", text: $goAPIKey, prompt: Text("Paste your OpenCode API key"))
                            .disabled(isConnecting)
                    }
                }
            }
            if let userCode {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter this code in the browser to authorize limit-bar.")
                        .font(.callout)
                    Text(userCode)
                        .font(.title3.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                    if isConnecting {
                        ProgressView("Waiting for approval…")
                    }
                }
                .padding(.vertical, 4)
            } else if isConnecting {
                ProgressView("Connecting to OpenCode…")
                    .padding(.vertical, 4)
            }
            if let connectionError {
                Text(connectionError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancelOrDismiss)
                    .keyboardShortcut(.cancelAction)
                Button(primaryActionTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || isConnecting)
            }
        }
        .padding()
        .frame(minWidth: 500, idealWidth: 500)
    }

    private var selectedGoAuthMethod: GoAuthMethod {
        GoAuthMethod(rawValue: goAuthMethodRawValue) ?? .consoleOAuth
    }

    private var canSubmit: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && (provider != .openCodeGo || selectedGoAuthMethod == .consoleOAuth || !goAPIKey.isEmpty)
    }

    private var primaryActionTitle: String {
        provider == .openCodeGo && selectedGoAuthMethod == .consoleOAuth
            ? NSLocalizedString("Connect with browser", comment: "OpenCode browser sign-in action")
            : NSLocalizedString("Add", comment: "add account action")
    }

    private var promptForDefaultLabel: String {
        switch provider {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCodeGo: "OpenCode"
        case .githubCopilot: "GitHub Copilot"
        }
    }

    private func submit() {
        var trimmedHome = codexHomeOverride.trimmingCharacters(in: .whitespaces)
        if trimmedHome == "~" || trimmedHome == "~/" {
            trimmedHome = ""
        }
        let account = Account(
            id: UUID(),
            provider: provider,
            label: label.trimmingCharacters(in: .whitespaces),
            displayedWindow: .fiveHour,
            codexHomeOverride: provider == .codex && !trimmedHome.isEmpty ? trimmedHome : nil,
            goAuthMethod: provider == .openCodeGo ? selectedGoAuthMethod : nil
        )

        guard provider == .openCodeGo else {
            onAdd(account)
            dismiss()
            return
        }

        switch selectedGoAuthMethod {
        case .apiKey:
            saveAPIKey(for: account)
        case .consoleOAuth:
            beginBrowserAuthorization(for: account)
        }
    }

    private func saveAPIKey(for account: Account) {
        let apiKey = goAPIKey
        isConnecting = true
        connectionError = nil
        connectionTask = Task {
            do {
                try await authManager.storeAPIKey(apiKey, for: account.id)
                guard Task.isCancelled == false else {
                    await clearCancelledCredentials(for: account)
                    return
                }
                onAdd(account)
                dismiss()
            } catch is CancellationError {
                isConnecting = false
                connectionTask = nil
            } catch {
                connectionError = localizedConnectionError(for: error)
                isConnecting = false
                connectionTask = nil
            }
        }
    }

    private func beginBrowserAuthorization(for account: Account) {
        isConnecting = true
        userCode = nil
        connectionError = nil
        connectionTask = Task {
            do {
                let authorization = try await authManager.requestDeviceAuthorization()
                try Task.checkCancellation()
                userCode = authorization.userCode
                openURL(authorization.verificationURL)
                try await authManager.authorize(authorization, for: account.id)
                guard Task.isCancelled == false else {
                    await clearCancelledCredentials(for: account)
                    return
                }
                onAdd(account)
                dismiss()
            } catch is CancellationError {
                userCode = nil
                isConnecting = false
                connectionTask = nil
            } catch {
                if Task.isCancelled {
                    userCode = nil
                } else {
                    connectionError = localizedConnectionError(for: error)
                }
                isConnecting = false
                connectionTask = nil
            }
        }
    }

    private func clearCancelledCredentials(for account: Account) async {
        do {
            try await authManager.deleteCredentials(for: account.id)
        } catch {
            connectionError = NSLocalizedString(
                "Could not clear OpenCode credentials after cancellation.",
                comment: "OpenCode local credential cleanup error"
            )
        }
        userCode = nil
        isConnecting = false
        connectionTask = nil
    }

    private func cancelOrDismiss() {
        guard isConnecting else {
            dismiss()
            return
        }
        connectionTask?.cancel()
        userCode = nil
        connectionError = nil
    }

    private func localizedConnectionError(for error: Error) -> String {
        GoAuthErrorMessage.localized(for: error)
    }
}
