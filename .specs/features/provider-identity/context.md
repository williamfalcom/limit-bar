# Provider Identity Context

**Gathered:** 2026-08-25
**Spec:** `.specs/features/provider-identity/spec.md`
**Status:** Ready for design

---

## Feature Boundary

Three changes shipped as one feature: (1) fixed per-provider accent colors for limit bars in the popover and menu bar icon — Claude `#FF8C00`, Codex `#4169E1`, OpenCode `#C0C0C0`; (2) real OpenCode Go quota usage via the official `https://opencode.ai/zen/go/v1/usage` endpoint, replacing the `.unsupported` spike; (3) a discreet version label (`v<CFBundleShortVersionString>`) in the popover's top-right corner.

---

## Implementation Decisions

### Color semantics (bars + icon)

- Provider color ALWAYS wins: no green/amber/red usage-level tinting on popover bar fills or menu bar icon bars/text, at any usage percentage (user: "sempre cor do provedor").
- The % number text remains the usage-level signal; no replacement warning affordance is added.
- The menu bar icon is colored per provider too (user: "ícone + popover") — superseding the old feature's "same color palette as the icon" rule with the new provider palette.
- Neutral (no-data) rendering and template-only-when-all-neutral behavior are preserved unchanged.

### OpenCode naming

- UI copy says "OpenCode" (picker, default-label prompt, API-key prompt, reauth instructions, unsupported fallback) — user choice.
- `ProviderKind.openCodeGo` case name and rawValue stay untouched (persisted `AppState` compatibility).

### Version label

- Top-right of the popover, format `v<version>`, caption-scale, secondary color, in both empty and tabbed states; hidden if version unavailable.

### GitHub Copilot Premium requests

- Add a fourth provider tab named "GitHub Copilot" with accent `#6A5ACD` on the popover bar and menu-bar icon.
- Read the quota through the installed Copilot CLI's headless stdio JSON-RPC interface (`connect`, then `account.getQuota`), using the CLI's existing login.
- Display only `premium_interactions`: the source reports `remainingPercentage`, so `usedPercent` is `100 - remainingPercentage`, clamped to `0...100`; unlimited `chat` and `completions` quotas are not rendered.
- Map the premium quota reset date to `LimitWindow.resetsAt`; no API-key field is added to Settings.
- Persist the provider raw value as `githubCopilot`.

### Agent's Discretion

- Exact layout mechanics of the version label (HStack beside the tab scroll view vs. overlay) as long as it never overlaps tab pills and appears in both states.
- Parser internals for the OpenCode payload (defensive field access, clamping) as long as EARS ACs PID-09…PID-14 hold.
- Whether `dollarCaps`/`periodKeys` statics are removed or repurposed when the spike parsing is replaced.

### Declined / Undiscussed Gray Areas → Assumptions

- Full live response shape of `/zen/go/v1/usage` (reset-timestamp field names, dollar fields, `status` values beyond `"ok"`) — pinned by capturing a real payload during implementation; parser treats unknown/missing fields defensively. Logged in spec Assumptions.
- `usedAbsolute` stays `nil` unless the payload explicitly carries a dollar amount (deriving from caps would mislead with "Use balance" enabled). Logged in spec Assumptions.
- `.unsupported` enum case + popover branch retained as graceful-degradation safety even though GoAdapter stops throwing it. Logged in spec Assumptions.
- Version label is not localized (locale-neutral `v%s`). Logged in spec Assumptions.
- Copilot CLI quota access is experimental and version-coupled to the CLI's headless JSON-RPC protocol; unavailable CLI, RPC failure, or invalid quota payload degrades through existing network/unauthorized/parseFailed states.

---

## Specific References

- Exact hex colors from the user: `#FF8C00` (Claude), `#4169E1` (Codex), `#C0C0C0` (OpenCode) — "ou o mais próximo dela"; exact sRGB components used, no approximation needed.
- User's screenshot of the current popover (tabs top-left, window rows with bars, footer with gear/refresh) — version label goes in the empty top-right area beside the tab row.
- Endpoint evidence: anomalyco/opencode issue #43983 (maintainer confirms `GET https://opencode.ai/zen/go/v1/usage`, Bearer API key, returns current rolling/weekly/monthly quota windows) and cc-switch issue #6433 (response envelope `usage.{rolling,weekly,monthly}` with `status: "ok"` + `percent: number`).
- Go plan caps for reference only: $12/5h, $30/week, $60/month (docs/go).

---

## Deferred Ideas

- Zen balance display (upstream #10448, open feature request) — no API-key endpoint today.
- Go usage history (upstream #43983) — only current windows matter for this feature.
- Removing/reworking the dead Codex auth.json→chatgpt.com fallback — pending candidate decision in STATE.md Handoff.
- Re-adding a usage-level warning affordance (e.g. colored % text) if "provider color always" proves to hide high usage in practice.
