import SwiftUI

enum IntervalValidator {
    struct ValidationError: Error, Equatable {
        let message: String
    }

    static let allowedRangeMessage = "Allowed range: 60–3600 seconds"
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
    var keychain: any CredentialStore = KeychainStore()

    @State private var showingAddSheet = false
    @State private var intervalText: String
    @State private var intervalError: String?
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLogin = LaunchAtLoginController()

    init(store: AccountStore, keychain: any CredentialStore = KeychainStore()) {
        self.store = store
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
            AddAccountSheet { account, apiKey in
                add(account:account, goAPIKey: apiKey)
            }
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

    private func add(account: Account, goAPIKey apiKey: String?) {
        if account.provider == .openCodeGo, let apiKey, !apiKey.isEmpty {
            try? keychain.set(apiKey, forKey: GoAdapter.apiKey(for: account))
        }
        store.add(account: account)
        if store.activeAccountID == nil {
            store.selectActive(account.id)
        }
    }

    private func remove(account: Account) {
        try? keychain.deleteSecret(forKey: account.id.uuidString)
        store.remove(account: account)
    }
}

private struct AccountRow: View {
    let account: Account
    let onRename: (Account) -> Void
    let onUpdate: (Account) -> Void
    let onDelete: () -> Void

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
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove account")
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch account.provider {
        case .claudeCode: "c.circle.fill"
        case .codex: "x.square.fill"
        case .openCodeGo: "g.circle.fill"
        }
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
    let onAdd: (Account, _ goAPIKey: String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var provider: ProviderKind = .claudeCode
    @State private var codexHomeOverride = ""
    @State private var goAPIKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Account")
                .font(.headline)
            Form {
                Picker("Provider", selection: $provider) {
                    Text("Claude Code").tag(ProviderKind.claudeCode)
                    Text("Codex").tag(ProviderKind.codex)
                    Text("OpenCode Go").tag(ProviderKind.openCodeGo)
                }
                TextField("Label", text: $label, prompt: Text(promptForDefaultLabel))
                if provider == .codex {
                    TextField("CODEX_HOME override (optional)", text: $codexHomeOverride)
                }
                if provider == .openCodeGo {
                    SecureField("API key", text: $goAPIKey, prompt: Text("Paste your OpenCode Go API key"))
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Add") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding()
        .frame(width: 340)
    }

    private var canAdd: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && (provider != .openCodeGo || !goAPIKey.isEmpty)
    }

    private var promptForDefaultLabel: String {
        switch provider {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCodeGo: "OpenCode Go"
        }
    }

    private func commit() {
        var trimmedHome = codexHomeOverride.trimmingCharacters(in: .whitespaces)
        if trimmedHome == "~" || trimmedHome == "~/" {
            trimmedHome = ""
        }
        let account = Account(
            id: UUID(),
            provider: provider,
            label: label.trimmingCharacters(in: .whitespaces),
            displayedWindow: .fiveHour,
            codexHomeOverride: provider == .codex && !trimmedHome.isEmpty ? trimmedHome : nil
        )
        onAdd(account, provider == .openCodeGo ? goAPIKey : nil)
        dismiss()
    }
}
