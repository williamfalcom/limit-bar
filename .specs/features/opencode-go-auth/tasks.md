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
- [ ] Old account JSON with no auth-method field decodes with API-key behavior.
- [ ] API-key and OAuth method values round-trip through JSON without changing provider raw values.
- [ ] Two focused Swift Testing cases pass; no existing model test is removed.
- [ ] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/ModelsTests.swift`, at least 2 focused assertions/cases)
**Gate**: Quick

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
- [ ] API keys remain under `go.api-key.<uuid>` and can fall back to `<uuid>` for reads.
- [ ] OAuth token envelope is versioned and stored under `go.oauth.<uuid>`; secrets never enter `AppState` serialization.
- [ ] Removal attempts canonical API, legacy API, and OAuth items; missing items are idempotent and Keychain failures are surfaced.
- [ ] At least 5 unit cases cover canonical/legacy reads, OAuth round-trip, deletion, missing items, and injected storage failure.
- [ ] Quick gate passes; existing `KeychainStoreTests` remain intact.

**Tests**: unit (`Tests/LimitBarTests/GoCredentialVaultTests.swift`, at least 5 cases)
**Gate**: Quick

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
- [ ] Device-code request sends JSON with `client_id=limit-bar` and `supports_org_scope=true` to the official Console endpoint.
- [ ] Only HTTPS `opencode.ai` verification URLs are emitted to the UI.
- [ ] Polling honors `interval`, `authorization_pending`, `slow_down` (+5 s), expiry, and Task cancellation.
- [ ] Tests cover request fields, trusted/untrusted URI, approval, pending/slow-down, expiry/cancel, and malformed/non-200 responses (at least 7 cases; no live network).
- [ ] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/GoOAuthClientTests.swift`, at least 7 cases)
**Gate**: Quick

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
- [ ] Authorization stores tokens before returning success; Keychain failure produces no usable account credential.
- [ ] Refresh occurs when expiry is within 60 seconds and persists the rotated pair before returning the new access token.
- [ ] Concurrent requests for one account cause exactly one refresh exchange; separate accounts do not share credentials.
- [ ] Invalid grant/401 never replays the consumed token; write failure leaves the prior Keychain envelope intact.
- [ ] At least 6 unit cases cover expiry, refresh, rotation, concurrency, invalid grant, and persistence failure.
- [ ] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/GoAuthManagerTests.swift`, at least 6 cases)
**Gate**: Quick

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
