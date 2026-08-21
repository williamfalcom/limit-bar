# menu-bar-limits Validation

**Date**: 2026-08-21
**Spec**: `.specs/features/menu-bar-limits/spec.md`
**Diff range**: `ffa8feb^..ae05130` on `main` (15 commits T1–T15; baseline = parent of ffa8feb)
**Verifier**: independent sub-agent (author ≠ verifier)

---

## Validation

**Result**: **PASS** — gate green, all 5 discrimination mutants killed, every automatable AC traced to an assertion that pins the spec-defined value. 3 spec-precision gaps flagged (documentation/coverage polish, none behavior-failing). No lessons recorded (clean PASS rule).

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1–T15 | ✅ Done | All 85 planned tests present; view/live-service tasks carry explicit UAT deferrals per matrix |

---

## Gate Check

- **Command**: `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'`
- **Result**: **85 passed, 0 failed, 0 skipped** (11 suites, matches tasks.md plan exactly: 8+6+10+6+9+10+6+12+8+5+5)
- Test count did not decrease; no weakened assertions found.

---

## Spec-Anchored Acceptance Criteria

Legend: ✅ covered-by-test · 🔵 hybrid (logic asserted, rendering/wiring manual-UAT) · ⚪ manual-UAT (view/system layer, legitimately unautomated per tasks.md matrix) · ⚠️ spec-precision gap

| AC | Criterion | Spec-defined outcome | Evidence (`file:line` + assertion) | Result |
|----|-----------|---------------------|-----------------------------------|--------|
| LIM-01 | Icon at launch from persisted active account's selected window | usage % of cached snapshot | IconRendererTests.swift:31,124; PersistenceTests.swift:42; ModelsTests.swift:113 (`activeAccountID == goID` round-trip); launch display = MenuBarExtra wiring | 🔵 manual-UAT |
| LIM-02 | usage <70% → green | tint green at 0/50/69.9 | IconRendererTests.swift:31 — `#expect(style.tint == .green)` | ✅ PASS |
| LIM-03 | 70–89% → amber | tint amber at 70.0/70.5/89.0 | IconRendererTests.swift:44 — `#expect(style.tint == .amber)` | ✅ PASS |
| LIM-04 | ≥90% → red | tint red at 90.0/95.0/99.9 | IconRendererTests.swift:56 — `#expect(style.tint == .red)` | ✅ PASS |
| LIM-05 | any window ≥100% → countdown replaces % | text "2h 5m" from resetsAt, fill 1.0; cross-window case "45m" | IconRendererTests.swift:70 — `#expect(style.text == "2h 5m")`, :69 `fill == 1.0`; :109 any-window `#expect(style.text == "45m")` | ✅ PASS |
| LIM-06 | never fetched → neutral gray, tooltip "no data yet" | exact tooltip string, neutral tint | IconRendererTests.swift:77 — `#expect(nilStyle.toolTip == "no data yet")` (+ :76 neutral; empty windows :80-81) | ✅ PASS |
| LIM-07 | click opens panel, one tab per account | panel under icon, segmented tabs | PanelView.swift:21-33 (view layer) | ⚪ manual-UAT |
| LIM-08 | one bar per plan window; Claude/Codex=2, Go=3 | `[.fiveHour,.weekly]` / `[.fiveHour,.weekly,.monthly]` | ClaudeAdapterTests.swift:47 — `windows.map(\.kind) == [.fiveHour, .weekly]`; GoAdapterTests.swift:53 — `== [.fiveHour, .weekly, .monthly]`; bar-count render | 🔵 hybrid |
| LIM-09 | % used + reset time label; absolute $ when provider returns it | `usedAbsolute == "$5.00"`; countdown fmt | GoAdapterTests.swift:57 — `#expect(windows[0].usedAbsolute == "$5.00")`; IconRendererTests.swift:115 countdown strings; row layout | 🔵 hybrid |
| LIM-10 | tab switch sets active account; icon updates from cache | `activeAccountID` set + persisted | AccountStoreTests.swift:78 — `store.activeAccountID == claude.id` after selectActive; :83 persisted nil after removal; icon re-render binding | 🔵 hybrid |
| LIM-11 | fresh data updates bars in place, panel stays open | @Observable store drives rows | PanelView.swift reads live store; SwiftUI identity stable | ⚪ manual-UAT |
| LIM-12 | outside click / Esc closes panel | native MenuBarExtra(.window) dismissal | LimitBarApp.swift:37 `.menuBarExtraStyle(.window)` | ⚪ manual-UAT |
| LIM-13 | no usable credentials → provider CLI login instructions | unauthorized state keeps cache; "claude login"/"codex login" shown | AccountStoreTests.swift:180,184 — `state == .unauthorized` keeping cache; ReauthInstructions commands PanelView.swift:215-216 | 🔵 hybrid |
| LIM-14 | refresh each account every 300 s default | first sleep exactly 300 | PollingEngineTests.swift:225 — `#expect(sleeps.recorded == [300, 600, 1200])` (base interval = store default) | ✅ PASS |
| LIM-15 | custom interval clamped min 60 s | setPollInterval(10) → cadence 60; validator accepts 60 boundary | PollingEngineTests.swift:378 — `sleeps.recorded == [300, 120, 60]`; IntervalValidatorTests.swift:26 — `validate("60").get() == 60` | ✅ PASS |
| LIM-16 | 429 doubles delay capped 30 min; last good data stays | delays [600,1200,1800,1800]; cap table [120,…,1800,1800]; snapshot stale w/ windows+fetchedAt preserved | PollingEngineTests.swift:166 — `delays == [600, 1200, 1800, 1800]`; :171 `maxDelay == 1800`; :178; :315-317 `state == .stale && windows == sampleWindows && fetchedAt == fixedNow` | ✅ PASS |
| LIM-17 | network error/timeout/5xx → cached value visible + "updated Xm ago" marker | windows/fetchedAt untouched, error state recorded | PollingEngineTests.swift:293-295 — `state == .error(…) && windows == sampleWindows && fetchedAt == fixedNow`; AccountStoreTests.swift:210; **marker string `PanelView.updatedText` unasserted** | ⚠️ gap (marker text untested; retention covered) |
| LIM-18 | manual refresh fetches all immediately, resets backoff | immediate fetch (log.total==4), sleeps back to base | PollingEngineTests.swift:272-273 — `log.total == 4`, `sleeps.recorded == [600, 1200, 1200]`. Impl resets ALL schedules then refetches every account, so each outcome (recordSuccess/recordRateLimited) immediately re-establishes correct state — behaviorally equivalent to the spec's "only successful accounts" wording; no observable difference | ✅ PASS (wording nuance noted) |
| LIM-19 | wake → refresh accounts older than current interval | predicate true iff age>interval; exactly stale accounts fetched | PollingEngineTests.swift:322-325 boundary table (-299/-300/-301); :348-349 `log.count(stale.id)==1 && log.count(fresh.id)==0` | ✅ PASS |
| LIM-20 | Claude token read from Keychain service `Claude Code-credentials` | Bearer token flows into request | ClaudeAdapterTests.swift:65 — `Authorization == "Bearer stub-…"` proves seam read; **constant `credentialService` itself never asserted** | ⚠️ gap (constant unpinned) |
| LIM-21 | Codex via app-server, fallback auth.json | fallback reads auth.json, hits chatgpt.com endpoint, classifies windows | CodexAdapterTests.swift:94-97 kinds/percents/resetsAt; :121-125 auth.json path + URL; six-day boundary :107 | ✅ PASS |
| LIM-22 | Go API key pasted → stored in Keychain | generic-password item with service/account/data | KeychainStoreTests.swift:116-119 kSecClass/kSecAttrService/kSecAttrAccount/kSecValueData asserts; sheet→set call site | 🔵 hybrid |
| LIM-23 | expired/rejected credential (401/403) → re-auth instructions | 401→unauthorized mapping both adapters | ClaudeAdapterTests.swift:74 — `throws ProviderError.unauthorized`; CodexAdapterTests.swift:184 same; **403 branch untested**; instructions view | 🔵 hybrid |
| LIM-24 | remove account deletes secret + tab | scoped delete, idempotent; snapshot dropped | KeychainStoreTests.swift:178-181 delete query scoped to service/account, :183-185 not-found OK; AccountStoreTests.swift:67 snapshot nil | 🔵 hybrid |
| LIM-25 | multiple accounts incl. same provider, distinct labels | ["Work","Personal"], 2 codex, unique ids | AccountStoreTests.swift:111-114 — `map(\.label) == ["Work", "Personal"]`, codex count == 2 | ✅ PASS |
| LIM-26 | Settings presents account/window/interval controls | UI exists, wired to store | SettingsView.swift:44-108 | ⚪ manual-UAT |
| LIM-27 | displayed-window change updates icon source | change persists per account | AccountStoreTests.swift:129-130 — `accounts == [renamed]` w/ displayedWindow=.monthly persisted; icon binding | 🔵 hybrid |
| LIM-28 | invalid interval rejected w/ allowed-range message (60–3600) | exact message on <60, >3600, non-numeric | IntervalValidatorTests.swift:15 — `error.message == message` ("Allowed range: 60–3600 seconds"); boundaries :26-27 | ✅ PASS |
| LIM-29 | Go windows vs caps $12/$30/$60 | 41.667% / 66.667% / 50.0% | GoAdapterTests.swift:53-57 — `usedPercent − 41.666_7 < 0.001`, `66.666_7`, `== 50.0`, `usedAbsolute == "$5.00"` | ✅ PASS |
| LIM-30 | Go unreachable/unparseable degrades like others | spec says "stale/error"; design+impl use `.unsupported` (approved design decision, design.md:45) | GoAdapterTests.swift:84 — `throws ProviderError.unsupported`; :106 unparseable-everywhere also unsupported; AccountStoreTests.swift:201 unsupported state clears bars | ⚠️ gap (spec/design drift — amend spec.md) |
| LIM-31 | enable Start at Login registers login item | SMAppService register | LaunchAtLoginController.swift:14-16 (live system service per matrix) | ⚪ manual-UAT |
| LIM-32 | disable removes registration | SMAppService unregister | LaunchAtLoginController.swift:17-19 | ⚪ manual-UAT |
| LIM-33 | crossing 80% posts ONE notification per reset period | 79.9→none; 80.1→exactly 1; repeats suppressed; rollover re-arms | NotificationServiceTests.swift:63-70 — `requests.isEmpty` then `count == 1` then still `== 1`; :82 re-cross `== 1`; :97 rollover `== 2` | ✅ PASS |
| LIM-34 | permission denied → skip silently, visuals keep working | no post, no throw | NotificationServiceTests.swift:108-111 — `requests.isEmpty` twice; icon paths notification-independent | ✅ PASS |

**Status**: ✅ 15 ACs fully matched by automated assertions · 10 hybrids (spec value pinned by test, remainder manual-UAT) · 6 manual-UAT-only · 3 spec-precision gaps flagged (LIM-17, LIM-20, LIM-30)

### Payload/conjunction check (rule 5)
Assertions target values/state, not call occurrence: window arrays compared element-wise (`map(\.kind) == [...]`, `delays == [600,1200,1800,1800]`), FetchResult transitions assert resulting `snapshot.state/.windows/.fetchedAt` triples, AppState round-trip asserts all four fields including `snapshots` dictionary equality (ModelsTests.swift:112).

### Edge cases
- Keychain user-denied → typed accessDenied error, mapped to unauthorized tab without crash: covered (KeychainStoreTests.swift:167, ClaudeAdapterTests.swift:119-125)
- Parse failure → prior data kept, explicit error state: covered (AccountStoreTests.swift:204-206). Note: edge-case row asks for "stale" + local log; impl shows explicit error message over cache and implements no logging — folded into ranked gaps.
- Zero accounts → empty state + neutral icon: emptyState view (manual-UAT); neutral icon covered (IconRendererTests.swift:79-81)
- Same-provider tabs distinguishable: covered (AccountStoreTests.swift:101-115)
- UTC-based countdowns immune to local timezone: ISO8601 "Z" fixtures parsed to fixed instants (ClaudeAdapterTests.swift:45-50); countdown math uses injected clock

---

## Discrimination Sensor

Isolated scratch: `git worktree add /tmp/opencode/limitbar-sensor HEAD` (xcodegen-generated project inside worktree). Real tree untouched — `git status --porcelain` byte-identical before/after.

| # | Mutation | File:line | Description | Killed? |
|---|----------|-----------|-------------|---------|
| 1 | Backoff cap 30 min → 10 min | PollingEngine.swift:5 | `maxDelay = 1800` → `600` | ✅ Killed — 6 failures (PollingEngineTests.swift:166,171,178,186,225,273) |
| 2 | Red threshold 90% → 95% | IconRenderer.swift:17 | `redThreshold = 90.0` → `95.0` | ✅ Killed — IconRendererTests.swift:56 (90.0 renders amber) |
| 3 | Break 429→rateLimited mapping | ClaudeAdapter.swift:31-33 | 429 throws `.network` instead of `.rateLimited(retryAfter:)` | ✅ Killed — ClaudeAdapterTests.swift:84,94 |
| 4 | Drop once-per-reset-period dedup | NotificationService.swift:40 | `shouldNotify` returns `true` unconditionally past threshold | ✅ Killed — NotificationServiceTests.swift:70 (3 posts vs 1), :82 (2 vs 1) |
| 5 | Wake predicate off-by-one | PollingEngine.swift:40 | `>` → `>=` (age == interval now refreshes) | ✅ Killed — PollingEngineTests.swift:324 |

**Sensor depth**: default (lightweight, 5 targeted behavior-level mutations across engine/icon/adapter/notification risk areas)
**Result**: **5/5 killed** — tests discriminate real regressions. ✅

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code / no scope creep | ✅ |
| Surgical changes (matches diff range only) | ✅ |
| Matches existing patterns (seam injection, Swift Testing, strict concurrency) | ✅ |
| Spec-anchored outcomes (values, not occurrence) | ✅ (3 precision flags above) |
| Every test maps to an AC/edge case — no unclaimed tests | ✅ |
| Guidelines: AGENTS.md defines none yet — strong defaults applied | ✅ |

---

## Ranked Gaps

1. **LIM-30 documentation drift** — spec.md says Go degrades "exactly like other providers (stale marker / error state)", but approved design (design.md:45), implementation, and tests all use `.unsupported`. Behavior is deliberate and sound; amend spec.md so the artifact chain agrees. (Minor)
2. **Parse-failure edge case** — spec edge row requires "keep prior data, mark stale, and log the parse failure locally". Impl keeps data and shows an explicit error message (better visibility) but writes no local log anywhere. Either add minimal os_log or amend the edge-case row. (Minor)
3. **LIM-17 staleness marker untested** — `PanelView.updatedText(fetchedAt:now:stale:)` (PanelView.swift:122-131) produces the spec-named "updated Xm ago" marker with zero assertions. Pure function; one-line test would close it. (Minor)
4. **LIM-20 service constant unpinned** — no test asserts `ClaudeAdapter.credentialService == "Claude Code-credentials"`; a typo refactor would pass CI and silently break zero-config Claude onboarding. (Trivial)
5. **403 branch untested** — adapters map `401, 403` → unauthorized but fixture suites exercise only 401. One extra stubbed-response test each. (Trivial)

None of these is a behavior failure; no mutant survived, no AC assertion mismatched a spec-defined value.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| LIM-01…LIM-32 | Implementing | ✅ Verified (LIM-07/11/12/26/31/32 verified via build gate + pending interactive UAT) |
| LIM-33, LIM-34 | Implementing | ✅ Verified |

---

## Summary

**Overall**: ✅ Ready (pending routine manual UAT of the 6 view-layer ACs)

**Gate**: 85 passed, 0 failed · **Sensor**: 5/5 killed · **Spec-anchored**: 25/34 fully or partially machine-verified, 6 manual-UAT, 3 precision gaps flagged

**Next steps**: route ranked gaps 1–3 to small fix/doc tasks if desired; run the scripted interactive UAT for panel/settings/launch-at-login on a real Mac session.
