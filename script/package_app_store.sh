#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROMPT_PRODUCER_APPSTORE_DIR:-${TMPDIR:-/tmp}/prompt-producer-appstore}"
VERSION="${PROMPT_PRODUCER_VERSION:-1.0}"
BUILD_NUMBER="${PROMPT_PRODUCER_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP_SIGNING_IDENTITY_REQUEST="${PROMPT_PRODUCER_APPSTORE_APP_IDENTITY:-Apple Distribution: Alex Richard Fiore (95W8G892Z4)}"
INSTALLER_SIGNING_IDENTITY_REQUEST="${PROMPT_PRODUCER_APPSTORE_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: Alex Richard Fiore (95W8G892Z4)}"
APP_BUNDLE_DIR="$BUILD_DIR/bundle"
PKG_PATH="$BUILD_DIR/PromptProducer-${VERSION}-${BUILD_NUMBER}.pkg"

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"

resolve_identity() {
  local requested="$1"
  local policy="${2:-}"

  if [[ "$requested" == "-" || "$requested" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo "$requested"
    return
  fi

  local args=(-v)
  if [[ -n "$policy" ]]; then
    args+=(-p "$policy")
  fi

  local resolved
  resolved="$(
    security find-identity "${args[@]}" 2>/dev/null \
      | awk -v name="$requested" 'index($0, "\"" name "\"") { resolved=$2 } END { if (resolved) print resolved }'
  )"

  echo "${resolved:-$requested}"
}

APP_SIGNING_IDENTITY="$(resolve_identity "$APP_SIGNING_IDENTITY_REQUEST" codesigning)"
INSTALLER_SIGNING_IDENTITY="$(resolve_identity "$INSTALLER_SIGNING_IDENTITY_REQUEST")"

purge_bundle_metadata() {
  local bundle_path="$1"

  find "$bundle_path" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
  xattr -cr "$bundle_path" 2>/dev/null || true

  while IFS= read -r -d '' bundled_path; do
    xattr -c "$bundled_path" 2>/dev/null || true
    xattr -d "com.apple.provenance" "$bundled_path" 2>/dev/null || true
    xattr -d "com.apple.FinderInfo" "$bundled_path" 2>/dev/null || true
    xattr -d "com.apple.fileprovider.fpfs#P" "$bundled_path" 2>/dev/null || true
  done < <(find "$bundle_path" -print0)
}

strip_arm64e_slices() {
  local bundle_path="$1"

  while IFS= read -r -d '' candidate; do
    local info
    info="$(lipo -info "$candidate" 2>/dev/null || true)"
    if [[ "$info" != *"arm64e"* ]]; then
      continue
    fi

    local mode
    mode="$(stat -f "%Lp" "$candidate")"
    lipo "$candidate" -remove arm64e -output "$candidate.without-arm64e"
    mv "$candidate.without-arm64e" "$candidate"
    chmod "$mode" "$candidate"
  done < <(find "$bundle_path" -type f -print0)
}

APP_BUNDLE="$(
  PROMPT_PRODUCER_DIST_DIR="$APP_BUNDLE_DIR" \
  PROMPT_PRODUCER_VERSION="$VERSION" \
  PROMPT_PRODUCER_BUILD_NUMBER="$BUILD_NUMBER" \
  PROMPT_PRODUCER_CODE_SIGN_STYLE="Manual" \
  PROMPT_PRODUCER_CODE_SIGN_IDENTITY="$APP_SIGNING_IDENTITY" \
  PROMPT_PRODUCER_CODE_SIGN_ENTITLEMENTS="$ROOT_DIR/Distribution/AppStore.entitlements" \
  "$ROOT_DIR/script/build_and_run.sh" package | tail -n 1
)"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "App bundle was not created: $APP_BUNDLE" >&2
  exit 1
fi

purge_bundle_metadata "$APP_BUNDLE"
strip_arm64e_slices "$APP_BUNDLE"

find "$APP_BUNDLE/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' dependency; do
  purge_bundle_metadata "$dependency"
  codesign --force --sign "$APP_SIGNING_IDENTITY" --timestamp=none "$dependency"
done

purge_bundle_metadata "$APP_BUNDLE"
codesign \
  --force \
  --deep \
  --strict \
  --sign "$APP_SIGNING_IDENTITY" \
  --timestamp=none \
  --entitlements "$ROOT_DIR/Distribution/AppStore.entitlements" \
  "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -f "$PKG_PATH"
productbuild \
  --component "$APP_BUNDLE" /Applications \
  --sign "$INSTALLER_SIGNING_IDENTITY" \
  "$PKG_PATH"

pkgutil --check-signature "$PKG_PATH"
echo "$PKG_PATH"
