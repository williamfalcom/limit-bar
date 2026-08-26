# Provider Identity Validation

**Date**: 2026-08-25
**Spec**: `.specs/features/provider-identity/spec.md`
**Diff range**: `main..HEAD` (`6ef197e..3809a6f`); Copilot extension commits `9369b4f..3809a6f`
**Verifier**: independent sub-agent (author != verifier)

**Verdict: PASS**

This verification covers the GitHub Copilot Premium requests extension (PID-22..PID-27) and retains the prior PID-01..PID-21 evidence below. No code or test files were changed during verification.

---

## Task Completion

| Task | Status | Evidence / notes |
| ---- | ------ | ---------------- |
| T1: ProviderTheme extensions | Done | `ProviderTheme.swift` + 4 prior exact-color tests |
| T2: IconRenderer provider tints | Done | Thresholds deleted, `.provider(kind)` tint; tests rewritten |
| T3: Provider-colored popover bars | Done | `WindowRow` threshold tint removed |
| T4: Pass provider to icon entries | Done | `redrawIcon()` entries carry `provider:` |
| T5: Version label in popover | Done | Both states; nil-hidden; wiring via `PanelHost` |
| T6: OpenCode Go official endpoint | Done | Live payload fixture, endpoint/error/clamp/reset evidence retained |
| T7: OpenCode naming and copy | Done | Three keys in all three tables; grep clean except code identifiers/comments |
| T8: AD-006 + traceability | Done | STATE.md AD-006 present; PID-01..PID-21 mapped |
| T9: GitHub Copilot provider identity | Done | Raw value, exact theme, picker, labels, and old raw values checked |
| T10: Copilot Premium requests adapter | Done | Framing, parser, inversion, clamp, reset, quota filtering, and failures checked |
| T11: Copilot adapter/account flow | Done | Adapter registered; no API-key field; existing provider paths compile |
| T12: Copilot extension close-out | Done | AD-007 and PID-22..PID-27 traceability present; independent verification is this report |

---

## Spec-Anchored Acceptance Criteria

Legend: **unit** means a direct test assertion. **build + practical** means source implementation plus the build gate and practical check, because the project has no UI-test target (tasks.md:18-27).

### Prior PID-01..PID-21 Evidence

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion / code location | Result |
| -- | ------------------------- | ------------------- | ---------------------------------------- | ------ |
| PID-01 | claudeCode bars use `#FF8C00` at any usedPercent | sRGB 255/255, 140/255, 0/255 | `Tests/LimitBarTests/ProviderThemeTests.swift:17-19` - `#expect(abs(r - 255/255) < 0.001)` etc.; popover fill wiring `Sources/LimitBar/UI/PanelView.swift:194` `tint: provider.barColor` from `PanelView.swift:88`; rendering is build + practical | PASS |
| PID-02 | codex bars use `#4169E1` | sRGB 65/255, 105/255, 225/255 | `Tests/LimitBarTests/ProviderThemeTests.swift:25-27` - `#expect(abs(r - 65/255) < 0.001)` / `(g - 105/255)` / `(b - 225/255)` | PASS |
| PID-03 | openCodeGo bars use `#C0C0C0` | sRGB 192/255 x3 | `Tests/LimitBarTests/ProviderThemeTests.swift:33-35` - `#expect(abs(r - 192/255) < 0.001)` etc. | PASS |
| PID-04 | No usage-threshold bar colors in popover | Green/orange/red logic absent from bar rendering | `Sources/LimitBar/UI/PanelView.swift:172-233` contains `provider.barColor` at `:194` and neutral track; threshold `tint` computed property deleted in `main..HEAD`; icon-side semantics are pinned by `IconRendererTests.swift:24-37` | PASS |
| PID-05 | Bar track neutral for all providers | `Color.primary.opacity(0.12)` | `Sources/LimitBar/UI/PanelView.swift:224` - `Capsule().fill(Color.primary.opacity(0.12))`; build + practical | PASS |
| PID-06 | Icon fill + percent text use provider color in every data state, including 100% countdown | `.provider(kind)` tint at boundaries and countdown | `Tests/LimitBarTests/IconRendererTests.swift:27-34` - `#expect(style.tint == .provider(provider))` across `[0, 42, 69.9, 70, 89, 90, 99.9]` x 3 providers; countdown `:62-64`; fill/text mappings `Sources/LimitBar/UI/IconRenderer.swift:95,128` | PASS |
| PID-07 | No-data account renders neutral (`tertiaryLabelColor`) | `.neutral` tint maps to tertiary label color | `Tests/LimitBarTests/IconRendererTests.swift:71-85` - nil/empty/unsupported styles assert `.neutral`; mapping `Sources/LimitBar/UI/IconRenderer.swift:111-115` | PASS; prior precision note retained: test asserts the enum case, not the private NSColor directly |
| PID-08 | Template only when every account is neutral | Mixed is false; all-neutral is true | `Tests/LimitBarTests/IconRendererTests.swift:157` and `:166`; single-account cases `:135`/`:145`; rule `Sources/LimitBar/UI/IconRenderer.swift:103` | PASS |
| PID-09 | GET official endpoint with Keychain Bearer key, canonical and legacy fallback | Official URL and `Authorization: Bearer <key>` | `Tests/LimitBarTests/GoAdapterTests.swift:51-52` exact URL/header; legacy fallback `:225`; missing key `:206-208` asserts `missingCredentials` | PASS |
| PID-10 | 200 maps rolling/weekly/monthly to fiveHour/weekly/monthly | Correct kinds and percent values | `Tests/LimitBarTests/GoAdapterTests.swift:59` kinds; `:61-62` fields; `:85` exact `42.5` value | PASS |
| PID-11 | Reset timestamp maps; absent/unparsable maps to nil | Exact dates or nil | `Tests/LimitBarTests/GoAdapterTests.swift:68-70` exact dates; unparsable `:100`; absent `:87-89` | PASS |
| PID-12 | Status and transport errors map exactly | 401/403 unauthorized; 429 rateLimited with Retry-After; other/transport network | `Tests/LimitBarTests/GoAdapterTests.swift:110` unauthorized; `:129` `rateLimited(retryAfter: 120)`; `:143` nil retry; `:158` bad-server-response network; `:174` transport URL error | PASS |
| PID-13 | 200 with no parseable windows maps to parseFailed | `ProviderError.parseFailed` | `Tests/LimitBarTests/GoAdapterTests.swift:186` and `:197` exact throws for malformed and empty usage | PASS |
| PID-14 | Clamp 0...100; never throw unsupported; cadence/backoff unchanged | Clamped values and no unsupported GoAdapter path | `Tests/LimitBarTests/GoAdapterTests.swift:84-86` exact `-5 -> 0`, `150 -> 100`, `42.5`; candidate probe path deleted in diff; PollingEngine is absent from diff and its tests passed | PASS; prior precision note retained: unsupported absence is negative-space evidence |
| PID-15 | Add Account picker/prompt say OpenCode | Picker, default label, and API-key prompt use OpenCode | `Sources/LimitBar/UI/SettingsView.swift:235`, `:271`, `:242`; all three localization tables carry changed keys | PASS |
| PID-16 | OpenCode-specific copy says OpenCode, not OpenCode Go | Reauth and fallback copy renamed in all locales | `Sources/LimitBar/UI/PanelView.swift:263`, `:99`; all three tables updated; grep finds only code identifiers/comments | PASS |
| PID-17 | rawValue stays `openCodeGo` | Existing persisted JSON continues decoding | `Sources/LimitBar/Core/Models.swift:3` unchanged for this value; absent from prior feature diff | PASS; prior precision note retained: no dedicated decode-regression guard |
| PID-18 | Version label is top-right, `v` + CFBundleShortVersionString | Runtime value formatted as `v<version>` | `Sources/LimitBar/App/LimitBarApp.swift:25` reads bundle value and `:58-59` injects it; `Sources/LimitBar/UI/PanelView.swift:42` formats text; `:24-34` places it beside tabs | PASS |
| PID-19 | Version unavailable hides label without placeholder | No `else` placeholder | `Sources/LimitBar/UI/PanelView.swift:40-46` uses `if let appVersion` only | PASS |
| PID-20 | Version label is discreet and does not displace controls | 12 pt monospaced, secondary, beside scroll view | `Sources/LimitBar/UI/PanelView.swift:43-44`; layout `:24-34`; build + prior practical screenshot | PASS |
| PID-21 | Version label appears in empty and tabbed states | Two render sites | `Sources/LimitBar/UI/PanelView.swift:33` tabbed and `:152-154` empty-state overlay | PASS |

Prior status: all 21 criteria were covered, with the three precision notes explicitly retained above. Prior evidence was based on the prior report and remains consistent with the current source and full gate.

### Copilot PID-22..PID-27 Evidence

| ID | Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + exact assertion / implementation | Result |
| -- | ------------------------- | ------------------- | ---------------------------------------------- | ------ |
| PID-22 | Persist provider as `githubCopilot` and display `GitHub Copilot` in picker | Exact raw value `githubCopilot`; exact picker/name text | `Tests/LimitBarTests/ModelsTests.swift:20` - `#expect(ProviderKind.githubCopilot.rawValue == "githubCopilot")`; `Sources/LimitBar/Core/Models.swift:3` declares `ProviderKind: String, Codable` with `githubCopilot`; picker `Sources/LimitBar/UI/SettingsView.swift:233-237` contains `Text("GitHub Copilot").tag(ProviderKind.githubCopilot)`; default label `:269-275` returns `"GitHub Copilot"`; no API-key field for this provider at `:243-245`; build gate compiled the path | PASS; precision gap G1 |
| PID-23 | Copilot bars and icon use exact `#6A5ACD` regardless of usage | sRGB 106/255, 90/255, 205/255; both existing render paths use provider tint | `Tests/LimitBarTests/ProviderThemeTests.swift:38-43` - exact component `#expect` expressions; bridge assertion `:46-50` - `#expect(kind.barColor == Color(nsColor: kind.barNSColor))`; source `Sources/LimitBar/UI/ProviderTheme.swift:10,14-15`; popover `Sources/LimitBar/UI/PanelView.swift:194`; icon provider mapping `Sources/LimitBar/UI/IconRenderer.swift:67,95,113,128`; provider carried by app `Sources/LimitBar/App/LimitBarApp.swift:83-91`; build gate compiled all paths | PASS; precision gap G2 |
| PID-24 | Refresh launches installed CLI, completes `connect`, then requests `account.getQuota` using existing login | `copilot --headless --no-auto-update --stdio`; length-delimited connect then quota RPC | Command assertion `Tests/LimitBarTests/CopilotAdapterTests.swift:134-136` - `#expect(CopilotAppServerClient.commandArguments == ["--headless", "--no-auto-update", "--stdio"])`; framing assertion `:139-149` checks `parts.count == 2`, exact UTF-8 length, and exact `account.getQuota` JSON body; implementation `Sources/LimitBar/Providers/CopilotAdapter.swift:62,64-94` launches located `copilot`, writes connect at `:89`, quota at `:90`, reads both at `:91-93`; independent smoke used the installed `copilot` 1.0.80 and returned `kind=monthly usedPercent=19.799999999999997 hasReset=true` | PASS; precision gap G3 |
| PID-25 | Premium quota maps to one monthly consumed percentage with reset date | One `.monthly`; `usedPercent = 100 - remainingPercentage`, clamp 0...100; parse `resetDate` | `Tests/LimitBarTests/CopilotAdapterTests.swift:32-43` exact one-window, `.monthly`, `17.5`, nil absolute, and ISO8601 fractional reset; boundaries `:61-75` assert `-25 -> 100` and `125 -> 0`; implementation `Sources/LimitBar/Providers/CopilotAdapter.swift:32-44` selects premium, inverts/clamps at `:38`, and maps reset at `:43`; optional reset `:77-87` asserts nil | PASS |
| PID-26 | Map CLI/transport to network, auth RPC to unauthorized, malformed/missing premium to parseFailed | Exact `ProviderError` categories | Missing premium `Tests/LimitBarTests/CopilotAdapterTests.swift:89-100` exact `throws: ProviderError.parseFailed`; RPC `:103-109` exact `throws: ProviderError.unauthorized`; malformed `:112-117` exact parseFailed; injected transport `:119-131` asserts `.network` and `.cannotConnectToHost`; code `Sources/LimitBar/Providers/CopilotAdapter.swift:15-21` preserves ProviderError and maps other errors to network, `:29-30` maps RPC error, `:25-36` maps malformed/missing premium | PASS; precision gap G4 |
| PID-27 | Presentation includes finite Premium requests only | Only `premium_interactions`; no chat/completions windows | `Tests/LimitBarTests/CopilotAdapterTests.swift:45-59` exact `windows.map(\.kind) == [.monthly]` and `usedPercent == 10` despite chat/completions; only premium is selected by `Sources/LimitBar/Providers/CopilotAdapter.swift:32-35`; missing premium remains parseFailed at `:35-36` | PASS |

**Extension status**: 6/6 Copilot criteria match their spec-defined outcomes. Four non-blocking precision gaps are ranked below; none is an observed behavior failure.

---

## New Task Done-When Checks

| Task | Done-when criterion | Evidence | Result |
| ---- | ------------------ | -------- | ------ |
| T9 | `githubCopilot.rawValue` is exact and model contract remains Codable | `ModelsTests.swift:17-20` asserts all four provider raw values, including `githubCopilot`; `Models.swift:3` is `String, Codable` | PASS |
| T9 | Exact Copilot sRGB theme and bridge | `ProviderThemeTests.swift:38-50` asserts all three components and `barColor` bridge; `ProviderTheme.swift:10,14-15` implements it | PASS |
| T9 | Picker and provider labels include GitHub Copilot; existing raw values unchanged | `SettingsView.swift:233-237,269-275`; `ModelsTests.swift:17-20`; build gate | PASS |
| T9 | Unit tests assert raw value and exact color | `ModelsTests.swift:20`; `ProviderThemeTests.swift:38-43` | PASS |
| T9 | Quick gate passes | Full real gate below passed 118 tests | PASS |
| T10 | Live transport sends framed connect then account.getQuota and returns structured response | `CopilotAdapter.swift:89-93`; real CLI smoke returned a monthly window; framing test `CopilotAdapterTests.swift:139-149` | PASS; G3 |
| T10 | Premium remaining maps to one monthly window, invert, clamp, reset | `CopilotAdapterTests.swift:32-43,61-75,77-87`; implementation `CopilotAdapter.swift:32-44` | PASS |
| T10 | Unlimited chat/completions ignored; missing Premium parseFailed | `CopilotAdapterTests.swift:45-59,89-100` | PASS |
| T10 | CLI/transport network, RPC unauthorized, malformed parseFailed | `CopilotAdapterTests.swift:103-131`; implementation `CopilotAdapter.swift:15-21,25-30,67-81` | PASS; G4 |
| T10 | Tests cover framing, 82.5% real-style inversion, boundaries, reset optionality, ignored quotas, and failures | `CopilotAdapterTests.swift:32-149` contains each named test and assertion | PASS |
| T10 | Quick gate passes | Full real gate below passed 118 tests | PASS |
| T11 | AppDelegate registers CopilotAdapter through polling path | `Sources/LimitBar/App/LimitBarApp.swift:29-35` includes `.githubCopilot: CopilotAdapter()`; build gate | PASS |
| T11 | Adding Copilot requires no API-key field and uses CLI login | `Sources/LimitBar/UI/SettingsView.swift:243-245` shows field only for `.openCodeGo`; `:290` passes a key only for Go; adapter default `CopilotAdapter.swift:7-9` uses CLI | PASS |
| T11 | Copilot tab/icon use theme path at any usage level | Popover `PanelView.swift:87-89,194`; icon entries `LimitBarApp.swift:83-91`; icon mapping `IconRenderer.swift:67,113,128`; exact theme test `ProviderThemeTests.swift:38-50`; build gate | PASS; G2 |
| T11 | Build gate passes | Real test gate rebuilt app and tests successfully | PASS |
| T12 | Copilot decision records source, inversion, and failure scope | `STATE.md:53-59` AD-007; `design.md:176-182` | PASS |
| T12 | All PID-22..PID-27 statuses are updated | `spec.md:198-203` marks all six Verified; `tasks.md:381-399` documents close-out | PASS |
| T12 | Full gate passes | Requested real `xcodebuild test` gate passed; scratch `xcodegen generate` also passed and the test gate rebuilt the target | PASS |
| T12 | Independent Verifier report and `validate_state.py` | This report is independent; closing validator run after writing returned 0 errors | PASS |

---

## Discrimination Sensor

The Copilot sensor used a temporary detached worktree at `/var/folders/bk/br883xc92mb_h6yd3bn2dzx40000gn/T/opencode/copilot-verify-scratch`, generated the project with `xcodegen generate`, ran each focused test, and restored the mutated file before the next mutation. The real-tree baseline was empty porcelain before and after. The worktree was removed with `git worktree remove --force` and pruned.

| Mutation | File:line | Description | Focused result |
| -------- | --------- | ----------- | -------------- |
| 1 | `Sources/LimitBar/UI/ProviderTheme.swift:10` | Changed Copilot red component `106 / 255` to `107 / 255` | KILLED - `ProviderThemeTests.githubCopilotIsSlateBlue()` failed |
| 2 | `Sources/LimitBar/Providers/CopilotAdapter.swift:38` | Removed inversion, changed `100 - remaining` to `remaining` | KILLED - monthly, ignored-quota, and boundary assertions failed |
| 3 | `Sources/LimitBar/Providers/CopilotAdapter.swift:38` | Removed clamp, changed expression to `100 - remaining` | KILLED - `remainingPercentageIsClamped()` failed |
| 4 | `Sources/LimitBar/Providers/CopilotAdapter.swift:30` | Mapped RPC `error` to `parseFailed` instead of `unauthorized` | KILLED - `rpcErrorMapsToUnauthorized()` failed |
| 5 | `Sources/LimitBar/Providers/CopilotAdapter.swift:51-58` | Disabled `resetDate` parsing by returning nil | KILLED - real-style monthly reset assertion failed |
| 6 | `Sources/LimitBar/Providers/CopilotAdapter.swift:34` | Accepted `chat` as fallback when premium is missing | KILLED - `missingPremiumQuotaThrowsParseFailed()` failed |
| 7 | `Sources/LimitBar/Providers/CopilotAdapter.swift:62` | Changed `--no-auto-update` to `--auto-update` | KILLED - `commandUsesHeadlessStdioMode()` failed |

**Sensor depth**: seven targeted behavior-level mutations across theme, parser, errors, reset handling, quota filtering, and CLI contract.
**Result**: 7/7 killed - PASS.
**Isolation**: real-tree `git status --porcelain=v1` was empty before and after; only the temporary worktree was mutated.

### Prior Sensor Evidence Retained

| Mutation | File:line | Description | Killed? |
| -------- | --------- | ----------- | ------- |
| 1 | `Sources/LimitBar/UI/ProviderTheme.swift:7-8` | Swapped claudeCode/codex sRGB component sets | KILLED - exact-component tests failed |
| 2 | `Sources/LimitBar/Providers/GoAdapter.swift:67` | Removed OpenCode clamp | KILLED - clamp test failed |
| 3 | `Sources/LimitBar/Providers/GoAdapter.swift:45` | Excluded 403 from unauthorized mapping | KILLED - status mapping test failed |
| 4 | `Sources/LimitBar/UI/IconRenderer.swift:33` | Returned neutral for data-bearing icon branch | KILLED - provider/tint/template tests failed |
| 5 | `Sources/LimitBar/Providers/GoAdapter.swift:76-78` | Disabled reset-date parsing | KILLED - exact-date tests failed |

Prior sensor result: 5/5 killed. Both prior and extension sensor evidence are retained; no sensor mutant survived.

---

## Gate Check

- **Gate command**: `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'`
- **Result**: 118 passed, 0 failed, 0 skipped, 13 suites; `TEST SUCCEEDED`
- **Test count before feature**: 97 (`git grep -h -E '^[[:space:]]*@Test' main -- 'Tests/LimitBarTests/*.swift' | wc -l`)
- **Test count after feature**: 118 (Xcode Swift Testing summary: `Test run with 118 tests in 13 suites passed`)
- **Delta**: +21 net tests from main; +11 over the prior 107-test provider-identity baseline, including 9 Copilot adapter tests, one raw-value assertion, and one Copilot theme test/bridge coverage addition
- **Skipped tests**: none
- **Failures**: none
- **Test integrity**: no test count decrease; all new Copilot tests ran and passed. The misleading XCTest footer reported `Executed 0 tests`, but Swift Testing reported all 118 tests explicitly, consistent with the project runbook.

---

## Practical Checks

- **Scratch generation**: `xcodegen generate` succeeded in the isolated sensor worktree.
- **CLI availability**: `copilot --version` returned `GitHub Copilot CLI 1.0.80.`
- **CLI smoke**: independently compiled `Models.swift`, `CopilotAdapter.swift`, and a temporary checker with `swiftc`; the authenticated installed CLI returned `kind=monthly usedPercent=19.799999999999997 hasReset=true`. This exercises `CopilotAdapter.fetchUsage` at `Sources/LimitBar/Providers/CopilotAdapter.swift:14-21` and the default client at `:7-9,64-94`.
- **UI/build**: the real test gate rebuilt `SettingsView`, `PanelView`, `LimitBarApp`, `ProviderTheme`, and `IconRenderer`; source checks above confirm picker/name, no-key conditional, provider propagation, and exact color paths. No independent Copilot screenshot was run because the repository declares no UI-test target and the requested gate is build/test based; this is reflected in precision gap G2.
- **No real-tree mutation**: the temporary checker and binary were deleted; real porcelain remained empty.

---

## Edge Cases

- [x] Remaining percentage below 0 or above 100 clamps consumed usage: `Tests/LimitBarTests/CopilotAdapterTests.swift:61-75` (`-25 -> 100`, `125 -> 0`).
- [x] Missing `resetDate` yields nil: `CopilotAdapterTests.swift:77-87`.
- [x] `chat` and `completions` are ignored when premium exists: `CopilotAdapterTests.swift:45-59`.
- [x] `chat` or `completions` as the only quota data yields parseFailed: `CopilotAdapterTests.swift:89-100`.
- [x] Malformed non-JSON response yields parseFailed: `CopilotAdapterTests.swift:112-117`.
- [x] RPC error yields unauthorized: `CopilotAdapterTests.swift:103-109`.
- [x] Generic transport failure yields network: `CopilotAdapterTests.swift:119-131`; CLI absence path is `CopilotAdapter.swift:67-69`.
- [x] Existing no-data neutral/template behavior remains covered by prior `IconRendererTests.swift:68-86,148-166`.
- [x] Copilot account creation has no API-key input: `SettingsView.swift:243-245,264-267,283-290`.

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | PASS |
| Surgical changes | PASS - extension changes are confined to the provider/model/theme/wiring/test surfaces in `main..HEAD` |
| No scope creep | PASS - no dashboard scraping, API-key field, or extra unlimited quota windows |
| Matches project patterns | PASS - Swift Testing, protocol adapter, injected test closure, exact source-string conventions |
| Spec-anchored outcome check | PASS - all 27 criteria have exact assertions or implementation/build/practical evidence; precision gaps are explicit |
| Per-layer coverage expectation | PASS - model/theme/adapter unit coverage; UI/app wiring uses the matrix-sanctioned build + practical check |
| Every new test maps to a requirement or edge case | PASS |
| Documented guidelines followed | PASS - `AGENTS.md`, tasks.md:16-28, and project runbook |
| Real-tree isolation | PASS - porcelain empty before and after sensor |

---

## Ranked Precision Gaps

These are evidence precision limitations, not observed failures. They do not change the PASS verdict.

1. **Minor - G3, PID-24/T10**: `CopilotAdapterTests.swift:139-149` asserts the quota frame's exact body and length, but no test captures both emitted frames or asserts that the `connect` response is consumed before `account.getQuota`. Implementation is at `CopilotAdapter.swift:89-93`; the independent authenticated CLI smoke test succeeded.
2. **Minor - G2, PID-23/T11**: `IconRendererTests.swift:10` defines `allProviders` as Claude, Codex, and OpenCode, so no direct icon-style assertion names or iterates `.githubCopilot`. The generic provider path is implemented at `IconRenderer.swift:67,95,113,128`, wired at `LimitBarApp.swift:83-91`, and exact Copilot theme/bridge tests pass at `ProviderThemeTests.swift:38-50`.
3. **Minor - G4, PID-26/T10**: `CopilotAdapterTests.swift:119-131` injects a generic thrown error and checks network mapping, but does not directly exercise the unavailable-executable branch at `CopilotAdapter.swift:67-69` or a real pipe EOF. The branch is explicit and the real CLI smoke verifies the available path.
4. **Minor - G1, PID-22/T9**: `ModelsTests.swift:20` asserts the persisted raw value and `Models.swift:3` supplies synthesized Codable behavior, but no Copilot-specific `Account`/`AppState` encode/decode round-trip is asserted. Existing model round-trip coverage remains in `ModelsTests.swift:104-129`.
5. **Minor - prior PID-17**: OpenCode raw-value preservation has no dedicated decode-regression test; prior diff-absence evidence is retained above.
6. **Minor - prior PID-07**: No-data color test asserts `.neutral` rather than sampling private `tertiaryLabelColor`; the mapping remains at `IconRenderer.swift:111-115`.
7. **Minor - pre-existing localization mismatch**: pt-BR/es contain a leading `The` in one Codex auth key while the source key does not. This predates `main..HEAD` and is outside this extension.

---

## Requirement Traceability Update

| Requirement | Previous status | Verification result |
| ----------- | --------------- | ------------------- |
| PID-01..PID-21 | Verified in prior report | Verified; prior evidence retained |
| PID-22 | Verified in spec | Verified; G1 precision note |
| PID-23 | Verified in spec | Verified; G2 precision note |
| PID-24 | Verified in spec | Verified; G3 precision note |
| PID-25 | Verified in spec | Verified |
| PID-26 | Verified in spec | Verified; G4 precision note |
| PID-27 | Verified in spec | Verified |

---

## Summary

**Overall**: PASS - ready.
**Spec-anchored check**: 27/27 criteria match their spec-defined outcomes; 7 non-blocking precision notes are documented (3 prior, 4 extension).
**Sensor**: 7/7 Copilot mutations killed; prior sensor 5/5 killed.
**Gate**: 118 passed, 0 failed, 0 skipped, 13 suites.
**Practical CLI**: Installed Copilot CLI 1.0.80 returned a real monthly consumed percentage and reset date through the compiled adapter.
**Isolation**: Scratch worktree removed and pruned; real-tree status unchanged and empty.
**Lessons**: No lesson distilled; no mutant survived and the verdict is a clean PASS.
