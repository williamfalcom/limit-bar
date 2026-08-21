# AGENTS.md

## Status

- **limit-bar**: native macOS 14+ menu bar app (SwiftUI `MenuBarExtra`, Swift 6 strict concurrency, zero third-party dependencies).
- Project is generated from `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Run `xcodegen generate` after editing `project.yml`; the generated `.xcodeproj` is not committed.
- Sources in `Sources/LimitBar/` (App/Core/Providers/UI), tests in `Tests/LimitBarTests/` using **Swift Testing** (`import Testing`).

## Conventions

- Test/build gate (run from repo root):
  `xcodebuild test -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'`
- Full build gate: `xcodegen generate && xcodebuild build ... && xcodebuild test ...` (see `.specs/features/menu-bar-limits/tasks.md` → Gate Check Commands)
- Spec-driven workflow lives in `.specs/` (STATE.md decisions AD-001…AD-005 are binding constraints).
