# Menu Bar Limits Context

**Gathered:** 2026-08-21
**Spec:** `.specs/features/menu-bar-limits/spec.md`
**Status:** Ready for design

---

## Feature Boundary

Native macOS menu bar app (limit-bar v1) that shows AI subscription limits (Claude Code, Codex, OpenCode Go) as a menu bar icon with an indicator for the selected plan's time window; clicking opens a small panel with tabs — one per account/plan — each rendering progress bars for every limit window.

---

## Implementation Decisions

### Providers & accounts scope

- P1: Claude Code + Codex (usage endpoints confirmed by research).
- P2: OpenCode Go (limits known — $12/5h, $30/wk, $60/mo dollar-denominated — but exact usage endpoint to be confirmed during Design).
- Multi-account from day one: one tab per account/plan; accounts added/removed in Settings; multiple accounts per provider allowed.

### Menu bar icon

- Icon renders a mini progress indicator of the **active account's selected window** usage %.
- Color states: green <70%, amber 70–89%, red ≥90%; at 100% shows time-until-reset countdown instead of %.
- Active account = last selected tab (persisted across launches).
- Optional % text next to the icon.

### Panel & bars

- Click opens small panel; one tab per configured account/plan.
- Each tab renders **one bar per plan window** (Claude/Codex: 5h + weekly; Go: 5h + weekly + monthly) with % used and time until reset; absolute values ($/tokens) shown when the provider returns them.
- Same color palette as the icon.

### Refresh strategy

- Default polling interval: **300s**, user-configurable in Settings (floor of 60s).
- Exponential backoff on HTTP 429 (endpoint do Claude satura fácil); last good data stays visible with "updated Xm ago" staleness marker.
- Immediate refresh on panel open, manual refresh button/menu item, and on wake from sleep for stale accounts.

### Credentials

- Reuse credentials the CLIs already store locally — Keychain service `Claude Code-credentials` for Claude; Codex CLI local storage (`~/.codex`) / app-server; OpenCode Go API key pasted once and stored in Keychain. No in-app OAuth flow.
- If a credential is missing/expired, the account's tab shows instructions to log in via that provider's CLI.

### Agent's Discretion

(no areas explicitly delegated; standard UX conventions apply where unspecified)

### Declined / Undiscussed Gray Areas → Assumptions

Recorded in the spec's Assumptions & Open Questions table (UI language = English, right-click menu = Refresh/Settings/Quit, displayed-window default = primary 5h, undocumented-endpoint risk accepted as best-effort).

---

## Specific References

- Competitor pattern acknowledged during research: Usagebar / SessionWatcher (single-provider trackers); limit-bar differentiates by aggregating multiple plans with per-account tabs.
- Data sources verified: `api.anthropic.com/api/oauth/usage` (Keychain OAuth token, header `anthropic-beta: oauth-2025-04-20`, fields `five_hour`/`seven_day` utilization + resets_at); Codex via `codex app-server` (`account/rateLimits/read`) or `chatgpt.com/backend-api/codex/usage`; OpenCode Go dollar-value caps per official docs.

---

## Deferred Ideas

- Cost estimation computed locally (ccusage-style) — out of scope; only provider-reported values.
- Usage history/graphs over time.
- Additional providers (GitHub Copilot, Cursor, Gemini).
