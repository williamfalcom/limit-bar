# OpenCode Go Dual Authentication Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: activate it by name and follow its Execute flow, test-coverage rules, post-gate review, and atomic commit protocol. Do not batch tasks into one commit.

---

**Design**: `.specs/features/opencode-go-auth/design.md`  
**Status**: In Progress

---

## Test Coverage Matrix

> Generated from repository guidelines and test samples. Guidelines: `AGENTS.md` (Swift Testing and xcodebuild gate), `Tests/LimitBarTests/` (Swift Testing, URLProtocol stubs, and injected dependencies), `project.yml` (unit-test target). Samples reviewed: `GoAdapterTests.swift`, `KeychainStoreTests.swift`, `ModelsTests.swift`, `AccountStoreTests.swift`, `PersistenceTests.swift`, `PollingEngineTests.swift`, and `TestSupport.swift`. There is no UI-test target or configured linter/formatter. SwiftUI view changes use build + manual UAT.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
|---|---|---|---|---|
| Account/auth-method model | unit | Round-trip OAuth and API key; old JSON without method decodes as API key; raw provider value unchanged | `Tests/LimitBarTests/ModelsTests.swift` | Quick |
| Keychain credential vault | unit | API-key canonical/legacy lookup; OAuth envelope round-trip; all key deletions; write/delete failures; no secret in `AppState` | `Tests/LimitBarTests/GoCredentialVaultTests.swift` | Quick |
| OAuth device client | unit | Request shape, trusted URL, pending/slow-down, approval, cancel/expiry, invalid payload/status | `Tests/LimitBarTests/GoOAuthClientTests.swift` | Quick |
| OAuth refresh manager | unit | 60-second expiry margin, token rotation persistence, concurrent refresh coalescing, revoked token, storage failure | `Tests/LimitBarTests/GoAuthManagerTests.swift` | Quick |
| Go provider adapter | unit | API key and OAuth Bearer selection; quota parsing; reset, clamp, empty payload; 401/403/429/other status/network mapping | `Tests/LimitBarTests/GoAdapterTests.swift` | Quick |
| SwiftUI setup/repair/removal and AppDelegate wiring | build + manual UAT | Browser-first/API-key paths, progress/cancel/error, same-method repair, local-only removal warning, all locales | `Sources/LimitBar/UI/SettingsView.swift`, `PanelView.swift`, `LimitBarApp.swift` | Build + manual |
| Documentation/localization resources | validation | English/pt-BR/es keys synchronized; README and spec match delivered setup; no secrets in diffs | `Sources/LimitBar/Resources/*.lproj/Localizable.strings`, READMEs | Full |

## Gate Check Commands

> Read from `AGENTS.md` and `project.yml`. `project.yml` includes all files beneath `Sources/LimitBar` and `Tests/LimitBarTests`; no project generation change is expected.

| Gate Level | When to Use | Command |
|---|---|---|
| Quick | After domain, Keychain, OAuth client/manager, and adapter tasks | `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Build | After SwiftUI/App wiring tasks; no UI-test target exists | `xcodebuild build -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Full | Final feature gate | `xcodebuild build -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS' && xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |

---

## Execution Plan

Phases run sequentially. Tasks in each phase run in listed order.

### Phase 1: Account and credential foundation

```text
T1 → T2 → T3
T1 ─────→ T3
```

### Phase 2: OAuth refresh and quota integration

```text
T4 → T5
```

T4 also depends on T3; T5 also depends on T1, T2, and T4.

### Phase 3: User-facing flows

```text
T6 → T7
```

T6 also depends on T1, T2, T3, and T5; T7 also depends on T5.

### Phase 4: Documentation and closure

```text
T7 → T8
```

---

## Task Breakdown

### Phase 1: Account and credential foundation

#### T1: Add backward-compatible OpenCode auth-method metadata

**What**: Add a Codable `GoAuthMethod` discriminator to `Account`; missing values in old persisted JSON resolve to API-key authentication, and `ProviderKind.openCodeGo` remains unchanged.
**Where**: `Sources/LimitBar/Core/Models.swift`
**Depends on**: None
**Reuses**: Existing synthesized Codable models and model tests.
**Requirement**: OGA-09

**Tools**:
- MCP: NONE
- Skills: `swift-language`, `swift-testing-pro`

**Done when**:
- [x] Old account JSON with no auth-method field decodes with API-key behavior.
- [x] API-key and OAuth method values round-trip through JSON without changing provider raw values.
- [x] Two focused Swift Testing cases pass; no existing model test is removed.
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/ModelsTests.swift`, at least 2 focused assertions/cases)
**Gate**: Quick

**T1 Post-Gate Review**:

*Check A - Sufficient (coverage mapping):*

| Done-when criterion / spec AC | `file:line` + assertion expression | Spec-defined outcome | Covered? |
|---|---|---|---|
| Legacy account without method retains API-key behavior | `Tests/LimitBarTests/ModelsTests.swift:79-81` - `#expect(decoded.goAuthMethod == nil)` and `#expect(decoded.effectiveGoAuthMethod == .apiKey)` | Missing field is treated as API-key auth (OGA-09). | ✅ |
| API-key and OAuth method values round-trip | `Tests/LimitBarTests/ModelsTests.swift:98-99` - `#expect(decoded == account)` and `#expect(decoded.effectiveGoAuthMethod == method)` | Both methods survive account JSON encoding/decoding (OGA-09). | ✅ |
| OpenCode provider raw value remains stable | `Tests/LimitBarTests/ModelsTests.swift:19` - `#expect(ProviderKind.openCodeGo.rawValue == "openCodeGo")` | Persisted provider identifier remains unchanged. | ✅ |
| Focused tests and full quick gate pass | `ModelsTests.swift:65-100`; test output confirms both names; full run has 121 Swift Testing passes and `TEST SUCCEEDED` | At least two focused tests pass without removing existing coverage. | ✅ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion expression | Maps to | Keep? |
|---|---|---|
| `ModelsTests.swift:79-81` - legacy provider/method/default assertions | OGA-09, old persisted account compatibility | ✅ |
| `ModelsTests.swift:98-99` - account and effective-method equality for each enum case | OGA-09, method round-trip | ✅ |
| `ModelsTests.swift:19` - OpenCode raw value assertion | T1 Done-when: provider raw value unchanged | ✅ |

- [x] Check A: all task criteria have test-output or assertion evidence; asserted outcomes match OGA-09.
- [x] Check B: assertions inspect decoded account state, not only calls or execution.
- [x] Check C: each assertion maps to T1 or OGA-09; no speculative test was added.
- [x] Check D: follows `AGENTS.md` Swift Testing conventions and the existing `ModelsTests.swift` style.

**Verdict**: T1 coverage is sufficient and necessary; no spec-precision gap or deviation.

#### T2: Add the OpenCode Keychain credential vault

**What**: Add account-scoped API-key/OAuth-envelope storage and cleanup, preserving canonical API key reads plus the bare-UUID legacy fallback.
**Where**: `Sources/LimitBar/Core/GoCredentialVault.swift` (new)
**Depends on**: T1
**Reuses**: `CredentialStore`, Keychain service `limit-bar`, and current Go key names.
**Requirement**: OGA-08, OGA-10, OGA-11, OGA-23, OGA-24

**Tools**:
- MCP: NONE
- Skills: `swift-language`, `swift-testing-pro`

**Done when**:
- [x] API keys remain under `go.api-key.<uuid>` and can fall back to `<uuid>` for reads.
- [x] OAuth token envelope is versioned and stored under `go.oauth.<uuid>`; secrets never enter `AppState` serialization.
- [x] Removal attempts canonical API, legacy API, and OAuth items; missing items are idempotent and Keychain failures are surfaced.
- [x] Eight unit cases cover canonical/legacy reads, OAuth round-trip, deletion, missing items, AppState secrecy, and injected storage failure.
- [x] Quick gate passes with all pre-existing Keychain tests intact.

**Tests**: unit (`Tests/LimitBarTests/GoCredentialVaultTests.swift`, at least 5 cases)
**Gate**: Quick

**T2 Post-Gate Review**:

*Check A - Sufficient (coverage mapping):*

| Done-when criterion / spec AC | `file:line` + assertion expression | Spec-defined outcome | Covered? |
|---|---|---|---|
| API key uses the canonical key and legacy fallback | `GoCredentialVaultTests.swift:86-88` - stored value, loaded key, and `readKeys == [key]`; `:99-100` - legacy value and canonical-then-UUID lookup | Store at `go.api-key.<uuid>` and fall back to bare UUID (OGA-10). | ✅ |
| OAuth tokens use a versioned Keychain envelope and stay out of AppState | `GoCredentialVaultTests.swift:121-122` - `loaded == oauth`, `envelope["version"] as? Int == 1`; `:152-154` - auth method present, access/refresh strings absent | Versioned OAuth secret is stored in Keychain and not serialized in app state (OGA-08). | ✅ |
| Removal attempts canonical, legacy, and OAuth items; missing entries are idempotent; errors surface | `GoCredentialVaultTests.swift:167-168`, `:178-182`, `:196-200` - exact deletion keys, empty store, thrown failure, all attempts, surviving failed item | Delete all local credential names, tolerate absent items, and report cleanup failure (OGA-23/24). | ✅ |
| Credential-store write failure is surfaced without overwriting the existing value | `GoCredentialVaultTests.swift:216-219` - exact Keychain error and prior envelope equality | Failed Keychain writes do not replace usable stored data (OGA-11 foundation). | ✅ |
| Required tests and Quick gate pass | `GoCredentialVaultTests.swift:77-219`; log contains eight named passes and `TEST SUCCEEDED` (129 Swift Testing passes total) | At least five focused tests pass; existing Keychain tests remain. | ✅ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion expression | Maps to | Keep? |
|---|---|---|
| `GoCredentialVaultTests.swift:86-88`, `:99-100` - canonical and legacy key state | OGA-10 / T2 key compatibility | ✅ |
| `GoCredentialVaultTests.swift:121-122`, `:152-154` - envelope version and state secrecy | OGA-08 / T2 secure storage | ✅ |
| `GoCredentialVaultTests.swift:167-168`, `:178-182`, `:196-200` - deletion coverage | OGA-23/24 / T2 local cleanup | ✅ |
| `GoCredentialVaultTests.swift:216-219` - write failure and preserved envelope | OGA-11 / T2 credential write failure | ✅ |

- [x] Check A: all T2 criteria map to concrete assertion/output evidence with matching outcomes.
- [x] Check B: assertions inspect stored/loaded values and failure state, not only spy call counts.
- [x] Check C: all tests map to T2 requirements; no speculative tests were added.
- [x] Check D: follows `AGENTS.md` Swift Testing conventions and existing Keychain/model test patterns.

**Verdict**: T2 coverage is sufficient and necessary; no spec-precision gap or deviation.

#### T3: Implement the Console device-authorization client

**What**: Implement device-code request, verification URL validation, polling, cancellation, expiry, and `slow_down` handling using the verified JSON contract.
**Where**: `Sources/LimitBar/Providers/GoOAuthClient.swift` (new)
**Depends on**: T1, T2
**Reuses**: Foundation `URLSession`, `StubURLProtocol`, and live-verified client ID/endpoints.
**Requirement**: OGA-01, OGA-02, OGA-03, OGA-06

**Tools**:
- MCP: NONE
- Skills: `swift-language`, `swift-testing-pro`

**Done when**:
- [x] Device-code request sends JSON with `client_id=limit-bar` and `supports_org_scope=true` to the official Console endpoint.
- [x] Only HTTPS `opencode.ai` verification URLs are emitted to the UI.
- [x] Polling honors `interval`, `authorization_pending`, `slow_down` (+5 s), expiry, and Task cancellation.
- [x] Nine tests cover request fields, trusted/untrusted URI, approval, pending/slow-down, expiry/cancel, malformed/non-200 responses, and refresh rotation (no live network).
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/GoOAuthClientTests.swift`, at least 7 cases)
**Gate**: Quick

**T3 Post-Gate Review**:

*Check A - Sufficient (coverage mapping):*

| Done-when criterion / spec AC / edge case | `file:line` + assertion expression | Spec-defined outcome | Covered? |
|---|---|---|---|
| Device-code JSON request and challenge fields | `GoOAuthClientTests.swift:183-195` - asserted device/user code, URL, expiry, interval, endpoint, method, content type, `client_id`, and `supports_org_scope` | Request uses the official device endpoint and obtains all challenge values (OGA-01). | ✅ |
| Only secure URLs on exact `opencode.ai` are accepted | `GoOAuthClientTests.swift:203-214` - four invalid URI shapes each throw `.untrustedVerificationURL`; `:185` asserts the accepted official URI | Refuse non-HTTPS, different host, non-default port, or user-info URL (OGA-02). | ✅ |
| Polling honors interval and pending/slow-down behavior | `GoOAuthClientTests.swift:235-249` - returned credential fields, `recordedIntervals == [1, 1, 6]`, token endpoint body assertions | Pending continues; slow_down increases the next interval by five seconds (OGA-03). | ✅ |
| Expiry and cancellation stop polling | `GoOAuthClientTests.swift:264-271` - exact expiration error, sleep duration, no request; `:280-284` - cancellation error and no request | Expired/cancelled flow does not poll or create credentials (OGA-03/06). | ✅ |
| Malformed and non-200 device-code responses are rejected | `GoOAuthClientTests.swift:295-310` - exact `.invalidResponse` and `.httpStatus(503)` | Invalid Console responses fail rather than creating a challenge. | ✅ |
| Refresh exchanges and maps the rotated token pair; unauthorized refresh requires reconnection | `GoOAuthClientTests.swift:329-340` - access/refresh/expiry/workspace values and JSON fields; `:354-360` - 401/403 map to `.invalidGrant` | Rotation and unauthorized response are represented without exposing token values in errors. | ✅ |
| Quick gate includes new tests | log confirms nine `GoOAuthClient` cases and `Test run with 137 tests ... passed` | Required OAuth client tests run with no live network; all prior tests remain. | ✅ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion expression | Maps to | Keep? |
|---|---|---|
| `GoOAuthClientTests.swift:183-195` | OGA-01 device request and challenge | ✅ |
| `GoOAuthClientTests.swift:185`, `:203-214` | OGA-02 trusted verification URL | ✅ |
| `GoOAuthClientTests.swift:235-249`, `:264-271` | OGA-03 poll timing, pending, slow_down, and expiry | ✅ |
| `GoOAuthClientTests.swift:280-284` | OGA-06 local cancellation | ✅ |
| `GoOAuthClientTests.swift:295-310` | T3 malformed/non-200 response handling | ✅ |
| `GoOAuthClientTests.swift:329-340`, `:354-360` | T3 token refresh protocol and OGA-17 invalid-grant pathway foundation | ✅ |

- [x] Check A: task criteria and applicable spec cases have exact test evidence and matching values.
- [x] Check B: tests assert returned challenge/token data and emitted request fields; no call-count-only coverage.
- [x] Check C: every test maps to T3 or the listed requirement; no speculative test was added.
- [x] Check D: follows `AGENTS.md` and Swift Testing conventions with injected HTTP, clock, and sleep dependencies.

**Verdict**: T3 coverage is sufficient and necessary; no spec-precision gap or deviation.

### Phase 2: OAuth refresh and quota integration

#### T4: Add the per-account OAuth credential manager

**What**: Orchestrate successful authorization and resolve Bearer tokens, refreshing at the 60-second expiry margin while coalescing concurrent refreshes per account.
**Where**: `Sources/LimitBar/Core/GoAuthManager.swift` (new)
**Depends on**: T3
**Reuses**: `GoOAuthClient`, `GoCredentialVault`, and actor isolation for serialized state.
**Requirement**: OGA-04, OGA-05, OGA-07, OGA-08, OGA-17, OGA-18

**Tools**:
- MCP: NONE
- Skills: `swift-language`, `swift-testing-pro`

**Done when**:
- [x] Authorization stores tokens before returning success; Keychain failure produces no usable account credential.
- [x] Refresh occurs when expiry is within 60 seconds and persists the rotated pair before returning the new access token.
- [x] Concurrent requests for one account cause exactly one refresh exchange; separate accounts do not share credentials.
- [x] Invalid grant/transient failures never replay the consumed token; write failure leaves the prior Keychain envelope intact.
- [x] Ten unit cases cover API-key selection, expiry, authorization persistence, rotation, concurrency, account isolation, invalid grant, transient failure, and persistence failure.
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/GoAuthManagerTests.swift`, at least 6 cases)
**Gate**: Quick

**T4 Post-Gate Review**:

*Check A - Sufficient (coverage mapping):*

| Done-when criterion / spec AC / edge case | `file:line` + assertion expression | Spec-defined outcome | Covered? |
|---|---|---|---|
| Authorization persists tokens before success; Keychain failure leaves no new credential | `GoAuthManager.swift:41-45`; `GoAuthManagerTests.swift:251-272` - stored credential equals expected and polling called once; `:274-297` - exact write error and missing item | Persist tokens before account setup can succeed; do not create an OAuth account without a saved credential (OGA-04/05). | ✅ |
| OAuth stays fresh outside the margin and refreshes at ≤60 seconds; rotation is persisted before Bearer return | `GoAuthManager.swift:58-71,102-115`; `GoAuthManagerTests.swift:343-390` - >60s returns current access token with zero refreshes; exactly 60s returns rotated token and vault equals rotated pair | Refresh before usage when expiry is within 60 seconds; use only persisted rotation (OGA-17; edge cases). | ✅ |
| One account's concurrent requests coalesce, and account credentials remain isolated | `GoAuthManagerTests.swift:392-427` - two tokens equal new access, refresh count is one, persisted pair is rotated; `:429-478` - each account returns and stores its own pair, refresh total is two | At most one refresh exchange per account, with independent credentials (OGA-18). | ✅ |
| Invalid-grant and transient failures never replay a consumed refresh token | `GoAuthManager.swift:87-100,116-119`; `GoAuthManagerTests.swift:480-534` - repeated calls surface the same error, one refresh call, original pair remains | Do not replay a possibly consumed refresh token; surface recoverable failure (OGA-17; edge case). | ✅ |
| Failed Keychain persistence does not use or overwrite the rotated credential | `GoAuthManager.swift:102-115`; `GoAuthManagerTests.swift:536-568` - both calls throw access denied, old envelope remains, exchange count stays one | Failed rotation write preserves the prior credential and never uses the unpersisted token (edge case). | ✅ |
| Quick gate includes manager coverage and existing tests | The ten T4 manager tests (current source: `GoAuthManagerTests.swift:251-297,328-568`) passed; T4 log reports `Test run with 147 tests in 16 suites passed` | At least six manager cases and the full test target pass. | ✅ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion expression | Maps to | Keep? |
|---|---|---|
| `GoAuthManagerTests.swift:251-297` - successful and failed authorization persistence | OGA-04/05 / T4 authorization persistence | ✅ |
| `GoAuthManagerTests.swift:343-390` - expiry boundary and token rotation | OGA-17 / refresh-before-use and persistence | ✅ |
| `GoAuthManagerTests.swift:392-478` - same-account coalescing and cross-account isolation | OGA-18 / per-account serialization | ✅ |
| `GoAuthManagerTests.swift:480-534` - invalid grant and transient failure no-replay | OGA-17 / single-use refresh safety | ✅ |
| `GoAuthManagerTests.swift:536-568` - Keychain failure preserves old credential | T4 edge-case acceptance criterion | ✅ |
| `GoAuthManagerTests.swift:328-341` - API key resolves without OAuth refresh | OGA-07 / API-key flow unaffected | ✅ |

- [x] Check A: every T4 criterion maps to assertion or gate evidence with outcomes matching the spec.
- [x] Check B: tests inspect credentials, errors, refresh counts, and persisted rotation, not only method calls.
- [x] Check C: every assertion maps to T4 or a named requirement/edge case; no speculative coverage was added.
- [x] Check D: follows `AGENTS.md` Swift Testing conventions with injected storage/client/clock dependencies.

**Verdict**: T4 coverage is sufficient and necessary; no spec-precision gap or deviation.

#### T5: Integrate both credential methods into GoAdapter

**What**: Resolve API-key or OAuth Bearer credentials per account and preserve the verified official quota parsing/error mapping.
**Where**: `Sources/LimitBar/Providers/GoAdapter.swift`
**Depends on**: T1, T2, T4
**Reuses**: Existing quota endpoint, parser, and `GoAdapterTests` URLProtocol router.
**Requirement**: OGA-12, OGA-13, OGA-14, OGA-15, OGA-16, OGA-17, OGA-18, OGA-19

**Tools**:
- MCP: NONE
- Skills: `swift-language`, `swift-testing-pro`

**Done when**:
- [x] Legacy nil method and explicit API-key accounts send the existing API key without OAuth refresh.
- [x] OAuth accounts send the manager's current access token as Bearer to `https://opencode.ai/zen/go/v1/usage`.
- [x] `rolling`/`weekly`/`monthly`, numeric clamp, fractional reset parsing, and missing/invalid windows match the spec.
- [x] 401/403, 429/Retry-After, other status, transport, and empty/malformed payload retain their specified error mapping; refresh `invalid_grant` maps to unauthorized before usage fetch.
- [x] All 13 pre-existing `GoAdapterTests` remain; add three cases for explicit API-key selection, OAuth refresh/Bearer integration, and invalid-grant mapping (16 total).
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/GoAdapterTests.swift`, 15+ total cases)
**Gate**: Quick

**T5 Post-Gate Review**:

*Check A - Sufficient (coverage mapping):*

| Done-when criterion / spec AC / edge case | `file:line` + assertion expression | Spec-defined outcome | Covered? |
|---|---|---|---|
| Legacy nil and explicit API-key methods use the stored API key, without OAuth refresh | `GoAdapterTests.swift:106-118` - URL and Bearer assertion for legacy nil; `:276-291` - bare-UUID fallback; `:293-321` - explicit key Bearer plus refresh count zero | Existing and explicit API-key accounts retain the compatible key path (OGA-09/10/12). | ✅ |
| OAuth method refreshes and sends the newly persisted access token to the official quota URL | `GoAdapter.swift:35-54`; `GoAdapterTests.swift:327-359` - endpoint, rotated Bearer, parsed windows, stored rotated pair, and one refresh | OAuth usage uses the manager's valid token and persists rotation before request (OGA-13/17/18). | ✅ |
| Refresh `invalid_grant` becomes unauthorized and does not issue a quota request | `GoAdapter.swift:35-49`; `GoAdapterTests.swift:362-386` - exact unauthorized error, no recorded usage request, one refresh | Refresh authorization failure feeds the account's unauthorized/reconnect state (OGA-17/19). | ✅ |
| Quota windows, numeric clamp, fractional reset dates, and omitted invalid windows retain existing behavior | `GoAdapterTests.swift:120-166` - period kinds, percentages, nil dollar values, fractional resets, and invalid reset handling | Preserve official `rolling`/`weekly`/`monthly` mapping and parser behavior (OGA-13/14/15). | ✅ |
| Endpoint status, retry, transport, and payload errors retain their mappings | `GoAdapterTests.swift:168-274` - 401/403, 429 with/without Retry-After, other statuses, transport failure, malformed/empty payload | Unauthorized, rate-limited, network, and parse failures remain distinct (OGA-16). | ✅ |
| Existing tests remain and the expanded Quick gate passes | `GoAdapterTests.swift` has 16 `@Test` cases; log confirms all three new cases and `Test run with 150 tests in 16 suites passed` | Preserve 13 prior cases and run at least 15 adapter tests. | ✅ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion expression | Maps to | Keep? |
|---|---|---|
| `GoAdapterTests.swift:106-118`, `:276-321` | OGA-09/10/12 and T5 API-key compatibility | ✅ |
| `GoAdapterTests.swift:327-359` | OGA-13/17/18 and T5 OAuth token selection/refresh | ✅ |
| `GoAdapterTests.swift:362-386` | OGA-17/19 and unauthorized reauth pathway | ✅ |
| `GoAdapterTests.swift:120-166` | OGA-13/14/15 and quota parsing | ✅ |
| `GoAdapterTests.swift:168-274` | OGA-16 and error mapping | ✅ |

- [x] Check A: each T5 criterion and applicable spec behavior has exact assertions or full-gate evidence.
- [x] Check B: tests assert Bearer selection, persisted rotated credentials, returned windows, and precise provider errors.
- [x] Check C: every assertion maps to T5 or named requirements; no existing test was removed.
- [x] Check D: follows `AGENTS.md` Swift Testing and URLProtocol patterns.

**Verdict**: T5 coverage is sufficient and necessary; no spec-precision gap or deviation.

### Phase 3: User-facing flows

#### T6: Add browser-first and API-key account setup

**What**: Add method selection and async browser authorization to Settings, save the account only after credential persistence, and inject one shared manager into Settings and `GoAdapter`.
**Where**: `Sources/LimitBar/UI/SettingsView.swift`
**Supporting files**: `Sources/LimitBar/App/LimitBarApp.swift`, `Sources/LimitBar/Providers/GoOAuthClient.swift`, corresponding OAuth client tests, and the three `Localizable.strings` tables.
**Depends on**: T1, T2, T3, T5
**Reuses**: Existing Add Account sheet, `SecureField`, Settings presentation, and `AppDelegate` adapter wiring.
**Requirement**: OGA-01, OGA-02, OGA-03, OGA-04, OGA-05, OGA-06, OGA-08, OGA-10, OGA-11

**Tools**:
- MCP: NONE
- Skills: `swiftui-pro`, `swift-language`

**Done when**:
- [x] Browser login is primary; API key remains selectable; auth method is assigned to the new account.
- [x] The device response's confirmed `verification_uri_complete` field decodes, including origin-relative paths resolved against `https://opencode.ai`; Settings opens only the validated official URL, displays the user code/progress, and allows cancellation.
- [x] Account appears only after credential storage succeeds; cancellation, network failure, malformed response, and Keychain failure leave no account behind.
- [x] `AppDelegate` injects the same manager instance into Settings and `GoAdapter`.
- [x] All new Add Account strings exist in `en`, `pt-BR`, and `es`.
- [x] Sign-in choices use a vertical radio group and the Add Account sheet has sufficient minimum width for localized labels.
- [x] Build gate passes.
- [x] Manual UAT on v0.2.3: OAuth browser setup succeeds, API-key setup succeeds, cancellation adds no account, and the Add Account interface shows all text without clipping (user-confirmed; no UI-test target exists).

**Tests**: build/manual UAT (SwiftUI has no unit/UI test target)
**Gate**: Build

**T6 Post-Gate Review**:

*Check A - Sufficient (coverage mapping):*

| Done-when criterion / spec AC | `file:line` + assertion/source evidence | Spec-defined outcome | Covered? |
|---|---|---|---|
| Browser is default; API key remains selectable; method is assigned to the new account | `SettingsView.swift:228-265` - `consoleOAuth` initial selection and vertical radio choices; `:326-338` - selected method assigned to OpenCode account | Browser-first setup with explicit API-key alternative (OGA-01/10). | ✅ |
| The verified `verification_uri_complete` response field decodes, including its documented origin-relative path, and the UI opens only the validated official URL | `GoOAuthClient.swift:25-38,92-107,253-267`; `GoOAuthClientTests.swift:130-138,173-195` asserts `/console/device?...` resolves to `https://opencode.ai/console/device?...`; `:198-216` rejects untrusted hosts | Resolve relative verification paths only against the fixed HTTPS origin and retain exact-host validation (OGA-01/02). | ✅ |
| Settings shows code/progress and permits cancellation | `SettingsView.swift:269-283,427-435`; cancellation test `GoOAuthClientTests.swift:274-285` verifies polling stops before a token request | User sees the code and can stop local polling (OGA-03/06). | ✅ |
| Account appears only after credentials persist; cancellation and failures do not add an account | `SettingsView.swift:354-375,378-408`; `GoAuthManager.swift:41-46`; `GoAuthManagerTests.swift:274-326` - injected storage failure and cancellation leave no credential | Credential persistence precedes account creation; failed/canceled attempts add no account (OGA-04/05/06/11). | ✅ |
| The app injects the same manager into Settings and `GoAdapter` | `LimitBarApp.swift:27-46` creates and injects one instance into `GoAdapter`; `:161-162` injects that instance into Settings | Setup and quota polling share the app-owned manager (T6 wiring). | ✅ |
| All new Add Account strings exist in all three locales | Localization key check found all 13 new keys in `en`, `pt-BR`, and `es` | Newly added user-facing strings are localized (OGA-26). | ✅ |
| Long localized method labels are not clipped in the Add Account sheet | `SettingsView.swift:257-262` selects `.radioGroup`; `:301-302` sets a 500 pt minimum/ideal width. User confirmed all text is visible on v0.2.3. | Browser/API key labels and surrounding fields remain fully visible. | ✅ |
| Build and full test gate pass | `xcodebuild build` reports `BUILD SUCCEEDED`; test output reports `Test run with 151 tests in 16 suites passed` | SwiftUI compiles and existing core/auth tests pass. | ✅ |
| Manual visual and lifecycle verification | User confirmed on v0.2.3 that OAuth and API-key setup work, cancellation adds no account, and the complete Add Account layout is visible | All prescribed T6 manual UAT outcomes pass. | ✅ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion/source evidence | Maps to | Keep? |
|---|---|---|
| `SettingsView.swift:228-265,326-338` | OGA-01/10 browser-first auth selection and account metadata | ✅ |
| `SettingsView.swift:257-262,301-302` | T6 layout adjustment for complete localized labels | ✅; visual UAT confirmed by user on v0.2.3 |
| `GoOAuthClient.swift:25-38,92-107,253-267`; `GoOAuthClientTests.swift:130-138,173-216`; `SettingsView.swift:269-283,389,427-435` | OGA-01/02/03/06 complete URL parsing, relative resolution, trusted opening, code/progress, cancellation | ✅ |
| `SettingsView.swift:354-375,378-408`; `GoAuthManagerTests.swift:274-326` | OGA-04/05/06/11 credential-before-account and failure/cancel safety | ✅ |
| `LimitBarApp.swift:27-46,161-162` | T6 shared manager injection | ✅ |
| Localization check for 13 new keys | OGA-26 localized Add Account text | ✅ |

- [x] Check A: code, automated evidence, and user-confirmed UAT cover the implementation criteria.
- [x] Check B: account creation follows successful credential persistence; displayed errors are localized and do not expose token values.
- [x] Check C: all changes map to T6; no unrelated account/settings behavior was changed.
- [x] Check D: follows SwiftUI data-flow and Swift Testing conventions; no UI-test target exists.

**Verdict**: T6 implementation, build, all 151 tests, and manual UAT pass; task complete.

#### T7: Add method-specific reauthentication and safe local removal

**What**: Offer same-method reconnect/key replacement and make account deletion surface Keychain cleanup errors and the local-only OAuth disconnect warning.
**Where**: `Sources/LimitBar/UI/PanelView.swift`
**Supporting files**: `Sources/LimitBar/UI/SettingsView.swift` and the three localized strings tables.
**Depends on**: T5, T6
**Reuses**: Existing unauthorized banner, cache-preserving snapshots, and destructive remove action.
**Requirement**: OGA-21, OGA-22, OGA-23, OGA-24, OGA-25, OGA-26

**Tools**:
- MCP: NONE
- Skills: `swiftui-pro`, `swift-language`

**Done when**:
- [x] OAuth unauthorized state offers browser reconnection for the same account; API-key unauthorized state offers key replacement.
- [x] Reauthentication preserves account UUID, label, displayed window, and selected method until success.
- [x] Account removal attempts all local credential names; on cleanup failure the account remains visible and the UI does not claim success.
- [x] OAuth removal presents a localized warning that the Console session is not revoked remotely.
- [x] New reauth/removal strings are present in all three locales; last-good data remains visible during repair.
- [x] Build and full test gates pass (151 tests).
- [ ] Manual UAT: verify OAuth reconnect, API-key replacement, cached quota visibility during repair, and the OAuth removal warning in the running app.

**Tests**: build/manual UAT (SwiftUI has no unit/UI test target)
**Gate**: Build

**T7 Post-Gate Review**:

*Check A - Sufficient (coverage mapping):*

| Done-when criterion / spec AC | `file:line` + assertion/source evidence | Spec-defined outcome | Covered? |
|---|---|---|---|
| Unauthorized OpenCode accounts offer method-matched repair while retaining the cached quota | `PanelView.swift:100-113,258-302` displays the previous snapshot and selects the browser/key action from the same account's auth method; `GoAccountReauthenticationSheet.swift:3-159` writes using the existing account UUID and never updates account metadata | OAuth reconnect and API-key replacement preserve account ID, label, displayed window, and selected method (OGA-21/22/25). | ✅ |
| Local removal attempts all OpenCode credential names and does not remove an account after partial Keychain failure | `SettingsView.swift:141-162`; `GoAuthManager.swift:53-56`; `GoCredentialVault.swift:68-89`; `GoCredentialVaultTests.swift:157-201` verifies all names are attempted and failures surfaced | The account remains visible after incomplete local cleanup (OGA-23/24). | ✅ |
| OAuth removal warns that only local credentials are deleted | `SettingsView.swift:199-220`; warning key exists in `en`, `pt-BR`, and `es` tables | No implication of remote Console logout/revocation (OGA-24). | ✅ |
| Reauthentication and cleanup messages are localized; last-good quota remains visible | All 14 new T7 strings are present in all locales; `PanelView.swift:100-108` renders cached windows for unauthorized state | Repair is actionable and prior data remains available (OGA-25/26). | ✅ |
| Build and test gate pass | `scripts/build.sh test` passed; xcresult summary reports 151 passed, 0 failed; signed v0.2.3 dev app builds | Code compiles and existing tests remain green. | ✅ |
| Manual UAT of reauthentication/removal | Pending user verification on the v0.2.3 development build | Verify actual browser reconnect, API-key replacement, cached quota display, and local-only warning. | ⏳ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion/source evidence | Maps to | Keep? |
|---|---|---|
| `PanelView.swift:100-113,258-302`; `GoAccountReauthenticationSheet.swift:3-159` | OGA-21/22/25 method-specific account repair and cache visibility | ✅ |
| `SettingsView.swift:141-162`; `GoAuthManager.swift:53-56`; `GoCredentialVault.swift:68-89`; `GoCredentialVaultTests.swift:157-201` | OGA-23/24 cleanup failure safety | ✅ |
| `SettingsView.swift:199-220`; localized strings tables | OGA-24 local-only OAuth disconnect warning; OGA-26 localization | ✅ |

- [x] Check A: implementation, existing automated credential cleanup coverage, and build/test evidence cover code criteria.
- [x] Check B: credential writes/deletes use Keychain and errors do not reveal credential values.
- [x] Check C: all changes map to OGA-21–26 and preserve the account's metadata/cache.
- [x] Check D: uses SwiftUI state/presentation conventions; no UI-test target exists.

**Verdict**: T7 implementation and automated build/test gates pass; task remains open until manual UAT.

### Phase 4: Documentation and closure

#### T8: Synchronize docs, traceability, and final validation

**What**: Document both OpenCode auth methods, mark requirements/tasks verified, preserve the AD-008 handoff, and run final build/test plus manual account lifecycle checks.
**Where**: `README.md`
**Supporting files**: `README.pt-BR.md`, `README.es.md`, `.specs/features/opencode-go-auth/`, and `.specs/STATE.md`.
**Depends on**: T7
**Reuses**: Existing three-language README provider/setup sections and spec-driven validation records.
**Requirement**: OGA-07, OGA-08, OGA-09, OGA-24, OGA-26

**Tools**:
- MCP: NONE
- Skills: `tlc-spec-driven`, `swift-testing-pro`

**Done when**:
- [x] English, Brazilian Portuguese, and Spanish instructions explain browser login, API-key alternative, and local-only disconnect accurately.
- [ ] Spec traceability and task status match test/build evidence; `.specs/STATE.md` Handoff points to the next unfinished or completed state without altering unrelated decisions.
- [ ] Full build and test gates pass; new Swift Testing cases are visible in test output.
- [ ] Manual UAT confirms V2 CLI login remains active, OAuth and API-key accounts both fetch the expected quota, and removal/reconnect behave as specified.
- [ ] No tokens, device codes, authorization headers, user identifiers, or live-account quota data are present in the repository diff.

**Tests**: full suite + localization/security audit + manual UAT
**Gate**: Full

## Pre-Approval Cross-Checks

### Diagram-definition cross-check

| Task | Depends on | Diagram edges | Result |
|---|---|---|---|
| T1 | None | None | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T1, T2 | T1 → T3; T2 → T3 | ✅ Match |
| T4 | T3 | Cross-phase dependency | ✅ Phase order enforces it |
| T5 | T1, T2, T4 | T4 → T5; T1/T2 are prior phases | ✅ Match |
| T6 | T1, T2, T3, T5 | T5 → T6; T1/T2/T3 are prior phases | ✅ Match |
| T7 | T5, T6 | T6 → T7; T5 is a prior phase | ✅ Match |
| T8 | T7 | T7 → T8 | ✅ Match |

### Test co-location validation

| Task | Code layer | Matrix requirement | Task tests | Result |
|---|---|---|---|---|
| T1 | Account/auth-method model | Unit | Legacy decode and method round-trip in same task | ✅ |
| T2 | Credential vault | Unit | Reads, envelope, deletion, failure in same task | ✅ |
| T3 | OAuth client | Unit | Request, URL, polling, cancel, expiry, errors in same task | ✅ |
| T4 | OAuth manager | Unit | Refresh margin, rotation, coalescing, invalid grant, failure in same task | ✅ |
| T5 | GoAdapter | Unit | Both credentials, quota mapping, all status/error paths in same task | ✅ |
| T6 | SwiftUI/App wiring | Build + manual | No UI test target; build and specified manual paths | ✅ |
| T7 | SwiftUI lifecycle | Build + manual | No UI test target; build and specified manual paths | ✅ |
| T8 | Docs/resources | Full validation | Full test/build, localization/security audit, UAT | ✅ |
