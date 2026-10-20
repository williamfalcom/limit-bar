import Foundation

enum GoAuthErrorMessage {
    static func localized(for error: Error) -> String {
        if error is KeychainStore.KeychainError {
            return NSLocalizedString(
                "Could not save OpenCode credentials to Keychain.",
                comment: "OpenCode credential storage error"
            )
        }
        if let error = error as? GoOAuthClientError {
            return switch error {
            case .authorizationExpired:
                NSLocalizedString("OpenCode authorization expired. Start again.", comment: "device authorization expiry")
            case .authorizationDenied:
                NSLocalizedString("OpenCode authorization was denied.", comment: "device authorization denial")
            case .network:
                NSLocalizedString("Could not connect to OpenCode. Check your network and try again.", comment: "OAuth network error")
            case .untrustedVerificationURL, .invalidResponse:
                NSLocalizedString("The OpenCode response was invalid. Try again.", comment: "OAuth response error")
            case .httpStatus, .invalidGrant:
                NSLocalizedString("Could not complete OpenCode authorization. Try again.", comment: "OAuth authorization error")
            }
        }
        return NSLocalizedString("Could not complete OpenCode authorization. Try again.", comment: "OAuth authorization error")
    }
}
