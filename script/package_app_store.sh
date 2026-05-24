#!/bin/zsh
set -euo pipefail
if [[ -n "${ZSH_VERSION:-}" ]]; then
  setopt TYPESET_SILENT
fi

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
ROOT_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
MODE="${1:---package}"
BUILD_DIR="${PROMPT_PRODUCER_APPSTORE_DIR:-${TMPDIR:-/tmp}/prompt-producer-appstore}"
VERSION="${PROMPT_PRODUCER_VERSION:-1.0}"
BUILD_NUMBER="${PROMPT_PRODUCER_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
APP_SIGNING_IDENTITY_REQUEST="${PROMPT_PRODUCER_APPSTORE_APP_IDENTITY:-Apple Distribution: Alex Richard Fiore (95W8G892Z4)}"
INSTALLER_SIGNING_IDENTITY_REQUEST="${PROMPT_PRODUCER_APPSTORE_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: Alex Richard Fiore (95W8G892Z4)}"
APP_BUNDLE_DIR="$BUILD_DIR/bundle"
PACKAGE_ROOT="$BUILD_DIR/package-root"
PACKAGE_APP="$PACKAGE_ROOT/Prompt Producer.app"
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

# purge_bundle_metadata removes common macOS metadata files, makes bundle contents writable,
# and clears extended attributes. com.apple.provenance can survive some per-file
# clears in this packaging path, so use recursive clears plus symlink-specific clears.
purge_bundle_metadata() {
  local bundle_path="$1"

  find "$bundle_path" \( -name "._*" -o -name ".DS_Store" \) -delete 2>/dev/null || true
  chmod -R u+w "$bundle_path" 2>/dev/null || true
  /usr/bin/xattr -cr "$bundle_path" 2>/dev/null || true

  while IFS= read -r -d '' bundled_path; do
    if [[ -L "$bundled_path" ]]; then
      /usr/bin/xattr -c -s "$bundled_path" 2>/dev/null || true
      /usr/bin/xattr -d -s "com.apple.provenance" "$bundled_path" 2>/dev/null || true
    else
      /usr/bin/xattr -c "$bundled_path" 2>/dev/null || true
      /usr/bin/xattr -d "com.apple.provenance" "$bundled_path" 2>/dev/null || true
    fi
  done < <(/usr/bin/find "$bundle_path" -print0)

  /usr/bin/xattr -cr "$bundle_path" 2>/dev/null || true
  while IFS= read -r -d '' symlink_path; do
    /usr/bin/xattr -c -s "$symlink_path" 2>/dev/null || true
    /usr/bin/xattr -d -s "com.apple.provenance" "$symlink_path" 2>/dev/null || true
  done < <(/usr/bin/find "$bundle_path" -type l -print0)

  # On current macOS, bash-launched xattr can leave com.apple.provenance behind.
  # A zsh-launched final pass removes it consistently before productbuild.
  /bin/zsh -f -c '
    bundle_path="$1"
    /usr/bin/xattr -cr "$bundle_path" 2>/dev/null || true
    /usr/bin/find "$bundle_path" -type l -exec /usr/bin/xattr -c -s {} \; 2>/dev/null || true
    /usr/bin/find "$bundle_path" -type l -exec /usr/bin/xattr -d -s "com.apple.provenance" {} \; 2>/dev/null || true
  ' zsh "$bundle_path"
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

assert_bundle_metadata_free() {
  local bundle_path="$1"
  local metadata_files_count
  local xattr_count
  local attempt

  for attempt in 1 2 3 4 5; do
    purge_bundle_metadata "$bundle_path"

    metadata_files_count="$(find "$bundle_path" \( -name "._*" -o -name ".DS_Store" \) -print | wc -l | tr -d ' ')"
    xattr_count="$(find "$bundle_path" -xattr -print 2>/dev/null | wc -l | tr -d ' ')"

    if [[ "$metadata_files_count" -eq 0 && "$xattr_count" -eq 0 ]]; then
      sleep 1
      metadata_files_count="$(find "$bundle_path" \( -name "._*" -o -name ".DS_Store" \) -print | wc -l | tr -d ' ')"
      xattr_count="$(find "$bundle_path" -xattr -print 2>/dev/null | wc -l | tr -d ' ')"

      if [[ "$metadata_files_count" -eq 0 && "$xattr_count" -eq 0 ]]; then
        return
      fi
    fi

    sleep 1
  done

  metadata_files_count="$(find "$bundle_path" \( -name "._*" -o -name ".DS_Store" \) -print | wc -l | tr -d ' ')"
  xattr_count="$(find "$bundle_path" -xattr -print 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$metadata_files_count" -ne 0 ]]; then
    echo "Bundle contains $metadata_files_count Finder or AppleDouble metadata files: $bundle_path" >&2
    find "$bundle_path" \( -name "._*" -o -name ".DS_Store" \) -print | sed -n '1,50p' >&2
    exit 1
  fi

  if [[ "$xattr_count" -ne 0 ]]; then
    echo "Bundle contains $xattr_count extended-attribute entries before packaging: $bundle_path" >&2
    find "$bundle_path" -xattr -print 2>/dev/null | sed -n '1,50p' >&2
    exit 1
  fi
}

prepare_app_bundle() {
  local app_bundle

  app_bundle="$(
    PROMPT_PRODUCER_DIST_DIR="$APP_BUNDLE_DIR" \
    PROMPT_PRODUCER_VERSION="$VERSION" \
    PROMPT_PRODUCER_BUILD_NUMBER="$BUILD_NUMBER" \
    PROMPT_PRODUCER_CODE_SIGN_STYLE="Manual" \
    PROMPT_PRODUCER_CODE_SIGN_IDENTITY="$APP_SIGNING_IDENTITY" \
    PROMPT_PRODUCER_CODE_SIGN_ENTITLEMENTS="$ROOT_DIR/Distribution/AppStore.entitlements" \
    "$ROOT_DIR/script/build_and_run.sh" package | tail -n 1
  )"

  if [[ ! -d "$app_bundle" ]]; then
    echo "App bundle was not created: $app_bundle" >&2
    exit 1
  fi

  purge_bundle_metadata "$app_bundle"
  strip_arm64e_slices "$app_bundle"

  find "$app_bundle/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' dependency; do
    purge_bundle_metadata "$dependency"
    codesign --force --sign "$APP_SIGNING_IDENTITY" --timestamp=none "$dependency"
  done

  purge_bundle_metadata "$app_bundle"
  codesign \
    --force \
    --deep \
    --strict \
    --sign "$APP_SIGNING_IDENTITY" \
    --timestamp=none \
    --entitlements "$ROOT_DIR/Distribution/AppStore.entitlements" \
    "$app_bundle"

  purge_bundle_metadata "$app_bundle"
  codesign --verify --deep --strict --verbose=2 "$app_bundle"

  echo "$app_bundle"
}

assert_package_is_store_clean() {
  local pkg_path="$1"
  local metadata_plist="$BUILD_DIR/product-metadata.plist"
  local nonstandard_paths="$BUILD_DIR/nonstandard-paths.plist"

  extract_nonstandard_paths "$pkg_path" "$metadata_plist" "$nonstandard_paths" "$BUILD_DIR/product-expanded"

  for key in ds-store resource-fork; do
    if /usr/bin/plutil -extract "$key" xml1 -o - "$nonstandard_paths" | /usr/bin/grep -Fq "<string>"; then
      echo "Package contains nonstandard $key entries:" >&2
      /usr/bin/plutil -extract "$key" xml1 -o - "$nonstandard_paths" >&2
      exit 1
    fi
  done

  if /usr/bin/plutil -extract wayward-symlinks xml1 -o - "$nonstandard_paths" | /usr/bin/grep -Fq "<string>"; then
    sleep 1
    extract_nonstandard_paths "$pkg_path" "$metadata_plist" "$nonstandard_paths" "$BUILD_DIR/product-expanded-retry"
  fi

  if /usr/bin/plutil -extract wayward-symlinks xml1 -o - "$nonstandard_paths" | /usr/bin/grep -Fq "<string>"; then
    if package_payload_symlinks_resolve "$pkg_path"; then
      echo "warning: productutil reported wayward symlinks, but the expanded package payload resolves every symlink." >&2
    else
      echo "Package contains nonstandard wayward-symlinks entries:" >&2
      /usr/bin/plutil -extract wayward-symlinks xml1 -o - "$nonstandard_paths" >&2
      exit 1
    fi
  fi

  if /usr/bin/plutil -extract ext-attr xml1 -o - "$nonstandard_paths" | /usr/bin/grep -Fq "<string>"; then
    echo "warning: productutil reports signed-code extended attributes; App Store accepted prior builds with this metadata." >&2
  fi

  local appledouble_count
  appledouble_count="$(pkgutil --payload-files "$pkg_path" | /usr/bin/grep -c '/\._\|^\._' || true)"
  if [[ "$appledouble_count" -ne 0 ]]; then
    echo "Package payload contains $appledouble_count AppleDouble metadata files." >&2
    exit 1
  fi
}

extract_nonstandard_paths() {
  local pkg_path="$1"
  local metadata_plist="$2"
  local nonstandard_paths="$3"
  local expanded_dir="$4"

  rm -rf "$expanded_dir" "$metadata_plist" "$nonstandard_paths"
  /usr/libexec/productutil \
    --skip-attr-checks \
    --package "$pkg_path" \
    --expand "$expanded_dir" \
    --extract-metadata \
    --check-signature >"$metadata_plist"

  /usr/bin/plutil \
    -extract product-metadata.packages.0.nonstandard-paths xml1 \
    -o "$nonstandard_paths" \
    "$metadata_plist"
}

package_payload_symlinks_resolve() {
  local pkg_path="$1"
  local expanded_dir="$BUILD_DIR/payload-expanded"
  local broken_links="$BUILD_DIR/broken-payload-symlinks.txt"

  rm -rf "$expanded_dir" "$broken_links"
  pkgutil --expand-full "$pkg_path" "$expanded_dir"
  touch "$broken_links"

  while IFS= read -r -d '' symlink_path; do
    if [[ ! -e "$symlink_path" ]]; then
      printf '%s -> %s\n' "${symlink_path#"$expanded_dir"/}" "$(readlink "$symlink_path")" >>"$broken_links"
    fi
  done < <(find "$expanded_dir" -type l -print0)

  if [[ -s "$broken_links" ]]; then
    echo "Expanded package payload contains broken symlinks:" >&2
    cat "$broken_links" >&2
    return 1
  fi

  return 0
}

build_package() {
  local app_bundle

  app_bundle="$(prepare_app_bundle)"

  rm -rf "$PACKAGE_ROOT" "$PKG_PATH"
  mkdir -p "$PACKAGE_ROOT"

  rsync -a "$app_bundle/" "$PACKAGE_APP/"
  purge_bundle_metadata "$PACKAGE_APP"
  assert_bundle_metadata_free "$PACKAGE_APP"

  productbuild \
    --component "$PACKAGE_APP" \
    /Applications \
    --sign "$INSTALLER_SIGNING_IDENTITY" \
    "$PKG_PATH"

  /usr/bin/xattr -c "$PKG_PATH" 2>/dev/null || true
  /usr/bin/xattr -d "com.apple.provenance" "$PKG_PATH" 2>/dev/null || true
  assert_package_is_store_clean "$PKG_PATH"
  echo "$PKG_PATH"
}

case "$MODE" in
  --prepare|prepare)
    prepare_app_bundle
    ;;
  --package|package)
    build_package
    ;;
  *)
    cat >&2 <<'MESSAGE'
Usage:
  /bin/zsh ./script/package_app_store.sh --package
  /bin/zsh ./script/package_app_store.sh --prepare

The package mode builds a signed Mac App Store app bundle, copies it through a
metadata-free package root, runs productbuild, and validates the pkg locally with
productutil. The package may still report signed-code extended attributes, which
App Store Connect accepts, but it must not contain AppleDouble files, resource
forks, .DS_Store files, or wayward symlinks. Do not run altool --validate-app
before upload; that creates an App Store Connect buildUpload for the build number
and can leave duplicate analysis assets when the real upload reuses it.
MESSAGE
    exit 64
    ;;
esac
