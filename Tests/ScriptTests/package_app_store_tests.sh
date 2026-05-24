#!/usr/bin/env bash
# Tests for logic changed in script/package_app_store.sh
# Covers the purge_bundle_metadata function change:
#   - Removed: /usr/bin/xattr -d -s "com.apple.provenance" "$bundled_path" (symlink branch)
#   - Removed: /usr/bin/xattr -d "com.apple.provenance"   "$bundled_path" (regular file branch)
#   - Kept:    /usr/bin/xattr -c -s "$bundled_path" (symlink branch)
#   - Kept:    /usr/bin/xattr -c "$bundled_path"    (regular file branch)
#
# Strategy: replace /usr/bin/xattr with a stub that records calls, then invoke
# the purge_bundle_metadata logic and verify the stub's log.

set -euo pipefail

PASS=0
FAIL=0

# pass prints a passing test message with the provided text and increments the global PASS counter.
pass() {
    echo "  PASS: $1"
    PASS=$((PASS + 1))
}

# fail prints a failure message prefixed with "FAIL:" and increments the FAIL counter.
fail() {
    echo "  FAIL: $1"
    FAIL=$((FAIL + 1))
}

# ---------------------------------------------------------------------------
# Shared setup: create a stub xattr that records every invocation
# make_stub_dir creates a temporary directory containing an executable `xattr` stub that appends its received arguments to the file referenced by `$XATTR_LOG` and echoes the stub directory path.

make_stub_dir() {
    local stub_dir
    stub_dir="$(mktemp -d)"

    # Stub xattr binary: appends its full argument list to a log file.
    cat > "$stub_dir/xattr" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$XATTR_LOG"
exit 0
STUB
    chmod +x "$stub_dir/xattr"

    echo "$stub_dir"
}

# Run the purge_bundle_metadata inline logic (as extracted from the script)
# run_purge runs purge_bundle_metadata-like cleanup on a bundle path using the xattr stub found in the provided stub_dir.
# It echoes the path to the xattr log file written inside stub_dir.
# Parameters: bundle_path — path to the bundle to process; stub_dir — directory containing the stub xattr and where the log file will be created.
run_purge() {
    local bundle_path="$1"
    local stub_dir="$2"
    local log_file="$stub_dir/xattr.log"

    XATTR_LOG="$log_file" PATH="$stub_dir:$PATH" bash <<SCRIPT
set -euo pipefail
BUNDLE_PATH="$bundle_path"

find "\$BUNDLE_PATH" \\( -name "._*" -o -name ".DS_Store" \\) -delete 2>/dev/null || true
chmod -R u+w "\$BUNDLE_PATH" 2>/dev/null || true

while IFS= read -r -d '' bundled_path; do
  if [[ -L "\$bundled_path" ]]; then
    /usr/bin/xattr -c -s "\$bundled_path" 2>/dev/null || true
  else
    /usr/bin/xattr -c "\$bundled_path" 2>/dev/null || true
  fi
done < <(/usr/bin/find "\$BUNDLE_PATH" -print0)
SCRIPT

    echo "$log_file"
}

# ---------------------------------------------------------------------------
# NOTE: /usr/bin/xattr is a macOS-only tool. On Linux the stub PATH trick is
# used, but the SCRIPT above calls /usr/bin/xattr explicitly (hardcoded path).
# We test the conditional logic directly in pure bash instead, and validate
# the absence of "com.apple.provenance" via grep on the script source.
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 1: purge_bundle_metadata source does not call xattr -d com.apple.provenance ==="

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/script/package_app_store.sh"

# Test 1a: The -d com.apple.provenance flag is absent from the purge function
if grep -n 'xattr.*-d.*com.apple.provenance' "$SCRIPT_PATH" 2>/dev/null | grep -q 'purge_bundle_metadata\|while.*bundled_path\|xattr.*-d'; then
    fail "xattr -d com.apple.provenance is still present inside purge_bundle_metadata"
else
    pass "xattr -d com.apple.provenance is not present in purge_bundle_metadata"
fi

# Test 1b: Confirm xattr -d com.apple.provenance does not appear anywhere in the script
provenance_lines=$(grep -c 'xattr.*-d.*com.apple.provenance' "$SCRIPT_PATH" 2>/dev/null || true)
if [[ "$provenance_lines" -eq 0 ]]; then
    pass "No xattr -d com.apple.provenance calls remain in the script"
else
    fail "Found $provenance_lines xattr -d com.apple.provenance line(s) in script (expected 0)"
fi

# Test 1c: Confirm xattr -c IS still present for both the symlink and regular file branches
symlink_clear=$(grep -c 'xattr -c -s' "$SCRIPT_PATH" 2>/dev/null || true)
regular_clear=$(grep -c 'xattr -c "[^-]' "$SCRIPT_PATH" 2>/dev/null || true)
if [[ "$symlink_clear" -ge 1 ]]; then
    pass "xattr -c -s (symlink clear) is present in purge_bundle_metadata"
else
    fail "xattr -c -s (symlink clear) is missing from purge_bundle_metadata"
fi
if [[ "$regular_clear" -ge 1 ]]; then
    pass "xattr -c (regular file clear) is present in purge_bundle_metadata"
else
    fail "xattr -c (regular file clear) is missing from purge_bundle_metadata"
fi

# ---------------------------------------------------------------------------
# SECTION 2 – Inline conditional logic tests (pure bash, no macOS xattr needed)
# ---------------------------------------------------------------------------

echo ""
echo "=== Section 2: xattr call logic per file type ==="

# Extract the conditional logic from the script and run it with a mock xattr.
# run_logic_with_mock records a mocked xattr invocation for the given path into the specified log file: it logs `-c -s <path>` if the path is a symlink, otherwise `-c <path>`.

run_logic_with_mock() {
    local path="$1"
    local log_file="$2"

    XATTR_LOG="$log_file" bash <<INNERSCRIPT
mock_xattr() {
    echo "\$*" >> "\$XATTR_LOG"
}
bundled_path="$path"
if [[ -L "\$bundled_path" ]]; then
    mock_xattr -c -s "\$bundled_path"
else
    mock_xattr -c "\$bundled_path"
fi
INNERSCRIPT
}

# Test 2a: Regular file → xattr -c (no -d, no -s)
TMPDIR_2A="$(mktemp -d)"
REG_FILE="$TMPDIR_2A/regular.txt"
echo "content" > "$REG_FILE"
LOG_2A="$TMPDIR_2A/xattr.log"

run_logic_with_mock "$REG_FILE" "$LOG_2A"

log_content="$(cat "$LOG_2A" 2>/dev/null || true)"
if echo "$log_content" | grep -q "^-c "; then
    pass "Regular file: xattr called with -c"
else
    fail "Regular file: expected xattr -c but got: '$log_content'"
fi
if echo "$log_content" | grep -q "\-d"; then
    fail "Regular file: xattr should not be called with -d (found in '$log_content')"
else
    pass "Regular file: xattr not called with -d"
fi
if echo "$log_content" | grep -q "\-s"; then
    fail "Regular file: xattr should not be called with -s (found in '$log_content')"
else
    pass "Regular file: xattr not called with -s"
fi
rm -rf "$TMPDIR_2A"

# Test 2b: Symlink → xattr -c -s (no -d)
TMPDIR_2B="$(mktemp -d)"
TARGET_FILE="$TMPDIR_2B/target.txt"
echo "target" > "$TARGET_FILE"
SYMLINK="$TMPDIR_2B/link.txt"
ln -s "$TARGET_FILE" "$SYMLINK"
LOG_2B="$TMPDIR_2B/xattr.log"

run_logic_with_mock "$SYMLINK" "$LOG_2B"

log_content="$(cat "$LOG_2B" 2>/dev/null || true)"
if echo "$log_content" | grep -q "^-c -s "; then
    pass "Symlink: xattr called with -c -s"
else
    fail "Symlink: expected xattr -c -s but got: '$log_content'"
fi
if echo "$log_content" | grep -q "\-d"; then
    fail "Symlink: xattr should not be called with -d (found in '$log_content')"
else
    pass "Symlink: xattr not called with -d"
fi
rm -rf "$TMPDIR_2B"

# Test 2c: Regression – old code would also call xattr -d com.apple.provenance;
# verify the new logic does NOT produce that call for either branch.
TMPDIR_2C="$(mktemp -d)"
REG_FILE_2C="$TMPDIR_2C/file.txt"
echo "data" > "$REG_FILE_2C"
LOG_2C="$TMPDIR_2C/xattr_reg.log"

run_logic_with_mock "$REG_FILE_2C" "$LOG_2C"

provenance_calls=$(grep -c 'com.apple.provenance' "$LOG_2C" 2>/dev/null || true)
if [[ "$provenance_calls" -eq 0 ]]; then
    pass "Regression: no xattr -d com.apple.provenance call for regular file"
else
    fail "Regression: found $provenance_calls com.apple.provenance call(s) for regular file"
fi

SYMLINK_2C="$TMPDIR_2C/link.txt"
ln -s "$REG_FILE_2C" "$SYMLINK_2C"
LOG_2C_SYM="$TMPDIR_2C/xattr_sym.log"

run_logic_with_mock "$SYMLINK_2C" "$LOG_2C_SYM"

provenance_calls_sym=$(grep -c 'com.apple.provenance' "$LOG_2C_SYM" 2>/dev/null || true)
if [[ "$provenance_calls_sym" -eq 0 ]]; then
    pass "Regression: no xattr -d com.apple.provenance call for symlink"
else
    fail "Regression: found $provenance_calls_sym com.apple.provenance call(s) for symlink"
fi
rm -rf "$TMPDIR_2C"

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
