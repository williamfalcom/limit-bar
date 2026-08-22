#!/usr/bin/env bash
# limit-bar build script.
#
# Usage:
#   scripts/build.sh dev                 # Debug build into .build/dd and launch it
#   scripts/build.sh dev --no-open       # Build but do not launch
#   scripts/build.sh prod                # Release build, package dist/limit-bar-v<version>.zip
#   scripts/build.sh prod --dmg          # Also produce a compressed DMG in dist/
#   scripts/build.sh test                # Full test gate (xcodegen + xcodebuild test)
#
# Versioning: the single source of truth is the VERSION file at the repo root
# (semver, e.g. 0.1.0). Bump it there; both dev and prod builds inject it as
# MARKETING_VERSION (CFBundleShortVersionString) and use the git commit count
# as CURRENT_PROJECT_VERSION (CFBundleVersion). Tag releases with `v<version>`.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-dev}"
FLAG="${2:-}"
VERSION="$(cat VERSION | tr -d '[:space:]')"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

XCODEBUILD="xcodebuild -project limit-bar.xcodeproj -scheme limit-bar -destination 'platform=macOS'"

need_xcodegen() {
  command -v xcodegen >/dev/null 2>&1 || { echo "error: xcodegen is required (brew install xcodegen)" >&2; exit 1; }
}

regen() {
  need_xcodegen
  xcodegen generate >/dev/null
}

app_path() { # $1 = configuration, $2 = derived data path
  echo "$2/Build/Products/$1/limit-bar.app"
}

case "$MODE" in
  dev)
    DD=".build/dd"
    regen
    echo "==> Building dev (Debug) v$VERSION ($BUILD_NUMBER)"
    eval "$XCODEBUILD -configuration Debug -derivedDataPath '$DD' MARKETING_VERSION='$VERSION' CURRENT_PROJECT_VERSION='$BUILD_NUMBER' build" \
      | tail -n 3
    if [ "$FLAG" != "--no-open" ]; then
      pkill -f "MacOS/limit-bar" 2>/dev/null || true
      sleep 1
      open "$(app_path Debug "$DD")"
      echo "==> launched $(app_path Debug "$DD")"
    fi
    ;;

  prod|package|release)
    DD=".build/release"
    OUT="$ROOT/dist"
    regen
    echo "==> Building release v$VERSION ($BUILD_NUMBER)"
    eval "$XCODEBUILD -configuration Release -derivedDataPath '$DD' MARKETING_VERSION='$VERSION' CURRENT_PROJECT_VERSION='$BUILD_NUMBER' clean build" \
      | tail -n 3

    APP="$(app_path Release "$DD")"
    mkdir -p "$OUT"
    rm -rf "$OUT/limit-bar.app"
    ditto "$APP" "$OUT/limit-bar.app"

    # Re-sign ad hoc after ditto to keep signature valid for local install
    codesign --force --deep --sign - "$OUT/limit-bar.app" >/dev/null

    ZIP="$OUT/limit-bar-v$VERSION.zip"
    rm -f "$ZIP"
    (cd "$OUT" && zip -qry "limit-bar-v$VERSION.zip" "limit-bar.app")
    echo "==> packaged $OUT/limit-bar.app"
    echo "==> packaged $ZIP"

    if [ "$FLAG" == "--dmg" ]; then
      DMG_STAGING="$(mktemp -d)"
      cp -R "$OUT/limit-bar.app" "$DMG_STAGING/"
      ln -s /Applications "$DMG_STAGING/Applications"
      DMG="$OUT/limit-bar-v$VERSION.dmg"
      rm -f "$DMG"
      hdiutil create -volname "limit-bar v$VERSION" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG" >/dev/null
      rm -rf "$DMG_STAGING"
      echo "==> packaged $DMG"
    fi

    echo "==> install: copy dist/limit-bar.app to /Applications (or open the DMG and drag)"
    echo "==> note: ad-hoc signed. On other Macs, right-click > Open on first run to bypass Gatekeeper."
    ;;

  test)
    regen
    echo "==> Running tests v$VERSION"
    eval "$XCODEBUILD test" | tail -n 5
    ;;

  *)
    echo "usage: scripts/build.sh [dev [--no-open] | prod [--dmg] | test]" >&2
    exit 1
    ;;
esac
