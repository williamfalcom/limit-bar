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
- **Status**: superseded by AD-008 for OpenCode Go

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

### AD-007
- **Decision**: GitHub Copilot usage is collected through the installed CLI's headless stdio JSON-RPC interface (`connect` followed by `account.getQuota`). Only the finite `premium_interactions` quota is rendered; its `remainingPercentage` is inverted into consumed usage, and unlimited `chat`/`completions` quotas are ignored.
- **Reason**: The Copilot CLI exposes the authenticated quota through a structured local RPC surface, while the user approved Premium requests as the useful quota to display.
- **Trade-off**: The adapter is coupled to the Copilot CLI headless protocol and requires the user to be logged in with that CLI; CLI absence or protocol drift degrades through existing error states.
- **Scope**: `CopilotAdapter`, GitHub Copilot provider identity, and the existing provider-colored icon/popover surfaces.
- **Date**: 2026-08-25
- **Status**: active

### AD-008
- **Decision**: OpenCode Go supports both API-key authentication and a separate limit-bar-owned Console device OAuth session. OAuth access/refresh tokens are stored only in the limit-bar Keychain; refresh is serialized per account. Existing accounts without an auth-method field remain API-key accounts. Removing an OAuth account deletes local credentials and clearly states that it does not revoke the remote Console session. The CLI V2 credential database and session are never read or modified.
- **Reason**: The user cannot create the key required by the current limit-bar setup. Live authorization confirmed that a separate device-flow token and its rotated replacement can read the official Go usage endpoint. The refresh token is single-use.
- **Trade-off**: The browser flow depends on Console availability. Local removal does not revoke the server-side session because no official device-session revocation route is documented.
- **Scope**: OpenCode Go account setup, Keychain credentials, `GoAdapter`, and OpenCode authentication UI only. AD-004 remains active for all other providers.
- **Date**: 2026-10-19
- **Status**: active

## Handoff

- **Feature**: OpenCode Go dual authentication (`.specs/features/opencode-go-auth/`)
- **Phase / Task**: v0.3.0 release preparation; T7/T8 retain the untested API-key replacement UAT
- **Completed**: T1–T6 implementation and user-confirmed UAT; T7 implementation; trilingual docs and `VERSION=0.3.0`. Previous automated gate: 151 passed, 0 failed. AGPLv3 licensing from PR #2 and its session closure from PR #3 are preserved; the only merge conflict was this handoff.
- **In-progress** (file:line): release notes, fresh build/test gates, administrative merge of PR #4, and ZIP/DMG packaging from merged `main`.
- **Next step**: rerun validation, merge PR #4, rebuild production artifacts from merged `main`, validate their signature/version/archive integrity, then publish annotated tag `v0.3.0` and GitHub release assets.
- **Release authorization**: on 2026-10-20, the user explicitly authorized administrative merge without external approval and publication with the known API-key replacement UAT gap disclosed. The authenticated account is the PR author and cannot approve its own PR. This exception is not evidence that the manual test passed.
- **Blockers**: no release blocker if fresh automated gates and package checks pass. API-key replacement manual UAT remains pending; no UI-test target exists. Test later with a temporary invalid-key account, repair locally, and remove it without sharing secrets or revoking a live Console session.
- **Uncommitted files**: none
- **Branch**: `feat/opencode-go-auth-v0.3`
