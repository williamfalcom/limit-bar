# Provider Identity Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: `.specs/features/provider-identity/design.md`
**Status**: Draft

---

## Test Coverage Matrix

> Generated from codebase, project guidelines, and spec - confirm before Execute. Guidelines found: `AGENTS.md` (Swift Testing, gate commands), `Tests/LimitBarTests/` (Swift Testing `import Testing`, URLProtocol stubbing in `TestSupport.swift`, inline payload fixtures). No UI-test target exists for SwiftUI views — view layer is build-gate + manual screenshot, matching repo practice.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Provider theme colors (`ProviderTheme`) | unit | Exact sRGB components per provider, 1:1 to PID-01…03 | `Tests/LimitBarTests/ProviderThemeTests.swift` | `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Provider identity model (`ProviderKind`) | unit | Persisted raw value for GitHub Copilot, 1:1 to PID-22 | `Tests/LimitBarTests/ModelsTests.swift` | same as above |
| Icon style logic (`IconRenderer.style`) | unit | All branches: provider tints, 100% countdown, neutral no-data, template rule; 1:1 to PID-06…08 | `Tests/LimitBarTests/IconRendererTests.swift` | same as above |
| Provider adapters (`GoAdapter`) | unit | 1:1 to PID-09…14 + edge cases (clamp, missing fields, status codes, Retry-After) | `Tests/LimitBarTests/GoAdapterTests.swift` | same as above |
| Provider adapter (`CopilotAdapter`) | unit | 1:1 to PID-24…26 + framing, inversion, reset, and unlimited-quota edge cases | `Tests/LimitBarTests/CopilotAdapterTests.swift` | same as above |
| SwiftUI views (`PanelView`, `SettingsView`) | none | Build gate + manual screenshot check (repo has no UI test target) | - | build gate |
| App wiring (`LimitBarApp`) | none | Build gate (logic exercised via IconRenderer unit tests) | - | build gate |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After tasks with unit tests | `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Build | After view/wiring/copy-only tasks | `xcodegen generate && xcodebuild build -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |
| Full | Phase completion and final close-out | `xcodegen generate && xcodebuild build -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS' && xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` |

---

## Execution Plan

Phases are ordered and run sequentially - each phase completes before the next begins. The arrows below are the full dependency graph (intra-phase and cross-phase):

```
T1 → T2
T1 → T3
T2 → T4
T3 → T5
T3 → T7 (cross-phase)
T5 → T7 (cross-phase)
T7 → T8 (cross-phase)
T8 → T9 (cross-phase)
T9 → T10
T10 → T11
T11 → T12
```

### Phase 1: Provider color identity

Foundation for all visual changes: color source of truth (T1), then its two consumers (T2 icon renderer, T3 popover bars), then wiring (T4) and the version label (T5).

### Phase 2: OpenCode real usage

Reworks the spike adapter onto the official endpoint with its tests. Single task: T6.

### Phase 3: Naming and copy

"OpenCode" naming across UI + the three localization tables. T7 needs T3 and T5 from Phase 1.

### Phase 4: Close-out

Decision log, traceability, final gate. T8 needs T7.

### Phase 5: GitHub Copilot Premium requests

Adds the fourth provider, its fixed color, real Premium requests quota, and UI wiring. T9 starts after the existing provider-identity feature; T12 closes this extension.

---

## Task Breakdown

### T1: Create ProviderTheme color extensions

**What**: New `ProviderKind` extensions exposing per-provider accent colors (claudeCode `#FF8C00`, codex `#4169E1`, openCodeGo `#C0C0C0` as exact sRGB components) for AppKit (`barNSColor`) and SwiftUI (`barColor`).
**Where**: `Sources/LimitBar/UI/ProviderTheme.swift` (new file; xcodegen picks it up automatically)
**Depends on**: None
**Reuses**: Nothing (leaf utility; consumed by T2/T3)
**Requirement**: PID-01, PID-02, PID-03

**Tools**:

- MCP: NONE
- Skill: `swift-language`

**Done when**:

- [x] `ProviderKind.barNSColor: NSColor` returns `NSColor(srgbRed:green:blue:alpha:)` with exact components (255,140,0 / 65,105,225 / 192,192,192, alpha 1)
- [x] `ProviderKind.barColor: Color` bridges from `barNSColor`
- [x] Unit tests assert sRGB components per provider (red/green/blue ±0.001 after conversion)
- [x] Quick gate passes; test count ≥ 3 new (no silent deletions)

**Tests**: unit
**Gate**: quick

**Commit**: `feat(ui): add per-provider accent color extensions`

---

### T2: Provider tints in IconRenderer

**What**: Replace usage-threshold tinting with provider-driven tinting: `Style.Tint` gains `.provider(ProviderKind)` (drops `.green/.amber/.red`), `style(for:window:provider:now:)` takes the provider, 100%-countdown branch keeps behavior with provider tint, `color(for:)` maps via `barNSColor`, threshold constants removed.
**Where**: `Sources/LimitBar/UI/IconRenderer.swift`
**Depends on**: T1
**Reuses**: existing `style`/`image`/`drawBar` structure and `formatCountdown`
**Requirement**: PID-06, PID-07, PID-08

**Tools**:

- MCP: NONE
- Skill: `swift-testing-pro`

**Done when**:

- [x] `style` returns `.provider(kind)` tint in every data-bearing branch (normal, ≥70%, ≥90%, 100% countdown) — no usage-based color switch remains
- [x] Neutral branch (nil snapshot / empty windows) unchanged; `isTemplate` true only when all tints neutral
- [x] `image(for:)` entries tuple gains `provider:` field (call site fixed in T4; keep a convenience overload compiling until T4 lands in the same phase)
- [x] `IconRendererTests` rewritten: per-provider tint at low/mid/high/100% usage, neutral cases, template rule; old green/amber/red assertions removed with their behavior
- [x] Quick gate passes

**Tests**: unit
**Gate**: quick

**Commit**: `feat(ui): provider tints in menu bar icon renderer`

---

### T3: Provider-colored popover bars

**What**: `WindowRow` gains `provider: ProviderKind`; its `tint` becomes `provider.barColor` (threshold logic deleted); `activeTabContent` passes `activeProvider`'s kind; bar track stays `Color.primary.opacity(0.12)`.
**Where**: `Sources/LimitBar/UI/PanelView.swift`
**Depends on**: T1
**Reuses**: `LimitProgressBar` unchanged; `activeProvider` accessor (`PanelView.swift:98`)
**Requirement**: PID-01, PID-02, PID-03, PID-04, PID-05

**Tools**:

- MCP: NONE
- Skill: `swiftui-pro`

**Done when**:

- [x] Bar fill color equals provider color at 0%, 70%, 90%, 100% usage (no `.green/.orange/.red` references left in `WindowRow`)
- [x] Track capsule unchanged; accessibility label unchanged
- [x] Build gate passes (view layer: build + manual screenshot per matrix)

**Tests**: none
**Gate**: build

**Commit**: `feat(ui): provider-colored bars in popover`

---

### T4: Pass provider to icon entries

**What**: `AppDelegate.redrawIcon()` includes `provider: account.provider` in each entry tuple passed to `IconRenderer.image(for:)`, dropping T2's temporary convenience overload if present.
**Where**: `Sources/LimitBar/App/LimitBarApp.swift`
**Depends on**: T2
**Reuses**: existing `redrawIcon`/observation loop (`LimitBarApp.swift:79-84`)
**Requirement**: PID-06

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] Icon renders per-provider colors for all configured accounts (manual: two accounts → two differently colored bars)
- [x] No compiler warnings; build gate passes

**Tests**: none
**Gate**: build

**Commit**: `feat(app): feed account provider into icon renderer`

---

### T5: Version label in popover

**What**: `PanelView` gains `appVersion: String?` and renders `v<version>` (≈12 pt, `.secondary`, monospacedDigit) beside the tab scroll view (HStack, never overlapping pills) and top-trailing in the empty state; hidden when nil. `AppDelegate` reads `CFBundleShortVersionString` once and passes it through `PanelHost`. Compile-coupled call sites (`PanelHost` in `LimitBarApp.swift`) updated in the same task.
**Where**: `Sources/LimitBar/UI/PanelView.swift` (plus `Sources/LimitBar/App/LimitBarApp.swift` `PanelHost` call site — compile coupling, per design "App wiring")
**Depends on**: T3
**Reuses**: VERSION→`MARKETING_VERSION`→Info.plist chain (no build changes); `PanelHost` wrapper
**Requirement**: PID-18, PID-19, PID-20, PID-21

**Tools**:

- MCP: NONE
- Skill: `swiftui-pro`

**Done when**:

- [x] Popover shows `v<VERSION>` top-right in tabbed AND empty states; matches `VERSION` file in dev build
- [x] Label hidden (no placeholder) when `appVersion` is nil; tab row never overlaps the label
- [x] Build gate passes + manual screenshot check

**Tests**: none
**Gate**: build

**Commit**: `feat(ui): show app version in popover corner`

---

### T6: OpenCode Go quota from official endpoint

**What**: Rework `GoAdapter`: single `usageURL` (`https://opencode.ai/zen/go/v1/usage`), proper status mapping (200→parse, 401/403→`.unauthorized`, 429→`.rateLimited(Retry-After)`, else `.network`), parse `usage.{rolling,weekly,monthly}` → `fiveHour/weekly/monthly` with `percent` (Int/Double) clamped 0...100, optional reset field → `resetsAt` (nil fallback), zero windows → `.parseFailed`; remove `candidateURLs`/`dollarCaps`/`periodKeys`; never throw `.unsupported`.
**Where**: `Sources/LimitBar/Providers/GoAdapter.swift`
**Depends on**: None
**Reuses**: `readKey`/`apiKey` (`GoAdapter.swift:70-80`), `TestSupport.stubbedSession`, inline-fixture test style from `ClaudeAdapterTests`
**Requirement**: PID-09, PID-10, PID-11, PID-12, PID-13, PID-14

**Tools**:

- MCP: NONE
- Skill: `swift-testing-pro`

**Done when**:

- [x] Live payload captured first (read key from Keychain `go.api-key.<uuid>` via `/usr/bin/security find-generic-password` or ask user; `curl -H "Authorization: Bearer <key>" https://opencode.ai/zen/go/v1/usage`) and pinned as inline test fixture; reset/dollar field names confirmed or explicitly defaulted to nil
- [x] Parser maps rolling/weekly/monthly with clamped percent; missing/blank key → `.missingCredentials` preserved
- [x] Error mapping tests: 401, 403, 429 (with/without Retry-After), 500, transport error, malformed 200, empty usage object
- [x] `GoAdapterTests` rewritten (spike URL tests removed with their behavior); quick gate passes
- [x] Manual: OpenCode tab shows real percentages within one poll cycle

**Tests**: unit
**Gate**: quick

**Commit**: `feat(providers): fetch OpenCode Go quota from official endpoint`

---

### T7: "OpenCode" naming and copy

**What**: Rename user-facing "OpenCode Go" copy to "OpenCode": Add Account picker/prompt/secure-field (`SettingsView.swift:235,242,271`), reauth instructions + unsupported fallback text and the double-`NSLocalizedString` fix (`PanelView.swift:84,87,250,258`), and the changed English keys updated in all three `Localizable.strings` tables (en, pt-BR, es).
**Where**: `Sources/LimitBar/UI/SettingsView.swift` (cohesive copy rename spans `PanelView.swift` + 3 `.strings` tables — one atomic rename)
**Depends on**: T3, T5
**Reuses**: existing `NSLocalizedString` key-is-source-string convention (AGENTS.md)
**Requirement**: PID-15, PID-16, PID-17

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] No user-facing "OpenCode Go" remains in the three tables or the touched views (`grep -ri "opencode go" Sources/LimitBar/Resources Sources/LimitBar/UI` returns only code identifiers/comments, not UI copy)
- [x] `ProviderKind.openCodeGo` identifier and persisted rawValue untouched
- [x] All three tables carry the changed keys (missing-key fallback never triggered)
- [x] Build gate passes

**Tests**: none
**Gate**: build

**Commit**: `chore(ui): rename OpenCode Go copy to OpenCode`

---

### T8: Decision log, traceability, final gate

**What**: Append AD-006 (provider-identity color semantics supersedes menu-bar-limits usage-color language; OpenCode Go usage now official endpoint behind `ProviderAdapter`) to `.specs/STATE.md`; fill spec Requirement Traceability statuses; update Handoff.
**Where**: `.specs/STATE.md` (plus `.specs/features/provider-identity/spec.md` traceability table)
**Depends on**: T7
**Reuses**: STATE.md decision format (AD-001…005)
**Requirement**: PID-01…PID-21 (traceability closure)

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [x] AD-006 recorded with Decision/Reason/Trade-off/Scope/Date/Status
- [x] All 21 requirement IDs mapped to tasks with statuses updated
- [x] Full gate passes: `xcodegen generate && xcodebuild build … && xcodebuild test …`

**Tests**: none
**Gate**: full

**Commit**: `docs(specs): record AD-006 and close provider-identity traceability`

---

### T9: Add GitHub Copilot provider identity

**What**: Add `ProviderKind.githubCopilot` with persisted raw value `githubCopilot`, exact slate-blue `#6A5ACD` theme, and exhaustive picker/label/icon/reauth switch cases so the new provider can render.
**Where**: `Sources/LimitBar/Core/Models.swift`, `Sources/LimitBar/UI/ProviderTheme.swift`, `Sources/LimitBar/UI/SettingsView.swift`, `Sources/LimitBar/UI/PanelView.swift`, `Tests/LimitBarTests/ModelsTests.swift`, `Tests/LimitBarTests/ProviderThemeTests.swift`
**Depends on**: T8
**Reuses**: Existing `ProviderKind` persistence and theme tests
**Requirement**: PID-22, PID-23

**Tools**:

- MCP: NONE
- Skill: `swift-language`, `swift-testing-pro`

**Done when**:

- [x] `ProviderKind.githubCopilot.rawValue` is exactly `githubCopilot` and survives the existing model contract
- [x] `ProviderKind.barNSColor` returns sRGB `(106/255, 90/255, 205/255)` and `barColor` bridges it
- [x] Account picker and all provider labels include "GitHub Copilot"; no existing provider raw values change
- [x] Unit tests assert the raw value and exact color components
- [x] Quick gate passes

**Tests**: unit
**Gate**: quick

**Commit**: `feat(ui): add GitHub Copilot provider identity`

---

### T10: Fetch Copilot Premium requests quota

**What**: Add `CopilotAdapter` using the installed CLI's `--headless --no-auto-update --stdio` JSON-RPC transport. Complete `connect`, request `account.getQuota`, parse only `premium_interactions`, invert `remainingPercentage` into consumed `usedPercent`, clamp, and map `resetDate`.
**Where**: `Sources/LimitBar/Providers/CopilotAdapter.swift`, `Tests/LimitBarTests/CopilotAdapterTests.swift`
**Depends on**: T9
**Reuses**: `ProviderAdapter`, `LimitWindow`, `ProviderError`, `CodexAppServerClient` process/CLI patterns, Swift Testing
**Requirement**: PID-24, PID-25, PID-26

**Tools**:

- MCP: NONE
- Skill: `swift-testing-pro`

**Done when**:

- [x] The live CLI transport sends framed `connect` then `account.getQuota` requests and returns the structured quota response
- [x] `premium_interactions.remainingPercentage` maps to one monthly window with `usedPercent = 100 - remainingPercentage`, clamp 0...100, and parseable `resetDate` mapped to `resetsAt`
- [x] Unlimited `chat`/`completions` are ignored; missing Premium data throws `.parseFailed`
- [x] CLI/transport errors map to `.network`; RPC error maps to `.unauthorized`; malformed response maps to `.parseFailed`
- [x] Unit tests cover framing/parser, 82.5% real-style inversion, boundaries, reset optionality, ignored quotas, and all failures
- [x] Quick gate passes

**Tests**: unit
**Gate**: quick

**Commit**: `feat(providers): fetch GitHub Copilot Premium requests quota`

---

### T11: Wire Copilot adapter and account flow

**What**: Register `CopilotAdapter` in `AppDelegate`, feed it to `PollingEngine`, and make the existing account picker create a GitHub Copilot account without an API-key field. Verify the existing provider-colored icon/popover paths accept the fourth provider.
**Where**: `Sources/LimitBar/App/LimitBarApp.swift`, `Sources/LimitBar/UI/SettingsView.swift`, `Sources/LimitBar/UI/PanelView.swift`
**Depends on**: T10
**Reuses**: Existing adapter dictionary, polling cadence, provider-colored `IconRenderer` and `WindowRow`
**Requirement**: PID-22, PID-23, PID-24

**Tools**:

- MCP: NONE
- Skill: `swiftui-pro`

**Done when**:

- [x] `AppDelegate` registers `.githubCopilot: CopilotAdapter()` and refreshes it through the normal polling path
- [x] Adding a GitHub Copilot account requires no API-key field and uses the CLI's existing login
- [x] The Copilot tab and icon use `#6A5ACD` through the existing provider theme path at any usage level
- [x] Build gate passes

**Tests**: none
**Gate**: build

**Commit**: `feat(app): wire GitHub Copilot quota provider`

---

### T12: Close GitHub Copilot extension

**What**: Record the Copilot quota decision in the feature docs, update all PID-22…PID-27 traceability statuses, update Handoff, and run the full gate. The independent Verifier then writes the final extension validation report.
**Where**: `.specs/STATE.md`, `.specs/features/provider-identity/spec.md`, `.specs/features/provider-identity/tasks.md`
**Depends on**: T11
**Reuses**: Existing AD-006/validation format and full gate
**Requirement**: PID-22…PID-27

**Tools**:

- MCP: NONE
- Skill: `tlc-spec-driven`

**Done when**:

- [x] Copilot Premium requests decision is recorded with source, inversion, and failure-state scope
- [x] All 27 requirement IDs are mapped to tasks with statuses updated
- [x] Full gate passes: `xcodegen generate && xcodebuild build … && xcodebuild test …`
- [x] Independent Verifier reports PASS and `validate_state.py provider-identity` passes

**Tests**: none
**Gate**: full

**Commit**: `docs(specs): close GitHub Copilot Premium requests extension`

---

## Phase Execution Map

Visual representation of task ordering. Phases run in sequence; inside Phase 1 the dependency graph branches:

```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5

Phase 1:  T1 → T2 → T4        (theme → icon renderer tints → icon wiring)
          T1 → T3 → T5        (theme → popover bars → version label)
Phase 2:  T6
Phase 3:  T7                  (needs T3 + T5)
Phase 4:  T8                  (needs T7)
Phase 5:  T9 → T10 → T11 → T12
```

Execution is strictly sequential. Total: 12 tasks → continuation remains inline because the user requested this extension in the existing PR.

---

## Task Granularity Check

| Task | Scope | Status |
| ------------------------------- | ------------- | ------------ |
| T1: ProviderTheme extensions | 1 file (new) | ✅ Granular |
| T2: IconRenderer provider tints | 1 file + its tests | ✅ Granular |
| T3: Popover bar tint | 1 file | ✅ Granular |
| T4: Icon entries wiring | 1 file | ✅ Granular |
| T5: Version label end-to-end | 1 view + compile-coupled call site | ✅ Granular (compile-coupling merge per tasks.md rule) |
| T6: GoAdapter rework + tests | 1 file + its tests | ✅ Granular |
| T7: Copy rename | 1 cohesive rename across views + 3 tables | ✅ Granular (atomic rename) |
| T8: STATE/traceability close-out | 2 spec docs | ✅ Granular |
| T9: Copilot provider identity | model/theme + exhaustive switch cases + tests | ✅ Granular |
| T10: Copilot adapter + tests | 1 file + its tests | ✅ Granular |
| T11: Copilot app wiring | 3 compile-coupled app/UI files | ✅ Granular (compile coupling) |
| T12: Copilot docs/close-out | 3 spec docs | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ---------------------- | ------------- | ------ |
| T1 | None | — (graph root) | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T1 | T1 → T3 | ✅ Match |
| T4 | T2 | T2 → T4 | ✅ Match |
| T5 | T3 | T3 → T5 | ✅ Match |
| T6 | None | — (phase head) | ✅ Match |
| T7 | T3, T5 | T3 → T7, T5 → T7 (cross-phase) | ✅ Match |
| T8 | T7 | T7 → T8 (cross-phase) | ✅ Match |
| T9 | T8 | T8 → T9 (cross-phase) | ✅ Match |
| T10 | T9 | T9 → T10 | ✅ Match |
| T11 | T10 | T10 → T11 | ✅ Match |
| T12 | T11 | T11 → T12 | ✅ Match |

---

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | --------------------------- | --------------- | --------- | ------ |
| T1 | Provider theme colors | unit | unit | ✅ OK |
| T2 | Icon style logic | unit | unit | ✅ OK |
| T3 | SwiftUI view | none | none | ✅ OK |
| T4 | App wiring | none | none | ✅ OK |
| T5 | SwiftUI view + wiring | none | none | ✅ OK |
| T6 | Provider adapter | unit | unit | ✅ OK |
| T7 | SwiftUI view + resources | none | none | ✅ OK |
| T8 | Spec docs | none | none | ✅ OK |
| T9 | Provider model/theme | unit | unit | ✅ OK |
| T10 | Provider adapter | unit | unit | ✅ OK |
| T11 | SwiftUI/app wiring | none | none | ✅ OK |
| T12 | Spec docs | none | none | ✅ OK |
