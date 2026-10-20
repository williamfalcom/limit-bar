import SwiftUI

struct GoAccountReauthenticationSheet: View {
    let account: Account
    let authManager: GoAuthManager
    let onReauthenticated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var apiKey = ""
    @State private var userCode: String?
    @State private var connectionError: String?
    @State private var isConnecting = false
    @State private var connectionTask: Task<Void, Never>?

    private var isOAuth: Bool {
        account.effectiveGoAuthMethod == .consoleOAuth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isOAuth ? "Reconnect OpenCode account" : "Replace OpenCode API key")
                .font(.headline)
            Text(account.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isOAuth {
                oauthStatus
            } else {
                Text("Your OpenCode API key was rejected. Replace it to restore quota updates.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("Paste a replacement OpenCode API key", text: $apiKey)
                    .disabled(isConnecting)
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
                    .disabled(isConnecting && !isOAuth)
                Button(primaryActionTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isConnecting || (!isOAuth && apiKey.isEmpty))
            }
        }
        .padding()
        .frame(minWidth: 440, idealWidth: 460)
        .interactiveDismissDisabled(isConnecting && !isOAuth)
    }

    @ViewBuilder
    private var oauthStatus: some View {
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
        } else {
            Text("Your OpenCode OAuth session was rejected or expired. Reconnect to restore quota updates.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryActionTitle: String {
        if isOAuth {
            NSLocalizedString("Reconnect with browser", comment: "OpenCode OAuth reauthentication action")
        } else {
            NSLocalizedString("Save API key", comment: "OpenCode API-key replacement action")
        }
    }

    private func submit() {
        if isOAuth {
            beginBrowserAuthorization()
        } else {
            replaceAPIKey()
        }
    }

    private func replaceAPIKey() {
        isConnecting = true
        connectionError = nil
        let replacement = apiKey
        connectionTask = Task {
            do {
                try await authManager.storeAPIKey(replacement, for: account.id)
                finishSuccessfully()
            } catch {
                connectionError = GoAuthErrorMessage.localized(for: error)
                isConnecting = false
                connectionTask = nil
            }
        }
    }

    private func beginBrowserAuthorization() {
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
                finishSuccessfully()
            } catch is CancellationError {
                userCode = nil
                isConnecting = false
                connectionTask = nil
            } catch {
                if !Task.isCancelled {
                    connectionError = GoAuthErrorMessage.localized(for: error)
                }
                userCode = nil
                isConnecting = false
                connectionTask = nil
            }
        }
    }

    private func finishSuccessfully() {
        userCode = nil
        isConnecting = false
        connectionTask = nil
        onReauthenticated()
        dismiss()
    }

    private func cancelOrDismiss() {
        guard isConnecting else {
            dismiss()
            return
        }
        connectionTask?.cancel()
        connectionError = nil
    }
}
