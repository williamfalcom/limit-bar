# Reliability Fixes Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: follow its Execute flow, test-coverage rules, post-gate review, and atomic commit protocol. Do not batch tasks into one commit.

---

**Spec**: `.specs/features/reliability-fixes/spec.md`
**Status**: Complete (Verifier PASS; REL-06 iteration 3)

## Test Coverage Matrix

> Guidelines: `AGENTS.md` (Swift Testing, xcodebuild gate), `Tests/LimitBarTests/` (injected dependencies, fakes guarded by `NSLock`). No UI-test target, no linter.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
|---|---|---|---|---|
| Notification authorization | unit | Request only when `.notDetermined`; provisional posts | `Tests/LimitBarTests/NotificationServiceTests.swift` | Quick |
| Polling engine wake wiring | unit | Posted wake triggers stale refresh; default center; stop unregisters | `Tests/LimitBarTests/PollingEngineTests.swift` | Quick |
| CLI process runner | unit (real `/bin/sh` processes) | Timeout, held-open stdout, early completion, termination, dead-process write | `Tests/LimitBarTests/CLIProcessRunnerTests.swift` | Quick |
| Codex / Copilot clients | unit | Env construction, override propagation, frame parsing, timeout mapping | `Tests/LimitBarTests/CodexAdapterTests.swift`, `CopilotAdapterTests.swift` | Quick |
| Localization tables | unit (bundle resources) | Equal key sets; required keys present; network message format | `Tests/LimitBarTests/LocalizationTests.swift` | Quick |
| App wiring | build | `AppDelegate` calls the authorization request | `Sources/LimitBar/App/LimitBarApp.swift` | Build |

## Gate Check Commands

| Gate Level | When to Use | Command |
|---|---|---|
| Quick | After each unit-tested task | `xcodegen generate && xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS,arch=arm64'` |
| Build | App wiring only | `xcodebuild build -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS,arch=arm64'` |
| Full | Final feature gate | `scripts/build.sh test` |

---

## Execution Plan

### Phase 1: Event wiring

```text
T1
T2
```

### Phase 2: CLI robustness

```text
T3 → T4
T3 → T5
```

### Phase 3: Localization

```text
T6
```

---

## Task Breakdown

### Phase 1: Event wiring

#### T1: Request notification permission at launch

**What**: Add `requestAuthorization` to `NotificationCentering`, add `NotificationService.requestAuthorizationIfNeeded()`, treat `.provisional` as authorized, and call it from `AppDelegate` at launch.
**Where**: `Sources/LimitBar/Core/NotificationService.swift`, `Sources/LimitBar/App/LimitBarApp.swift`
**Depends on**: None
**Requirement**: REL-01

**Done when**:
- [x] `.notDetermined` triggers exactly one request with `.alert` and `.sound`.
- [x] `.authorized`, `.denied`, `.provisional` trigger no request.
- [x] A crossing under `.provisional` posts one notification.
- [x] A throwing request does not crash or propagate.
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/NotificationServiceTests.swift`)
**Gate**: Quick

**T1 Post-Gate Review**:

| Criterion | `file:line` + assertion | Spec outcome | Covered? |
|---|---|---|---|
| REL-01 AC1 | `NotificationServiceTests.swift:146` - `#expect(center.authorizationRequests == [[.alert, .sound]])` | One request, `.alert` + `.sound` | ✅ |
| REL-01 AC2 | `NotificationServiceTests.swift:157` - `#expect(center.authorizationRequests.isEmpty)` (parameterized over `.authorized`, `.denied`, `.provisional`) | No request | ✅ |
| REL-01 AC3 | `NotificationServiceTests.swift:178` - `#expect(center.requests.count == 1)` | One notification under `.provisional` | ✅ |
| Edge: request throws | `NotificationServiceTests.swift:168-169` - one attempt, no notification posted | Launch continues, no notifications | ✅ |

Every assertion maps to REL-01. `AppDelegate` wiring is build-verified; it skips the request while hosting tests (`XCTestConfigurationFilePath`) so test runs never prompt. Gate: 155 passed, 0 failed (was 151).

**Verdict**: Covered and necessary; no spec deviation.

#### T2: Observe wake on the workspace notification center

**What**: Inject the wake `NotificationCenter` into `PollingEngine`, defaulting to `NSWorkspace.shared.notificationCenter`.
**Where**: `Sources/LimitBar/Core/PollingEngine.swift`
**Depends on**: None
**Requirement**: REL-02

**Done when**:
- [x] Posting `NSWorkspace.didWakeNotification` on the injected center refreshes stale accounts only.
- [x] Default center is `NSWorkspace.shared.notificationCenter`.
- [x] After `stop()`, a posted wake triggers no refresh.
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/PollingEngineTests.swift`)
**Gate**: Quick

**T2 Post-Gate Review**:

| Criterion | `file:line` + assertion | Spec outcome | Covered? |
|---|---|---|---|
| REL-02 AC1 | `PollingEngineTests.swift:429-430` - `#expect(log.count(stale.id) == 2)`, `#expect(log.count(fresh.id) == 1)` | Only the stale account refreshes after a posted wake | ✅ |
| REL-02 AC2 | `PollingEngineTests.swift:438-439` - `engine.wakeCenter === NSWorkspace.shared.notificationCenter`, `!== NotificationCenter.default` | Workspace center by default | ✅ |
| REL-02 AC3 | `PollingEngineTests.swift:461` - `#expect(log.count(stale.id) == 1)` | No refresh after `stop()` | ✅ |

The test helper gained `wakeCenter` and `blockingSleep` parameters; existing tests keep their defaults. Gate: 158 passed, 0 failed.

**Verdict**: Covered and necessary; no spec deviation.

### Phase 2: CLI robustness

#### T3: Add a timeout-bounded CLI process runner

**What**: Add `CLIProcessRunner.run` that launches a `Process`, writes stdin without `SIGPIPE`, collects stdout via a readability handler, returns on completion or timeout, and terminates the process.
**Where**: `Sources/LimitBar/Providers/CLIProcessRunner.swift` (new)
**Depends on**: None
**Requirement**: REL-04

**Done when**:
- [x] Silent process returns within timeout + 2 s and is terminated.
- [x] Process whose child holds stdout open still returns within timeout + 2 s.
- [x] Completion condition returns before the timeout with the collected output and terminates the process.
- [x] Writing to an exited process throws; the test process survives.
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/CLIProcessRunnerTests.swift`)
**Gate**: Quick

**T3 Post-Gate Review**:

| Criterion | `file:line` + assertion | Spec outcome | Covered? |
|---|---|---|---|
| REL-04 AC1 | `CLIProcessRunnerTests.swift:39-42` - `outcome == .timedOut`, `elapsed < 0.5 + 2`, `await isTerminated(childPID)` | Returns within timeout + 2 s; process terminated | ✅ |
| REL-04 AC2 | `CLIProcessRunnerTests.swift:57-59` - `outcome == .timedOut`, `elapsed < 0.5 + 2`, output `"started\n"` | Held-open stdout still bounded | ✅ |
| REL-04 AC3 | `CLIProcessRunnerTests.swift:74-79` - `outcome == .completed`, `elapsed < 2` with a 10 s timeout, last line `"ping"`, `await isTerminated(childPID)` | Early return with output; process terminated | ✅ |
| REL-04 AC4 | `CLIProcessRunnerTests.swift:83` - `#expect(throws: (any Error).self)` writing 1 MB to `/usr/bin/true` | Throws; app keeps running | ✅ |

AC4 is backed by a manual probe on 2026-11-03: the same write without `F_SETNOSIGPIPE` killed the process with exit 141 (`SIGPIPE`). The runner also sends stderr to `/dev/null`, since an unread stderr pipe can stall the child. Gate: 162 passed, 0 failed.

**Verdict**: Covered and necessary; no spec deviation.

#### T4: Route Codex through the runner with per-account CODEX_HOME

**What**: Pass the account's expanded `codexHomeOverride` to the app-server client, build the child environment, and replace the blocking read loop with `CLIProcessRunner` (6 s).
**Where**: `Sources/LimitBar/Providers/CodexAdapter.swift`
**Depends on**: T3
**Requirement**: REL-03, REL-04

**Done when**:
- [x] Adapter passes the tilde-expanded override to the app-server closure; `nil` when absent.
- [x] Environment builder sets `CODEX_HOME` and preserves other variables; returns the inherited environment for `nil`.
- [x] Silent Codex output throws.
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/CodexAdapterTests.swift`)
**Gate**: Quick

**T4 Post-Gate Review**:

| Criterion | `file:line` + assertion | Spec outcome | Covered? |
|---|---|---|---|
| REL-03 AC1 (adapter) | `CodexAdapterTests.swift:346` - `recorder.recorded == [home + "/alt-codex"]` | Tilde-expanded override reaches the client | ✅ |
| REL-03 AC1 (process) | `CodexAdapterTests.swift:382` - child prints `$CODEX_HOME` == `/tmp/alt-codex-home` | Launched process sees the override | ✅ |
| REL-03 AC2 | `CodexAdapterTests.swift:355` - `recorded == [nil]`; `:369` - `environment(codexHome: nil, …) == nil` | Inherited environment unchanged | ✅ |
| REL-03 AC3 | `CodexAdapterTests.swift:364` - full dictionary equality with `PATH`/`HOME` kept | Other variables preserved | ✅ |
| REL-04 AC7 | `CodexAdapterTests.swift:393-396` - throws, elapsed `< 0.3 + 2` | Silent Codex throws | ✅ |
| Edge: > 4 MiB | `CodexAdapterTests.swift:409-410` - output `> maxOutputBytes`, elapsed `< 5` with a 20 s timeout | Stops reading, returns collected output | ✅ |

The completion check now searches bytes for `"id":2` instead of decoding the whole buffer on every chunk; the 5 MB case dropped from 10.4 s to 0.19 s. Existing adapter tests keep their zero-argument closures through the helper wrapper. Gate: 169 passed, 0 failed.

**Verdict**: Covered and necessary; no spec deviation.

#### T5: Route Copilot through the runner with a 15 s timeout

**What**: Replace the blocking frame reader with `CLIProcessRunner`, a pure frame parser, and a timeout that maps to `ProviderError.network(URLError(.timedOut))`.
**Where**: `Sources/LimitBar/Providers/CopilotAdapter.swift`
**Depends on**: T3
**Requirement**: REL-04

**Done when**:
- [x] Frame parser returns the second frame body from two complete frames, including split chunks.
- [x] Incomplete output after timeout throws `ProviderError.network(URLError(.timedOut))`.
- [x] Client timeout constant is 15 s.
- [x] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/CopilotAdapterTests.swift`)
**Gate**: Quick

**T5 Post-Gate Review**:

| Criterion | `file:line` + assertion | Spec outcome | Covered? |
|---|---|---|---|
| REL-04 AC6 (one buffer) | `CopilotAdapterTests.swift:161` - both bodies in order | Second frame body available | ✅ |
| REL-04 AC6 (split writes) | `CopilotAdapterTests.swift:184` - `response == #"{"result":1}"#` with the header split across writes | Returns second frame body | ✅ |
| REL-04 AC6 (partial) | `CopilotAdapterTests.swift:174` - only the first body | Incomplete frame never returned | ✅ |
| REL-04 AC5 | `CopilotAdapterTests.swift:193-196` - throws `ProviderError.network(URLError(.timedOut))`, elapsed `< 0.3 + 2` | Timeout maps to `.timedOut` | ✅ |
| REL-04 AC5 (bound) | `CopilotAdapterTests.swift:201` - `responseTimeout == 15` | 15 s default | ✅ |

The old reader discarded bytes after the first frame, so two frames in one chunk blocked the second read forever; the buffer-wide parser removes that hang. End of output before two frames keeps the previous `networkConnectionLost` mapping. Gate: 174 passed, 0 failed.

**Verdict**: Covered and necessary; no spec deviation.

### Phase 3: Localization

#### T6: Synchronize and complete localization tables

**What**: Rename the pt-BR/es Codex key, add the missing keys to all three tables, and localize the network error message.
**Where**: `Sources/LimitBar/Resources/{en,pt-BR,es}.lproj/Localizable.strings`, `Sources/LimitBar/Core/AccountStore.swift`
**Depends on**: None
**Requirement**: REL-05

**Done when**:
- [x] The three tables have identical key sets.
- [x] All seven keys from REL-05 AC2 exist.
- [x] A network failure stores the localized `Network error: %d` message with the code.
- [x] Full gate passes.

**Tests**: unit (`Tests/LimitBarTests/LocalizationTests.swift`, `Tests/LimitBarTests/AccountStoreTests.swift`)
**Gate**: Full

**T6 Post-Gate Review**:

| Criterion | `file:line` + assertion | Spec outcome | Covered? |
|---|---|---|---|
| REL-05 AC1 | `LocalizationTests.swift:35-36` - both set differences empty for pt-BR and es | Identical key sets | ✅ |
| REL-05 AC2 | `LocalizationTests.swift:44` - `missing.isEmpty` for each locale | Seven keys present | ✅ |
| REL-05 AC3 | `LocalizationTests.swift:73-74` - snapshot state equals the localized format for `-1001` | Localized message with code | ✅ |
| REL-05 AC3 (translation) | `LocalizationTests.swift:51`, `:57` - every locale ends in `: -1001`; pt-BR is `"Erro de rede: -1001"` | Code kept; message translated | ✅ |

Two existing assertions (`AccountStoreTests.swift:210`, `PollingEngineTests.swift:300`) compared against the hard-coded English `"Network error: …"`. REL-05 AC3 changes that message on purpose, and the developer machine runs pt-BR, so they now compare against the same exact string built from `NSLocalizedString`. Specificity is unchanged: full-string equality. Gate: `scripts/build.sh test` - 179 passed, 0 failed.

**Verdict**: Covered and necessary; no spec deviation.

### Phase 4: Keychain prompt reduction

```text
T7
```

#### T7: Cache OpenCode credentials in the auth manager

**What**: Keep each account's API key or OAuth credential in `GoAuthManager` memory after the first successful read; update it on store, authorize, and refresh; clear it on delete; never cache failures.
**Where**: `Sources/LimitBar/Core/GoAuthManager.swift`
**Depends on**: None
**Requirement**: REL-06

**Done when**:
- [x] Repeated API-key and OAuth bearer requests read the Keychain once.
- [x] After a rotation, the next request returns the rotated token with no further read.
- [x] Store and authorize serve the new credential with no read.
- [x] Delete forces a new read; failed reads are retried.
- [x] Full gate passes.

**Tests**: unit (`Tests/LimitBarTests/GoAuthManagerTests.swift`)
**Gate**: Full

**T7 Post-Gate Review**:

| Criterion | `file:line` + assertion | Spec outcome | Covered? |
|---|---|---|---|
| REL-06 AC1 (API key) | `GoAuthManagerTests.swift:410-411` - three equal tokens, `readCount == 1` | One Keychain read | ✅ |
| REL-06 AC1 (OAuth) | `GoAuthManagerTests.swift:425-426` - three equal tokens, `readCount == 1` | One Keychain read | ✅ |
| REL-06 AC2 | `GoAuthManagerTests.swift:442-446` - both calls `"new-access"`, one refresh of `old-refresh`, none of `new-refresh`, `readCount == 1` | Rotated token from memory | ✅ |
| REL-06 AC3 | `GoAuthManagerTests.swift:461-464` - stored key and authorized token returned, `readCount == 0` for both | No read after store/authorize | ✅ |
| REL-06 AC4 | `GoAuthManagerTests.swift:476-479` - `missingCredentials` after delete, `readCount == 1` | Delete forces a read | ✅ |
| REL-06 AC5 | `GoAuthManagerTests.swift:488-495` - first read fails, later read succeeds, `readCount == 2` | Failure not cached | ✅ |

Red-green: the four cache tests failed before the change (`readCount` 3/3/2/1 instead of 1/1/1/0); AC4 and AC5 already held and keep guarding the invalidation paths. The cache is cleared before deletion so a partial delete still forces a fresh read. Gate: `scripts/build.sh test` - 192 passed, 0 failed.

**Verdict**: Covered and necessary; no spec deviation.

---

## Verification Fix Iteration 1

The first Verifier run returned FAIL: 15/19 mutants killed. Fixes:

| Gap | Fix | Evidence |
|---|---|---|
| REL-01 AC1: launch request untested (M12) | Launch work moved into `AppDelegate.startServices(notifications:engine:environment:)` | `NotificationServiceTests.swift` - `launchServicesRequestAuthorization`, `launchServicesSkipAuthorizationUnderTests` |
| REL-03 AC2: inherited environment unchecked (M19) | Runner and Codex client tests compare the child's `HOME`/`PATH`/`CODEX_HOME` with the parent's | `CLIProcessRunnerTests.swift` - `nilEnvironmentInherits`; `CodexAdapterTests.swift` - `launchedProcessInheritsWithoutOverride` |
| REL-04 AC7: 6 s default unpinned (M13) | `timeout` is now readable; test pins the default client | `CodexAdapterTests.swift` - `defaultCodexTimeoutIsSixSeconds` |
| REL-04 AC5: 15 s default unpinned (M18) | Test pins `CopilotAppServerClient().timeout` | `CopilotAdapterTests.swift` - `defaultTimeoutIsFifteenSeconds` |
| REL-05 AC3: locale-dependent check (M14) | `networkErrorMessage(_:bundle:)` tested against the pt-BR bundle | `LocalizationTests.swift` - `networkMessageUsesLocaleTable` |

Residual: deleting the single `Task { await Self.startServices(...) }` line in `applicationDidFinishLaunching` is still build-only. It would also stop polling, so a manual smoke test catches it. Gate: 185 passed, 0 failed.

## Verification Fix Iteration 2

The second Verifier run returned FAIL. Every earlier gap was closed, but `9aa5fe3` made `startServices` await the permission prompt before `engine.start()`, so a first launch would not poll until the user answered.

| Gap | Fix | Evidence |
|---|---|---|
| Polling blocked by the pending prompt | `startServices` starts the engine first, then requests authorization | `NotificationServiceTests.swift` - `launchServicesPollWhilePromptPending` (fake prompt never answers; fetch count ≥ 1) |

Accepted residual: on an English machine, `AccountStore.apply` hard-coding English is output-identical to the localized call; `networkMessageUsesLocaleTable` covers the function with a fixed pt-BR bundle. Gate: 186 passed, 0 failed.

## Verification Fix Iteration 4 (REL-06)

The Verifier returned FAIL for T7 (8/11 mutants killed) with three gaps:

| Gap | Fix | Evidence |
|---|---|---|
| A second limit-bar process (another app copy or the test host) could resubmit a consumed refresh token from a stale cache | The manager re-reads the Keychain before each due refresh and uses a credential that another process already rotated (REL-06 AC6). The test host no longer polls (AC7) | `GoAuthManagerTests.swift` - `crossProcessRotationIsNotReplayed`; `NotificationServiceTests.swift` - `launchServicesSkipAuthorizationUnderTests` (no prompt, no fetch) |
| AC3 race untested: reauthorization during an in-flight refresh | Probe adopted as a test (current code already correct) | `GoAuthManagerTests.swift` - `reauthorizationDuringRefreshWins` |
| AC5 API-key failure path untested | New test | `GoAuthManagerTests.swift` - `failedAPIKeyReadIsNotCached` |

AC1 now allows one read before each refresh, so `rotatedCredentialServedWithoutRead` expects 2 reads (initial + pre-refresh) instead of 1; the post-rotation request still reads nothing. Discovery: before this fix every `xcodebuild test` run polled the developer's real accounts and read the real Keychain from a new Debug cdhash, which itself raised Keychain dialogs. Residual: two processes refreshing the same account at the same instant can still race (pre-existing; needs cross-process locking). Gate: `scripts/build.sh test` - 195 passed, 0 failed.

## Verification Fix Iteration 5 (REL-06)

The Verifier returned FAIL with one decision gap: after a local refresh failure, a credential rotated by another process was never picked up (mutant N4 survived, not equivalent).

| Gap | Fix | Evidence |
|---|---|---|
| AC6 vs. failed-refresh state undecided | Decision: a recorded failed refresh wins (no Keychain re-read, no resubmission). AC6 narrowed; AC8 added and pinned | `GoAuthManagerTests.swift` - `failedRefreshStaysQuiet` (4 calls, 1 read, 1 refresh) |
| Two dialogs back to back when the first poll finds a due token | No re-read when the value was just read from the Keychain (AC9) | `GoAuthManagerTests.swift` - `rotatedCredentialServedWithoutRead` now expects exactly 1 read (stricter than the previous 2) |

The simultaneous two-process refresh race is now recorded in the spec assumptions as an accepted residual. Gate: `scripts/build.sh test` - 196 passed, 0 failed.

## Manual UAT

- 2026-11-04, build 0.3.2 (113), cdhash `4153b2c0…`: after one "Always Allow" approval, the user confirmed that no Keychain dialogs return during later polls (REL-06 Independent Test passed). The user reported "tests OK".
