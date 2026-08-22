# LESSONS - auto-maintained by scripts/lessons.py

> Machine-owned. Do NOT hand-edit. Changes are overwritten on the next `lessons.py` write.
> Canonical state lives in `.specs/lessons.json`. Edit lessons only via the script.
> promote_threshold=2 distinct features · window_days=45 · quarantine_threshold=2

## Confirmed (load these at Specify/Design)

Corroborated across multiple features. Safe to apply as guidance.

_none_

## Candidates (under observation - do NOT load as guidance yet)

Seen once or not yet corroborated. Tracked, not trusted.

### L-001 - MenuBarExtra window content does not re-render on @Observable changes; force identity rebuild (.id) or host in NSPopover/NSStatusItem (AD-001 fallback).
- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `ui` · harmful: 0
- features: menu-bar-limits
- evidence: UAT: invisible icon (ui)
- last seen: 2026-08-22T03:44:37Z

### L-002 - Always draw the track of a status-item progress bar; a nil-fill neutral state must still render visibly.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `ui` · harmful: 0
- features: menu-bar-limits
- evidence: UAT: LIM-06 neutral state (ui)
- last seen: 2026-08-22T03:44:37Z

### L-003 - Interrupt the polling sleep when an account is added; never let a fresh account wait out an in-flight 300s cycle.
- signal: `ac_gap` · recurrence: 1 feature(s) · scope: `core` · harmful: 0
- features: menu-bar-limits
- evidence: UAT: new accounts stale (core)
- last seen: 2026-08-22T03:44:37Z

### L-004 - Codex app-server requires initialize with clientInfo before any request and returns camelCase result.rateLimits.{primary,secondary} with epoch-seconds resetsAt.
- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `providers` · harmful: 0
- features: menu-bar-limits
- evidence: codex app-server live probe (providers)
- last seen: 2026-08-22T03:44:37Z

### L-005 - Anthropic oauth usage needs User-Agent claude-code/* to avoid the throttled bucket; parse the normalized limits[] array (session/weekly_all/weekly_scoped) first, legacy seven_day_* as fallback.
- signal: `spec_precision_gap` · recurrence: 1 feature(s) · scope: `providers` · harmful: 0
- features: menu-bar-limits
- evidence: anthropic usage live probe (providers)
- last seen: 2026-08-22T03:44:37Z

### L-006 - Unit tests resolve NSLocalizedString in the user language; assert against source constants, never against English literals.
- signal: `gate_fail` · recurrence: 1 feature(s) · scope: `tests` · harmful: 0
- features: menu-bar-limits
- evidence: IconRendererTests locale failures (tests)
- last seen: 2026-08-22T03:44:37Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
