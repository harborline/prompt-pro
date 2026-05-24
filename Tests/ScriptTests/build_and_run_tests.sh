#!/usr/bin/env bash
# Tests for logic changed in script/build_and_run.sh
# Covers:
#   1. Safe rm with :? param expansion on APP_RESOURCES and bundle_name
#   2. BlockNoteEditor conditional copy: only copies when not already present

set -euo pipefail

PASS=0
FAIL=0

pass() {
    echo "  PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
}

# Run a bash snippet and capture its exit code without triggering set -e.
# Usage: capture_exit_code <varname> <script>
capture_exit_code() {
    local _varname="$1"
    local _script="$2"
    local _code=0
    bash -c "$_script" 2>/dev/null || _code=$?
    printf -v "$_varname" '%d' "$_code"
}

# ---------------------------------------------------------------------------
# SECTION 1 – safe rm with :? parameter expansion
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 1: Safe rm with :? parameter expansion ==="

# Test 1a: rm fails when APP_RESOURCES is empty
capture_exit_code ec1a '
    set -euo pipefail
    APP_RESOURCES=""
    bundle_name="foo.bundle"
    rm -rf "${APP_RESOURCES:?}/${bundle_name:?}"
'
if [[ "$ec1a" -ne 0 ]]; then
    pass "rm fails when APP_RESOURCES is empty (exit $ec1a)"
else
    fail "rm should fail when APP_RESOURCES is empty, but it succeeded"
fi

# Test 1b: rm fails when bundle_name is empty
capture_exit_code ec1b '
    set -euo pipefail
    APP_RESOURCES="/tmp"
    bundle_name=""
    rm -rf "${APP_RESOURCES:?}/${bundle_name:?}"
'
if [[ "$ec1b" -ne 0 ]]; then
    pass "rm fails when bundle_name is empty (exit $ec1b)"
else
    fail "rm should fail when bundle_name is empty, but it succeeded"
fi

# Test 1c: rm succeeds when both vars are set (uses a real temp dir)
TMPDIR_1C="$(mktemp -d)"
mkdir -p "$TMPDIR_1C/some.bundle"

capture_exit_code ec1c "
    set -euo pipefail
    APP_RESOURCES=\"$TMPDIR_1C\"
    bundle_name=\"some.bundle\"
    rm -rf \"\${APP_RESOURCES:?}/\${bundle_name:?}\"
"

if [[ "$ec1c" -eq 0 && ! -d "$TMPDIR_1C/some.bundle" ]]; then
    pass "rm succeeds and removes target when both vars are non-empty"
else
    fail "rm should succeed when both vars are non-empty (exit=$ec1c, exists=$(test -d "$TMPDIR_1C/some.bundle" && echo yes || echo no))"
fi
rm -rf "$TMPDIR_1C"

# Test 1d: Regression – plain rm -rf with empty path does NOT fail
# (shows why the :? guard is necessary)
capture_exit_code ec1d '
    APP_RESOURCES=""
    bundle_name="foo.bundle"
    rm -rf "$APP_RESOURCES/$bundle_name"
'
if [[ "$ec1d" -eq 0 ]]; then
    pass "Regression: plain rm -rf with empty APP_RESOURCES does NOT fail (confirms :? is the safeguard)"
else
    fail "Unexpected: plain rm -rf with empty vars returned non-zero ($ec1d)"
fi

# ---------------------------------------------------------------------------
# SECTION 2 – BlockNoteEditor conditional copy
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 2: BlockNoteEditor conditional copy ==="

# Inline the changed conditional for isolated testing:
#   if [[ -d "$RESOURCE_BUNDLE/BlockNoteEditor" && ! -d "$APP_RESOURCES/BlockNoteEditor" ]]; then
#     cp -R "$RESOURCE_BUNDLE/BlockNoteEditor" "$APP_RESOURCES/"
#   fi

# Test 2a: BlockNoteEditor IS copied when source exists and destination does NOT exist
TMPDIR_2A="$(mktemp -d)"
RESOURCE_BUNDLE_2A="$TMPDIR_2A/resource_bundle"
APP_RESOURCES_2A="$TMPDIR_2A/app_resources"
mkdir -p "$RESOURCE_BUNDLE_2A/BlockNoteEditor" "$APP_RESOURCES_2A"
echo "editor_file" > "$RESOURCE_BUNDLE_2A/BlockNoteEditor/index.html"

bash -c "
    set -euo pipefail
    RESOURCE_BUNDLE=\"$RESOURCE_BUNDLE_2A\"
    APP_RESOURCES=\"$APP_RESOURCES_2A\"
    if [[ -d \"\$RESOURCE_BUNDLE/BlockNoteEditor\" && ! -d \"\$APP_RESOURCES/BlockNoteEditor\" ]]; then
        cp -R \"\$RESOURCE_BUNDLE/BlockNoteEditor\" \"\$APP_RESOURCES/\"
    fi
"
if [[ -d "$APP_RESOURCES_2A/BlockNoteEditor" && -f "$APP_RESOURCES_2A/BlockNoteEditor/index.html" ]]; then
    pass "BlockNoteEditor is copied when source exists and destination is absent"
else
    fail "BlockNoteEditor should have been copied but was not"
fi
rm -rf "$TMPDIR_2A"

# Test 2b: BlockNoteEditor is NOT overwritten when it already exists in APP_RESOURCES
TMPDIR_2B="$(mktemp -d)"
RESOURCE_BUNDLE_2B="$TMPDIR_2B/resource_bundle"
APP_RESOURCES_2B="$TMPDIR_2B/app_resources"
mkdir -p "$RESOURCE_BUNDLE_2B/BlockNoteEditor" "$APP_RESOURCES_2B/BlockNoteEditor"
echo "updated_file" > "$RESOURCE_BUNDLE_2B/BlockNoteEditor/index.html"
echo "original_file" > "$APP_RESOURCES_2B/BlockNoteEditor/index.html"

bash -c "
    set -euo pipefail
    RESOURCE_BUNDLE=\"$RESOURCE_BUNDLE_2B\"
    APP_RESOURCES=\"$APP_RESOURCES_2B\"
    if [[ -d \"\$RESOURCE_BUNDLE/BlockNoteEditor\" && ! -d \"\$APP_RESOURCES/BlockNoteEditor\" ]]; then
        cp -R \"\$RESOURCE_BUNDLE/BlockNoteEditor\" \"\$APP_RESOURCES/\"
    fi
"
content="$(cat "$APP_RESOURCES_2B/BlockNoteEditor/index.html")"
if [[ "$content" == "original_file" ]]; then
    pass "BlockNoteEditor is NOT overwritten when it already exists in APP_RESOURCES"
else
    fail "BlockNoteEditor was overwritten when it should have been preserved (content='$content')"
fi
rm -rf "$TMPDIR_2B"

# Test 2c: Nothing is copied when source BlockNoteEditor does NOT exist
TMPDIR_2C="$(mktemp -d)"
RESOURCE_BUNDLE_2C="$TMPDIR_2C/resource_bundle"
APP_RESOURCES_2C="$TMPDIR_2C/app_resources"
mkdir -p "$RESOURCE_BUNDLE_2C" "$APP_RESOURCES_2C"

bash -c "
    set -euo pipefail
    RESOURCE_BUNDLE=\"$RESOURCE_BUNDLE_2C\"
    APP_RESOURCES=\"$APP_RESOURCES_2C\"
    if [[ -d \"\$RESOURCE_BUNDLE/BlockNoteEditor\" && ! -d \"\$APP_RESOURCES/BlockNoteEditor\" ]]; then
        cp -R \"\$RESOURCE_BUNDLE/BlockNoteEditor\" \"\$APP_RESOURCES/\"
    fi
"
if [[ ! -d "$APP_RESOURCES_2C/BlockNoteEditor" ]]; then
    pass "Nothing is copied when source BlockNoteEditor does not exist"
else
    fail "BlockNoteEditor should not have been copied when source is absent"
fi
rm -rf "$TMPDIR_2C"

# Test 2d: Regression – old condition would overwrite existing destination;
# new condition prevents that.
TMPDIR_2D="$(mktemp -d)"
RESOURCE_BUNDLE_2D="$TMPDIR_2D/resource_bundle"
APP_RESOURCES_2D="$TMPDIR_2D/app_resources"
mkdir -p "$RESOURCE_BUNDLE_2D/BlockNoteEditor" "$APP_RESOURCES_2D/BlockNoteEditor"
echo "new_from_bundle" > "$RESOURCE_BUNDLE_2D/BlockNoteEditor/index.html"
echo "existing_in_app"  > "$APP_RESOURCES_2D/BlockNoteEditor/index.html"

# Simulate OLD behavior (no existence guard on destination)
bash -c "
    set -euo pipefail
    RESOURCE_BUNDLE=\"$RESOURCE_BUNDLE_2D\"
    APP_RESOURCES=\"$APP_RESOURCES_2D\"
    if [[ -d \"\$RESOURCE_BUNDLE/BlockNoteEditor\" ]]; then
        cp -R \"\$RESOURCE_BUNDLE/BlockNoteEditor\" \"\$APP_RESOURCES/\"
    fi
"
old_content="$(cat "$APP_RESOURCES_2D/BlockNoteEditor/index.html")"

# Reset destination, then apply NEW behavior (destination already exists – no copy)
echo "existing_in_app" > "$APP_RESOURCES_2D/BlockNoteEditor/index.html"
bash -c "
    set -euo pipefail
    RESOURCE_BUNDLE=\"$RESOURCE_BUNDLE_2D\"
    APP_RESOURCES=\"$APP_RESOURCES_2D\"
    if [[ -d \"\$RESOURCE_BUNDLE/BlockNoteEditor\" && ! -d \"\$APP_RESOURCES/BlockNoteEditor\" ]]; then
        cp -R \"\$RESOURCE_BUNDLE/BlockNoteEditor\" \"\$APP_RESOURCES/\"
    fi
"
new_content="$(cat "$APP_RESOURCES_2D/BlockNoteEditor/index.html")"

if [[ "$old_content" == "new_from_bundle" && "$new_content" == "existing_in_app" ]]; then
    pass "Regression: old condition overwrote destination; new condition preserves it"
else
    fail "Regression check failed (old='$old_content', new='$new_content')"
fi
rm -rf "$TMPDIR_2D"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -ne 0 ]]; then
    exit 1
fi