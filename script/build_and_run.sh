#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Prompt Producer"
EXECUTABLE_NAME="PromptProducer"
BUNDLE_ID="aloes"
MIN_SYSTEM_VERSION="14.0"
VERSION="${PROMPT_PRODUCER_VERSION:-1.0}"
BUILD_NUMBER="${PROMPT_PRODUCER_BUILD_NUMBER:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROMPT_PRODUCER_DIST_DIR:-$HOME/Library/Application Support/Prompt Producer/Build}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
SENTRY_DSN="${PROMPT_PRODUCER_SENTRY_DSN:-}"
SENTRY_ENVIRONMENT="${PROMPT_PRODUCER_SENTRY_ENVIRONMENT:-development}"
DEVELOPMENT_TEAM="${PROMPT_PRODUCER_DEVELOPMENT_TEAM:-95W8G892Z4}"
CODE_SIGN_STYLE="${PROMPT_PRODUCER_CODE_SIGN_STYLE:-Automatic}"
CODE_SIGN_IDENTITY="${PROMPT_PRODUCER_CODE_SIGN_IDENTITY:-}"
CODE_SIGN_ENTITLEMENTS="${PROMPT_PRODUCER_CODE_SIGN_ENTITLEMENTS:-}"

cd "$ROOT_DIR"

pkill -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true

if [[ -z "$SENTRY_DSN" ]] && command -v doppler >/dev/null 2>&1; then
  SENTRY_DSN="$(doppler secrets get PROMPT_PRODUCER_SENTRY_DSN --plain --project quickapp --config dev 2>/dev/null || true)"
fi

"$ROOT_DIR/script/build_blocknote_assets.sh"

swift build --disable-automatic-resolution
BUILD_BIN_DIR="$(swift build --disable-automatic-resolution --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$EXECUTABLE_NAME"
RESOURCE_BUNDLE="$BUILD_BIN_DIR/PromptProducer_PromptProducer.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

find "$BUILD_BIN_DIR" -maxdepth 1 -type d -name "*.bundle" -print0 | while IFS= read -r -d '' resource_bundle; do
  bundle_name="$(basename "$resource_bundle")"
  rm -rf "$APP_RESOURCES/$bundle_name"
  cp -R "$resource_bundle" "$APP_RESOURCES/"
done

if [[ -d "$RESOURCE_BUNDLE/BlockNoteEditor" ]]; then
  rm -rf "$APP_RESOURCES/BlockNoteEditor"
  cp -R "$RESOURCE_BUNDLE/BlockNoteEditor" "$APP_RESOURCES/"
fi

if [[ ! -f "$APP_ICON_SOURCE" ]]; then
  swift "$ROOT_DIR/script/generate_app_icon.swift"
fi

if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

find "$BUILD_BIN_DIR" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' dependency; do
  cp -R "$dependency" "$APP_FRAMEWORKS/"
done

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Prompt Producer can paste a selected prompt into the app you were using when you ask it to.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>Prompt Producer uses accessibility access only to paste a selected prompt into the active text field when requested.</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
</dict>
</plist>
PLIST

if [[ -n "$SENTRY_DSN" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SentryDSN string $SENTRY_DSN" "$INFO_PLIST" >/dev/null
  /usr/libexec/PlistBuddy -c "Add :SentryEnvironment string $SENTRY_ENVIRONMENT" "$INFO_PLIST" >/dev/null
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_BUNDLE" 2>/dev/null || true
  xattr -dr "com.apple.provenance" "$APP_BUNDLE" 2>/dev/null || true
  xattr -dr "com.apple.FinderInfo" "$APP_BUNDLE" 2>/dev/null || true
  xattr -dr "com.apple.fileprovider.fpfs#P" "$APP_BUNDLE" 2>/dev/null || true
  while IFS= read -r -d '' bundled_path; do
    xattr -c "$bundled_path" 2>/dev/null || true
    xattr -d "com.apple.provenance" "$bundled_path" 2>/dev/null || true
    xattr -d "com.apple.FinderInfo" "$bundled_path" 2>/dev/null || true
    xattr -d "com.apple.fileprovider.fpfs#P" "$bundled_path" 2>/dev/null || true
  done < <(find "$APP_BUNDLE" -print0)
fi

resolve_signing_identity() {
  if [[ "$CODE_SIGN_STYLE" != "Automatic" ]]; then
    echo "${CODE_SIGN_IDENTITY:--}"
    return
  fi

  if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    echo "$CODE_SIGN_IDENTITY"
    return
  fi

  local identity
  # Prefer Developer ID for locally launched packaged macOS apps.
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n "s/^ *[0-9]*) *\\([A-Fa-f0-9]*\\) \".*Developer ID Application: .* (${DEVELOPMENT_TEAM})\".*/\\1/p" \
      | head -n 1
  )"

  # Fallback to Apple Development identities for the specified DEVELOPMENT_TEAM.
  if [[ -z "$identity" ]]; then
    identity="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | sed -n "s/^ *[0-9]*) *\\([A-Fa-f0-9]*\\) \".*Apple Development: .* (${DEVELOPMENT_TEAM})\".*/\\1/p" \
        | head -n 1
    )"
  fi

  # If no team-specific identity was found, try any Developer ID or Apple Development identity.
  if [[ -z "$identity" ]]; then
    identity="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/^ *[0-9]*) *\([A-Fa-f0-9]*\) ".*Developer ID Application: .*".*/\1/p' \
        | head -n 1
    )"
  fi

  if [[ -z "$identity" ]]; then
    identity="$(
      security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/^ *[0-9]*) *\([A-Fa-f0-9]*\) ".*Apple Development: .*".*/\1/p' \
        | head -n 1
    )"
  fi

  echo "${identity:--}"
}

SIGNING_IDENTITY="$(resolve_signing_identity)"
CODESIGN_ARGS=(--force --sign "$SIGNING_IDENTITY" --timestamp=none)
APP_CODESIGN_ARGS=(--force --deep --sign "$SIGNING_IDENTITY" --timestamp=none)

if [[ -n "$CODE_SIGN_ENTITLEMENTS" ]]; then
  APP_CODESIGN_ARGS+=(--entitlements "$CODE_SIGN_ENTITLEMENTS")
fi

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  echo "warning: no suitable signing identity found for team $DEVELOPMENT_TEAM; falling back to ad-hoc signing" >&2
else
  echo "Signing with $SIGNING_IDENTITY (CODE_SIGN_STYLE=$CODE_SIGN_STYLE, DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM)"
fi

find "$APP_FRAMEWORKS" -mindepth 1 -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' dependency; do
  codesign "${CODESIGN_ARGS[@]}" "$dependency"
done

if ! codesign "${APP_CODESIGN_ARGS[@]}" "$APP_BUNDLE"; then
  echo "warning: codesigning failed; continuing for local development launch" >&2
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  package|--package)
    echo "$APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$EXECUTABLE_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$EXECUTABLE_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
