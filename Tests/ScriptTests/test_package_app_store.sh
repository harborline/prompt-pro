#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

pass() {
    echo "PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
}

XATTR_LOG=""
MOCK_XATTR_BIN=""

setup_xattr_spy() {
    XATTR_LOG="$(mktemp)"
    MOCK_XATTR_BIN="$(mktemp)"
    cat >"$MOCK_XATTR_BIN" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$XATTR_LOG"
exit 0
MOCK
    chmod +x "$MOCK_XATTR_BIN"
    export XATTR_LOG
}

teardown_xattr_spy() {
    rm -f "$XATTR_LOG" "$MOCK_XATTR_BIN"
}

run_purge_loop_body() {
    local bundled_path="$1"
    local xattr_bin="$2"

    if [[ -L "$bundled_path" ]]; then
        "$xattr_bin" -c -s "$bundled_path" 2>/dev/null || true
        "$xattr_bin" -d -s "com.apple.provenance" "$bundled_path" 2>/dev/null || true
    else
        "$xattr_bin" -c "$bundled_path" 2>/dev/null || true
        "$xattr_bin" -d "com.apple.provenance" "$bundled_path" 2>/dev/null || true
    fi
}

assert_log_matches() {
    local expected="$1"
    local message="$2"

    if grep -Eq "$expected" "$XATTR_LOG" 2>/dev/null; then
        pass "$message"
    else
        fail "$message (missing pattern: $expected)"
    fi
}

assert_call_count() {
    local expected="$1"
    local message="$2"
    local count

    count="$(wc -l < "$XATTR_LOG" | tr -d ' ')"
    if [[ "$count" -eq "$expected" ]]; then
        pass "$message"
    else
        fail "$message (expected $expected calls, got $count)"
    fi
}

setup_xattr_spy
tmpfile="$(mktemp)"
run_purge_loop_body "$tmpfile" "$MOCK_XATTR_BIN"
assert_log_matches '^-c ' "regular file: xattr -c is invoked"
assert_log_matches '^-d com\.apple\.provenance ' "regular file: provenance is explicitly removed"
assert_call_count 2 "regular file: exactly two xattr calls are made"
teardown_xattr_spy
rm -f "$tmpfile"

setup_xattr_spy
link_tmpdir="$(mktemp -d)"
tmpfile="$link_tmpdir/target"
tmplink="$link_tmpdir/link"
touch "$tmpfile"
ln -s "$tmpfile" "$tmplink"
run_purge_loop_body "$tmplink" "$MOCK_XATTR_BIN"
assert_log_matches '^-c -s ' "symlink: xattr -c -s is invoked"
assert_log_matches '^-d -s com\.apple\.provenance ' "symlink: provenance is explicitly removed with -s"
assert_call_count 2 "symlink: exactly two xattr calls are made"
teardown_xattr_spy
rm -rf "$link_tmpdir"

XATTR_BIN=""
for candidate in /usr/bin/xattr xattr; do
    if command -v "$candidate" >/dev/null 2>&1; then
        XATTR_BIN="$candidate"
        break
    fi
done

if [[ -n "$XATTR_BIN" ]]; then
    tmpfile="$(mktemp)"
    if "$XATTR_BIN" -w "software.pdx.promptproducer.test" "test" "$tmpfile" 2>/dev/null; then
        "$XATTR_BIN" -c "$tmpfile" 2>/dev/null || true
        remaining="$("$XATTR_BIN" -l "$tmpfile" 2>/dev/null || true)"
        if ! grep -q "software.pdx.promptproducer.test" <<<"$remaining"; then
            pass "live regression: xattr -c clears ordinary extended attributes"
        else
            fail "live regression: ordinary test attribute remains after cleanup ($remaining)"
        fi
    else
        pass "live regression: xattr -w not supported; skipping live attribute test"
    fi
    rm -f "$tmpfile"
else
    pass "live regression: xattr unavailable; skipping live attribute test"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
