import Foundation
import Testing
@testable import limit_bar

private final class GoAuthCredentialStoreSpy: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var failedWrites: Set<String> = []
    private var reads: [String: Int] = [:]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func failWrites(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        failedWrites.insert(key)
    }

    var valuesSnapshot: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func set(_ secret: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard failedWrites.contains(key) == false else {
            throw KeychainStore.KeychainError.accessDenied
        }
        values[key] = secret
    }

    func readCount(forKey key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return reads[key, default: 0]
    }

    func secret(forKey key: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        reads[key, default: 0] += 1
        guard let value = values[key] else {
            throw KeychainStore.KeychainError.itemNotFound
        }
        return value
    }

    func deleteSecret(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard values.removeValue(forKey: key) != nil else {
            throw KeychainStore.KeychainError.itemNotFound
        }
    }
}

private actor GoOAuthClientStub: GoOAuthClientProtocol {
    private let authorizationResult: Result<GoOAuthCredential, GoOAuthClientError>
    private let refreshResults: [String: Result<GoOAuthCredential, GoOAuthClientError>]
    private let blockedRefreshTokens: Set<String>
    private let challenge: GoDeviceAuthorization
    private var pollCalls = 0
    private var refreshCalls: [String: Int] = [:]
    private var refreshStartWaiter: CheckedContinuation<Void, Never>?
    private var pendingRefreshes: [CheckedContinuation<GoOAuthCredential, Error>] = []
    private var releasedCredential: GoOAuthCredential?

    init(
        challenge: GoDeviceAuthorization,
        authorizationResult: Result<GoOAuthCredential, GoOAuthClientError> = .failure(.authorizationDenied),
        refreshResults: [String: Result<GoOAuthCredential, GoOAuthClientError>] = [:],
        blockedRefreshTokens: Set<String> = []
    ) {
        self.challenge = challenge
        self.authorizationResult = authorizationResult
        self.refreshResults = refreshResults
        self.blockedRefreshTokens = blockedRefreshTokens
    }

    func requestDeviceAuthorization() async throws -> GoDeviceAuthorization {
        challenge
    }

    func pollForAuthorization(_ authorization: GoDeviceAuthorization) async throws -> GoOAuthCredential {
        pollCalls += 1
        return try authorizationResult.get()
    }

    func refresh(_ credential: GoOAuthCredential) async throws -> GoOAuthCredential {
        refreshCalls[credential.refreshToken, default: 0] += 1
        refreshStartWaiter?.resume()
        refreshStartWaiter = nil

        if blockedRefreshTokens.contains(credential.refreshToken) {
            if let releasedCredential { return releasedCredential }
            return try await withCheckedThrowingContinuation { continuation in
                pendingRefreshes.append(continuation)
            }
        }
        guard let result = refreshResults[credential.refreshToken] else {
            throw GoOAuthClientError.invalidGrant
        }
        return try result.get()
    }

    func waitForRefreshCall() async {
        guard refreshCalls.values.reduce(0, +) == 0 else { return }
        await withCheckedContinuation { refreshStartWaiter = $0 }
    }

    func releaseBlockedRefresh(with credential: GoOAuthCredential) {
        releasedCredential = credential
        let continuations = pendingRefreshes
        pendingRefreshes = []
        for continuation in continuations {
            continuation.resume(returning: credential)
        }
    }

    func refreshCallCount(for refreshToken: String) -> Int {
        refreshCalls[refreshToken, default: 0]
    }

    func totalRefreshCalls() -> Int {
        refreshCalls.values.reduce(0, +)
    }

    func pollCallCount() -> Int { pollCalls }
}

private actor GoOAuthAuthorizationGate: GoOAuthClientProtocol {
    private let challenge: GoDeviceAuthorization
    private let credential: GoOAuthCredential
    private var pollingStarted = false
    private var pollingWaiter: CheckedContinuation<Void, Never>?
    private var approval: CheckedContinuation<GoOAuthCredential, Error>?

    init(challenge: GoDeviceAuthorization, credential: GoOAuthCredential) {
        self.challenge = challenge
        self.credential = credential
    }

    func requestDeviceAuthorization() async throws -> GoDeviceAuthorization { challenge }

    func pollForAuthorization(_ authorization: GoDeviceAuthorization) async throws -> GoOAuthCredential {
        pollingStarted = true
        pollingWaiter?.resume()
        pollingWaiter = nil
        return try await withCheckedThrowingContinuation { approval = $0 }
    }

    func refresh(_ credential: GoOAuthCredential) async throws -> GoOAuthCredential {
        throw GoOAuthClientError.invalidGrant
    }

    func waitForPollingToStart() async {
        guard pollingStarted == false else { return }
        await withCheckedContinuation { pollingWaiter = $0 }
    }

    func approve() {
        approval?.resume(returning: credential)
        approval = nil
    }
}

private final class GoAuthManagerClock: @unchecked Sendable {
    private let lock = NSLock()
    private let date: Date
    private var readCount = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(_ date: Date) {
        self.date = date
    }

    func read() -> Date {
        lock.lock()
        readCount += 1
        let ready = waiters.filter { $0.0 <= readCount }
        waiters.removeAll { $0.0 <= readCount }
        let result = date
        lock.unlock()
        for (_, continuation) in ready {
            continuation.resume()
        }
        return result
    }

    func waitForReads(_ count: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if readCount >= count {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((count, continuation))
                lock.unlock()
            }
        }
    }
}

struct GoAuthManagerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeChallenge() -> GoDeviceAuthorization {
        GoDeviceAuthorization(
            deviceCode: "device-code",
            userCode: "ABCD-EFGH",
            verificationURL: URL(string: "https://opencode.ai/console/device")!,
            expiresAt: now.addingTimeInterval(600),
            interval: 5
        )
    }

    private func makeCredential(
        accessToken: String,
        refreshToken: String,
        expiresAt: Date,
        workspaceID: String? = "workspace-1"
    ) -> GoOAuthCredential {
        GoOAuthCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            workspaceID: workspaceID
        )
    }

    private func makeAccount(id: UUID = UUID(), method: GoAuthMethod = .consoleOAuth) -> Account {
        Account(
            id: id,
            provider: .openCodeGo,
            label: "Go",
            displayedWindow: .weekly,
            codexHomeOverride: nil,
            goAuthMethod: method
        )
    }

    private func makeManager(
        store: GoAuthCredentialStoreSpy,
        client: GoOAuthClientStub,
        clock: GoAuthManagerClock? = nil
    ) -> GoAuthManager {
        let managerClock = clock ?? GoAuthManagerClock(now)
        return GoAuthManager(
            vault: GoCredentialVault(credentials: store),
            oauthClient: client,
            now: { managerClock.read() }
        )
    }

    @Test("Device authorization stores the OAuth credential before succeeding")
    func authorizationPersistsOAuthCredential() async throws {
        let account = makeAccount()
        let credential = makeCredential(
            accessToken: "authorized-access",
            refreshToken: "authorized-refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            authorizationResult: .success(credential)
        )
        let manager = makeManager(store: store, client: client)

        let challenge = try await manager.requestDeviceAuthorization()
        try await manager.authorize(challenge, for: account.id)

        #expect(try vault.oauthCredential(for: account.id) == credential)
        #expect(await client.pollCallCount() == 1)
    }

    @Test("Failed OAuth credential storage leaves no usable credential")
    func authorizationStorageFailureDoesNotCreateCredential() async {
        let account = makeAccount()
        let credential = makeCredential(
            accessToken: "authorized-access",
            refreshToken: "authorized-refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        store.failWrites(forKey: GoCredentialVault.oauthKey(for: account.id))
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            authorizationResult: .success(credential)
        )
        let manager = makeManager(store: store, client: client)

        await #expect(throws: KeychainStore.KeychainError.accessDenied) {
            try await manager.authorize(makeChallenge(), for: account.id)
        }
        #expect(throws: KeychainStore.KeychainError.itemNotFound) {
            try vault.oauthCredential(for: account.id)
        }
    }

    @Test("Cancelled authorization does not persist credentials when polling completes")
    func cancelledAuthorizationDoesNotPersistCredential() async throws {
        let account = makeAccount()
        let credential = makeCredential(
            accessToken: "authorized-access",
            refreshToken: "authorized-refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        let challenge = makeChallenge()
        let client = GoOAuthAuthorizationGate(challenge: challenge, credential: credential)
        let manager = GoAuthManager(vault: vault, oauthClient: client, now: { self.now })

        let authorization = Task {
            try await manager.authorize(challenge, for: account.id)
        }
        await client.waitForPollingToStart()
        authorization.cancel()
        await client.approve()

        await #expect(throws: CancellationError.self) {
            try await authorization.value
        }
        #expect(throws: KeychainStore.KeychainError.itemNotFound) {
            try vault.oauthCredential(for: account.id)
        }
    }

    @Test("API-key accounts resolve their Keychain Bearer without OAuth refresh")
    func apiKeyAccountUsesStoredKey() async throws {
        let account = makeAccount(method: .apiKey)
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        try vault.storeAPIKey("go-api-key", for: account.id)
        let client = GoOAuthClientStub(challenge: makeChallenge())
        let manager = makeManager(store: store, client: client)

        let token = try await manager.bearerToken(for: account)

        #expect(token == "go-api-key")
        #expect(await client.totalRefreshCalls() == 0)
    }

    @Test("OAuth account returns its token without refreshing when more than 60 seconds remain")
    func unexpiredOAuthCredentialSkipsRefresh() async throws {
        let account = makeAccount()
        let credential = makeCredential(
            accessToken: "current-access",
            refreshToken: "current-refresh",
            expiresAt: now.addingTimeInterval(61)
        )
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeOAuthCredential(credential, for: account.id)
        let client = GoOAuthClientStub(challenge: makeChallenge())
        let manager = makeManager(store: store, client: client)

        let token = try await manager.bearerToken(for: account)

        #expect(token == "current-access")
        #expect(await client.totalRefreshCalls() == 0)
    }

    @Test("OAuth credential refreshes at the 60-second margin and persists rotation")
    func refreshesAtExpiryMarginAndStoresRotation() async throws {
        let account = makeAccount()
        let prior = makeCredential(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(60)
        )
        let rotated = makeCredential(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: now.addingTimeInterval(3600),
            workspaceID: "workspace-2"
        )
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        try vault.storeOAuthCredential(prior, for: account.id)
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            refreshResults: ["old-refresh": .success(rotated)]
        )
        let manager = makeManager(store: store, client: client)

        let token = try await manager.bearerToken(for: account)

        #expect(token == "new-access")
        #expect(try vault.oauthCredential(for: account.id) == rotated)
        #expect(await client.refreshCallCount(for: "old-refresh") == 1)
    }

    @Test("Repeated API-key bearer requests read the Keychain once")
    func repeatedAPIKeyRequestsReadOnce() async throws {
        let account = makeAccount(method: .apiKey)
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeAPIKey("go-api-key", for: account.id)
        let manager = makeManager(store: store, client: GoOAuthClientStub(challenge: makeChallenge()))

        var tokens: [String] = []
        for _ in 0..<3 { tokens.append(try await manager.bearerToken(for: account)) }

        #expect(tokens == ["go-api-key", "go-api-key", "go-api-key"])
        #expect(store.readCount(forKey: GoCredentialVault.apiKeyKey(for: account.id)) == 1)
    }

    @Test("Repeated OAuth bearer requests read the Keychain once")
    func repeatedOAuthRequestsReadOnce() async throws {
        let account = makeAccount()
        let credential = makeCredential(accessToken: "current-access", refreshToken: "current-refresh", expiresAt: now.addingTimeInterval(3600))
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeOAuthCredential(credential, for: account.id)
        let manager = makeManager(store: store, client: GoOAuthClientStub(challenge: makeChallenge()))

        var tokens: [String] = []
        for _ in 0..<3 { tokens.append(try await manager.bearerToken(for: account)) }

        #expect(tokens == ["current-access", "current-access", "current-access"])
        #expect(store.readCount(forKey: GoCredentialVault.oauthKey(for: account.id)) == 1)
    }

    @Test("A rotated OAuth credential is served from memory after refresh")
    func rotatedCredentialServedWithoutRead() async throws {
        let account = makeAccount()
        let prior = makeCredential(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: now.addingTimeInterval(10))
        let rotated = makeCredential(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: now.addingTimeInterval(3600))
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeOAuthCredential(prior, for: account.id)
        let client = GoOAuthClientStub(challenge: makeChallenge(), refreshResults: ["old-refresh": .success(rotated)])
        let manager = makeManager(store: store, client: client)

        let first = try await manager.bearerToken(for: account)
        let second = try await manager.bearerToken(for: account)

        #expect(first == "new-access")
        #expect(second == "new-access")
        #expect(await client.refreshCallCount(for: "old-refresh") == 1)
        #expect(await client.refreshCallCount(for: "new-refresh") == 0)
        // One initial read plus the read before the refresh (REL-06 AC1); none after rotation.
        #expect(store.readCount(forKey: GoCredentialVault.oauthKey(for: account.id)) == 2)
    }

    @Test("Stored API keys and completed authorizations are served without a Keychain read")
    func storedCredentialsServedWithoutRead() async throws {
        let keyAccount = makeAccount(method: .apiKey)
        let oauthAccount = makeAccount()
        let authorized = makeCredential(accessToken: "authorized-access", refreshToken: "authorized-refresh", expiresAt: now.addingTimeInterval(3600))
        let store = GoAuthCredentialStoreSpy()
        let client = GoOAuthClientStub(challenge: makeChallenge(), authorizationResult: .success(authorized))
        let manager = makeManager(store: store, client: client)

        try await manager.storeAPIKey("replacement-key", for: keyAccount.id)
        try await manager.authorize(makeChallenge(), for: oauthAccount.id)

        #expect(try await manager.bearerToken(for: keyAccount) == "replacement-key")
        #expect(try await manager.bearerToken(for: oauthAccount) == "authorized-access")
        #expect(store.readCount(forKey: GoCredentialVault.apiKeyKey(for: keyAccount.id)) == 0)
        #expect(store.readCount(forKey: GoCredentialVault.oauthKey(for: oauthAccount.id)) == 0)
    }

    @Test("Deleting credentials forces the next request to read the Keychain")
    func deleteForcesKeychainRead() async throws {
        let account = makeAccount(method: .apiKey)
        let store = GoAuthCredentialStoreSpy()
        let manager = makeManager(store: store, client: GoOAuthClientStub(challenge: makeChallenge()))
        try await manager.storeAPIKey("go-api-key", for: account.id)

        try await manager.deleteCredentials(for: account.id)

        await #expect(throws: GoAuthManagerError.missingCredentials) {
            try await manager.bearerToken(for: account)
        }
        #expect(store.readCount(forKey: GoCredentialVault.apiKeyKey(for: account.id)) == 1)
    }

    @Test("A failed Keychain read is retried on the next request")
    func failedReadIsNotCached() async throws {
        let account = makeAccount()
        let store = GoAuthCredentialStoreSpy()
        let manager = makeManager(store: store, client: GoOAuthClientStub(challenge: makeChallenge()))

        await #expect(throws: GoAuthManagerError.missingCredentials) {
            try await manager.bearerToken(for: account)
        }
        let credential = makeCredential(accessToken: "late-access", refreshToken: "late-refresh", expiresAt: now.addingTimeInterval(3600))
        try GoCredentialVault(credentials: store).storeOAuthCredential(credential, for: account.id)

        #expect(try await manager.bearerToken(for: account) == "late-access")
        #expect(store.readCount(forKey: GoCredentialVault.oauthKey(for: account.id)) == 2)
    }

    @Test("A failed API-key read is retried on the next request")
    func failedAPIKeyReadIsNotCached() async throws {
        let account = makeAccount(method: .apiKey)
        let store = GoAuthCredentialStoreSpy()
        let manager = makeManager(store: store, client: GoOAuthClientStub(challenge: makeChallenge()))

        await #expect(throws: GoAuthManagerError.missingCredentials) {
            try await manager.bearerToken(for: account)
        }
        try GoCredentialVault(credentials: store).storeAPIKey("late-key", for: account.id)

        #expect(try await manager.bearerToken(for: account) == "late-key")
        #expect(store.readCount(forKey: GoCredentialVault.apiKeyKey(for: account.id)) == 2)
    }

    @Test("A credential rotated by another limit-bar process is used instead of resubmitting the consumed refresh token")
    func crossProcessRotationIsNotReplayed() async throws {
        final class MovingClock: @unchecked Sendable {
            private let lock = NSLock()
            private var date: Date
            init(_ date: Date) { self.date = date }
            func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
            func set(_ value: Date) { lock.lock(); defer { lock.unlock() }; date = value }
        }
        let account = makeAccount()
        let prior = makeCredential(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: now.addingTimeInterval(120))
        let rotated = makeCredential(accessToken: "new-access", refreshToken: "new-refresh", expiresAt: now.addingTimeInterval(3600))
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeOAuthCredential(prior, for: account.id)
        let client = GoOAuthClientStub(challenge: makeChallenge(), refreshResults: ["old-refresh": .success(rotated)])
        let clock = MovingClock(now)
        let otherProcess = GoAuthManager(vault: GoCredentialVault(credentials: store), oauthClient: client, now: { clock.read() })
        let thisProcess = GoAuthManager(vault: GoCredentialVault(credentials: store), oauthClient: client, now: { clock.read() })

        #expect(try await thisProcess.bearerToken(for: account) == "old-access")
        clock.set(now.addingTimeInterval(100))
        #expect(try await otherProcess.bearerToken(for: account) == "new-access")

        let token = try await thisProcess.bearerToken(for: account)

        #expect(token == "new-access")
        #expect(await client.refreshCallCount(for: "old-refresh") == 1)
        #expect(await client.refreshCallCount(for: "new-refresh") == 0)
    }

    @Test("A reauthorization during an in-flight refresh wins over the refresh result", .timeLimit(.minutes(1)))
    func reauthorizationDuringRefreshWins() async throws {
        let account = makeAccount()
        let prior = makeCredential(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: now.addingTimeInterval(10))
        let rotated = makeCredential(accessToken: "rotated-access", refreshToken: "rotated-refresh", expiresAt: now.addingTimeInterval(3600))
        let reauthorized = makeCredential(accessToken: "reauth-access", refreshToken: "reauth-refresh", expiresAt: now.addingTimeInterval(3600))
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        try vault.storeOAuthCredential(prior, for: account.id)
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            authorizationResult: .success(reauthorized),
            blockedRefreshTokens: ["old-refresh"]
        )
        let manager = makeManager(store: store, client: client)

        let inFlight = Task { try await manager.bearerToken(for: account) }
        await client.waitForRefreshCall()
        try await manager.authorize(makeChallenge(), for: account.id)
        await client.releaseBlockedRefresh(with: rotated)

        #expect(try await inFlight.value == "reauth-access")
        #expect(try await manager.bearerToken(for: account) == "reauth-access")
        #expect(try vault.oauthCredential(for: account.id) == reauthorized)
    }

    @Test("Concurrent requests for one account share a single refresh", .timeLimit(.minutes(1)))
    func concurrentRequestsCoalesceRefresh() async throws {
        let account = makeAccount()
        let prior = makeCredential(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(10)
        )
        let rotated = makeCredential(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeOAuthCredential(prior, for: account.id)
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            blockedRefreshTokens: ["old-refresh"]
        )
        let clock = GoAuthManagerClock(now)
        let manager = makeManager(store: store, client: client, clock: clock)

        let first = Task { try await manager.bearerToken(for: account) }
        await client.waitForRefreshCall()
        let second = Task { try await manager.bearerToken(for: account) }
        await clock.waitForReads(2)
        await client.releaseBlockedRefresh(with: rotated)

        let firstToken = try await first.value
        let secondToken = try await second.value

        #expect(firstToken == "new-access")
        #expect(secondToken == "new-access")
        #expect(await client.refreshCallCount(for: "old-refresh") == 1)
        #expect(try GoCredentialVault(credentials: store).oauthCredential(for: account.id) == rotated)
    }

    @Test("OAuth accounts keep credentials isolated across account IDs")
    func refreshesCredentialsPerAccount() async throws {
        let firstAccount = makeAccount()
        let secondAccount = makeAccount()
        let firstPrior = makeCredential(
            accessToken: "first-old",
            refreshToken: "first-refresh",
            expiresAt: now.addingTimeInterval(10),
            workspaceID: "first-workspace"
        )
        let secondPrior = makeCredential(
            accessToken: "second-old",
            refreshToken: "second-refresh",
            expiresAt: now.addingTimeInterval(10),
            workspaceID: "second-workspace"
        )
        let firstRotated = makeCredential(
            accessToken: "first-new",
            refreshToken: "first-rotated",
            expiresAt: now.addingTimeInterval(3600),
            workspaceID: "first-workspace"
        )
        let secondRotated = makeCredential(
            accessToken: "second-new",
            refreshToken: "second-rotated",
            expiresAt: now.addingTimeInterval(3600),
            workspaceID: "second-workspace"
        )
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        try vault.storeOAuthCredential(firstPrior, for: firstAccount.id)
        try vault.storeOAuthCredential(secondPrior, for: secondAccount.id)
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            refreshResults: [
                "first-refresh": .success(firstRotated),
                "second-refresh": .success(secondRotated),
            ]
        )
        let manager = makeManager(store: store, client: client)

        let firstToken = try await manager.bearerToken(for: firstAccount)
        let secondToken = try await manager.bearerToken(for: secondAccount)

        #expect(firstToken == "first-new")
        #expect(secondToken == "second-new")
        #expect(try vault.oauthCredential(for: firstAccount.id) == firstRotated)
        #expect(try vault.oauthCredential(for: secondAccount.id) == secondRotated)
        #expect(await client.totalRefreshCalls() == 2)
    }

    @Test("Invalid grant is surfaced without replaying the consumed refresh token")
    func invalidGrantIsNotRetried() async throws {
        let account = makeAccount()
        let prior = makeCredential(
            accessToken: "old-access",
            refreshToken: "single-use-refresh",
            expiresAt: now.addingTimeInterval(10)
        )
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeOAuthCredential(prior, for: account.id)
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            refreshResults: ["single-use-refresh": .failure(.invalidGrant)]
        )
        let manager = makeManager(store: store, client: client)

        await #expect(throws: GoOAuthClientError.invalidGrant) {
            try await manager.bearerToken(for: account)
        }
        await #expect(throws: GoOAuthClientError.invalidGrant) {
            try await manager.bearerToken(for: account)
        }

        #expect(await client.refreshCallCount(for: "single-use-refresh") == 1)
        #expect(try GoCredentialVault(credentials: store).oauthCredential(for: account.id) == prior)
    }

    @Test("Transient refresh failure is surfaced without replaying the refresh token")
    func transientRefreshFailureIsNotRetried() async throws {
        let account = makeAccount()
        let prior = makeCredential(
            accessToken: "old-access",
            refreshToken: "possibly-consumed-refresh",
            expiresAt: now.addingTimeInterval(10)
        )
        let store = GoAuthCredentialStoreSpy()
        try GoCredentialVault(credentials: store).storeOAuthCredential(prior, for: account.id)
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            refreshResults: [
                "possibly-consumed-refresh": .failure(.network(URLError(.timedOut))),
            ]
        )
        let manager = makeManager(store: store, client: client)

        await #expect(throws: GoOAuthClientError.network(URLError(.timedOut))) {
            try await manager.bearerToken(for: account)
        }
        await #expect(throws: GoOAuthClientError.network(URLError(.timedOut))) {
            try await manager.bearerToken(for: account)
        }

        #expect(await client.refreshCallCount(for: "possibly-consumed-refresh") == 1)
        #expect(try GoCredentialVault(credentials: store).oauthCredential(for: account.id) == prior)
    }

    @Test("Refresh persistence failure preserves the old credential and does not repeat the exchange")
    func refreshWriteFailurePreservesStoredCredential() async throws {
        let account = makeAccount()
        let prior = makeCredential(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(10)
        )
        let rotated = makeCredential(
            accessToken: "new-access",
            refreshToken: "new-refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
        let store = GoAuthCredentialStoreSpy()
        let vault = GoCredentialVault(credentials: store)
        try vault.storeOAuthCredential(prior, for: account.id)
        store.failWrites(forKey: GoCredentialVault.oauthKey(for: account.id))
        let client = GoOAuthClientStub(
            challenge: makeChallenge(),
            refreshResults: ["old-refresh": .success(rotated)]
        )
        let manager = makeManager(store: store, client: client)

        await #expect(throws: KeychainStore.KeychainError.accessDenied) {
            try await manager.bearerToken(for: account)
        }
        await #expect(throws: KeychainStore.KeychainError.accessDenied) {
            try await manager.bearerToken(for: account)
        }

        #expect(try vault.oauthCredential(for: account.id) == prior)
        #expect(await client.refreshCallCount(for: "old-refresh") == 1)
    }
}
