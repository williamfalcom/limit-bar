# Reliability Fixes Specification

## Problem Statement

A full code review on 2026-11-03 found four behaviors users believe work but do not. Threshold notifications never post because the app never asks for notification permission. The wake handler listens on the wrong notification center, so it never runs. Every Codex account reports the default account's limits because `codexHomeOverride` never reaches the `codex app-server` process. A silent Codex or Copilot CLI blocks its read forever, and because polling is serial, it freezes updates for every account. Several UI strings are also missing from the localization tables or use mismatched keys.

## Goals

- [x] An 80% threshold crossing posts a macOS notification after the user grants permission.
- [x] Waking the Mac refreshes accounts whose data is older than the poll interval.
- [x] Each Codex account reports the limits of its own `CODEX_HOME`.
- [x] A Codex or Copilot CLI that never answers releases the polling loop within its timeout.
- [x] Every UI string named in this spec resolves in en, pt-BR, and es.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Persistence corruption backup, Claude `URLError` mapping, Codex HTTP fallback removal | Review items 5–7; separate follow-up |
| OAuth refresh retry policy, interval-change sleep interruption, Retry-After/backoff on manual refresh | Review items 8–10; behavior decisions pending |
| Settings window `isReleasedWhenClosed` | Review item 11; needs manual reproduction first |
| Live-updating popover countdowns and other UX items | Review UX section; separate follow-up |
| Parallel polling of accounts | Bounded timeouts remove the freeze; parallelism changes rate-limit behavior |
| Persisting error kinds instead of localized messages | Requires a `SnapshotState` schema change |
| Version bump / release | Release is a separate, explicitly authorized step |
| Signing with an Apple Team ID | Only a `teamid:` partition survives rebuilds; no Apple identity is available yet (user decision 2026-11-03) |
| Moving tokens out of the Keychain | Would revert AD-008; user chose the in-memory cache |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| When to ask for notification permission | Once at launch, only while status is `.notDetermined`, requesting `.alert` and `.sound` | Standard macOS pattern; no prompt when the user already decided | y |
| Provisional authorization | `.provisional` counts as authorized for posting | Provisional delivery is a granted state on macOS | y |
| Codex timeout | Keep the existing 6 s `CodexAppServerClient.responseTimeout` | Value already chosen; it is now enforced | y |
| Copilot timeout | 15 s | Node-based CLI cold start is slower than the Rust Codex CLI | y |
| Timeout outcome | Codex with partial output keeps parsing what arrived; with no output it throws. Copilot throws `ProviderError.network(URLError(.timedOut))` unless both frames arrived | Codex parser already tolerates partial output; Copilot needs two complete frames | y |
| CLI process after completion or timeout | Terminated by the runner | Avoids orphan CLI processes | y |
| Writing to a CLI that already exited | Write fails with an error instead of raising `SIGPIPE` | `SIGPIPE` would terminate limit-bar | y |
| Codex override path | `~` is expanded; the override is set as `CODEX_HOME` in the child environment; without override the inherited environment is unchanged | Matches `authFileURL` override semantics | y |
| Codex key mismatch | Code key stays `Codex authentication failed or auth.json is missing. Log in again with the Codex CLI, then refresh.`; pt-BR/es keys are renamed to it | English table and code already agree | y |
| Network error message | `Network error: %d` becomes a localized format key | Smallest change; still shows the code | y |

| Cache scope (REL-06) | Process memory inside `GoAuthManager`; never persisted; cleared on delete | Only limit-bar writes these items, always through the manager | y |
| Keychain read before refresh (REL-06 AC6) | Re-read once per due refresh, bypassing the cache | The refresh token is single-use; another limit-bar process (a second copy or the test host) may have rotated it. One read per token lifetime keeps prompts rare | y |
| Test host polling (REL-06 AC7) | `startServices` skips both the permission request and `engine.start()` under `XCTestConfigurationFilePath` | The test host was polling real accounts and reading the real Keychain on every test run | y |
| Failed refresh vs. rotation elsewhere (REL-06 AC6/AC8) | A recorded failed refresh wins: no Keychain re-read, no resubmission; recovery comes from reconnecting or restarting | Re-reading would bring back a dialog on every poll while stuck; retry policy is out of scope | y |
| Simultaneous refresh in two processes (REL-06) | Accepted residual: both may submit the same refresh token at the same instant | Pre-existing; preventing it needs cross-process locking | y |
| Cached failures (REL-06) | Not cached; a denied or missing read retries on the next poll | A denial must stay recoverable without a restart | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Threshold notifications reach the user ⭐ MVP

**User Story**: As a user, I want the 80% notification to actually appear so that I learn about a near-cap limit without opening the popover.

**Why P1**: The feature is documented but cannot fire today.

**Acceptance Criteria**:

1. WHEN the app finishes launching AND the notification authorization status is `.notDetermined` THEN the system SHALL request authorization with options `.alert` and `.sound` exactly once
2. IF the notification authorization status is `.authorized`, `.denied`, or `.provisional` at launch THEN the system SHALL NOT request authorization
3. WHEN a window crosses 80% AND the authorization status is `.provisional` THEN the system SHALL post one notification

**Independent Test**: Delete the app's notification setting, launch, accept the prompt, and push a window past 80% — one notification appears.

---

### P1: Wake refresh runs after sleep ⭐ MVP

**User Story**: As a user, I want stale data refreshed when my Mac wakes so that the icon is current after sleep.

**Why P1**: The wake handler exists but is never triggered.

**Acceptance Criteria**:

1. WHEN `NSWorkspace.didWakeNotification` is posted on the engine's wake notification center THEN the engine SHALL refresh every account whose `fetchedAt` is older than its poll interval
2. The engine's default wake notification center SHALL be `NSWorkspace.shared.notificationCenter`
3. WHEN the engine stops THEN later wake notifications SHALL NOT trigger refreshes

**Independent Test**: Sleep the Mac longer than the poll interval, wake it, and see the popover's "updated" time reset within seconds.

---

### P1: Codex accounts honor their CODEX_HOME ⭐ MVP

**User Story**: As a user with several Codex logins, I want each account to show its own limits so that multi-account Codex works as advertised.

**Why P1**: Multi-account Codex silently shows wrong data today.

**Acceptance Criteria**:

1. WHEN a Codex account has `codexHomeOverride` set THEN the adapter SHALL launch the app-server with `CODEX_HOME` equal to the tilde-expanded override
2. WHEN a Codex account has no `codexHomeOverride` THEN the adapter SHALL launch the app-server with the inherited environment unchanged
3. The child environment SHALL preserve every other inherited variable when `CODEX_HOME` is set

**Independent Test**: Configure two Codex accounts with different `CODEX_HOME` overrides for different logins and see different percentages.

---

### P1: A silent CLI cannot freeze polling ⭐ MVP

**User Story**: As a user, I want one stuck CLI to fail on its own so that my other accounts keep updating.

**Why P1**: A single hung CLI stops all accounts indefinitely.

**Acceptance Criteria**:

1. IF a CLI process writes no output THEN the runner SHALL return within its timeout plus 2 s and SHALL terminate the process
2. IF a CLI process keeps its stdout open through a child process THEN the runner SHALL still return within its timeout plus 2 s
3. WHEN the runner's completion condition is met THEN the runner SHALL return the collected output without waiting for the timeout and SHALL terminate the process
4. IF the CLI process exits before its input is written THEN the runner SHALL throw an error and the app SHALL keep running
5. IF the Copilot CLI does not deliver both response frames within 15 s THEN the Copilot client SHALL throw `ProviderError.network(URLError(.timedOut))`
6. WHEN the Copilot CLI's output contains two complete `Content-Length` frames THEN the Copilot client SHALL return the body of the second frame
7. IF the Codex CLI writes no output within 6 s THEN the Codex client SHALL throw

**Independent Test**: Replace `copilot` on `PATH` with a script that sleeps forever; Claude accounts keep refreshing and the Copilot tab shows a network error after about 15 s.

---

### P2: Complete localization of reviewed strings

**User Story**: As a pt-BR or es user, I want every message in my language so that the app does not mix languages.

**Why P2**: Cosmetic but visible; the Codex instruction is currently English-only in two locales.

**Acceptance Criteria**:

1. The en, pt-BR, and es `Localizable.strings` tables SHALL contain the same set of keys
2. The tables SHALL contain the keys `Quit limit-bar`, `Settings…`, `Remove`, `Seconds`, `Network error: %d`, `Your GitHub Copilot authentication was rejected. Log in with the Copilot CLI and refresh.`, and `Codex authentication failed or auth.json is missing. Log in again with the Codex CLI, then refresh.`
3. WHEN a fetch fails with `ProviderError.network` THEN the snapshot error message SHALL be the localized `Network error: %d` format with the `URLError` code

**Independent Test**: Run the app in pt-BR, trigger a Codex sign-in error, and read the instruction in Portuguese.

---

### P1: OpenCode credentials do not prompt on every poll ⭐ MVP

**User Story**: As a user of an ad-hoc signed build, I want the Keychain approval to be asked at most once per app run so that polling does not open password dialogs every 5 minutes.

**Why P1**: Found in v0.3.2 install testing on 2026-11-03. Keychain ACLs and partition IDs of ad-hoc signed apps are bound to the build's cdhash, so each new build prompts on every Keychain read until "Always Allow" is granted with the login password.

**Acceptance Criteria**:

1. WHEN bearer tokens are requested repeatedly for the same OpenCode account THEN the auth manager SHALL read that account's Keychain credential once, plus once before each OAuth refresh, while the app runs
2. WHEN an OAuth refresh rotates the credential THEN later bearer requests SHALL return the rotated access token without reading the Keychain
3. WHEN an API key is stored or a device authorization completes, including while a refresh is in flight, THEN the next bearer request for that account SHALL return the new credential without reading the Keychain
4. WHEN an account's credentials are deleted THEN the next bearer request SHALL read the Keychain again
5. IF a Keychain read fails for an API-key or OAuth account THEN the auth manager SHALL NOT cache the failure, and the next request SHALL read the Keychain again
6. WHEN an OAuth refresh is due AND no failed refresh is recorded for the account AND the Keychain holds a credential that another limit-bar process already rotated THEN the auth manager SHALL use the stored credential and SHALL NOT submit the consumed refresh token
7. WHILE limit-bar runs as the unit-test host the app SHALL NOT start polling
8. IF an OAuth refresh failed for an account THEN later requests SHALL rethrow that failure without reading the Keychain or submitting the refresh token again, until the account's credentials are stored, authorized, or deleted
9. WHEN the first request of a run finds an OAuth credential already due for refresh THEN the auth manager SHALL read the Keychain only once before refreshing

**Independent Test**: Install a new build, approve the Keychain dialog once with "Allow" (not "Always Allow"), and see no further dialogs during later polls until the app restarts.

---

## Edge Cases

- IF the Codex override is `~/alt` THEN the child `CODEX_HOME` SHALL be `<home>/alt`
- IF the CLI writes more than 4 MiB without a completion marker THEN the Codex client SHALL stop reading and return what it collected
- IF the authorization request throws THEN the system SHALL continue launching without notifications

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| REL-01 | P1: Threshold notifications reach the user | Execute | Verified |
| REL-02 | P1: Wake refresh runs after sleep | Execute | Verified |
| REL-03 | P1: Codex accounts honor their CODEX_HOME | Execute | Verified |
| REL-04 | P1: A silent CLI cannot freeze polling | Execute | Verified |
| REL-05 | P2: Complete localization of reviewed strings | Execute | Verified |
| REL-06 | P1: OpenCode credentials do not prompt on every poll | Execute | Verified |

**Coverage:** 6 total, 6 mapped to tasks, 0 unmapped

---

## Success Criteria

- [x] All five requirements verified by Swift Testing cases; full gate passes with no removed tests.
- [ ] Manual check: one notification appears after granting permission and crossing 80%.
