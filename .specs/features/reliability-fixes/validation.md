## Validation: reliability-fixes - PASS ✅

**Verdict**: PASS. All six requirements are verified.

- REL-01..REL-05 were verified in iteration 3. REL-06 is verified in its iteration 3 at `ff0c233`.
- Commit `ff0c233` resolves the last decision gap. A failed refresh now wins (AC8, pinned by `failedRefreshStaysQuiet`), AC6 is narrowed accordingly, and the redundant second Keychain read on a cold start is gone (AC9).
- Every REL-06 mutant is killed, including N4, which survived last round.
- The four scratch probes match the spec at HEAD: cross-process rotation, cold start after rotation elsewhere, local failure vs. rotation elsewhere, and the failed-state read budget.
- The gate passes: 196 passed, 0 failed.

The remaining items are documented, accepted residuals.

- **Date**: 2026-11-04
- **Spec**: `.specs/features/reliability-fixes/spec.md`
- **Diff range**: REL-01..05 `853fa4e..c15acd7`; REL-06 `d200197..ff0c233` (T7 `02fa504`, fixes `c3bb18e`, `ff0c233`)
- **Verifier**: independent sub-agent (author ≠ verifier)

---

## Iteration History

| Scope | Iteration | HEAD | Gate | Sensor | Verdict | Findings |
| ----- | --------- | ---- | ---- | ------ | ------- | -------- |
| REL-01..05 | 1 | `3f0ec72` | 179 passed, 0 failed | 15/19 killed | ❌ | M12, M13, M18, M19 survived; M14 locale-dependent |
| REL-01..05 | 2 | `9aa5fe3` | 185 passed, 0 failed | 9/9 gating killed | ❌ | Gaps closed; polling blocked behind the permission prompt |
| REL-01..05 | 3 | `c15acd7` | 186 passed, 0 failed | 3/3 killed | ✅ | Fixed; residuals M12r, M14-en accepted |
| REL-06 | 1 | `02fa504` | 192 passed, 0 failed | 8/11 killed | ❌ | R6-7b (AC5), R6-9 (AC3) survived; F1 cross-process resubmission |
| REL-06 | 2 | `c3bb18e` | 195 passed, 0 failed | 6/7 killed | ❌ | F1 fixed; N4 survived (failed-refresh state unspecified) |
| REL-06 | 3 | `ff0c233` | 196 passed, 0 failed | 4/4 killed (N4, N5, N6, N1); probes B, B2, C, D pass | ✅ | Decision recorded (AC6 narrowed, AC8, AC9); no new findings |

---

## REL-06: OpenCode credentials do not prompt on every poll

### Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T7 Cache credentials (`02fa504`) | ✅ Done | - |
| Fix iteration 4 (`c3bb18e`) | ✅ Done | Pre-refresh Keychain re-read (AC6); test host does not poll (AC7) |
| Fix iteration 5 (`ff0c233`) | ✅ Done | Failed refresh stays quiet (AC8); no redundant read on a cold start (AC9); two-process race recorded in the spec |

### Spec-Anchored Acceptance Criteria (at `ff0c233`)

| Criterion | Spec-defined outcome | `file:line` + assertion | Verdict |
| --------- | -------------------- | ----------------------- | ------- |
| AC1: one read, plus one before each OAuth refresh | 1 read over repeated requests | `GoAuthManagerTests.swift:410`, `:411` - API key `readCount == 1`; `:425`, `:426` - OAuth `readCount == 1`; `:448` - `readCount == 1` across a cold-start refresh and a later request | ✅ PASS (R6-1, R6-2 it1; N5 killed at `:448`) |
| AC2: after a rotation, the rotated token is served without a read | `"new-access"`; no re-refresh | `:442-445`, `:448` | ✅ PASS (R6-3 it1) |
| AC3: after store/authorize, including mid-refresh, the new credential is served without a read | New credential; 0 reads; the reauthorization wins | `:463-466` (sequential); `:588` - in-flight `== "reauth-access"`, `:589` - next `== "reauth-access"`, `:590` - vault holds `reauthorized` | ✅ PASS (R6-4, R6-5 it1; R6-9 it2) |
| AC4: after delete, the next request reads the Keychain | `missingCredentials`; read happens | `:478`, `:481` | ✅ PASS (R6-6 it1) |
| AC5: a failed read is not cached (both kinds) | Retry reads and succeeds | OAuth `:490`, `:496`, `:497`; API key `:506`, `:511`, `:512` | ✅ PASS (R6-7a it1; R6-7b it2) |
| AC6: due + no recorded failure + rotated elsewhere → use the stored credential; never submit the consumed token | `"new-access"`; `refreshCallCount("old-refresh") == 1` | `:534`, `:536`, `:540` - `token == "new-access"`; `:541` - `refreshCallCount("old-refresh") == 1`; `:542` - `"new-refresh"` never submitted | ✅ PASS (N1 killed at `:541`; N6 killed at `:541`; probes B, B2 pass) |
| AC7: the unit-test host does not poll | No fetch, no prompt | `NotificationServiceTests.swift:214`, `:215` - `fetches.count == 0` | ✅ PASS (N3 it2) |
| AC8: a failed refresh rethrows without reading the Keychain or resubmitting, until credentials are stored, authorized, or deleted | The same error each time; 1 read total; 1 submission | `:558` - 4× `#expect(throws: GoOAuthClientError.network(URLError(.timedOut)))`; `:563` - `readCount == 1`; `:564` - `refreshCallCount("old-refresh") == 1` | ✅ PASS (N4 killed at `:563`; N5, N6 killed at `:563`; probes C, D pass). Release clause: see the note below |
| AC9: a cold-start request with a due token reads the Keychain once before refreshing | 1 read | `:448` - `readCount == 1` | ✅ PASS (N5, N6 killed at `:448`; probe B2: 1 read) |

**Status**: ✅ 9/9 ACs covered with spec-matching assertions.

**AC8 release clause ("until … stored, authorized, or deleted")**: no committed test runs the sequence "failed refresh → reauthorize → request". Release works structurally:

- `authorize` and `storeAPIKey` overwrite the cache and clear the refresh work (`GoAuthManager.swift:56-58`, `:62-64`).
- `deleteCredentials` clears both (`:69-71`).
- The next request is then served from the new cached credential and never reaches the failed work.

The overwrite this depends on is guarded (removing it, R6-5, is killed at `:466`). Optional hardening: a direct "failed refresh → `authorize` → `"authorized-access"`" test. Non-gating.

### Discrimination Sensor, REL-06 iteration 3 (HEAD `ff0c233`)

The scratch worktree's unmutated baseline was 196/196.

| # | File:line | Mutation | Spec | Outcome |
| - | --------- | -------- | ---- | ------- |
| N4 | `GoAuthManager.swift` `reloadOAuthCredential` | Drop the `refreshWorkByAccount == nil` guard | AC8 | ✅ Killed (`GoAuthManagerTests.swift:563`: 4 reads instead of 1) |
| N5 | `GoAuthManager.swift` bearer OAuth path | Always reload, even when the value was just read (`let stored = try reloadOAuthCredential(…)`) | AC9 / AC8 | ✅ Killed (`:448`, `:563`) |
| N6 | same | Inverted: reload only on a cache miss, refresh from a cached value (`wasCached ? cached : reload`) | AC6 / AC9 / AC8 | ✅ Killed (`:448`, `:541`: consumed `old-refresh` resubmitted, `:563`) |
| N1 (regression) | same | Never reload (`let stored = cached`) | AC6 | ✅ Killed (`:541`) |

**Score**: 4/4 killed.

### Scratch Probes (appended to `GoAuthManagerTests.swift` in the scratch copy only; never committed)

| Probe | Scenario | Expected per spec | HEAD | Under N4 | Under N6 |
| ----- | -------- | ----------------- | ---- | -------- | -------- |
| B | Process B caches `prior`; process A rotates; B makes a request | AC6: `"new-access"`, 1 submission | ✅ | ✅ | ❌ 2 submissions |
| B2 | Process A rotates; a fresh process C starts (cache miss) with the due token | AC6 + AC9: `"new-access"`, 1 read, 1 submission | ✅ | ✅ | ✅ |
| C | This process's refresh fails; another process rotates; this process makes a request | AC8: rethrows `network(timedOut)`; 0 reads during the request; 1 local submission | ✅ | ❌ returns `"new-access"`, 1 read | ✅ |
| D | Refresh fails; 4 polls on one manager | AC8: 1 read total; 1 submission | ✅ | ❌ 4 reads | ❌ 2 reads |

**Reading B2**: skipping the reload on a cache miss does **not** reopen the stale-cache replay. The cache-miss check (`wasCached`) and `loadOAuthCredential` run in one non-suspending actor segment, so a value read on a miss is the current Keychain value. B2 is the cold-start variant of F1, and it uses the rotated credential with one read and no resubmission.

### Safety Summary (REL-06, at `ff0c233`)

| Guarantee | Status | Evidence |
| --------- | ------ | -------- |
| Consumed refresh token never resubmitted in-process | ✅ | Coalescing `:626`; invalid grant `:704`; transient `:733`; persistence failure `:760-768` (R6-10 it1); failed state `:564` |
| Cross-process rotation used instead of resubmitting (no local failure) | ✅ | `:540-542`; probes B and B2 |
| After a local failure, the failure wins (no read, no resubmission) | ✅ | `:558`, `:563`, `:564`; probe C |
| Reauthorization mid-refresh wins | ✅ | `:588-590` |
| Test host never polls real accounts | ✅ | `NotificationServiceTests.swift:215` |

### Residuals (REL-06), accepted

- **Simultaneous two-process refresh race**: two processes that both find the token due within one network round trip can submit the same refresh token. This existed before T7, needs cross-process locking, and is now recorded in the spec's assumptions table ("Simultaneous refresh in two processes (REL-06)").
- **Failed refresh vs. rotation elsewhere**: by decision, a recorded failure wins until reconnect or restart. This is recorded in the spec assumptions and AC6/AC8, and pinned by `:563`.
- **R6-8 (equivalent)**: kind isolation is unreachable in the app, because an account's sign-in method is fixed at creation (`SettingsView.swift:386`).

### Final Sensor Table, REL-06 (latest outcome per mutant)

| # | Mutation | Spec | Latest outcome |
| - | -------- | ---- | -------------- |
| R6-1 | OAuth read never populates the cache | AC1 | ✅ Killed (it1) |
| R6-2 | API-key read never populates the cache | AC1 | ✅ Killed (it1) |
| R6-3 | Cache not updated after rotation | AC2 | ✅ Killed (it1; not re-run since `c3bb18e`) |
| R6-4 | `storeAPIKey` does not update the cache | AC3 | ✅ Killed (it1) |
| R6-5 | `authorize` does not update the cache | AC3 / AC8 release | ✅ Killed (it1) |
| R6-6 | `deleteCredentials` does not clear the cache | AC4 | ✅ Killed (it1) |
| R6-7a | OAuth failure cached | AC5 | ✅ Killed (it1) |
| R6-7b | API-key failure cached | AC5 | ✅ Killed (it2) |
| R6-8 | API-key branch serves cached `.oauth` | (kind isolation) | ⚠️ Equivalent (unreachable) |
| R6-9 | Cache `refreshed` when `current != base` | AC3 | ✅ Killed (it2) |
| R6-10 | Cache before the vault write in refresh | AC2 / persistence safety | ✅ Killed (it1) |
| N1 | Never reload before refresh | AC6 | ✅ Killed (it3) |
| N2 | Reload always keeps the cache | AC6 | ✅ Killed (it2) |
| N3 | Test host starts the engine | AC7 | ✅ Killed (it2) |
| N4 | Drop the refresh-work guard in reload | AC8 | ✅ Killed (it3) |
| N5 | Always reload, even after a fresh read | AC9 | ✅ Killed (it3) |
| N6 | Reload only on a cache miss | AC6 / AC9 | ✅ Killed (it3) |

**REL-06 cumulative**: 16/16 gating mutants killed; 1 equivalent (R6-8).

---

## REL-01..REL-05 (verified in iteration 3)

Since `c15acd7`, the only change to these requirements' sources is the test-host guard in `startServices`, which REL-06 AC7 covers. The launch-services tests still pass in the gate, and the M3 regression check was re-killed in REL-06 iteration 2.

| Requirement | Criteria | Key evidence (`file:line`) | Verdict |
| ----------- | -------- | -------------------------- | ------- |
| REL-01 | AC1 launch request `.alert` + `.sound` once; AC2 no request once decided; AC3 `.provisional` posts once | `NotificationServiceTests.swift:163`, `:189` (`authorizationRequests == [[.alert, .sound]]`), `:214` (none under the test host); parameterized `decidedStatusSkipsAuthorizationRequest`; `:247` (`requests.count == 1`) | ✅ PASS |
| REL-02 | AC1 wake refreshes stale only; AC2 workspace center; AC3 none after `stop()` | `PollingEngineTests.swift:429-430`, `:438-439`, `:461` | ✅ PASS |
| REL-03 | AC1 override reaches the child; AC2 inherited env; AC3 other vars kept | `CodexAdapterTests.swift:346`, `:382`; `CLIProcessRunnerTests.swift:95`, `CodexAdapterTests.swift:398`; `CodexAdapterTests.swift:364` | ✅ PASS |
| REL-04 | AC1-AC3 runner timeout/termination/early return; AC4 no SIGPIPE; AC5 Copilot 15 s `.timedOut`; AC6 second frame; AC7 Codex 6 s | `CLIProcessRunnerTests.swift:39-42`, `:57-59`, `:74-79`, `:103`; `CopilotAdapterTests.swift:193`, `:196`, `:201`, `:202`, `:161`, `:174`, `:184`; `CodexAdapterTests.swift:403`, `:414`, `:417` | ✅ PASS |
| REL-05 | AC1 key parity; AC2 required keys; AC3 localized network message | `LocalizationTests.swift:35-36`, `:44`, `:79`, `:70`, `:57` | ✅ PASS |

**Edge cases**: `~/alt` → `CodexAdapterTests.swift:346`; > 4 MiB → `CodexAdapterTests.swift:430-431`; authorization throws → `failingAuthorizationRequestIsAbsorbed`, with polling started first in `startServices`.

**Sensor**: 21/21 gating mutants killed across iterations 1-3 (M1-M19, M12′, MR1).

**Accepted residuals**:

- **M12r**: deleting the launch `Task {}` line. All decision logic is tested in `startServices`, and deletion also stops polling, which is visible on any launch. Conditional on the spec's manual Success Criterion.
- **M14-en**: an en-host call-site revert produces byte-identical en output. It is killed on pt-BR/es hosts, and the function is guarded on all hosts by `LocalizationTests.swift:79`.

---

## Code Quality (`ff0c233`)

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ One `wasCached` flag and a conditional reload |
| Surgical changes | ✅ `GoAuthManager.swift` (+7/-4), its tests, the spec, tasks |
| No scope creep | ✅ Retry policy and cross-process locking stay out of scope, as recorded in the spec |
| Matches patterns | ✅ |
| Spec-anchored outcome check | ✅ 9/9 (REL-06), 18/18 (REL-01..05) |
| Tests changed | ✅ `:448` tightened from `readCount == 2` to `== 1` (stricter, per AC9) |
| Documented guidelines followed | ✅ `AGENTS.md` |

---

## Gate Check

- **Gate command**: `scripts/build.sh test` (real tree, HEAD `ff0c233`)
- **Exit code**: 0
- **Counts** (xcresult summary): **196 passed, 0 failed, 0 skipped, 0 expected failures**. Counting each parameterized case, the device total is 202.
- **Test count**: 151 (`853fa4e`) → 179 → 185 → 186 (`c15acd7`) → 192 (`02fa504`) → 195 (`c3bb18e`) → 196 (`ff0c233`); no tests removed
- **Isolation**: before the sensor work, the real tree's `git status --porcelain` showed only this report (` M validation.md`), and it is unchanged after cleanup. The scratch worktree, derived data, harness, and probes were removed.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| REL-01 | ✅ Verified | ✅ Verified |
| REL-02 | ✅ Verified | ✅ Verified |
| REL-03 | ✅ Verified | ✅ Verified |
| REL-04 | ✅ Verified | ✅ Verified |
| REL-05 | ✅ Verified | ✅ Verified (accepted residual M14-en) |
| REL-06 | ❌ Needs Fix | ✅ Verified (accepted residuals: two-process race, failure-wins decision) |

(spec.md was not edited: the Verifier's only write is this report. The orchestrator may update the traceability table.)

---

## Summary

**Overall**: ✅ Ready

- **Spec-anchored check**: REL-01..05: 18/18 ACs and 3/3 edge cases. REL-06: 9/9 ACs.
- **Sensor**: REL-06 16/16 gating mutants killed, plus 1 equivalent. REL-01..05 21/21, plus 2 accepted residuals.
- **Gate**: 196 passed, 0 failed, 0 skipped

**What works**: all six reliability fixes, including:

- an OpenCode credential cache that reads the Keychain once per run, plus once per due refresh
- picking up a credential that another process rotated
- quiet handling of a failed refresh
- a test host that never touches real accounts
- every single-use refresh-token guarantee, both in-process and across processes, except the accepted simultaneous-refresh race

**Next steps**:

1. Perform the spec's manual Success Criteria before release: one notification after granting permission and crossing 80% (M12r depends on it), and the REL-06 Independent Test on an ad-hoc build.
2. Optional: add a direct "failed refresh → reauthorize" test for the AC8 release clause.
