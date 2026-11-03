## Validation: reliability-fixes - PASS ✅

**Verdict (iteration 3 of 3)**: PASS.

- All 18 acceptance criteria and all 3 edge cases have discriminating, spec-matching assertions.
- The iteration-2 regression is fixed and guarded: `startServices` now starts polling before the permission prompt, and the new test kills the reverted order.
- Every gating mutant across the three iterations is killed in the final code.
- The gate passes: 186 passed, 0 failed.

Two survivors remain. Both are accepted residuals, explained below: deleting the launch line, and an English-host call-site revert.

- **Date**: 2026-11-03
- **Spec**: `.specs/features/reliability-fixes/spec.md`
- **Diff range**: `853fa4e..c15acd7` (9 commits: 7 feature commits, plus fix commits `9aa5fe3` and `c15acd7`)
- **Verifier**: independent sub-agent (author ≠ verifier)

---

## Iteration History

| Iteration | HEAD | Gate | Sensor | Verdict | Findings |
| --------- | ---- | ---- | ------ | ------- | -------- |
| 1 | `3f0ec72` | 179 passed, 0 failed | 15/19 killed | ❌ | M12 (REL-01 AC1 launch), M13 (REL-04 AC7 6 s), M18 (REL-04 AC5 15 s), M19 (REL-03 AC2 env) survived; M14 (REL-05 AC3) caught only on a non-en host |
| 2 | `9aa5fe3` | 185 passed, 0 failed | 9/9 gating killed | ❌ | All iteration-1 gaps closed. New regression: `startServices` awaited the permission prompt before `engine.start()`. A scratch probe recorded 0 fetches while the prompt was pending |
| 3 | `c15acd7` | 186 passed, 0 failed | 3/3 killed | ✅ | Regression fixed and guarded; no new findings |

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 Notification permission | ✅ Done | Launch logic is tested via `AppDelegate.startServices`; polling starts before the prompt |
| T2 Wake center | ✅ Done | - |
| T3 CLI runner | ✅ Done | - |
| T4 Codex via runner | ✅ Done | - |
| T5 Copilot via runner | ✅ Done | - |
| T6 Localization | ✅ Done | Accepted en call-site residual (below) |
| Fix iteration 1 (`9aa5fe3`) | ✅ Done | Closed 5 gaps |
| Fix iteration 2 (`c15acd7`) | ✅ Done | Launch order fixed; `launchServicesPollWhilePromptPending` added |

---

## Spec-Anchored Acceptance Criteria (at `c15acd7`)

### REL-01: Threshold notifications reach the user

| Criterion | Spec-defined outcome | `file:line` + assertion | Verdict |
| --------- | -------------------- | ----------------------- | ------- |
| AC1: on launch, `.notDetermined` → request `.alert` + `.sound` exactly once | One request, `[.alert, .sound]`, made by the launch path | `NotificationServiceTests.swift:163` - `#expect(center.authorizationRequests == [[.alert, .sound]])` via `AppDelegate.startServices(…, environment: [:])`; `:189` - same, with a prompt that never answers; `:151` - service level; `:206` - `authorizationRequests.isEmpty` under the XCTest env key | ✅ PASS (M12′ killed in iterations 2 and 3) |
| AC2: `.authorized` / `.denied` / `.provisional` → no request | Zero requests | `NotificationServiceTests.swift:217` - `#expect(center.authorizationRequests.isEmpty)`, parameterized over all three (`func` at `:212`) | ✅ PASS (M2 killed) |
| AC3: crossing under `.provisional` → one notification | Exactly 1 posted | `NotificationServiceTests.swift:238` - `#expect(center.requests.count == 1)` | ✅ PASS (M3 killed) |

### REL-02: Wake refresh runs after sleep

| Criterion | Spec-defined outcome | `file:line` + assertion | Verdict |
| --------- | -------------------- | ----------------------- | ------- |
| AC1: wake on the engine's center → refresh stale accounts | Only the stale account is refetched | `PollingEngineTests.swift:429` - `log.count(stale.id) == 2`; `:430` - `log.count(fresh.id) == 1` | ✅ PASS (M1 killed in iterations 1 and 2) |
| AC2: default center is `NSWorkspace.shared.notificationCenter` | Identity | `PollingEngineTests.swift:438` - `===`; `:439` - `!== NotificationCenter.default` | ✅ PASS |
| AC3: no refresh after `stop()` | Count unchanged | `PollingEngineTests.swift:461` - `log.count(stale.id) == 1` | ✅ PASS (M15 killed) |

### REL-03: Codex accounts honor their CODEX_HOME

| Criterion | Spec-defined outcome | `file:line` + assertion | Verdict |
| --------- | -------------------- | ----------------------- | ------- |
| AC1: override → child `CODEX_HOME` = expanded override | Expanded path reaches the child | `CodexAdapterTests.swift:346` - `recorder.recorded == [home + "/alt-codex"]`; `:382` - child prints `/tmp/alt-codex-home` | ✅ PASS (M4, M6 killed) |
| AC2: no override → inherited environment unchanged | Child sees the parent's `HOME`/`PATH`/`CODEX_HOME` | `CLIProcessRunnerTests.swift:95` - child `"$HOME\|$PATH"` == the parent's; `CodexAdapterTests.swift:398` - child `HOME`/`CODEX_HOME` == the parent's; `:355`, `:369` - `nil` passthrough | ✅ PASS (M19 killed in iterations 2 and 3) |
| AC3: other variables preserved | Full dictionary equality | `CodexAdapterTests.swift:364` | ✅ PASS (M5 killed) |

### REL-04: A silent CLI cannot freeze polling

| Criterion | Spec-defined outcome | `file:line` + assertion | Verdict |
| --------- | -------------------- | ----------------------- | ------- |
| AC1: no output → within timeout + 2 s, process terminated | `.timedOut`, < t+2, PID gone | `CLIProcessRunnerTests.swift:39`, `:40`, `:42` | ✅ PASS (M7, M8 killed) |
| AC2: child holds stdout → within timeout + 2 s | `.timedOut`, < t+2 | `CLIProcessRunnerTests.swift:57-59` | ✅ PASS (M8 killed) |
| AC3: completion → early return with output, process terminated | `.completed`, < 2 s with a 10 s timeout, output, PID gone | `CLIProcessRunnerTests.swift:74`, `:75`, `:77`, `:79` | ✅ PASS (M7 killed) |
| AC4: CLI exited before input → throws; app survives | Throws, no SIGPIPE | `CLIProcessRunnerTests.swift:103` - `await #expect(throws: (any Error).self)` | ✅ PASS (M10 killed by a crash) |
| AC5: Copilot without both frames in 15 s → `ProviderError.network(URLError(.timedOut))` | Exact error; 15 s production bound | `CopilotAdapterTests.swift:193` - exact error; `:196` - elapsed; `:201` - `responseTimeout == 15`; `:202` - `CopilotAppServerClient().timeout == 15` | ✅ PASS (M16, M18 killed) |
| AC6: two frames → second body | Second body | `CopilotAdapterTests.swift:161`, `:174`, `:184` | ✅ PASS (M9 killed) |
| AC7: Codex silent within 6 s → throws | Throws; 6 s production bound | `CodexAdapterTests.swift:414` - throws; `:417` - elapsed; `:403` - `CodexAppServerClient().timeout == 6` | ✅ PASS (M13 killed) |

### REL-05: Complete localization

| Criterion | Spec-defined outcome | `file:line` + assertion | Verdict |
| --------- | -------------------- | ----------------------- | ------- |
| AC1: identical key sets | Both differences empty | `LocalizationTests.swift:35-36` | ✅ PASS (M11 killed) |
| AC2: seven named keys present | All present per locale | `LocalizationTests.swift:44` | ✅ PASS (M11 killed) |
| AC3: network failure → localized `Network error: %d` with the code | Localized format + code | `LocalizationTests.swift:79` - `networkErrorMessage(URLError(.timedOut), bundle: pt-BR) == "Erro de rede: -1001"`; `:70` - store state == `networkErrorMessage(…)`; `:57` - pt-BR table | ✅ PASS (M14 killed under pt-BR; M14b killed under en). Accepted residual: M14-en |

**Status**: ✅ 18/18 ACs covered with spec-matching assertions.

---

## Edge Cases

- [x] `~/alt` → `<home>/alt`: `CodexAdapterTests.swift:346`
- [x] > 4 MiB without marker → stop and return collected: `CodexAdapterTests.swift:430` (size), `:431` (elapsed < 5 with a 20 s timeout). M17 killed
- [x] Authorization request throws → continue without notifications: `NotificationServiceTests.swift:228` (one attempt), `:229` (`requests.isEmpty`). Polling no longer depends on the request at all, because `engine.start()` runs first (`LimitBarApp.swift:101`)

---

## Discrimination Sensor

All runs used a scratch `git worktree` at `/tmp/lb-verify` with a separate `-derivedDataPath`, reset between mutants and removed afterwards. In every iteration, the real tree's `git status --porcelain` matched its baseline.

### Final sensor table (all mutants, latest outcome)

| # | File:line | Mutation | Spec | Latest outcome |
| - | --------- | -------- | ---- | -------------- |
| M1 | `PollingEngine.swift:89` | Wake observer on `NotificationCenter.default` | REL-02 AC1 | ✅ Killed (iteration 2) |
| M2 | `NotificationService.swift:60` | Request also when `.denied`/`.provisional` | REL-01 AC2 | ✅ Killed (iteration 1) |
| M3 | `NotificationService.swift:76` | `.provisional` no longer posts | REL-01 AC3 | ✅ Killed (iteration 1) |
| M4 | `CodexAdapter.swift:32` | Adapter passes `nil` instead of the override | REL-03 AC1 | ✅ Killed (iteration 1) |
| M5 | `CodexAdapter.swift:219` | Env builder drops base variables | REL-03 AC3 | ✅ Killed (iteration 1) |
| M6 | `CodexAdapter.swift:203` | Env not passed to the runner | REL-03 AC1 | ✅ Killed (iteration 1) |
| M7 | `CLIProcessRunner.swift:122` | No terminate on finish | REL-04 AC1/AC3 | ✅ Killed (iteration 2) |
| M8 | `CLIProcessRunner.swift:88` | Timeout not scheduled | REL-04 AC1/2/5/7 | ✅ Killed (iteration 1) |
| M9 | `CopilotAdapter.swift:129` | Only the first frame returned | REL-04 AC6 | ✅ Killed (iteration 2) |
| M10 | `CLIProcessRunner.swift:46` | `F_SETNOSIGPIPE` removed | REL-04 AC4 | ✅ Killed by crash (iteration 1) |
| M11 | `pt-BR.lproj/Localizable.strings:15` | Codex key reverted | REL-05 AC1/AC2 | ✅ Killed (iteration 1) |
| M12′ | `LimitBarApp.swift:103` | Remove `requestAuthorizationIfNeeded()` in `startServices` | REL-01 AC1 | ✅ Killed (iteration 3: `NotificationServiceTests.swift:163`, `:189`) |
| M13 | `CodexAdapter.swift:182` | Codex timeout 6 → 60 | REL-04 AC7 | ✅ Killed (iteration 2: `CodexAdapterTests.swift:403`) |
| M14 | `AccountStore.swift:96` | Call site hard-codes English (default language pt-BR) | REL-05 AC3 | ✅ Killed (iteration 2) |
| M14b | `AccountStore.swift` `networkErrorMessage` | Function hard-codes English (`-testLanguage en`) | REL-05 AC3 | ✅ Killed (iteration 2: `LocalizationTests.swift:79`) |
| M15 | `PollingEngine.swift:105` | `stop()` keeps the observer | REL-02 AC3 | ✅ Killed (iteration 1) |
| M16 | `CopilotAdapter.swift:101` | Timeout → `.networkConnectionLost` | REL-04 AC5 | ✅ Killed (iteration 1) |
| M17 | `CodexAdapter.swift:207` | 4 MiB cap removed | Edge | ✅ Killed (iteration 1) |
| M18 | `CopilotAdapter.swift:69` | Default `init` timeout → 150 | REL-04 AC5 | ✅ Killed (iteration 2: `CopilotAdapterTests.swift:202`) |
| M19 | `CLIProcessRunner.swift:36-38` | `nil` env → `[:]` | REL-03 AC2 | ✅ Killed (iteration 3: `CLIProcessRunnerTests.swift:95`, `CodexAdapterTests.swift:398`) |
| MR1 | `LimitBarApp.swift:101-104` | Await the permission request before `engine.start()` (iteration-2 regression reverted) | Launch polling (non-AC regression) | ✅ Killed (iteration 3: `NotificationServiceTests.swift:190`, `fetches.count >= 1`) |
| M12r | `LimitBarApp.swift:59-65` | Delete the `Task { await Self.startServices(…) }` launch line | REL-01 AC1 | ⚠️ Survives (accepted residual) |
| M14-en | `AccountStore.swift:96` | Call site hard-codes English, with `-testLanguage en` | REL-05 AC3 | ⚠️ Survives (accepted residual; en output identical) |

**Iteration 3 runs** (HEAD `c15acd7`, scratch baseline 186/186): MR1 killed, M12′ killed, M19 killed (regression spot-check, REL-03). Score: **3/3**.

**Cumulative**: 21/21 gating mutants killed; 2 accepted residuals.

**Sensor depth**: expanded (P1 feature, ≥5 mutations per iteration in iterations 1 and 2)

### Accepted residuals

**M12r (deleting the launch `Task {}` line).** I accept this residual for four reasons:

1. All REL-01 AC1 decision logic lives in `AppDelegate.startServices`, and M12′ and MR1 discriminate it: whether to ask, which options, the test-host skip, and that polling starts first.
2. What remains is one unconditional call in the `NSApplicationDelegate` entry point.
3. Deleting it also disables `engine.start()`, so every account stays blank. Any launch shows this immediately, and both the spec's Independent Test and its manual Success Criterion catch it.
4. Covering it automatically would need a test-only "started" flag on the delegate.

**Condition**: the manual check in `spec.md` → Success Criteria must be performed before release.

**M14-en (English-host call-site revert).** If `AccountStore.apply` bypasses `networkErrorMessage` with a hard-coded `"Network error: \(code)"`, the output on an en host is byte-identical to the localized en string, so the mutant is equivalent there. On pt-BR and es hosts it is killed (`LocalizationTests.swift:70`, `AccountStoreTests.swift:210`, `PollingEngineTests.swift:300`). The function itself is guarded on every host by `LocalizationTests.swift:79`, which uses a fixed pt-BR bundle. Optional hardening: inject a `Bundle` into `AccountStore`.

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ |
| Surgical changes | ✅ `c15acd7` is a 1-line reorder plus doc comment; the test fake gains a `hangOnRequest` flag |
| No scope creep | ✅ Nothing from Out of Scope was touched |
| Matches patterns | ✅ Injected fakes guarded by `NSLock`, Swift Testing, real `/bin/sh` processes |
| Spec-anchored outcome check | ✅ 18/18 |
| Per-layer coverage expectation | ✅ App wiring is unit-tested via `startServices`; entry-point residual accepted |
| Every test maps to a spec requirement | ✅ The new `launchServicesPollWhilePromptPending` maps to REL-01 AC1 (request made) plus the launch-polling regression guard |
| Would a senior engineer approve? | ✅ |
| Documented guidelines followed | ✅ `AGENTS.md` |

---

## Gate Check

- **Gate command**: `scripts/build.sh test` (real tree, HEAD `c15acd7`)
- **Exit code**: 0, `** TEST SUCCEEDED **`
- **Counts** (xcresult summary): **186 passed, 0 failed, 0 skipped, 0 expected failures**. Counting each parameterized case, the device total is 192.
- **Test count**: 151 before the feature (`853fa4e`) → 179 (`3f0ec72`) → 185 (`9aa5fe3`) → 186 (`c15acd7`)
- **Delta**: +35; no tests removed. Two pre-existing assertions (`AccountStoreTests.swift:210`, `PollingEngineTests.swift:300`) were rewritten from hard-coded English to the localized format, which is still full-string equality.
- **Isolation**: real-tree `git status --porcelain` showed only this report before and after all sensor work. The scratch worktree, derived data, and harness were removed.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| REL-01 | ✅ ACs verified; launch regression open | ✅ Verified |
| REL-02 | ✅ Verified | ✅ Verified |
| REL-03 | ✅ Verified | ✅ Verified |
| REL-04 | ✅ Verified | ✅ Verified |
| REL-05 | ✅ Verified (minor residual) | ✅ Verified (accepted residual M14-en) |

(spec.md was not edited: the Verifier's only write is this report. The orchestrator may update the traceability table.)

---

## Summary

**Overall**: ✅ Ready

- **Spec-anchored check**: 18/18 ACs matched the spec outcome; all 3 edge cases are covered.
- **Sensor**: 3/3 killed this iteration; 21/21 gating mutants killed cumulatively; 2 accepted residuals.
- **Gate**: 186 passed, 0 failed, 0 skipped

**What works**:

- Notification permission at launch, without blocking polling
- Provisional posting
- Wake refresh on the workspace center
- Per-account `CODEX_HOME` with an inherited environment
- Timeout-bounded CLI runner with termination and SIGPIPE safety
- Copilot frame parsing and timeout mapping
- Synchronized localization tables

**Next steps**:

- Perform the manual success-criterion check (grant permission, cross 80%, one notification) before release. The M12r acceptance depends on it.
- Optional: inject a `Bundle` into `AccountStore` to close M14-en.
