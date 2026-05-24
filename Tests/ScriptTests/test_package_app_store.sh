#!/usr/bin/env bash
# Tests for changes introduced in script/package_app_store.sh
#
# The PR removed two redundant xattr -d calls from the purge_bundle_metadata
# function.  Before the change the loop body was:
#
#   if [[ -L "$bundled_path" ]]; then
#       /usr/bin/xattr -c -s "$bundled_path"  2>/dev/null || true
#       /usr/bin/xattr -d -s "com.apple.provenance" "$bundled_path" 2>/dev/null || true  # REMOVED
#   else
#       /usr/bin/xattr -c "$bundled_path"  2>/dev/null || true
#       /usr/bin/xattr -d "com.apple.provenance" "$bundled_path" 2>/dev/null || true  # REMOVED
#   fi
#
# After the change only `xattr -c [-s]` is invoked; the separate
# `xattr -d com.apple.provenance` lines are gone because `xattr -c` already
# clears every extended attribute on the file.
set -uo pipefail

PASS=0
FAIL=0

# pass echoes a PASS message prefixed with "PASS: " for the given text and increments the global PASS counter.
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
# fail echoes a failure message prefixed with 'FAIL:' and increments the FAIL counter.
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Spy infrastructure
#
# We replace /usr/bin/xattr with a wrapper that records every invocation into
# a temporary log file so tests can assert which flags were (or were not) used.
# ---------------------------------------------------------------------------
XATTR_LOG=""

# setup_xattr_spy creates a temporary XATTR_LOG and a mock xattr executable that appends each invocation's arguments to the log and exits successfully.
setup_xattr_spy() {
    XATTR_LOG="$(mktemp)"
    # Create a mock xattr that logs calls and succeeds.
    mock_xattr_bin="$(mktemp)"
    cat >"$mock_xattr_bin" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$XATTR_LOG"
exit 0
MOCK
    chmod +x "$mock_xattr_bin"
    MOCK_XATTR_BIN="$mock_xattr_bin"
    export XATTR_LOG
}

# teardown_xattr_spy removes the temporary xattr invocation log file and the mock xattr executable.
teardown_xattr_spy() {
    rm -f "$XATTR_LOG" "$MOCK_XATTR_BIN"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRODUCTION_SCRIPT="$SCRIPT_DIR/script/package_app_store.sh"

# run_purge_loop_body invokes the actual production purge_bundle_metadata loop
# body from package_app_store.sh against a test file, using the mock xattr.
# This creates a temporary bundle, calls the real production function, and
# asserts the observable side effects (xattr calls logged via the mock).
run_purge_loop_body() {
    local bundled_path="$1"
    local mock_xattr="$2"

    # Create a minimal test bundle containing just our test file
    local test_bundle
    test_bundle="$(mktemp -d)"

    # Preserve file type (symlink vs regular) when copying to test bundle
    if [[ -L "$bundled_path" ]]; then
        cp -P "$bundled_path" "$test_bundle/testfile"
    else
        cp "$bundled_path" "$test_bundle/testfile"
    fi

    # Invoke production script's purge_bundle_metadata with mocked xattr.
    # Create a wrapper script that patches /usr/bin/xattr path in the heredoc.
    local modified_script
    modified_script="$(mktemp)"

    # Extract and modify the production function to use our mock xattr
    sed -n '/^purge_bundle_metadata()/,/^}/p' "$PRODUCTION_SCRIPT" | \
        sed "s|/usr/bin/xattr|$mock_xattr|g" > "$modified_script"

    # Source the modified function and execute it
    (
        source "$modified_script"
        purge_bundle_metadata "$test_bundle"
    ) 2>/dev/null || true

    rm -f "$modified_script"
    rm -rf "$test_bundle"
}

# ===========================================================================
# Section 1: Regular files — only xattr -c, no xattr -d com.apple.provenance
# ===========================================================================

# 1a. xattr -c is called for a regular file.
setup_xattr_spy
tmpfile="$(mktemp)"
run_purge_loop_body "$tmpfile" "$MOCK_XATTR_BIN"
if grep -q "\-c " "$XATTR_LOG" 2>/dev/null || grep -q "^-c " "$XATTR_LOG" 2>/dev/null; then
    pass "regular file: xattr -c is invoked"
else
    fail "regular file: xattr -c was not invoked"
fi
teardown_xattr_spy
rm -f "$tmpfile"

# 1b. xattr -d com.apple.provenance is NOT called for a regular file.
setup_xattr_spy
tmpfile="$(mktemp)"
run_purge_loop_body "$tmpfile" "$MOCK_XATTR_BIN"
if grep -q "com.apple.provenance" "$XATTR_LOG" 2>/dev/null; then
    fail "regular file: xattr -d com.apple.provenance should not be called (it was removed as redundant)"
else
    pass "regular file: xattr -d com.apple.provenance is not called after removal"
fi
teardown_xattr_spy
rm -f "$tmpfile"

# 1c. xattr -d (in any form) is not called for a regular file.
setup_xattr_spy
tmpfile="$(mktemp)"
run_purge_loop_body "$tmpfile" "$MOCK_XATTR_BIN"
if grep -qE "(^| )-d( |$)" "$XATTR_LOG" 2>/dev/null; then
    fail "regular file: xattr -d should not be invoked at all after the change"
else
    pass "regular file: xattr -d is never called"
fi
teardown_xattr_spy
rm -f "$tmpfile"

# 1d. Exactly one xattr call is made for a regular file (not two as before).
setup_xattr_spy
tmpfile="$(mktemp)"
run_purge_loop_body "$tmpfile" "$MOCK_XATTR_BIN"
call_count="$(wc -l < "$XATTR_LOG" | tr -d ' ')"
if [[ "$call_count" -eq 1 ]]; then
    pass "regular file: exactly one xattr call is made"
else
    fail "regular file: expected 1 xattr call, got $call_count"
fi
teardown_xattr_spy
rm -f "$tmpfile"

# ===========================================================================
# Section 2: Symbolic links — only xattr -c -s, no xattr -d -s com.apple.provenance
# ===========================================================================

# 2a. xattr -c -s is called for a symlink.
setup_xattr_spy
tmpfile="$(mktemp)"
tmplink="$(mktemp -u)_link"
ln -s "$tmpfile" "$tmplink"
run_purge_loop_body "$tmplink" "$MOCK_XATTR_BIN"
if grep -q "\-c" "$XATTR_LOG" 2>/dev/null && grep -q "\-s" "$XATTR_LOG" 2>/dev/null; then
    pass "symlink: xattr -c -s is invoked"
else
    fail "symlink: xattr -c -s was not invoked"
fi
teardown_xattr_spy
rm -f "$tmpfile" "$tmplink"

# 2b. xattr -d com.apple.provenance is NOT called for a symlink.
setup_xattr_spy
tmpfile="$(mktemp)"
tmplink="$(mktemp -u)_link2"
ln -s "$tmpfile" "$tmplink"
run_purge_loop_body "$tmplink" "$MOCK_XATTR_BIN"
if grep -q "com.apple.provenance" "$XATTR_LOG" 2>/dev/null; then
    fail "symlink: xattr -d com.apple.provenance should not be called (it was removed as redundant)"
else
    pass "symlink: xattr -d com.apple.provenance is not called after removal"
fi
teardown_xattr_spy
rm -f "$tmpfile" "$tmplink"

# 2c. xattr -d (in any form) is not called for a symlink.
setup_xattr_spy
tmpfile="$(mktemp)"
tmplink="$(mktemp -u)_link3"
ln -s "$tmpfile" "$tmplink"
run_purge_loop_body "$tmplink" "$MOCK_XATTR_BIN"
if grep -qE "(^| )-d( |$)" "$XATTR_LOG" 2>/dev/null; then
    fail "symlink: xattr -d should not be invoked at all after the change"
else
    pass "symlink: xattr -d is never called"
fi
teardown_xattr_spy
rm -f "$tmpfile" "$tmplink"

# 2d. Exactly one xattr call is made for a symlink (not two as before).
setup_xattr_spy
tmpfile="$(mktemp)"
tmplink="$(mktemp -u)_link4"
ln -s "$tmpfile" "$tmplink"
run_purge_loop_body "$tmplink" "$MOCK_XATTR_BIN"
call_count="$(wc -l < "$XATTR_LOG" | tr -d ' ')"
if [[ "$call_count" -eq 1 ]]; then
    pass "symlink: exactly one xattr call is made"
else
    fail "symlink: expected 1 xattr call, got $call_count"
fi
teardown_xattr_spy
rm -f "$tmpfile" "$tmplink"

# ===========================================================================
# Section 3: Routing — symlinks and regular files take different code paths
# ===========================================================================

# 3a. Regular file is NOT treated as a symlink (does not use -s flag).
setup_xattr_spy
tmpfile="$(mktemp)"
run_purge_loop_body "$tmpfile" "$MOCK_XATTR_BIN"
if grep -q "\-s" "$XATTR_LOG" 2>/dev/null; then
    fail "regular file should not receive the -s (symlink) flag"
else
    pass "regular file: symlink flag -s is not used"
fi
teardown_xattr_spy
rm -f "$tmpfile"

# 3b. Symlink uses the -s flag (to operate on the link itself, not the target).
setup_xattr_spy
tmpfile="$(mktemp)"
tmplink="$(mktemp -u)_link5"
ln -s "$tmpfile" "$tmplink"
run_purge_loop_body "$tmplink" "$MOCK_XATTR_BIN"
if grep -q "\-s" "$XATTR_LOG" 2>/dev/null; then
    pass "symlink: -s flag is used so xattr acts on the link itself"
else
    fail "symlink should receive the -s flag"
fi
teardown_xattr_spy
rm -f "$tmpfile" "$tmplink"

# ===========================================================================
# Section 4: Regression — verify xattr -c clears all attributes
#
# On platforms where xattr is available (macOS), xattr -c removes every
# extended attribute, making a separate xattr -d for com.apple.provenance
# unnecessary.  This test verifies the claim using real xattr when possible,
# and documents the expected behaviour on platforms that lack it.
# ===========================================================================

# 4a. If real xattr is available, verify that -c removes com.apple.provenance.
XATTR_BIN=""
for candidate in /usr/bin/xattr xattr; do
    if command -v "$candidate" >/dev/null 2>&1; then
        XATTR_BIN="$candidate"
        break
    fi
done

if [[ -n "$XATTR_BIN" ]]; then
    tmpfile="$(mktemp)"
    # Set a dummy attribute if supported; xattr -w needs a value string.
    if "$XATTR_BIN" -w "com.apple.provenance" "test" "$tmpfile" 2>/dev/null; then
        "$XATTR_BIN" -c "$tmpfile" 2>/dev/null || true
        remaining="$("$XATTR_BIN" -l "$tmpfile" 2>/dev/null || true)"
        if [[ -z "$remaining" ]]; then
            pass "regression: xattr -c clears com.apple.provenance without a separate -d call"
        else
            fail "regression: xattr -c did not clear all attributes (remaining: $remaining)"
        fi
    else
        pass "regression: xattr -w not supported on this platform; skipping live attribute test"
    fi
    rm -f "$tmpfile"
else
    pass "regression: xattr not available on this platform; live attribute test skipped"
fi

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
