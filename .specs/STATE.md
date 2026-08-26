# STATE

## Decisions

### AD-001
- **Decision**: UI architecture is native SwiftUI `MenuBarExtra` (macOS 14+), with AppKit `NSStatusItem` + `NSPopover` as the named fallback if a blocking platform quirk appears.
- **Reason**: Native panel anchoring/dismissal, zero third-party dependencies, modern Observation-based state.
- **Trade-off**: MenuBarExtra window-style quirks (sizing/focus) accepted; fallback contained to app-scene layer.
- **Scope**: All limit-bar UI features.
- **Date**: 2026-08-21
- **Status**: active

### AD-002
- **Decision**: Project/build source of truth is xcodegen `project.yml`; the generated `.xcodeproj` is git-ignored.
- **Reason**: Diffable, regenerable build config suited to agent-driven development; tests run via `xcodebuild test`.
- **Trade-off**: Contributors must install xcodegen and regenerate before opening Xcode.
- **Scope**: Repository build system.
- **Date**: 2026-08-21
- **Status**: active

### AD-003
- **Decision**: Every provider integration lives behind the `ProviderAdapter` protocol; undocumented endpoints are treated as best-effort with graceful degradation (stale/error/unsupported states), never crashes.
- **Reason**: Claude OAuth usage endpoint, ChatGPT backend-api, and OpenCode Go usage are unofficial or absent; isolation contains breakage.
- **Trade-off**: Extra protocol indirection; some provider richness may be delayed behind adapter work.
- **Scope**: All current and future provider integrations.
- **Date**: 2026-08-21
- **Status**: active

### AD-004
- **Decision**: Credentials are reused from the CLIs' own local storage (macOS Keychain `Claude Code-credentials`, Codex `CODEX_HOME` storage); app-owned secrets (OpenCode Go API keys) go exclusively to the macOS Keychain. No in-app OAuth flows in v1.
- **Reason**: Zero-friction setup; avoids duplicating sessions/tokens across apps.
- **Trade-off**: Token refresh remains the CLIs' job - expired tokens surface as re-login instructions instead of self-healing.
- **Scope**: All credential handling in limit-bar.
- **Date**: 2026-08-21
- **Status**: active

### AD-005
- **Decision**: Usage polling defaults to 300 s per account, user-configurable with a hard 60 s floor; HTTP 429 triggers exponential backoff doubling the delay, capped at 30 min.
- **Reason**: Anthropic's OAuth usage endpoint aggressively rate-limits pollers; conservative cadence keeps monitoring from breaking the monitored tools.
- **Trade-off**: Slower freshness than competitors' default 30–60 s polling.
- **Scope**: PollingEngine and any future background data collection.
- **Date**: 2026-08-21
- **Status**: active

### AD-006
- **Decision**: Bar surfaces use fixed per-provider accent colors - popover fills and menu bar icon both tint with Claude `#FF8C00`, Codex `#4169E1`, OpenCode `#C0C0C0` (ProviderTheme); usage-level green/amber/red tinting is retired from bars and icon. OpenCode Go usage comes from the official `https://opencode.ai/zen/go/v1/usage` endpoint behind `ProviderAdapter`; `.unsupported` is no longer thrown by GoAdapter but kept as a snapshot state for graceful degradation.
- **Reason**: User decision ("sempre cor do provedor"); usage level remains conveyed by the % text and 80% threshold notifications; maintainer-confirmed official endpoint makes the candidate-URL spike obsolete.
- **Trade-off**: High usage no longer changes bar color anywhere; live endpoint shape was pinned by one captured payload (2026-08-25), so parser treats unknown/missing fields defensively (`resetsAt: nil`, `usedAbsolute: nil`).
- **Scope**: `IconRenderer`, `PanelView`/`WindowRow`, `GoAdapter`, provider naming copy across the three `.strings` tables.
- **Date**: 2026-08-25
- **Status**: active

## Handoff

- **Feature**: `.specs/features/provider-identity/` - fully implemented and validated on branch `feat/provider-identity` (T1-T8 committed); v0.2.0 bump and PR remain
- **Phase / Task**: Execute closed; independent Verifier + manual checks pass recorded in `validation.md`
- **Completed**: per-provider colors (ProviderTheme -> IconRenderer tints + popover WindowRow fills); GoAdapter reworked onto official `/zen/go/v1/usage` (live payload pinned as fixture; resetsAt parsed ISO8601-fractional; 401/403/429/network/parse mapping); "OpenCode" copy rename across en/pt-BR/es; version label `v<CFBundleShortVersionString>` in popover top-right (both states)
- **In-progress** (file:line): none
- **Next step**: bump `VERSION` to 0.2.0, run the release build gate, push the branch, open the PR, then merge and tag `v0.2.0`. Deferred (context.md): Zen balance display (#10448), Go usage history, dead Codex auth.json fallback decision, possible warning affordance re-addition if provider-only color hides high usage
- **Blockers**: none
- **Uncommitted files**: none
- **Branch**: feat/provider-identity
