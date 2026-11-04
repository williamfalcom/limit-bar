import Foundation
import Testing
@testable import limit_bar

@Suite("Localization")
struct LocalizationTests {

    private static let locales = ["en", "pt-BR", "es"]

    private static let requiredKeys = [
        "Quit limit-bar",
        "Settings…",
        "Remove",
        "Seconds",
        "Network error: %d",
        "Your GitHub Copilot authentication was rejected. Log in with the Copilot CLI and refresh.",
        "Codex authentication failed or auth.json is missing. Log in again with the Codex CLI, then refresh.",
    ]

    private func table(_ locale: String) throws -> [String: String] {
        let url = try #require(Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: locale
        ))
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    @Test("en, pt-BR, and es tables contain the same keys")
    func tablesShareKeys() throws {
        let english = Set(try table("en").keys)
        for locale in Self.locales.dropFirst() {
            let keys = Set(try table(locale).keys)
            #expect(keys.subtracting(english).isEmpty, "\(locale) has keys missing from en")
            #expect(english.subtracting(keys).isEmpty, "en has keys missing from \(locale)")
        }
    }

    @Test("Every reviewed UI string has a key in each table", arguments: locales)
    func requiredKeysExist(locale: String) throws {
        let keys = Set(try table(locale).keys)
        let missing = Self.requiredKeys.filter { !keys.contains($0) }
        #expect(missing.isEmpty)
    }

    @Test("A network failure message carries the URLError code in every locale", arguments: locales)
    func networkErrorFormatsCode(locale: String) throws {
        let format = try #require(try table(locale)["Network error: %d"])
        let message = String(format: format, URLError.timedOut.rawValue)
        #expect(message.hasSuffix(": -1001"))
    }

    @Test("pt-BR shows the network failure message in Portuguese")
    func networkErrorIsTranslated() throws {
        let format = try #require(try table("pt-BR")["Network error: %d"])
        #expect(String(format: format, URLError.timedOut.rawValue) == "Erro de rede: -1001")
    }

    @MainActor
    @Test("A network fetch failure stores the localized message with the URLError code")
    func storeUsesLocalizedNetworkMessage() {
        let store = AccountStore(persistence: InMemoryPersistence())
        let account = Account(id: UUID(), provider: .codex, label: "Codex", displayedWindow: .fiveHour, codexHomeOverride: nil)
        store.add(account: account)

        store.apply(.failure(.network(URLError(.timedOut))), for: account.id)

        let expected = AccountStore.networkErrorMessage(URLError(.timedOut))
        #expect(store.snapshot(for: account.id)?.state == .error(expected))
        #expect(expected.hasSuffix(": -1001"))
    }

    @Test("The network failure message is translated regardless of the machine language")
    func networkMessageUsesLocaleTable() throws {
        let path = try #require(Bundle.main.path(forResource: "pt-BR", ofType: "lproj"))
        let portuguese = try #require(Bundle(path: path))

        #expect(AccountStore.networkErrorMessage(URLError(.timedOut), bundle: portuguese) == "Erro de rede: -1001")
    }
}

private final class InMemoryPersistence: StatePersisting, @unchecked Sendable {
    func load() -> AppState? { nil }
    func save(_ state: AppState) {}
}
