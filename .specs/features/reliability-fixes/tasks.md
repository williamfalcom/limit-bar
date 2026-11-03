# Reliability Fixes Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: follow its Execute flow, test-coverage rules, post-gate review, and atomic commit protocol. Do not batch tasks into one commit.

---

**Spec**: `.specs/features/reliability-fixes/spec.md`
**Status**: In Progress

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
- [ ] Adapter passes the tilde-expanded override to the app-server closure; `nil` when absent.
- [ ] Environment builder sets `CODEX_HOME` and preserves other variables; returns the inherited environment for `nil`.
- [ ] Silent Codex output throws.
- [ ] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/CodexAdapterTests.swift`)
**Gate**: Quick

#### T5: Route Copilot through the runner with a 15 s timeout

**What**: Replace the blocking frame reader with `CLIProcessRunner`, a pure frame parser, and a timeout that maps to `ProviderError.network(URLError(.timedOut))`.
**Where**: `Sources/LimitBar/Providers/CopilotAdapter.swift`
**Depends on**: T3
**Requirement**: REL-04

**Done when**:
- [ ] Frame parser returns the second frame body from two complete frames, including split chunks.
- [ ] Incomplete output after timeout throws `ProviderError.network(URLError(.timedOut))`.
- [ ] Client timeout constant is 15 s.
- [ ] Quick gate passes.

**Tests**: unit (`Tests/LimitBarTests/CopilotAdapterTests.swift`)
**Gate**: Quick

### Phase 3: Localization

#### T6: Synchronize and complete localization tables

**What**: Rename the pt-BR/es Codex key, add the missing keys to all three tables, and localize the network error message.
**Where**: `Sources/LimitBar/Resources/{en,pt-BR,es}.lproj/Localizable.strings`, `Sources/LimitBar/Core/AccountStore.swift`
**Depends on**: None
**Requirement**: REL-05

**Done when**:
- [ ] The three tables have identical key sets.
- [ ] All seven keys from REL-05 AC2 exist.
- [ ] A network failure stores the localized `Network error: %d` message with the code.
- [ ] Full gate passes.

**Tests**: unit (`Tests/LimitBarTests/LocalizationTests.swift`, `Tests/LimitBarTests/AccountStoreTests.swift`)
**Gate**: Full
