# OpenCode Go Dual Authentication Specification

## Problem Statement

limit-bar currently requires an OpenCode API key, while the user is on OpenCode CLI V2 and cannot create the key needed by the current setup. OpenCode's Console supports a browser device-authorization flow, and live verification confirms that its OAuth access token and rotated refresh token can read the Go quota endpoint. The app must add this path without breaking API-key accounts or sharing the CLI's session.

## Goals

- [ ] Add browser authorization for each OpenCode Go account.
- [ ] Preserve API-key authentication and existing persisted accounts.
- [ ] Store OAuth/API secrets only in the limit-bar Keychain and refresh OAuth tokens safely.
- [ ] Continue displaying official Go rolling, weekly, and monthly quota windows.
- [ ] Give users actionable reauthentication and local-disconnect behavior.

## Out of Scope

| Feature | Reason |
|---|---|
| Read, import, or modify OpenCode CLI V2's SQLite credential database | The app uses an independent OAuth session and must not interfere with the CLI. |
| Revoke the Console device session remotely when removing an account | No official device-session revocation endpoint was found; removal is local and must say so. |
| Scrape the Console or estimate quotas locally | The official Go usage endpoint returned current quota data for the OAuth session. |
| Replace Go quota with workspace/member budget data | Budgets measure spend and are not equivalent to Go rolling/weekly/monthly quotas. |
| Remove API-key support or force old accounts to reconnect | Existing accounts remain compatible. |
| Add OAuth for other providers | This exception is limited to OpenCode Go. |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
|---|---|---|---|
| Authentication choice for new OpenCode accounts | Browser login is primary; API key remains an explicit alternative | User approved the dual-auth plan and defaults. | y |
| OAuth session ownership | Create a separate `limit-bar` Console device session for each account | Reusing the CLI refresh token could revoke the CLI session. | y |
| Device-flow client ID and request format | Use `client_id=limit-bar`, JSON body, and `supports_org_scope=true` | Live device-code request succeeded using this contract on 2026-10-19. | y |
| Go usage endpoint authentication | Send the device-flow access token as Bearer; no `x-org-id` is required for the verified endpoint | Live `GET /zen/go/v1/usage` returned HTTP 200 without the workspace header. | y |
| OAuth token lifetime | Treat `expires_in` as authoritative; do not hard-code the observed roughly 30-day lifetime | The lifetime is provided by the server and may change. | y |
| Refresh token semantics | Treat refresh tokens as single-use; serialize refresh and persist rotation before use | Official docs and a successful live refresh confirm rotation. | y |
| Existing account with no auth-method field | Interpret it as API-key auth | Preserves decoding and behavior for persisted accounts. | y |
| Remote logout when removing OAuth account | Delete local credentials and show that the Console session is not remotely revoked | User approved the local-only behavior; no official revocation route was found. | y |
| Device-flow cancellation | Stop local polling and persist no account/credential; the server-issued code expires on its own | No device-code cancellation endpoint is documented. | y |
| Unrecognized or empty quota payload | Return a parse error, preserve last-good data, never display it as 0% | Prevents a schema/auth failure from looking like unused quota. | y |

**Open questions:** none - implementation uncertainties are resolved above or bounded by these defaults.

---

## User Stories

### P1: Connect OpenCode Go through the browser ⭐ MVP

**User Story**: As an OpenCode Go subscriber using CLI V2, I want to connect limit-bar through the Console browser flow so that I can monitor quota without creating or sharing a CLI API key.

**Why P1**: This fixes the reported blocker while keeping the authentication session isolated from OpenCode CLI V2.

**Acceptance Criteria**:

1. WHEN the user selects browser authentication THEN limit-bar SHALL POST JSON with `client_id=limit-bar` and `supports_org_scope=true` to `https://opencode.ai/console/auth/device/code` and receive a device code, user code, verification URI, expiry, and polling interval. <!-- event-driven -->
2. IF the verification URI is not HTTPS on the exact `opencode.ai` host THEN limit-bar SHALL refuse to open it and SHALL not submit authorization. <!-- unwanted-behavior -->
3. WHILE device authorization is pending THEN limit-bar SHALL poll no faster than the server-provided interval and SHALL add five seconds after a `slow_down` response. <!-- state-driven -->
4. WHEN authorization completes THEN limit-bar SHALL store the returned access token, refresh token, and expiry in the Keychain before adding the account to persisted app state. <!-- event-driven -->
5. IF Keychain storage fails during account creation THEN limit-bar SHALL not add the account and SHALL show a localized error. <!-- unwanted-behavior -->
6. IF the user cancels device authorization THEN limit-bar SHALL stop local polling and SHALL persist neither the new account nor its OAuth credential. <!-- unwanted-behavior -->
7. The system SHALL NOT read, import, modify, or reuse credentials from the OpenCode CLI's SQLite database, Keychain entries, or files. <!-- ubiquitous -->
8. The system SHALL store access tokens and refresh tokens only in the limit-bar Keychain, never in `AppState`, logs, or user-facing error text. <!-- ubiquitous -->

**Independent Test**: Complete device authorization for a Go workspace, add the account, and confirm it appears only after its credential is saved; the CLI's existing login remains active.

---

### P1: Preserve API-key compatibility

**User Story**: As an existing limit-bar user or a user who has a Console API key, I want API-key auth to remain available so that existing accounts keep working.

**Why P1**: Adding OAuth must not break deployed accounts or remove a working alternate credential path.

**Acceptance Criteria**:

1. IF a persisted OpenCode account has no authentication-method field THEN limit-bar SHALL treat it as API-key authentication. <!-- unwanted-behavior -->
2. WHEN the user chooses API-key authentication THEN limit-bar SHALL store and read the key using the existing `go.api-key.<uuid>` Keychain name with the existing bare-UUID read fallback. <!-- event-driven -->
3. IF API-key storage fails THEN limit-bar SHALL not add the account and SHALL show a localized error. <!-- unwanted-behavior -->
4. WHEN an API-key account requests usage THEN limit-bar SHALL send its stored key as the Bearer credential without attempting OAuth refresh. <!-- event-driven -->

**Independent Test**: Load a pre-feature `AppState` and legacy API-key account, poll it with a stubbed endpoint, and verify the exact stored key is sent as Bearer.

---

### P1: Read Go quota with either credential

**User Story**: As an OpenCode Go subscriber, I want the same live quota windows regardless of authentication method so that the provider tab remains useful.

**Why P1**: Authentication is only useful if it powers the existing quota display.

**Acceptance Criteria**:

1. WHEN an OAuth account requests usage THEN limit-bar SHALL send `GET https://opencode.ai/zen/go/v1/usage` with its valid access token as Bearer and SHALL refresh an expired token before the request. <!-- event-driven -->
2. WHEN a valid response contains `usage.rolling`, `usage.weekly`, and `usage.monthly` numeric percentages THEN the adapter SHALL map them to `.fiveHour`, `.weekly`, and `.monthly` windows respectively. <!-- event-driven -->
3. WHEN a quota percentage is numeric and outside `0...100` THEN the adapter SHALL clamp the returned percentage to that range. <!-- event-driven -->
4. WHEN a quota entry has a parseable `resetsAt` THEN the adapter SHALL map it to `resetsAt`; IF it is missing or invalid THEN it SHALL return `nil` for that window's reset. <!-- complex -->
5. IF the endpoint returns HTTP 401 or 403 THEN the adapter SHALL report unauthorized; IF it returns 429 THEN it SHALL report rate-limited and preserve a valid `Retry-After`; IF it returns another non-200 status or a transport error THEN it SHALL report a network error. <!-- complex -->
6. IF a 200 response has no parseable quota windows THEN the adapter SHALL report a parse error and SHALL NOT report zero usage. <!-- unwanted-behavior -->
7. IF OAuth refresh returns `invalid_grant` or an unauthorized response THEN limit-bar SHALL preserve the last-good quota snapshot and offer reconnection for that same account. <!-- unwanted-behavior -->
8. WHILE multiple requests for the same account need a refresh THEN limit-bar SHALL perform at most one refresh-token exchange and SHALL use the newly persisted token for all requests. <!-- state-driven -->

**Independent Test**: Stub the usage endpoint for API-key and OAuth accounts and assert identical window mapping, exact Bearer selection, refresh behavior, and status mapping.

---

### P1: Reauthenticate and disconnect without ambiguity

**User Story**: As a user managing OpenCode accounts, I want to repair or remove a connection without losing account identity or confusing local removal with server logout.

**Why P1**: Expired/revoked credentials and account removal are expected lifecycle states for long-lived authentication.

**Acceptance Criteria**:

1. WHEN an OAuth account becomes unauthorized THEN limit-bar SHALL offer a new browser authorization for that same account without changing its UUID, label, or displayed window. <!-- event-driven -->
2. WHEN an API-key account becomes unauthorized THEN limit-bar SHALL allow the user to replace its key without silently switching its auth method or workspace. <!-- event-driven -->
3. WHEN an account is removed THEN limit-bar SHALL delete its canonical API-key item, legacy bare-UUID item, and OAuth item from the local Keychain. <!-- event-driven -->
4. IF local Keychain deletion fails THEN limit-bar SHALL keep the account visible and report that local credential cleanup did not complete. <!-- unwanted-behavior -->
5. WHEN the user removes an OAuth account THEN limit-bar SHALL state that this removes the credential from this Mac but does not revoke the Console session remotely. <!-- event-driven -->
6. The system SHALL localize all new user-facing authentication text in English, Brazilian Portuguese, and Spanish. <!-- ubiquitous -->

**Independent Test**: Force an OAuth 401 and an API-key 401; verify each offers the matching repair path, then remove an OAuth account and verify the local-only warning and Keychain cleanup.

---

## Edge Cases

- IF the verification endpoint returns malformed JSON or a non-200 status THEN the UI SHALL show an actionable localized error and create no account.
- IF `expires_in` is zero or negative THEN the OAuth response SHALL be rejected as invalid and no account SHALL be created.
- IF device authorization expires before approval THEN polling SHALL stop and the UI SHALL allow a fresh attempt.
- IF device-code polling returns `authorization_pending` THEN polling SHALL continue; IF it returns `slow_down` THEN the next delay SHALL increase by five seconds.
- IF the access token expires within 60 seconds THEN the manager SHALL refresh before making the usage request.
- IF writing rotated OAuth credentials fails THEN the old Keychain credential SHALL remain intact and the new token SHALL NOT be used.
- IF a refresh request fails transiently THEN the manager SHALL not replay the same consumed refresh token; it SHALL surface a recoverable auth/network failure.
- IF a quota entry is missing or nonnumeric THEN that window SHALL be omitted; if every window is omitted, the adapter SHALL report a parse error.
- IF an account removal deletes one local credential item but fails on another item THEN the account SHALL remain visible and the UI SHALL report partial cleanup without claiming remote revocation.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
|---|---|---|---|
| OGA-01 | P1: Browser connection | Design | In Design |
| OGA-02 | P1: Browser connection | Design | In Design |
| OGA-03 | P1: Browser connection | Design | In Design |
| OGA-04 | P1: Browser connection | Design | In Design |
| OGA-05 | P1: Browser connection | Design | In Design |
| OGA-06 | P1: Browser connection | Design | In Design |
| OGA-07 | P1: Browser connection | Design | In Design |
| OGA-08 | P1: Browser connection | Design | In Design |
| OGA-09 | P1: API-key compatibility | Design | In Design |
| OGA-10 | P1: API-key compatibility | Design | In Design |
| OGA-11 | P1: API-key compatibility | Design | In Design |
| OGA-12 | P1: API-key compatibility | Design | In Design |
| OGA-13 | P1: Quota reading | Design | In Design |
| OGA-14 | P1: Quota reading | Design | In Design |
| OGA-15 | P1: Quota reading | Design | In Design |
| OGA-16 | P1: Quota reading | Design | In Design |
| OGA-17 | P1: Quota reading | Design | In Design |
| OGA-18 | P1: Quota reading | Design | In Design |
| OGA-19 | P1: Reauthentication | Design | In Design |
| OGA-20 | P1: Reauthentication | Design | In Design |
| OGA-21 | P1: Reauthentication | Design | In Design |
| OGA-22 | P1: Reauthentication | Design | In Design |
| OGA-23 | P1: Reauthentication | Design | In Design |
| OGA-24 | P1: Reauthentication | Design | In Design |
| OGA-25 | P1: Reauthentication | Design | In Design |
| OGA-26 | P1: Reauthentication | Design | In Design |

**ID format:** `OGA-[NUMBER]`  
**Status values:** Pending → In Design → In Tasks → Implementing → Verified  
**Coverage:** 26 total, 26 mapped to design/tasks, 0 unmapped.

## Success Criteria

- [ ] A V2 user can authorize limit-bar through the official browser flow and see current Go quota.
- [ ] An existing API-key account continues to work without migration or a new login.
- [ ] Refresh rotation does not invalidate the CLI V2 session or allow concurrent reuse.
- [ ] No OAuth/API secrets appear in app state, logs, or repository files.
- [ ] Full build and Swift Testing gates pass; manual account lifecycle checks pass.
