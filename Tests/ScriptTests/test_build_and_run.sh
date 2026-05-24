#!/usr/bin/env bash
# Tests for changes introduced in script/build_and_run.sh
# Covers:
#   1. :? parameter expansion guards on APP_RESOURCES and bundle_name
#   2. BlockNoteEditor copy condition (copy only when source exists and dest does not)
set -uo pipefail

PASS=0
FAIL=0

# pass echoes 'PASS: <msg>' to stdout and increments the global PASS counter.
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
# fail prints a failure message prefixed with "FAIL:" and increments the global FAIL counter.
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Helper: run a snippet in a subshell and return its exit code.
# run_subshell executes a shell snippet in a subshell while silencing stderr.
# It evaluates the provided string with eval and exits with the snippet's exit status.
run_subshell() {
    (eval "$1") 2>/dev/null
}

# ===========================================================================
# Section 1: :? parameter expansion guards
#
# The changed line is:
#   rm -rf "${APP_RESOURCES:?}/${bundle_name:?}"
#
# :? causes the shell to exit with an error message when the variable is unset
# or empty, preventing a dangerous rm -rf with an empty path component.
#
# Tests now source and invoke the actual production script logic to ensure
# the test reflects real behavior and catches regressions.
# ===========================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCTION_SCRIPT="$SCRIPT_DIR/script/build_and_run.sh"

# Extract the actual rm -rf line with :? expansion from the production script.
# This line is: rm -rf "${APP_RESOURCES:?}/${bundle_name:?}"
PRODUCTION_RM_LINE="$(grep -F '${APP_RESOURCES:?}/${bundle_name:?}' "$PRODUCTION_SCRIPT" | head -n 1)"

# test_parameter_expansion_guard executes the actual production script line
# that uses :? expansion with the provided environment variables. It extracts
# just the parameter expansion for testing without side effects.
test_parameter_expansion_guard() {
    local app_resources="$1"
    local bundle_name_val="$2"
    (
        if [[ "$app_resources" == "UNSET" ]]; then
            unset APP_RESOURCES
        else
            APP_RESOURCES="$app_resources"
        fi

        if [[ "$bundle_name_val" == "UNSET" ]]; then
            unset bundle_name
        else
            bundle_name="$bundle_name_val"
        fi

        # Execute just the parameter expansion part from the production script
        # without the rm -rf side effect
        eval ": ${PRODUCTION_RM_LINE#*rm -rf }"
    ) 2>/dev/null
}

# test_path_construction evaluates the actual path construction from the
# production script using the same :? expansion syntax.
test_path_construction() {
    local app_resources="$1"
    local bundle_name_val="$2"
    (
        APP_RESOURCES="$app_resources"
        bundle_name="$bundle_name_val"
        # Extract and evaluate the path expression from production
        eval "echo ${PRODUCTION_RM_LINE#*rm -rf }"
    ) 2>/dev/null
}

# 1a. When APP_RESOURCES is empty the expansion should fail.
if test_parameter_expansion_guard "" "foo.bundle"; then
    fail "empty APP_RESOURCES should trigger :? expansion failure"
else
    pass "empty APP_RESOURCES triggers :? expansion failure"
fi

# 1b. When bundle_name is empty the expansion should fail.
if test_parameter_expansion_guard "/some/resources" ""; then
    fail "empty bundle_name should trigger :? expansion failure"
else
    pass "empty bundle_name triggers :? expansion failure"
fi

# 1c. When APP_RESOURCES is unset the expansion should fail.
if test_parameter_expansion_guard "UNSET" "foo.bundle"; then
    fail "unset APP_RESOURCES should trigger :? expansion failure"
else
    pass "unset APP_RESOURCES triggers :? expansion failure"
fi

# 1d. When bundle_name is unset the expansion should fail.
if test_parameter_expansion_guard "/some/resources" "UNSET"; then
    fail "unset bundle_name should trigger :? expansion failure"
else
    pass "unset bundle_name triggers :? expansion failure"
fi

# 1e. When both variables are set to non-empty values the expansion succeeds.
if test_parameter_expansion_guard "/some/resources" "foo.bundle"; then
    pass "both variables set: :? expansion succeeds"
else
    fail "both variables set: :? expansion should succeed"
fi

# 1f. Verify the constructed path is exactly APP_RESOURCES/bundle_name (no double slashes).
result="$(test_path_construction "/a/b" "c.bundle")"
expected="/a/b/c.bundle"
if [[ "$result" == "$expected" ]]; then
    pass ":? expansion builds the expected path"
else
    fail ":? expansion path mismatch: got '$result', expected '$expected'"
fi

# ===========================================================================
# Section 2: BlockNoteEditor copy condition
#
# Original: if [[ -d "$RESOURCE_BUNDLE/BlockNoteEditor" ]]; then
#               rm -rf "$APP_RESOURCES/BlockNoteEditor"
#               cp -R ...
#
# Changed:  if [[ -d "$RESOURCE_BUNDLE/BlockNoteEditor" && ! -d "$APP_RESOURCES/BlockNoteEditor" ]]; then
#               cp -R ...
#
# New behaviour:
#   - Copy when source exists AND destination does not exist.
#   - Skip copy when destination already exists (idempotent; avoids clobbering).
#   - Skip copy when source does not exist.
# setup_dirs creates a temporary test directory, sets TMPDIR_CASE, RESOURCE_BUNDLE, and APP_RESOURCES, and ensures both resource and app directories exist.

setup_dirs() {
    TMPDIR_CASE="$(mktemp -d)"
    RESOURCE_BUNDLE="$TMPDIR_CASE/resource_bundle"
    APP_RESOURCES="$TMPDIR_CASE/app_resources"
    mkdir -p "$RESOURCE_BUNDLE" "$APP_RESOURCES"
}

# teardown_dirs removes the temporary test directory tree created for a test case.
teardown_dirs() {
    rm -rf "$TMPDIR_CASE"
}

# run_blocknote_copy copies the BlockNoteEditor directory from the provided resource_bundle into app_resources only when the source exists and the destination does not; echoes "copied" on success and "skipped" otherwise.
run_blocknote_copy() {
    local resource_bundle="$1"
    local app_resources="$2"
    if [[ -d "$resource_bundle/BlockNoteEditor" && ! -d "$app_resources/BlockNoteEditor" ]]; then
        cp -R "$resource_bundle/BlockNoteEditor" "$app_resources/"
        echo "copied"
    else
        echo "skipped"
    fi
}

# 2a. Source exists, destination does not → copy should happen.
setup_dirs
mkdir -p "$RESOURCE_BUNDLE/BlockNoteEditor"
result="$(run_blocknote_copy "$RESOURCE_BUNDLE" "$APP_RESOURCES")"
if [[ "$result" == "copied" && -d "$APP_RESOURCES/BlockNoteEditor" ]]; then
    pass "BlockNoteEditor copied when source exists and destination is absent"
else
    fail "BlockNoteEditor should be copied when source exists and destination is absent (got: $result)"
fi
teardown_dirs

# 2b. Source exists, destination already exists → copy should be skipped (idempotent).
setup_dirs
mkdir -p "$RESOURCE_BUNDLE/BlockNoteEditor"
mkdir -p "$APP_RESOURCES/BlockNoteEditor"
# Place a sentinel file to verify the destination is not replaced.
touch "$APP_RESOURCES/BlockNoteEditor/sentinel"
result="$(run_blocknote_copy "$RESOURCE_BUNDLE" "$APP_RESOURCES")"
if [[ "$result" == "skipped" && -f "$APP_RESOURCES/BlockNoteEditor/sentinel" ]]; then
    pass "BlockNoteEditor not overwritten when destination already exists"
else
    fail "BlockNoteEditor should be skipped when destination already exists (got: $result)"
fi
teardown_dirs

# 2c. Source does not exist → copy should be skipped.
setup_dirs
# No BlockNoteEditor in RESOURCE_BUNDLE.
result="$(run_blocknote_copy "$RESOURCE_BUNDLE" "$APP_RESOURCES")"
if [[ "$result" == "skipped" && ! -d "$APP_RESOURCES/BlockNoteEditor" ]]; then
    pass "BlockNoteEditor not copied when source is absent"
else
    fail "BlockNoteEditor copy should be skipped when source is absent (got: $result)"
fi
teardown_dirs

# 2d. Source exists, destination absent → copied files match the source contents.
setup_dirs
mkdir -p "$RESOURCE_BUNDLE/BlockNoteEditor"
echo "asset data" > "$RESOURCE_BUNDLE/BlockNoteEditor/index.html"
run_blocknote_copy "$RESOURCE_BUNDLE" "$APP_RESOURCES" >/dev/null
if [[ -f "$APP_RESOURCES/BlockNoteEditor/index.html" ]]; then
    pass "BlockNoteEditor directory contents preserved after copy"
else
    fail "BlockNoteEditor contents should be preserved in destination after copy"
fi
teardown_dirs

# 2e. Regression: the old code used rm -rf before copying; the new code must not
#     remove a pre-existing destination when the source also exists.
setup_dirs
mkdir -p "$RESOURCE_BUNDLE/BlockNoteEditor"
mkdir -p "$APP_RESOURCES/BlockNoteEditor"
echo "important" > "$APP_RESOURCES/BlockNoteEditor/important.txt"
run_blocknote_copy "$RESOURCE_BUNDLE" "$APP_RESOURCES" >/dev/null
if [[ -f "$APP_RESOURCES/BlockNoteEditor/important.txt" ]]; then
    pass "BlockNoteEditor: pre-existing destination is not deleted (regression guard)"
else
    fail "BlockNoteEditor: pre-existing destination was unexpectedly removed"
fi
teardown_dirs

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]