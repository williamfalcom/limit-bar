# Menu Bar Limits Specification

## Problem Statement

Juggling multiple AI coding subscriptions (Claude Code, Codex, OpenCode Go) means hitting invisible usage walls mid-session: each provider hides its limits in a different CLI command or web console, and none shows them at a glance while working. limit-bar puts every plan's remaining capacity in the macOS menu bar so switching tasks before a lockout becomes a glance, not a hunt.

## Goals

- [ ] Glanceable menu bar indicator of the active account's selected window usage (correct within one poll cycle).
- [ ] Zero-config onboarding for Claude Code and Codex when their CLIs are already logged in.
- [ ] Continuous 24h operation without triggering provider-side rate limiting (429).

## Out of Scope

| Feature | Reason |
| --- | --- |
| Local cost estimation engines (ccusage-style) | Only provider-reported values; estimation drifts and adds parsing surface |
| Usage history / graphs over time | v1 is current-state only |
| Additional providers beyond Claude Code / Codex / OpenCode Go | Architecture supports later addition; not built now |
| In-app OAuth login flows for Claude/Codex | Credentials are reused from the CLIs' local storage instead |
| Windows / Linux support | macOS menu bar app |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| UI language | English strings | Dev-tool convention; localization later if wanted | n |
| Right-click on icon | Native menu: Refresh now, Settings…, Quit | Standard menu bar UX | n |
| Displayed window default per account | Primary window (5h) pre-selected | Primary window is the day-to-day constraint on all three providers | n |
| Poll interval floor | 60s minimum even if user configures lower | Protects against 429 lockout observed on Anthropic OAuth endpoint | y |
| Active account persistence | Last selected tab restored on launch | Continuity of the "glance" workflow | n |
| Undocumented endpoints risk | Treat Claude/Codex/Go endpoints as best-effort; parse failures degrade to stale/error state, never crash | Ecosystem reality for these APIs; no SLA exists | n |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Menu bar icon with live limit indicator ⭐ MVP

**User Story**: As a developer running multiple AI plans, I want a menu bar icon that shows my active account's selected-window usage at a glance so that I know when I'm approaching a wall without opening anything.

**Why P1**: Core value proposition; the app is pointless without ambient visibility.

**Acceptance Criteria**:

1. WHEN the app launches THEN system SHALL display a menu bar icon showing usage % of the persisted active account's selected window from cached data. <!-- event-driven -->
2. WHILE selected-window usage is below 70% THEN icon SHALL render its indicator green. <!-- state-driven -->
3. WHILE selected-window usage is between 70% and 89% THEN icon SHALL render its indicator amber. <!-- state-driven -->
4. WHILE selected-window usage is at or above 90% THEN icon SHALL render its indicator red. <!-- state-driven -->
5. WHEN any plan window of the active account reaches 100% THEN icon SHALL display time until that window resets in place of the percentage. <!-- event-driven -->
6. IF no successful fetch has ever completed for the active account THEN icon SHALL render a neutral gray state and its tooltip SHALL show "no data yet". <!-- unwanted-behavior -->

**Independent Test**: Launch app with valid CLI credentials; verify icon appears with correct color for known usage; simulate >90% cached value and observe red; clear cache and relaunch to see neutral state.

---

### P1: Panel with per-account tabs and limit bars ⭐ MVP

**User Story**: As a developer with several accounts/plans, I want clicking the icon to open a small panel with one tab per account where I can see a progress bar per limit window so that I can check everything in one place.

**Why P1**: This is the detail view the user explicitly specified (tabs per account/plan, bars per limit).

**Acceptance Criteria**:

1. WHEN the user clicks the menu bar icon THEN system SHALL open a compact panel anchored under the icon showing one tab per configured account. <!-- event-driven -->
2. WHEN an account tab is selected THEN panel SHALL render one labeled progress bar per plan window (Claude Code and Codex: 5-hour + weekly; OpenCode Go: 5-hour + weekly + monthly) showing % used and time until reset. <!-- event-driven -->
3. WHERE the provider returns absolute consumption values ($ or tokens) THEN the corresponding bar label SHALL include that absolute value alongside the percentage. <!-- optional-feature -->
4. WHEN the user selects a different account tab THEN system SHALL set it as the active account and the menu bar icon SHALL update to that account's selected window using cached data immediately. <!-- event-driven -->
5. WHILE the panel is open AND fresh data arrives THEN bars SHALL update in place without closing the panel. <!-- state-driven -->
6. WHEN the user clicks outside the panel or presses Esc THEN panel SHALL close. <!-- event-driven -->
7. IF an account has no usable credentials THEN its tab SHALL show provider-specific setup instructions (CLI login command) instead of bars. <!-- unwanted-behavior -->

**Independent Test**: Configure two accounts; click icon; switch tabs; verify bar count, %, reset countdowns, active-account handoff to icon, Esc closes.

---

### P1: Usage polling service with rate-limit safety ⭐ MVP

**User Story**: As a heavy AI user, I want limit-bar to keep usage data fresh in the background without getting my tokens rate-limited so that monitoring never breaks the tools themselves.

**Why P1**: Data freshness with 429-safety is what makes the indicators trustworthy; research showed Anthropic's OAuth usage endpoint locks out aggressive pollers.

**Acceptance Criteria**:

1. The system SHALL refresh each configured account's usage every 300 seconds by default. <!-- ubiquitous -->
2. WHERE the user sets a custom interval in Settings THEN system SHALL use that interval clamped to a minimum of 60 seconds. <!-- optional-feature -->
3. WHEN a provider responds HTTP 429 THEN system SHALL double that account's next delay (capped at 30 minutes) and continue displaying its last good data. <!-- event-driven -->
4. IF a request fails with a network error, timeout, or HTTP 5xx THEN system SHALL keep the cached value visible with an "updated Xm ago" staleness marker. <!-- unwanted-behavior -->
5. WHEN manual refresh is triggered from the menu item or panel button THEN system SHALL fetch all configured accounts immediately, resetting backoff for accounts whose last fetch succeeded. <!-- event-driven -->
6. WHEN the Mac wakes from sleep THEN system SHALL refresh every account whose data is older than its current interval. <!-- event-driven -->

**Independent Test**: Run app 10+ minutes observing request log (~300s cadence); force a 429 response via proxy and observe doubled delays with stale marker; trigger manual refresh and see immediate fetches.

---

### P1: Local credential reuse and account management ⭐ MVP

**User Story**: As a user whose CLIs are already logged in, I want limit-bar to reuse those existing credentials and let me add/remove accounts in Settings so that setup takes seconds and secrets stay where they already live.

**Why P1**: Multi-account tabs require account management; credential reuse is the approved zero-friction auth model.

**Acceptance Criteria**:

1. WHEN adding a Claude Code account THEN system SHALL read the OAuth token from macOS Keychain service `Claude Code-credentials`. <!-- event-driven -->
2. WHEN adding a Codex account THEN system SHALL obtain rate-limit data via the Codex app-server interface, falling back to reading `~/.codex/auth.json`. <!-- event-driven -->
3. WHERE the user adds an OpenCode Go account THEN system SHALL accept a pasted API key and store it in macOS Keychain. <!-- optional-feature -->
4. IF a stored credential is expired or rejected (HTTP 401/403) THEN the account's tab SHALL show re-authentication instructions naming the provider's CLI login command. <!-- unwanted-behavior -->
5. WHEN the user removes an account THEN system SHALL delete any secret it stored for that account and remove its tab. <!-- event-driven -->
6. The system SHALL support multiple configured accounts, including multiple for the same provider, distinguished by a user-editable label. <!-- ubiquitous -->

**Independent Test**: With Claude/Codex CLIs logged in, add both account types without typing passwords; add two Codex accounts with distinct labels; remove one and confirm tab and stored secret disappear.

---

### P1: Settings ⭐ MVP

**User Story**: As a user with preferences, I want a Settings window to manage accounts, pick which window each account displays on the icon, and set the refresh interval so that the app adapts to how I work.

**Why P1**: The 300s-configurable polling and per-account window choice were explicit user requirements.

**Acceptance Criteria**:

1. WHEN the user opens Settings THEN system SHALL present controls for managing accounts, choosing the displayed window per account, and setting the refresh interval. <!-- event-driven -->
2. WHEN the displayed-window selection for the active account changes THEN menu bar icon SHALL update to the newly selected window on the next UI refresh using cached data. <!-- event-driven -->
3. IF the user enters an invalid refresh interval (below floor or non-numeric) THEN Settings SHALL reject it and show the allowed range (60–3600 seconds). <!-- unwanted-behavior -->

**Independent Test**: Change interval to 120s and observe cadence change; try 10s and see rejection message; swap displayed window 5h→weekly and watch icon source change.

---

### P2: OpenCode Go provider

**User Story**: As an OpenCode Go subscriber, I want my dollar-denominated Go limits tracked like the others so that all my plans live in one place.

**Why P2**: Provider confirmed but its exact usage endpoint needs Design-phase validation; P1 ships without it.

**Acceptance Criteria**:

1. WHERE an OpenCode Go account is configured THEN system SHALL fetch and display used-percentage for each Go window (5-hour cap $12, weekly cap $30, monthly cap $60) as reported by the provider. <!-- optional-feature -->
2. IF the Go usage endpoint cannot be reached or parsed THEN the Go tab SHALL degrade exactly like other providers (stale marker / error state). <!-- unwanted-behavior -->

**Independent Test**: Add Go account with API key; verify three bars with correct caps; revoke key temporarily and confirm error state.

---

### P2: Launch at login

**User Story**: As a daily driver user, I want limit-bar to start automatically at login so that monitoring is always present after reboot.

**Why P2**: Convenience standard for menu bar apps; not needed to prove core value.

**Acceptance Criteria**:

1. WHEN "Start at Login" is enabled in Settings THEN system SHALL register the app as a login item that launches without a Dock icon. <!-- event-driven -->
2. WHEN "Start at Login" is disabled THEN system SHALL remove the registration. <!-- event-driven -->

**Independent Test**: Toggle on, reboot/re-login, app appears in menu bar only; toggle off and repeat to confirm absence.

---

### P3: Threshold notifications

**User Story**: As a focused worker, I want a notification when a window nears its cap so that I can wrap up before lockout even while looking elsewhere.

**Why P3**: Nice-to-have polish; icon colors already cover visible states.

**Acceptance Criteria**:

1. WHEN a plan window crosses 80% used THEN system SHALL post one local notification for that window per reset period. <!-- event-driven -->
2. IF notifications are denied in System Settings THEN system SHALL skip notifications silently and keep visual states working. <!-- unwanted-behavior -->

**Independent Test**: Seed 79%→81% transition; expect single notification; deny permission and confirm no crash/no notification.

---

## Edge Cases

- IF Keychain access is denied by the user THEN system SHALL show an error state in the affected tab explaining how to grant access, without crashing. <!-- unwanted-behavior -->
- IF a provider response cannot be parsed (format changed) THEN system SHALL keep prior data, mark the account stale, and log the parse failure locally. <!-- unwanted-behavior -->
- WHEN zero accounts are configured THEN panel SHALL show an empty state directing to "Add account" and icon SHALL render the neutral state. <!-- event-driven -->
- WHEN two accounts share a provider THEN tabs SHALL be distinguishable by their labels at all times. <!-- state-driven -->
- The system SHALL compute reset countdowns from the UTC timestamps returned by providers, immune to local timezone changes. <!-- ubiquitous -->

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| LIM-01 | P1: Menu bar icon | - | Implementing |
| LIM-02 | P1: Menu bar icon | - | Pending |
| LIM-03 | P1: Menu bar icon | - | Pending |
| LIM-04 | P1: Menu bar icon | - | Pending |
| LIM-05 | P1: Menu bar icon | - | Pending |
| LIM-06 | P1: Menu bar icon | - | Pending |
| LIM-07 | P1: Panel tabs & bars | - | Pending |
| LIM-08 | P1: Panel tabs & bars | - | Implementing |
| LIM-09 | P1: Panel tabs & bars | - | Implementing |
| LIM-10 | P1: Panel tabs & bars | - | Implementing |
| LIM-11 | P1: Panel tabs & bars | - | Pending |
| LIM-12 | P1: Panel tabs & bars | - | Pending |
| LIM-13 | P1: Panel tabs & bars | - | Pending |
| LIM-14 | P1: Polling service | - | Implementing |
| LIM-15 | P1: Polling service | - | Implementing |
| LIM-16 | P1: Polling service | - | Implementing |
| LIM-17 | P1: Polling service | - | Implementing |
| LIM-18 | P1: Polling service | - | Implementing |
| LIM-19 | P1: Polling service | - | Implementing |
| LIM-20 | P1: Credentials & accounts | - | Implementing |
| LIM-21 | P1: Credentials & accounts | - | Implementing |
| LIM-22 | P1: Credentials & accounts | - | Implementing |
| LIM-23 | P1: Credentials & accounts | - | Implementing |
| LIM-24 | P1: Credentials & accounts | - | Implementing |
| LIM-25 | P1: Credentials & accounts | - | Implementing |
| LIM-26 | P1: Settings | - | Pending |
| LIM-27 | P1: Settings | - | Pending |
| LIM-28 | P1: Settings | - | Pending |
| LIM-29 | P2: OpenCode Go | - | Implementing |
| LIM-30 | P2: OpenCode Go | - | Implementing |
| LIM-31 | P2: Launch at login | - | Pending |
| LIM-32 | P2: Launch at login | - | Pending |
| LIM-33 | P3: Notifications | - | Pending |
| LIM-34 | P3: Notifications | - | Pending |

**Coverage:** 34 total, 0 mapped to tasks yet, 34 unmapped (Tasks phase pending).

---

## Success Criteria

- [ ] With CLIs logged in, first useful icon within 60s of first launch without any in-app login.
- [ ] All configured plans readable in one panel interaction (< 5s open-to-informed).
- [ ] 24h continuous run produces zero sustained 429 lockouts and no crash.
