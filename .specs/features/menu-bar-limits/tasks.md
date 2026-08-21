# Menu Bar Limits Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/menu-bar-limits/design.md`
**Status**: Draft

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec - confirm before Execute. Guidelines found: none - strong defaults applied (fresh scaffold; AGENTS.md defines no test commands yet). Test framework and commands come from the approved design (AD-002: xcodegen + `xcodebuild`; Swift Testing framework).

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Core domain logic (models, AccountStore, PollingEngine/backoff, icon style decision, interval validator, notification detector) | unit | All branches; 1:1 to spec ACs; every listed edge case has a test | `Tests/LimitBarTests/*Tests.swift` | `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Provider adapters (Claude/Codex/Go parsing + error mapping) | unit | Happy path + every error path (401→unauthorized, 429→rateLimited, parse failure); fixture-driven | `Tests/LimitBarTests/{Claude,Codex,Go}AdapterTests.swift` | same |
| PersistenceController | unit | Round-trip save/load; corrupt-file → nil; atomic replace | `Tests/LimitBarTests/PersistenceTests.swift` | same |
| SwiftUI views (PanelView, SettingsView, app scene) | none | Build gate + scripted manual UAT (menu bar app has no automated e2e without third-party deps) | `Sources/LimitBar/UI/**` | build gate |
| System wrappers live paths (SecItem real keychain, SMAppService registration) | none | Build gate; verified manually in UAT (automation would touch real user credentials/login items) | `Sources/LimitBar/Core/{KeychainStore,LaunchAtLoginController}.swift` | build gate |

## Gate Check Commands

> Generated from codebase - confirm before Execute. No linter configured (zero-dependency decision); Swift 6 strict concurrency in project.yml acts as the static-analysis floor.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests | `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Full | Same as Quick - project has unit tests only | `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Build | After config-only tasks and phase completion | `xcodegen generate && xcodebuild build -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS' && xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |

---

## Execution Plan

Phases are ordered and run sequentially - each phase completes before the next begins, and tasks within a phase execute in order.

Dependency graphs (`A → B` = B depends on A). Tasks still execute in numbered order within each phase.

### Phase 1: Foundation

Project skeleton, domain models, persistence, observable store.

```
T1 → T2
T2 → T3
T2 → T4
T3 → T4
```

### Phase 2: Providers

Keychain utility plus one adapter task per provider.

```
T1 → T5
T2 → T6
T5 → T6
T2 → T7
T2 → T8
T5 → T8
```

### Phase 3: Engine & Icon

Background scheduling and menu bar rendering decisions.

```
T4 → T9
T2 → T10
T4 → T10
```

### Phase 4: Interface

Panel, settings, launch-at-login.

```
T4 → T11
T4 → T12
T5 → T12
T12 → T13
```

### Phase 5: Integration & Polish

App-level wiring and threshold notifications (P3).

```
T9 → T14
T10 → T14
T11 → T14
T12 → T14
T4 → T15
```

---

## Task Breakdown

### T1: Scaffold Xcode project and app skeleton

**What**: Create `project.yml` (app target `limit-bar` with LSUIElement, deployment target macOS 14, Swift 6 strict concurrency, unit test target `limit-barTests`) and a minimal `LimitBarApp` showing a static MenuBarExtra icon; update `.gitignore` to exclude generated `.xcodeproj`.
**Where**: `project.yml`
**Depends on**: None
**Reuses**: Apple template patterns; `.gitignore` already covers xcuserdata
**Requirement**: LIM-01 (infrastructure)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] `xcodegen generate` produces a building project
- [ ] App launches showing a static menu bar icon (manual run) <!-- deferred to UAT: build succeeds and MenuBarExtra scene present -->
- [x] Test target discovered empty-but-runnable
- [x] Gate check passes: build gate (`xcodegen generate && xcodebuild build ...`)
- [x] Test count: 0 tests (scaffold)

**Tests**: none
**Gate**: build

---

### T2: Domain models and provider contract

**What**: Implement `ProviderKind`, `WindowKind`, `LimitWindow`, `Account`, `SnapshotState`, `AccountSnapshot`, `AppState` plus `ProviderError` and the `ProviderAdapter` protocol, all `Codable`/`Sendable`.
**Where**: `Sources/LimitBar/Core/Models.swift`
**Depends on**: T1
**Reuses**: design.md Data Models section verbatim
**Requirement**: LIM-08, LIM-09 (model substrate)

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] All seven types match design field-for-field
- [x] Codable round-trips preserve every field including optional dates/percentages
- [x] Gate check passes: quick gate
- [x] Test count: 8 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T3: PersistenceController

**What**: JSON load/save of `AppState` at Application Support with atomic replace; corrupt/missing file returns nil.
**Where**: `Sources/LimitBar/Core/PersistenceController.swift`
**Depends on**: T2
**Reuses**: T2 models
**Requirement**: LIM-01 (persisted active account + last-good cache)

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] Save→load round-trip identical state (temp-dir injected location)
- [x] Corrupt JSON yields nil without throwing
- [x] Writes are atomic (no partial file observed on simulated failure)
- [x] Gate check passes: quick gate
- [x] Test count: 6 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T4: AccountStore

**What**: `@Observable` MainActor store: account add/remove/update, snapshot map, active-account selection, `apply(FetchResult)` state transitions (fresh/stale/error/unauthorized/unsupported).
**Where**: `Sources/LimitBar/Core/AccountStore.swift`
**Depends on**: T2, T3
**Reuses**: T2 models, T3 persistence seam (protocol-injected)
**Requirement**: LIM-10, LIM-24, LIM-25

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] Removing an account drops its snapshot and clears active selection when needed
- [x] Multiple accounts per provider coexist distinguished by label
- [x] Snapshot state transitions cover all five cases
- [x] Gate check passes: quick gate
- [x] Test count: 10 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T5: KeychainStore

**What**: SecItem-backed secret CRUD under service `limit-bar` with an injectable SecItem seam; maps errSecItemNotFound/user-denied to typed errors.
**Where**: `Sources/LimitBar/Core/KeychainStore.swift`
**Depends on**: T1
**Reuses**: Security framework conventions
**Requirement**: LIM-22

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] set/get/delete round-trip through the injected seam
- [x] Not-found and access-denied OSStatus codes map to distinct typed errors
- [x] Gate check passes: quick gate
- [x] Test count: 6 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T6: ClaudeAdapter

**What**: Adapter that reads the OAuth token from Keychain service `Claude Code-credentials`, calls `api.anthropic.com/api/oauth/usage` (header `anthropic-beta: oauth-2025-04-20`) and parses `five_hour`/`seven_day` into windows.
**Where**: `Sources/LimitBar/Providers/ClaudeAdapter.swift`
**Depends on**: T2, T5
**Reuses**: `ProviderAdapter` protocol (T2), KeychainStore seam (T5), URLProtocol stubbing pattern
**Requirement**: LIM-20, LIM-23

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] Fixture JSON maps to two windows with utilization % and resets_at
- [x] 401→`.unauthorized`, 429→`.rateLimited(retryAfter:)`, malformed body→`.parseFailed`, missing keychain item→`.missingCredentials`
- [x] Request carries Bearer token and beta header (asserted on stubbed request)
- [x] Gate check passes: quick gate
- [x] Test count: 9 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T7: CodexAdapter

**What**: Adapter preferring `codex app-server --stdio` JSON-RPC `account/rateLimits/read`, falling back to `$CODEX_HOME/auth.json` + `chatgpt.com/backend-api/codex/usage`; classifies windows from `limit_window_seconds`.
**Where**: `Sources/LimitBar/Providers/CodexAdapter.swift`
**Depends on**: T2
**Reuses**: `ProviderAdapter` protocol (T2); injectable process-runner and URLProtocol seams
**Requirement**: LIM-21, LIM-23

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] ~18k s window→fiveHour, ≥6-day window→weekly classification from fixtures
- [x] App-server transport failure falls back to auth.json path (verified with stubbed runner)
- [x] Optional `codexHomeOverride` honored when reading auth.json
- [x] Error mapping: 401/403→unauthorized, network→network, bad payload→parseFailed
- [x] Gate check passes: quick gate
- [x] Test count: 10 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T8: GoAdapter (spike)

**What**: Adapter probing candidate OpenCode Go usage endpoints with the Keychain-stored API key; success maps dollar-cap usage to three windows; exhausted candidates return `.unsupported`.
**Where**: `Sources/LimitBar/Providers/GoAdapter.swift`
**Depends on**: T2, T5
**Reuses**: `ProviderAdapter` protocol (T2), KeychainStore (T5), URLProtocol stubbing
**Requirement**: LIM-29, LIM-30

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] Probe sequence documented in code matches design spike list
- [x] Successful fixture yields 5h/weekly/monthly windows vs $12/$30/$60 caps
- [x] All-fail produces `.unsupported` (not error)
- [x] Gate check passes: quick gate
- [x] Test count: 6 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T9: PollingEngine

**What**: Actor scheduling per-account refreshes: base interval (clamped 60–3600 s), ×2 backoff on rateLimited capped 30 min, success/manual-refresh resets backoff, wake-from-sleep catch-up for accounts older than their interval, staleness marking.
**Where**: `Sources/LimitBar/Core/PollingEngine.swift`
**Depends on**: T4
**Reuses**: `ProviderAdapter` protocol (T2), AccountStore apply API (T4), BackoffPolicy extracted pure struct
**Requirement**: LIM-14, LIM-15, LIM-16, LIM-17, LIM-18, LIM-19

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] BackoffPolicy table-driven tests: doubling, 30-min cap, reset-on-success/manual
- [x] Mock-clock loop fires at base interval then backed-off intervals
- [x] Wake catch-up refreshes exactly the stale accounts (predicate unit-tested)
- [x] Failed fetch keeps previous snapshot visible (store untouched on error paths)
- [x] Gate check passes: quick gate
- [x] Test count: 12 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T10: IconRenderer

**What**: Pure style decision (`usage`→tint green <70 / amber 70–89 / red ≥90; blocked→countdown text; no-data→neutral gray) plus NSImage drawing of the mini progress indicator and optional % text.
**Where**: `Sources/LimitBar/UI/IconRenderer.swift`
**Depends on**: T2, T4
**Reuses**: T2 snapshot/window types
**Requirement**: LIM-01, LIM-02, LIM-03, LIM-04, LIM-05, LIM-06

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] Decision function covers boundary values 69.9/70/89/90/100 and nil snapshot
- [x] Countdown formatting renders h/m from resetsAt
- [x] Rendered image is non-nil template image at standard status-bar size
- [x] Gate check passes: quick gate
- [x] Test count: 8 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

### T11: PanelView

**What**: Compact SwiftUI panel: per-account tabs, one labeled bar per plan window (% used, absolute value when present, reset countdown), staleness footer ("updated Xm ago"), refresh button, and empty/setup/error/unsupported tab states.
**Where**: `Sources/LimitBar/UI/PanelView.swift`
**Depends on**: T4
**Reuses**: T2/T4 snapshot states driving view states
**Requirement**: LIM-07, LIM-08, LIM-09, LIM-11, LIM-13, LIM-17, LIM-23

**Tools**:

- MCP: NONE
- Skill: `swiftui-pro`

**Done when**:

- [x] Bar count matches provider window sets (Claude/Codex 2, Go 3)
- [x] All four non-fresh tab states render their designated content
- [x] Fixed compact frame; footer shows relative time from fetchedAt
- [x] Gate check passes: build gate
- [x] Test count: 0 automated (view layer per matrix; UAT script covers)

**Tests**: none
**Gate**: build

---

### T12: SettingsWindow

**What**: Settings UI: account list add/remove/rename with provider picker and CODEX_HOME override field, Go API key SecureField persisted via KeychainStore, displayed-window picker per account, poll-interval field validated 60–3600 s by a pure validator.
**Where**: `Sources/LimitBar/UI/SettingsView.swift`
**Depends on**: T4, T5
**Reuses**: AccountStore APIs (T4), KeychainStore (T5)
**Requirement**: LIM-26, LIM-27, LIM-28, LIM-22, LIM-24, LIM-25

**Tools**:

- MCP: NONE
- Skill: `swiftui-pro`, `swift-testing-pro`

**Done when**:

- [x] IntervalValidator rejects <60, >3600, non-numeric with allowed-range message (unit-tested)
- [x] Adding/removing an account updates store and (for Go) stores/deletes its Keychain secret
- [x] Displayed-window change persists per account
- [x] Gate check passes: quick gate
- [x] Test count: 5 tests pass (validator suite)

**Tests**: unit
**Gate**: quick

---

### T13: Launch-at-login

**What**: LaunchAtLoginController wrapping SMAppService register/unregister/status, wired to the "Start at Login" toggle in SettingsView.
**Where**: `Sources/LimitBar/Core/LaunchAtLoginController.swift`
**Depends on**: T12
**Reuses**: SettingsView (T12) for the toggle binding
**Requirement**: LIM-31, LIM-32

**Tools**:

- MCP: NONE
- Skill: `swiftui-pro`

**Done when**:

- [ ] Toggle on registers, off unregisters, status reflects current SMAppService state (manual verification)
- [ ] Gate check passes: build gate
- [ ] Test count: 0 automated (live system service per matrix)

**Tests**: none
**Gate**: build

---

### T14: App integration

**What**: Wire everything in `LimitBarApp`: MenuBarExtra label bound to IconRenderer(active account snapshot), Esc/outside-click dismissal, tab selection handoff to active account, restore persisted state and cached snapshots at launch, refresh button/menu-item triggering engine refreshAllNow, Settings scene attachment.
**Where**: `Sources/LimitBar/App/LimitBarApp.swift`
**Depends on**: T9, T10, T11, T12
**Reuses**: all prior components
**Requirement**: LIM-01, LIM-07, LIM-10, LIM-12, LIM-18

**Tools**:

- MCP: NONE
- Skill: `swiftui-pro`

**Done when**:

- [ ] Selecting a tab changes the icon source immediately from cached data
- [ ] Esc and outside click close the panel
- [ ] Relaunch restores accounts, snapshots, active account, and interval
- [ ] Manual UAT script from spec ACs executes clean end-to-end
- [ ] Gate check passes: build gate
- [ ] Test count: unchanged (integration is scene-level wiring; store/engine logic already tested)

**Tests**: none
**Gate**: build

---

### T15: Threshold notifications (P3)

**What**: Pure crossing-detector (window crosses 80% once per reset period) plus UNUserNotificationCenter posting; denied permission skips silently.
**Where**: `Sources/LimitBar/Core/NotificationService.swift`
**Depends on**: T4
**Reuses**: T2 windows/resetsAt, T9 fetch results stream
**Requirement**: LIM-33, LIM-34

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [ ] Detector fires exactly once per window per reset period across repeated polls (table-driven tests incl. 79.9→80.1 and reset-period rollover)
- [ ] Denied authorization center short-circuits without error
- [ ] Gate check passes: quick gate
- [ ] Test count: 5 tests pass (no silent deletions)

**Tests**: unit
**Gate**: quick

---

## Phase Execution Map

Phases run in sequence; within a phase, tasks execute in numbered order. Dependency edges are defined once in the Execution Plan graphs above and are not repeated here.

| Order | Phase | Tasks (in order) |
| ----- | ----- | ---------------- |
| 1 | Foundation | T1, T2, T3, T4 |
| 2 | Providers | T5, T6, T7, T8 |
| 3 | Engine & Icon | T9, T10 |
| 4 | Interface | T11, T12, T13 |
| 5 | Integration & Polish | T14, T15 |

Execution is strictly sequential - there is no intra-phase parallelism. A single agent (or batch worker) works one task at a time, in order.

Total tasks: **15** (> ~8) - batch sub-agents will be offered before Execute (~7-task budget ⇒ 2 batches: Phase 1–2, Phases 3–5).

---

## Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: Project scaffold | 1 config + skeleton scene | ✅ Granular |
| T2: Domain models | 1 file, cohesive value types | ✅ Granular |
| T3: PersistenceController | 1 component | ✅ Granular |
| T4: AccountStore | 1 component | ✅ Granular |
| T5: KeychainStore | 1 component | ✅ Granular |
| T6: ClaudeAdapter | 1 component | ✅ Granular |
| T7: CodexAdapter | 1 component (two transports behind one adapter) | ✅ Granular |
| T8: GoAdapter | 1 component | ✅ Granular |
| T9: PollingEngine | 1 actor (+pure policy struct) | ✅ Granular |
| T10: IconRenderer | 1 component (+pure decision fn) | ✅ Granular |
| T11: PanelView | 1 component | ✅ Granular |
| T12: SettingsWindow | 1 component (+pure validator) | ✅ Granular |
| T13: Launch-at-login | 1 controller + toggle wiring | ✅ Granular |
| T14: App integration | 1 scene file wiring | ✅ Granular |
| T15: Notifications | 1 service | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | phase head | ✅ Match |
| T2 | T1 | T1→T2 | ✅ Match |
| T3 | T2 | T2→T3 | ✅ Match |
| T4 | T2, T3 | T2→T3→T4 chain implies both | ✅ Match |
| T5 | T1 | phase head (prior phase) | ✅ Match |
| T6 | T2, T5 | T5→T6 (T2 satisfied earlier) | ✅ Match |
| T7 | T2 | T6→T7 order; dep on earlier phase | ✅ Match |
| T8 | T2, T5 | T7→T8 order; deps earlier phase | ✅ Match |
| T9 | T4 | phase head (earlier phase) | ✅ Match |
| T10 | T2, T4 | T9→T10 order; deps earlier phase | ✅ Match |
| T11 | T4 | phase head (earlier phase) | ✅ Match |
| T12 | T4, T5 | T11→T12 order; deps earlier phases | ✅ Match |
| T13 | T12 | T12→T13 | ✅ Match |
| T14 | T9, T10, T11, T12 | phase head; all earlier phases | ✅ Match |
| T15 | T4 | T14→T15 order; dep earlier phase | ✅ Match |

No dependency points to a later phase. ✅

---

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Config/project | none | none | ✅ OK |
| T2 | Core domain models | unit | unit | ✅ OK |
| T3 | Persistence | unit | unit | ✅ OK |
| T4 | Core domain store | unit | unit | ✅ OK |
| T5 | Core wrapper (seam-tested logic) | unit | unit | ✅ OK |
| T6 | Provider adapter | unit | unit | ✅ OK |
| T7 | Provider adapter | unit | unit | ✅ OK |
| T8 | Provider adapter | unit | unit | ✅ OK |
| T9 | Core engine | unit | unit | ✅ OK |
| T10 | Core decision logic + drawing | unit (decision fn) | unit | ✅ OK |
| T11 | SwiftUI view | none (build + UAT) | none | ✅ OK |
| T12 | View + pure validator | unit (validator) | unit | ✅ OK |
| T13 | System service wrapper | none (live path) | none | ✅ OK |
| T14 | Scene wiring | none (logic pre-tested) | none | ✅ OK |
| T15 | Core notification logic | unit | unit | ✅ OK |

All tasks satisfy matrix requirements. ✅
