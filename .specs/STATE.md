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

## Handoff

- **Feature**: `.specs/features/menu-bar-limits/` - RELEASED as v0.1.1 (tag pushed to origin)
- **Phase / Task**: Project closed for the session; 33 commits on main, 95 tests / 0 failed
- **Completed**: v0.1.0 pipeline (spec→design→tasks→2 batches→Verifier PASS→UAT hardening); v0.1.1: NSStatusItem right-click menu (Refresh/Settings…/Quit), own settings window replacing private selector; app icon + icns; trilingual README w/ screenshots; build.sh dev/prod/dmg/test; VERSION semver
- **In-progress** (file:line): none
- **Next step**: If resuming — OpenCode Go still .unsupported by design until upstream API (#10448/#18648); candidate follow-ups are dashboard scraping or local estimation (needs new spec decision), plus GitHub Release attachments upload
- **Blockers**: none
- **Uncommitted files**: none expected besides this handoff edit (committed with lessons)
- **Branch**: main
