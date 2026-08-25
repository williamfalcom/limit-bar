# Provider Identity Specification

## Problem Statement

All limit bars render in usage-level colors (green/amber/red), so users cannot tell at a glance which account belongs to Claude, Codex, or OpenCode — every provider looks the same in the popover and the menu bar icon. Additionally, the OpenCode integration is a dead spike (`.unsupported` by design) even though OpenCode now exposes an official Go quota endpoint, and the popover gives no hint of which app version is running.

## Goals

- [ ] Each provider is visually identifiable by a fixed accent color: Claude `#FF8C00`, Codex `#4169E1`, OpenCode `#C0C0C0`, in both the popover bars and the menu bar icon.
- [ ] OpenCode accounts show real 5-hour/weekly/monthly usage from `https://opencode.ai/zen/go/v1/usage` instead of the "not available yet" placeholder.
- [ ] The popover shows the running app version (e.g. `v0.1.3`) discretely in its top-right corner.

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
| ----------- | ----------- |
| Zen balance display (upstream #10448) | No API-key endpoint exists; balance ≠ Go quota windows |
| Go usage history (upstream #43983) | Only current quota windows are needed for limit bars |
| Dashboard scraping / local usage estimation | Rejected in prior spec decisions; official endpoint makes them unnecessary |
| Removing the dead Codex auth.json→chatgpt.com fallback | Separate pending decision (candidate in STATE.md Handoff) |
| Warning colors (amber/red) on bars or icon | User decision: provider color always; usage level stays conveyed by the % text |
| Notification threshold behavior | Unrelated to bar/icon tint; untouched |

---

## Assumptions & Open Questions

Every ambiguity is resolved or recorded here - nothing is left silently unclear.

| Assumption / decision | Chosen default  | Rationale | Confirmed? |
| --------------------- | --------------- | --------- | ---------- |
| Bar color vs. usage warning | Provider color always; no amber/red on bars or icon | User chose "sempre cor do provedor"; % text remains the usage signal | y |
| Icon coloring scope | Icon + popover both provider-colored | User chose consistency; old spec's "same palette" rule now means provider palette | y |
| OpenCode display name | "OpenCode" (drop "Go" from UI copy) | User choice; `ProviderKind.openCodeGo` rawValue unchanged for persistence | y |
| Colors are exact sRGB hex | `#FF8C00`, `#4169E1`, `#C0C0C0` via RGB components (r/255, g/255, b/255) | User said "ou o mais próximo dela"; exact components need no approximation | y |
| Response fields beyond `percent` (e.g. reset timestamps) | Pinned during implementation by capturing a live payload; parser treats unknown/missing fields defensively (`resetsAt: nil`) | Endpoint shape confirmed by maintainer only for `usage.{rolling,weekly,monthly}.percent`; full shape not documented | n |
| Dollar absolute (`usedAbsolute`) | `nil` unless the live payload carries an explicit dollar/usage-amount field | Endpoint documented as returning percent; deriving dollars from caps would mislead when "Use balance" fallback is on | n |
| `.unsupported` snapshot state | Kept in enum + UI branch as graceful-degradation safety; GoAdapter stops throwing it | AD-003 pattern; persisted state decoding stays compatible | y |
| Version label localization | Not localized; format `v<CFBundleShortVersionString>` | Locale-neutral token; AGENTS.md rule applies to translatable text only | y |
| Version read at runtime | `Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")` read in AppDelegate, injected into `PanelView` | Keeps view testable; MARKETING_VERSION already flows VERSION→project.yml→Info.plist | y |

**Open questions:** none - all resolved or logged above (required before the spec is confirmed).

---

## User Stories

### P1: Provider-colored popover bars ⭐ MVP

**User Story**: As a user with multiple provider accounts, I want each provider's bars in its own color so that I instantly know which limits I am looking at.

**Why P1**: Core request; eliminates the Claude/Codex/OpenCode confusion.

**Acceptance Criteria** (each line is one EARS pattern):

1. WHILE the active account's provider is `claudeCode`, WHEN limit windows render THEN each progress-bar fill SHALL use `#FF8C00` regardless of `usedPercent`
2. WHILE the active account's provider is `codex`, WHEN limit windows render THEN each progress-bar fill SHALL use `#4169E1` regardless of `usedPercent`
3. WHILE the active account's provider is `openCodeGo`, WHEN limit windows render THEN each progress-bar fill SHALL use `#C0C0C0` regardless of `usedPercent`
4. The system SHALL NOT derive popover bar-fill colors from usage thresholds (green/amber/red logic removed from bar rendering)
5. The system SHALL keep the bar track neutral (`Color.primary.opacity(0.12)`) for all providers

**Independent Test**: Add accounts for each provider, open the popover, switch tabs — Claude bars are dark orange, Codex bars royal blue, OpenCode bars silver at any usage percentage.

---

### P1: Provider-colored menu bar icon ⭐ MVP

**User Story**: As a user, I want the menu bar mini-bars colored per provider so that the icon matches the popover and providers are distinguishable without opening it.

**Why P1**: The icon is the always-visible surface; leaving it green/red would break the new identity system.

**Acceptance Criteria**:

1. WHEN the status item image renders an account with data THEN that account's bar fill and percentage text SHALL use the account provider's color in every usage state, including the 100%-full countdown state
2. IF an account has no data (never fetched or empty windows) THEN the icon SHALL render that account neutral (`tertiaryLabelColor`) exactly as today
3. The icon SHALL be marked template only when every rendered account is neutral

**Independent Test**: Launch with one Claude and one Codex account — the icon shows an orange bar and a blue bar side by side; unit tests pin `IconRenderer.style` tint per provider.

---

### P1: OpenCode Go real usage ⭐ MVP

**User Story**: As an OpenCode Go subscriber, I want the app to show my actual 5-hour/weekly/monthly quota usage so that the OpenCode tab is useful instead of a placeholder.

**Why P1**: The official quota endpoint now exists; the spike's "not available yet" state is obsolete.

**Acceptance Criteria**:

1. WHEN `fetchUsage` runs for an OpenCode account THEN the adapter SHALL send `GET https://opencode.ai/zen/go/v1/usage` with `Authorization: Bearer <key>` where `<key>` is read from the Keychain (`go.api-key.<uuid>`, legacy bare-UUID fallback)
2. WHEN the endpoint returns 200 with `usage.rolling`, `usage.weekly`, `usage.monthly` entries THEN the adapter SHALL return `LimitWindow`s mapping rolling→`fiveHour`, weekly→`weekly`, monthly→`monthly` with `usedPercent` taken from each entry's `percent`
3. WHEN an entry provides a reset timestamp field THEN the adapter SHALL map it to `resetsAt`; IF the field is absent or unparsable THEN `resetsAt` SHALL be `nil`
4. IF the HTTP status is 401 or 403 THEN the adapter SHALL throw `ProviderError.unauthorized`; IF 429 THEN `rateLimited(retryAfter:)` honoring `Retry-After`; IF any other non-200 or a transport error occurs THEN `network`
5. IF a 200 payload yields no parseable quota windows THEN the adapter SHALL throw `ProviderError.parseFailed`
6. The system SHALL clamp parsed `usedPercent` into 0...100
7. The adapter SHALL NOT throw `ProviderError.unsupported` anymore; existing polling cadence, backoff, and wake-from-sleep behavior (AD-005) SHALL apply unchanged

**Independent Test**: Unit tests stub the endpoint (URLProtocol) with a captured live payload fixture and assert window mapping, error mapping, and clamping; manual check shows real percentages in the OpenCode tab.

---

### P2: "OpenCode" naming and copy

**User Story**: As a user, I want the provider consistently called "OpenCode" in the UI so that naming matches what I call it.

**Why P2**: Cosmetic consistency; zero functional impact.

**Acceptance Criteria**:

1. WHEN the Add Account sheet is open THEN the provider picker and the default-label prompt for OpenCode SHALL display "OpenCode" (API key prompt reads "Paste your OpenCode API key")
2. WHEN OpenCode-specific UI copy renders (reauth instructions, unsupported fallback) THEN it SHALL say "OpenCode", not "OpenCode Go"
3. The `ProviderKind` case rawValue SHALL remain `openCodeGo` so persisted `AppState` JSON keeps decoding

**Independent Test**: Open Settings → Add Account — picker shows "OpenCode"; grep-level check that user-facing "OpenCode Go" strings are gone from the three `.strings` tables' UI copy.

---

### P2: Version label in popover ⭐

**User Story**: As a user testing builds, I want the app version visible in the popover so that I know which version is running without opening Settings or Finder.

**Why P2**: Small quality-of-life addition; explicitly requested.

**Acceptance Criteria**:

1. WHEN the popover is shown THEN a version label SHALL appear in its top-right corner displaying `v` followed by `CFBundleShortVersionString` (e.g. `v0.1.3`)
2. IF the version string is unavailable THEN the label SHALL be hidden (no placeholder)
3. The version label SHALL render discreetly: caption-scale font (~11–12 pt), secondary/tertiary color, and SHALL NOT displace the tab row or footer controls
4. The version label SHALL appear in both the empty state (no accounts) and the tabbed state

**Independent Test**: Build via `scripts/build.sh dev`, open the popover — `v<VERSION>` shows top-right in both states; matches the `VERSION` file.

---

## Edge Cases

Edge cases are usually unwanted-behavior (IF/THEN) or boundary (WHEN) criteria:

- IF the OpenCode endpoint returns `percent` above 100 or below 0 THEN the adapter SHALL clamp `usedPercent` into 0...100 (covered by PID-11)
- IF the OpenCode API key is missing or blank in the Keychain THEN the adapter SHALL throw `missingCredentials` (existing behavior preserved)
- IF the popover has more tabs than fit the width THEN the tab row SHALL scroll horizontally without the version label overlapping tab pills (version sits beside the scroll view, not on top of it)
- WHEN an account is deleted THEN its provider color has no lingering state (colors are derived, not persisted)

---

## Requirement Traceability

Each requirement gets a unique ID for tracking across design, tasks, and validation.

| Requirement ID | Story       | Phase  | Status  |
| -------------- | ----------- | ------ | ------- |
| PID-01 | P1: Provider-colored popover bars | Design | Implementing |
| PID-02 | P1: Provider-colored popover bars | Design | Implementing |
| PID-03 | P1: Provider-colored popover bars | Design | Implementing |
| PID-04 | P1: Provider-colored popover bars | Design | Implementing |
| PID-05 | P1: Provider-colored popover bars | Design | Implementing |
| PID-06 | P1: Provider-colored menu bar icon | Design | Implementing |
| PID-07 | P1: Provider-colored menu bar icon | Design | Implementing |
| PID-08 | P1: Provider-colored menu bar icon | Design | Implementing |
| PID-09 | P1: OpenCode Go real usage | Design | Implementing |
| PID-10 | P1: OpenCode Go real usage | Design | Implementing |
| PID-11 | P1: OpenCode Go real usage | Design | Implementing |
| PID-12 | P1: OpenCode Go real usage | Design | Implementing |
| PID-13 | P1: OpenCode Go real usage | Design | Implementing |
| PID-14 | P1: OpenCode Go real usage | Design | Implementing |
| PID-15 | P2: "OpenCode" naming and copy | Design | Implementing |
| PID-16 | P2: "OpenCode" naming and copy | Design | Implementing |
| PID-17 | P2: "OpenCode" naming and copy | Design | Implementing |
| PID-18 | P2: Version label in popover | Design | Implementing |
| PID-19 | P2: Version label in popover | Design | Implementing |
| PID-20 | P2: Version label in popover | Design | Implementing |
| PID-21 | P2: Version label in popover | Design | Implementing |

**ID format:** `PID-[NUMBER]`

**Status values:** Pending → In Design → In Tasks → Implementing → Verified

**Coverage:** 21 total, 0 mapped to tasks, 21 unmapped ⚠️

---

## Success Criteria

How we know the feature is successful:

- [ ] With Claude, Codex, and OpenCode accounts configured, each tab's bars and the menu bar icon are instantly distinguishable by color at any usage level
- [ ] The OpenCode tab shows real percentages from the official endpoint within one poll cycle (default 300 s) instead of "not available yet"
- [ ] The popover's top-right corner shows `v<version>` matching the `VERSION` file in both empty and populated states
- [ ] Full gate passes: `xcodegen generate && xcodebuild build && xcodebuild test` green, including rewritten `GoAdapterTests` and `IconRendererTests`
