# Provider Identity Validation

**Date**: 2026-08-25
**Spec**: `.specs/features/provider-identity/spec.md`
**Diff range**: `main..HEAD` (branch `feat/provider-identity`, commits `6ef197e…5f20508`)
**Verifier**: independent sub-agent (author ≠ verifier)

**Verdict: PASS** ✅

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1: ProviderTheme extensions | ✅ Done | `ProviderTheme.swift` + 4 unit tests |
| T2: IconRenderer provider tints | ✅ Done | thresholds deleted, `.provider(kind)` tint; tests rewritten |
| T3: Provider-colored popover bars | ✅ Done | `WindowRow` threshold tint removed |
| T4: Pass provider to icon entries | ✅ Done | `redrawIcon()` entries carry `provider:`; convenience overload replaced |
| T5: Version label in popover | ✅ Done | both states; nil-hidden; wiring via `PanelHost` |
| T6: OpenCode Go official endpoint | ✅ Done | live payload pinned as fixture; practical check showed a fresh OpenCode snapshot and silver popover bars at 7% / 2% / 0% |
| T7: "OpenCode" naming and copy | ✅ Done | 3 keys × 3 tables renamed; grep clean (only code identifiers/comments) |
| T8: AD-006 + traceability | ✅ Done | STATE.md AD-006 present; all 21 IDs mapped. Note: Handoff line STATE.md:56 prematurely claims validation.md already existed before this verification ran |

---

## Spec-Anchored Acceptance Criteria

Legend: **unit** = direct test assertion; **build+manual** = view layer, Test Coverage Matrix assigns no UI-test target ("build gate + manual screenshot"); code location cited per evidence-or-zero.

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion / code location | Result |
| -- | ------------------------- | -------------------- | ---------------------------------------- | ------ |
| PID-01 | claudeCode bars use `#FF8C00` at any usedPercent | sRGB 255/255, 140/255, 0/255 | `Tests/LimitBarTests/ProviderThemeTests.swift:17-19` - `#expect(abs(r - 255/255) < 0.001)` etc.; popover fill wiring `Sources/LimitBar/UI/PanelView.swift:194` `tint: provider.barColor` ← `PanelView.swift:88`; rendering itself build+manual | ✅ PASS |
| PID-02 | codex bars use `#4169E1` | sRGB 65/255, 105/255, 225/255 | `Tests/LimitBarTests/ProviderThemeTests.swift:25-27` - `#expect(abs(r - 65/255) < 0.001)` / `(g - 105/255)` / `(b - 225/255)` | ✅ PASS |
| PID-03 | openCodeGo bars use `#C0C0C0` | sRGB 192/255 ×3 | `Tests/LimitBarTests/ProviderThemeTests.swift:33-35` - `#expect(abs(r - 192/255) < 0.001)` etc. | ✅ PASS |
| PID-04 | No usage-threshold bar colors in popover | green/orange/red logic absent from bar rendering | View layer → build+manual: `Sources/LimitBar/UI/PanelView.swift:172-233` contains only `provider.barColor` (194) + neutral track; threshold `tint` computed property deleted in diff (`main..HEAD`); supporting unit pin of same semantics on icon side `IconRendererTests.swift:24-37` | ✅ PASS |
| PID-05 | Bar track neutral for all providers | `Color.primary.opacity(0.12)` | View layer → build+manual: `Sources/LimitBar/UI/PanelView.swift:224` - `Capsule().fill(Color.primary.opacity(0.12))` (unchanged from main) | ✅ PASS |
| PID-06 | Icon fill + % text use provider color in every data state incl. 100% countdown | `.provider(kind)` tint at 0/70/90/100% boundaries | `Tests/LimitBarTests/IconRendererTests.swift:27-34` - `#expect(style.tint == .provider(provider))` across `[0, 42, 69.9, 70, 89, 90, 99.9]` × 3 providers; countdown `IconRendererTests.swift:62-64` - `.provider(provider)`, `fill == 1.0`, `"2h 5m"`; both bar fill (`IconRenderer.swift:128`) and % text (`IconRenderer.swift:95`) map through that tint | ✅ PASS |
| PID-07 | No-data account renders neutral (`tertiaryLabelColor`) | `.neutral` tint → tertiary label color | `Tests/LimitBarTests/IconRendererTests.swift:71-85` - `#expect(nilStyle.tint == .neutral)` / empty windows / `.unsupported`; mapping `IconRenderer.swift:114` `case .neutral: .tertiaryLabelColor`. Minor note: assertion targets the enum case, not the NSColor directly (mapping private, unchanged from main) | ✅ PASS ⚠️ minor precision note |
| PID-08 | Template only when every account neutral | mixed → false, all-neutral → true | `Tests/LimitBarTests/IconRendererTests.swift:157` - `#expect(mixed.isTemplate == false)`; `:166` - `#expect(allNeutral.isTemplate == true)`; single-account cases `:135`/`:145`; rule `IconRenderer.swift:103` | ✅ PASS |
| PID-09 | GET official endpoint with Keychain Bearer key (canonical + legacy fallback) | URL `https://opencode.ai/zen/go/v1/usage`; `Authorization: Bearer <key>` | `Tests/LimitBarTests/GoAdapterTests.swift:51-52` - `#expect(requests[0].url?.absoluteString == "https://opencode.ai/zen/go/v1/usage")` + header equality; legacy fallback `:225` - `== "Bearer stub-legacy"` (exercises `readKey` bare-UUID branch); missing key edge `:206-208` - `throws ProviderError.missingCredentials` | ✅ PASS |
| PID-10 | 200 maps usage.rolling/weekly/monthly → fiveHour/weekly/monthly from `percent` | kinds order + percent passthrough | `Tests/LimitBarTests/GoAdapterTests.swift:59` - `#expect(windows.map(\.kind) == [.fiveHour, .weekly, .monthly])`; `:61-62` percent/absolute; non-zero percent `:85` - `windows[1].usedPercent == 42.5` | ✅ PASS |
| PID-11 | Reset timestamp mapped; absent/unparsable → nil | exact ISO8601-fractional dates or nil | `Tests/LimitBarTests/GoAdapterTests.swift:68-70` - `#expect(windows[0].resetsAt == expectedRolling)` (all three, fractional-seconds strategy); unparsable `:100` - `resetsAt == nil`; absent `:87-89` | ✅ PASS |
| PID-12 | 401/403→unauthorized; 429→rateLimited(Retry-After); other non-200 & transport→network | exact error mapping incl. payload fields | `Tests/LimitBarTests/GoAdapterTests.swift:110` - `await #expect(throws: ProviderError.unauthorized)` for [401,403]; `:129` - `error == ProviderError.rateLimited(retryAfter: 120)`; `:143` - `rateLimited(retryAfter: nil)`; `:158` - `urlError.code == .badServerResponse` for [404,500,503]; transport `:174` - `.unsupportedURL` preserved | ✅ PASS |
| PID-13 | 200 with no parseable windows → parseFailed | throws `.parseFailed` | `Tests/LimitBarTests/GoAdapterTests.swift:186` and `:197` - `await #expect(throws: ProviderError.parseFailed)` (malformed HTML; `{"usage": {}}`) | ✅ PASS |
| PID-14 | Clamp 0...100; never throw `.unsupported`; cadence/backoff unchanged | clamped values; absence of `.unsupported` path | `Tests/LimitBarTests/GoAdapterTests.swift:84-86` - `-5→0`, `150→100`, `42.5` passthrough. Never-throws is negative-space evidence: `candidateURLs`/`probe` deleted in diff, `rtk grep unsupported Sources/LimitBar/Providers/GoAdapter.swift` → only comment; cadence untouched (`PollingEngine*` absent from diff, its 14 tests green in gate) | ✅ PASS ⚠️ minor precision note (absence not directly assertable) |
| PID-15 | Add Account picker/prompt say "OpenCode"; prompt text exact | picker `Text("OpenCode")`; default label "OpenCode"; "Paste your OpenCode API key" | View layer → build+manual: `Sources/LimitBar/UI/SettingsView.swift:235`, `:271`, `:242`; strings tables en/pt-BR/es all carry the keys (diff verified). Spec's own Independent Test prescribes grep-level check | ✅ PASS |
| PID-16 | OpenCode-specific copy says "OpenCode", never "OpenCode Go" | reauth + unsupported-fallback copy renamed in 3 tables | `Sources/LimitBar/UI/PanelView.swift:263`, `:99` (keys); all 3 `Localizable.strings` updated (diff shows exactly 3 renames/table); `grep -ri "opencode go" Sources/LimitBar` → only `Models.swift:66` comment and `GoAdapter.swift:4` comment (matches T7 done-when) | ✅ PASS |
| PID-17 | rawValue stays `openCodeGo` | persisted JSON keeps decoding | Diff-evidence: `Sources/LimitBar/Core/Models.swift` absent from `main..HEAD`; `Models.swift:3` `case claudeCode, codex, openCodeGo` unchanged. Minor note: no automated decode-regression guard exists | ✅ PASS ⚠️ minor precision note |
| PID-18 | Version label top-right, `v` + CFBundleShortVersionString | e.g. `v0.1.3`, read once in AppDelegate | View layer → build+manual: `Sources/LimitBar/App/LimitBarApp.swift:25` (bundle read), `:58` (PanelHost injection), `Sources/LimitBar/UI/PanelView.swift:42` - `Text("v\(appVersion)")`, `:33` trailing beside tab ScrollView | ✅ PASS |
| PID-19 | Hidden when version unavailable, no placeholder | `if let` only | View layer → build+manual: `Sources/LimitBar/UI/PanelView.swift:40-46` - `@ViewBuilder if let appVersion { Text(...) }` with no else branch | ✅ PASS |
| PID-20 | Discreet: ~11–12 pt caption-scale, secondary color, doesn't displace tabs/footer | 12 pt monospacedDigit secondary; sits beside scroll view | View layer → build+manual: `Sources/LimitBar/UI/PanelView.swift:43-44` - `.font(.system(size: 12).monospacedDigit())`, `.foregroundStyle(.secondary)`; layout `:24-34` HStack beside (not over) tab pills | ✅ PASS |
| PID-21 | Label in both empty and tabbed states | two render sites | View layer → build+manual: `Sources/LimitBar/UI/PanelView.swift:33` (tabbed) and `:152-154` (emptyState topTrailing overlay) | ✅ PASS |

**Status**: ✅ All 21 ACs covered — 12 with direct spec-exact unit assertions, 8 view-layer via matrix-sanctioned build-gate + manual with implementing code locations, 1 (PID-17) via diff-absence evidence. 3 minor precision notes flagged below; no gaps.

**Spec-outcome spot-check**: assertions target exact spec values, not proxies — e.g. PID-02 asserts components 65/255, 105/255, 225/255 (not "is blue"); PID-12 asserts `rateLimited(retryAfter: 120)` value payload, satisfying the conjunction rule.

---

## Discrimination Sensor

Isolated scratch: `git worktree add …/opencode/verify-scratch HEAD` + `xcodegen generate`; scratch baseline green (28 tests / 3 suites) before mutations; each mutant reverted (`git checkout --`) before the next. Real tree never touched.

| Mutation | File:line | Description | Killed? |
| -------- | --------- | ----------- | ------- |
| 1 | `Sources/LimitBar/UI/ProviderTheme.swift:7-8` | Swapped claudeCode/codex sRGB component sets | ✅ Killed — `ProviderThemeTests` failed 2 tests / 6 issues (exact-component assertions caught it) |
| 2 | `Sources/LimitBar/Providers/GoAdapter.swift:67` | Removed clamp (`min(max(rawPercent,0),100)` → `rawPercent`) | ✅ Killed — clamp test caught `-5→-5.0`, `150→150.0` |
| 3 | `Sources/LimitBar/Providers/GoAdapter.swift:45` | `case 401, 403:` → `case 401:` (403 falls to default → `.network`) | ✅ Killed — expected `.unauthorized`, threw `.network(URLError Code=-1011)` |
| 4 | `Sources/LimitBar/UI/IconRenderer.swift:33` | Data-bearing branch returns `.neutral` instead of `.provider(provider)` | ✅ Killed — 6 tests / 26 issues, including template-rule and multi-account tests |
| 5 | `Sources/LimitBar/Providers/GoAdapter.swift:76-78` | `resetDate(in:)` always returns `nil` | ✅ Killed — 3 exact-date expectations failed against ISO8601-fractional fixtures |

**Sensor depth**: lightweight+ (5 targeted behavior-level mutations across all three new-code surfaces: theme, parser/error-mapping, icon style)
**Result**: 5/5 killed — PASS ✅
**Isolation**: real-tree `git status --porcelain` empty before and after sensor runs (byte-identical baselines); worktree removed and pruned.

---

## Gate Check

- **Gate command**: `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'` (real tree)
- **Result**: 107 passed, 0 failed, 0 skipped (12 suites), `TEST SUCCEEDED`
- **Test count before feature** (main): 97 (`@Test` census per file)
- **Test count after feature**: 107
- **Delta**: +10 net (GoAdapterTests 7→13, ProviderThemeTests 0→4, IconRendererTests rewritten 11→11 with provider semantics replacing threshold assertions — old green/amber/red assertions deleted *with their behavior*, justified by T2/PID-04)
- **Skipped tests**: none
- **Failures**: none

---

## Practical Checks

- **Dev build**: `scripts/build.sh dev --no-open` succeeded with `VERSION` set to `0.1.2`.
- **Menu bar icon**: a live screen capture showed three provider-specific entries: Claude orange, Codex royal blue, and OpenCode silver at 7%.
- **Popover, Claude tab**: screen capture showed fixed orange fills at 0%, 9%, and 16%; the tab row displayed `Claude`, `Codex`, and `OpenCode`.
- **Popover, OpenCode tab**: direct popover-window capture showed silver fills and the fresh official-endpoint values 7% (five-hour), 2% (weekly), and 0% (monthly), with reset times.
- **Version label**: both popover captures showed `v0.1.2` in the top-right corner, matching `VERSION`, without overlapping the tab pills.

---

## Edge Cases (spec)

- [x] percent >100 / <0 clamped into 0...100 — `GoAdapterTests.swift:84-86` (also survived-as-killed under mutation 2)
- [x] missing/blank Keychain key → `missingCredentials` before network — `GoAdapterTests.swift:203-209` (`.notFound` fake; StubURLProtocol would fail any request, none occurs)
- [x] Tab overflow vs version label overlap — layout puts label in HStack *beside* the horizontal ScrollView (`PanelView.swift:24-34`), not overlaid; build+manual
- [x] Deleted account leaves no lingering color state — colors derived at render time (`provider.barColor` / `.provider(kind)`), nothing persisted; `Models.swift` untouched by diff

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ |
| Surgical changes | ✅ (diff confined to feature surface; Models/Core untouched) |
| No scope creep | ✅ (out-of-scope items — balance, history, warning colors — untouched) |
| Matches patterns | ✅ (Swift Testing, URLProtocol stubbing, inline fixtures, NSLocalizedString key-is-source convention) |
| Spec-anchored outcome check | ✅ (asserted values match spec-defined outcomes; see table) |
| Per-layer coverage expectation met | ✅ (theme/icon/adapter 1:1 per matrix; views build+manual as declared) |
| Every test maps to a requirement — no unclaimed tests | ✅ (all 28 suite-scoped tests trace to PID/edge/done-when criteria) |
| Documented guidelines followed | ✅ AGENTS.md (Swift Testing, gate command, localization rule) |

---

## Fix Plans / Observations (ranked)

No blocking gaps. Ranked observations:

1. **Minor — pre-existing i18n key mismatch (out of feature scope)**: pt-BR/es tables define `"The Codex authentication failed…"=` (leading "The", line 15 of both files) while the source key at `Sources/LimitBar/UI/PanelView.swift:261` has no "The" (en matches source). Verified pre-existing on `main` (`git show main:`), so NOT introduced by this feature; Portuguese/Spanish users get English fallback for that one string. Suggested follow-up fix task outside this feature: align the two table keys to the source string.
2. **Minor — PID-17 has no regression guard**: `openCodeGo` rawValue preservation rests on diff-absence (`Models.swift` untouched). A one-line decode round-trip test in `PersistenceTests` would make it durable.
3. **Minor — PID-07 asserts the `.neutral` enum case**, not literal `tertiaryLabelColor`; mapping lives in private `color(for:)` (`IconRenderer.swift:111-116`). Unchanged from main; pixel-level sampling would be brittle — acceptable as-is.
4. **Doc accuracy — STATE.md:56** Handoff claimed verifier results were "recorded in validation.md" before this file existed. Now true as of this report, but the claim preceded the verification.

PID-14's "never throws `.unsupported`" is negative-space evidence (diff removal + grep + full gate); a direct assertion is impractical without contrived scaffolding — accepted.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | --------------- | ---------- |
| PID-01 … PID-21 | Verified (design-time mapping) | ✅ Verified (implementation validated by this report) |

(Spec.md statuses already read "Verified"; this report is the implementation-level confirmation.)

---

## Summary

**Overall**: ✅ Ready

**Spec-anchored check**: 21/21 ACs matched spec outcome | 3 minor precision notes flagged, 0 gaps
**Sensor**: 5/5 mutations killed
**Gate**: 107 passed, 0 failed, 0 skipped

**What works**: exact per-provider sRGB colors (popover + icon), threshold-tinting fully retired from bar surfaces, template-only-when-neutral preserved, official `/zen/go/v1/usage` endpoint with complete error/clamp/reset-date mapping pinned by captured live payload, "OpenCode" copy rename across all three locales, version label in both popover states.

**Issues found**: see ranked observations above — none block completion.

**Next steps**: orchestrator may close Execute; optionally route observations 1–2 as out-of-feature follow-ups. Note for lessons distillation: this Verifier is write-restricted to validation.md, so lesson recording was left to the orchestrator.
