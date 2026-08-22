# AGENTS.md

## Status

- **limit-bar**: native macOS 14+ menu bar app (SwiftUI `MenuBarExtra`, Swift 6 strict concurrency, zero third-party dependencies).
- Project is generated from `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Run `xcodegen generate` after editing `project.yml`; the generated `.xcodeproj` is not committed.
- Sources in `Sources/LimitBar/` (App/Core/Providers/UI), tests in `Tests/LimitBarTests/` using **Swift Testing** (`import Testing`).

## Conventions

- Build script (single entry point): `scripts/build.sh [dev [--no-open] | prod [--dmg] | test]`
- Test/build gate (run from repo root):
  `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'`
- Full build gate: `xcodegen generate && xcodebuild build ... && xcodebuild test ...` (see `.specs/features/menu-bar-limits/tasks.md` → Gate Check Commands)
- Spec-driven workflow lives in `.specs/` (STATE.md decisions AD-001…AD-005 are binding constraints).

## Versioning

- Single source of truth: `VERSION` file at repo root (semver; current `0.1.0`). Bump it there only.
- `scripts/build.sh` injects it as `MARKETING_VERSION` (`CFBundleShortVersionString`); git commit count becomes `CURRENT_PROJECT_VERSION` (build number).
- Releases are tagged `v<version>` (e.g., `v0.1.0`). Prod artifacts land in `dist/` (.app, .zip, optional .dmg via `--dmg`).
- Localization: keys are English source strings; tables in `Sources/LimitBar/Resources/{en,pt-BR,es}.lproj/Localizable.strings`. When adding UI text, add the key to all three tables (missing keys fall back to English automatically).
