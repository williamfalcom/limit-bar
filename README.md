<p align="center">
  <img src="docs/img/icon-512.png" width="128" alt="limit-bar icon">
</p>

<h1 align="center">limit-bar</h1>

<p align="center">
  <strong>Your AI subscription limits, live in the macOS menu bar.</strong><br>
  Claude Code · Codex · OpenCode · GitHub Copilot — one glance, never a surprise lockout.
</p>

<p align="center">
  <strong>English</strong> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.es.md">Español</a>
</p>

---

## What it does

limit-bar sits quietly in your menu bar and shows how much of your AI plan's time window you have already used. Click the icon to open a compact panel with one tab per account and one progress bar per limit window — percentages, absolute values when the provider reports them, and countdowns to the next reset.

| Where | What you see |
| --- | --- |
| Menu bar | One live bar **per account**, tinted with its provider's color (Claude orange, Codex blue, OpenCode silver, Copilot purple); at 100% the bar's % becomes a reset countdown |
| Panel (click) | Tabs per account/plan, provider-colored progress bars for every limit window, reset countdowns, staleness footer, app version, refresh button, settings gear |

<p align="center">
  <img src="docs/img/menubar.png" width="220" alt="limit-bar live icon in the macOS menu bar"><br>
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
| **OpenCode** | 5-hour rolling · weekly · monthly | Official OpenCode Go usage endpoint, authenticated with the API key stored in your Keychain |
| **GitHub Copilot** | Monthly Premium requests | Authenticated Copilot CLI (`account.getQuota` over headless JSON-RPC); unlimited chat and completions quotas are omitted |

## Installation

**Requirements:** macOS 14 (Sonoma) or later.

1. Download `limit-bar-v0.2.0.dmg` (or the `.zip`) from the [latest release](https://github.com/williamfalcom/limit-bar/releases/latest).
2. Open it and drag **limit-bar.app** into **Applications**.
3. Launch limit-bar — its icon appears in the menu bar (the app has no Dock icon by design).

<p align="center">
  <img src="docs/img/install.png" width="360" alt="Installing limit-bar from the DMG"><br>
  <em>Drag limit-bar into Applications.</em>
</p>

> The released build is **ad-hoc signed**. If Gatekeeper blocks the first launch, right-click the app and choose **Open**.

## First run

1. Click the menu bar icon → the panel opens with an empty state.
2. Hit the **gear** (or *Add your first account*) to open Settings.
3. Add accounts:
   - **Claude Code** — nothing to type. limit-bar reads the OAuth token your Claude Code CLI already stored in the Keychain (`Claude Code-credentials`). When macOS asks, choose **Always Allow**.
   - **Codex** — also automatic: rate limits come from `codex app-server`, using whatever login your CLI already has.
   - **OpenCode** — paste your API key once; it is stored in the Keychain and used with the official usage endpoint.
   - **GitHub Copilot** — automatic when the `copilot` CLI is installed and authenticated (`copilot login`). limit-bar shows the finite Premium requests quota.
4. New accounts are polled immediately; afterwards every account refreshes on a conservative cadence (default **300 s**, configurable 60–3600 s) with exponential backoff whenever a provider answers `429`.

<p align="center">
  <img src="docs/img/settings.png" width="420" alt="limit-bar Settings with one account per provider"><br>
  <em>Add each provider as a separate account in Settings.</em>
</p>

### Using it day to day

- The **icon bars** mirror every account in its provider color; selecting a tab in the panel decides which account's % text shows next to them.
- **Esc** or clicking outside closes the panel; the ⟳ button forces an immediate refresh of all accounts.
- Right-click the menu bar icon to refresh, open Settings or quit limit-bar.
- Enable **Start at Login** in Settings so monitoring survives reboots.
- The interface follows your macOS language (**English**, **Português**, **Español** today). Per-app override works too: System Settings → limit-bar → Language.

## Privacy

Everything stays on your machine. There is no telemetry, no account service and no analytics. limit-bar uses the existing local CLI sessions for Claude Code, Codex and GitHub Copilot, keeps your OpenCode API key in the Keychain, and polls read-only usage endpoints at a deliberately slow cadence so monitoring never disturbs your quotas.

## Build from source

Requirements: Xcode with `xcodebuild`, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Zero third-party dependencies.

```bash
scripts/build.sh dev          # Debug build and launch
scripts/build.sh prod --dmg   # Release .app + .zip + .dmg into dist/
scripts/build.sh test         # Full test gate (Swift Testing suite)
```

The project layout is generated from `project.yml`; run `xcodegen generate` after editing it. Sources live in `Sources/LimitBar/` (App/Core/Providers/UI), tests in `Tests/LimitBarTests/`.

## Versioning

Single source of truth: the [`VERSION`](VERSION) file (semver). Builds inject it as the bundle's marketing version; the git commit count becomes the build number. Releases are tagged `v<version>` — currently **[v0.2.0](https://github.com/williamfalcom/limit-bar/releases/tag/v0.2.0)**.

---

<div align="center">
  <sub>Built for developers who juggle several AI plans at once.</sub><br>
  <sub><strong>English</strong> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.es.md">Español</a></sub>
</div>
