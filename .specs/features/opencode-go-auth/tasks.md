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
| Authorization persists tokens before success; Keychain failure leaves no new credential | `GoAuthManager.swift:41-45`; `GoAuthManagerTests.swift:215-235` - stored credential equals expected and polling called once; `:238-260` - exact write error and missing item | Persist tokens before account setup can succeed; do not create an OAuth account without a saved credential (OGA-04/05). | ✅ |
| OAuth stays fresh outside the margin and refreshes at ≤60 seconds; rotation is persisted before Bearer return | `GoAuthManager.swift:60-65,96-109`; `GoAuthManagerTests.swift:278-324` - >60s returns current access token with zero refreshes; exactly 60s returns rotated token and vault equals rotated pair | Refresh before usage when expiry is within 60 seconds; use only persisted rotation (OGA-17; edge cases). | ✅ |
| One account's concurrent requests coalesce, and account credentials remain isolated | `GoAuthManagerTests.swift:327-362` - two tokens equal new access, refresh count is one, persisted pair is rotated; `:364-413` - each account returns and stores its own pair, refresh total is two | At most one refresh exchange per account, with independent credentials (OGA-18). | ✅ |
| Invalid-grant and transient failures never replay a consumed refresh token | `GoAuthManager.swift:81-94,110-114`; `GoAuthManagerTests.swift:415-469` - two calls surface the same error, one refresh call, original pair remains | Do not replay a possibly consumed refresh token; surface recoverable failure (OGA-17; edge case). | ✅ |
| Failed Keychain persistence does not use or overwrite the rotated credential | `GoAuthManager.swift:96-109`; `GoAuthManagerTests.swift:471-503` - both calls throw access denied, old envelope remains, exchange count stays one | Failed rotation write preserves the prior credential and never uses the unpersisted token (edge case). | ✅ |
| Quick gate includes manager coverage and existing tests | `GoAuthManagerTests.swift:215-503`; test log shows all ten manager cases passed and `Test run with 147 tests in 16 suites passed` | At least six manager cases and the full test target pass. | ✅ |

*Check C - Necessary (reverse mapping):*

| `file:line` + assertion expression | Maps to | Keep? |
|---|---|---|
| `GoAuthManagerTests.swift:215-260` - successful and failed authorization persistence | OGA-04/05 / T4 authorization persistence | ✅ |
| `GoAuthManagerTests.swift:278-324` - expiry boundary and token rotation | OGA-17 / refresh-before-use and persistence | ✅ |
| `GoAuthManagerTests.swift:327-413` - same-account coalescing and cross-account isolation | OGA-18 / per-account serialization | ✅ |
| `GoAuthManagerTests.swift:415-469` - invalid grant and transient failure no-replay | OGA-17 / single-use refresh safety | ✅ |
| `GoAuthManagerTests.swift:471-503` - Keychain failure preserves old credential | T4 edge-case acceptance criterion | ✅ |
| `GoAuthManagerTests.swift:263-276` - API key resolves without OAuth refresh | OGA-07 / API-key flow unaffected | ✅ |

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
- [ ] Legacy nil method and explicit API-key accounts send the existing API key without OAuth refresh.
- [ ] OAuth accounts send the manager's current access token as Bearer to `https://opencode.ai/zen/go/v1/usage`.
- [ ] `rolling`/`weekly`/`monthly`, numeric clamp, fractional reset parsing, and missing/invalid windows match the spec.
- [ ] 401/403, 429/Retry-After, other status, transport, and empty/malformed payload retain their specified error mapping.
- [ ] All 13 pre-existing `GoAdapterTests` remain; add at least 2 cases for OAuth selection/refresh integration (15 or more total).
- [ ] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/GoAdapterTests.swift`, 15+ total cases)
**Gate**: Quick

### Phase 3: User-facing flows

#### T6: Add browser-first and API-key account setup

**What**: Add method selection and async browser authorization to Settings, save the account only after credential persistence, and inject one shared manager into Settings and `GoAdapter`.
**Where**: `Sources/LimitBar/UI/SettingsView.swift`
**Supporting files**: `Sources/LimitBar/App/LimitBarApp.swift` and the three `Localizable.strings` tables.
**Depends on**: T1, T2, T3, T5
**Reuses**: Existing Add Account sheet, `SecureField`, Settings presentation, and `AppDelegate` adapter wiring.
**Requirement**: OGA-01, OGA-02, OGA-03, OGA-04, OGA-05, OGA-06, OGA-08, OGA-10, OGA-11

**Tools**:
- MCP: NONE
- Skills: `swiftui-pro`, `swift-language`

**Done when**:
- [ ] Browser login is primary; API key remains selectable; auth method is assigned to the new account.
- [ ] Settings opens only the validated official verification URL, displays the user code/progress, and allows cancellation.
- [ ] Account appears only after credential storage succeeds; cancellation, network failure, malformed response, and Keychain failure leave no account behind.
- [ ] `AppDelegate` injects the same manager instance into Settings and `GoAdapter`.
- [ ] All new Add Account strings exist in `en`, `pt-BR`, and `es`.
- [ ] Build gate passes; manually verify both setup paths and cancellation (no UI-test target exists).

**Tests**: build/manual UAT (SwiftUI has no unit/UI test target)
**Gate**: Build

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
- [ ] OAuth unauthorized state offers browser reconnection for the same account; API-key unauthorized state offers key replacement.
- [ ] Reauthentication preserves account UUID, label, displayed window, and selected method until success.
- [ ] Account removal attempts all local credential names; on cleanup failure the account remains visible and the UI does not claim success.
- [ ] OAuth removal presents a localized warning that the Console session is not revoked remotely.
- [ ] New reauth/removal strings are present in all three locales; last-good data remains visible during repair.
- [ ] Build gate passes; manually verify both reauth paths and removal warning.

**Tests**: build/manual UAT (SwiftUI has no unit/UI test target)
**Gate**: Build

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
- [ ] English, Brazilian Portuguese, and Spanish instructions explain browser login, API-key alternative, and local-only disconnect accurately.
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
