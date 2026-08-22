<p align="center">
  <img src="docs/img/icon-512.png" width="128" alt="limit-bar icon">
</p>

<h1 align="center">limit-bar</h1>

<p align="center">
  <strong>Your AI subscription limits, live in the macOS menu bar.</strong><br>
  Claude Code · Codex · OpenCode Go — one glance, never a surprise lockout.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.es.md">Español</a>
</p>

---

## What it does

limit-bar sits quietly in your menu bar and shows how much of your AI plan's time window you have already used. Click the icon to open a compact panel with one tab per account and one progress bar per limit window — percentages, absolute values when the provider reports them, and countdowns to the next reset.

| Where | What you see |
| --- | --- |
| Menu bar | One live bar **per account**, each tinted green (<70%), amber (70–89%) or red (≥90%); at 100% the bar's % becomes a reset countdown |
| Panel (click) | Tabs per account/plan, one labeled progress bar per limit window, staleness footer, refresh button, settings gear |

<p align="center">
  <img src="docs/img/menubar.png" width="320" alt="limit-bar live icon in the macOS menu bar"><br>
  <em>The live menu bar icon: one bar per account with its own percentage.</em>
</p>

<p align="center">
  <img src="docs/img/panel.png" width="420" alt="limit-bar limits panel"><br>
  <em>The limits panel: every window of the selected account on one screen.</em>
</p>

## Supported providers

| Provider | Windows tracked | Data source |
| --- | --- | --- |
| **Claude Code** (Pro/Max/Team) | 5-hour session · Weekly · per-model weekly buckets (Fable, Opus, …) | Anthropic OAuth usage endpoint, token read locally from your Keychain |
| **Codex** (Plus/Pro) | ~5-hour primary · weekly secondary | `codex app-server` JSON-RPC, falling back to `$CODEX_HOME/auth.json` |
| **OpenCode Go** | 5h · weekly · monthly ($12/$30/$60 caps) | Awaiting a public usage API (upstream issues [#10448](https://github.com/anomalyco/opencode/issues/10448), [#18648](https://github.com/anomalyco/opencode/issues/18648)); the tab shows an explicit "not available yet" state |

## Installation

**Requirements:** macOS 14 (Sonoma) or later.

1. Download `limit-bar-v0.1.0.dmg` (or the `.zip`) from the latest release.
2. Open it and drag **limit-bar.app** into **Applications**.
3. Launch limit-bar — its icon appears in the menu bar (the app has no Dock icon by design).

<p align="center">
  <img src="docs/img/install.png" width="480" alt="Installing limit-bar from the DMG"><br>
  <em>Drag limit-bar into Applications.</em>
</p>

> The released build is **ad-hoc signed**. On this Mac it opens right away; on other Macs, right-click → **Open** on first run to pass Gatekeeper.

## First run

1. Click the menu bar icon → the panel opens with an empty state.
2. Hit the **gear** (or *Add your first account*) to open Settings.
3. Add accounts:
   - **Claude Code** — nothing to type. limit-bar reads the OAuth token your Claude Code CLI already stored in the Keychain (`Claude Code-credentials`). When macOS asks, choose **Always Allow**.
   - **Codex** — also automatic: rate limits come from `codex app-server`, using whatever login your CLI already has.
   - **OpenCode Go** — paste your API key once; it is stored in the Keychain.
4. New accounts are polled immediately; afterwards every account refreshes on a conservative cadence (default **300 s**, configurable 60–3600 s) with exponential backoff whenever a provider answers `429`.

### Using it day to day

- The **icon bars** mirror every account; selecting a tab in the panel decides which account's % text shows next to them.
- **Esc** or clicking outside closes the panel; the ⟳ button forces an immediate refresh of all accounts.
- Enable **Start at Login** in Settings so monitoring survives reboots.
- The interface follows your macOS language (**English**, **Português**, **Español** today). Per-app override works too: System Settings → limit-bar → Language.

## Privacy

Everything stays on your machine. There is no telemetry, no account service and no analytics. limit-bar only talks to the providers you configured, reusing the credentials their own CLIs store locally, and polls read-only usage endpoints at a deliberately slow cadence so monitoring never disturbs your quotas.

## Build from source

Requirements: Xcode with `xcodebuild`, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Zero third-party dependencies.

```bash
scripts/build.sh dev          # Debug build and launch
scripts/build.sh prod --dmg   # Release .app + .zip + .dmg into dist/
scripts/build.sh test         # Full test gate (Swift Testing suite)
```

The project layout is generated from `project.yml`; run `xcodegen generate` after editing it. Sources live in `Sources/LimitBar/` (App/Core/Providers/UI), tests in `Tests/LimitBarTests/`.

## Versioning

Single source of truth: the [`VERSION`](VERSION) file (semver). Builds inject it as the bundle's marketing version; the git commit count becomes the build number. Releases are tagged `v<version>` — currently **v0.1.0**.

---

<div align="center">
  <sub>Built for developers who juggle several AI plans at once.</sub><br>
  <sub><strong>English</strong> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.es.md">Español</a></sub>
</div>
