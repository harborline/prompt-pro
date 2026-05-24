#!/usr/bin/env bash
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

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/script/package_app_store.sh"

echo ""
echo "=== package_app_store.sh metadata cleanup contract ==="

if grep -Fq '/usr/bin/xattr -c -s "$bundled_path"' "$SCRIPT_PATH"; then
    pass "symlink branch clears all attributes with xattr -c -s"
else
    fail "symlink branch is missing xattr -c -s"
fi

if grep -Fq '/usr/bin/xattr -d -s "com.apple.provenance" "$bundled_path"' "$SCRIPT_PATH"; then
    pass "symlink branch explicitly removes com.apple.provenance"
else
    fail "symlink branch is missing explicit com.apple.provenance removal"
fi

if grep -Fq '/usr/bin/xattr -c "$bundled_path"' "$SCRIPT_PATH"; then
    pass "regular file branch clears all attributes with xattr -c"
else
    fail "regular file branch is missing xattr -c"
fi

if grep -Fq '/usr/bin/xattr -d "com.apple.provenance" "$bundled_path"' "$SCRIPT_PATH"; then
    pass "regular file branch explicitly removes com.apple.provenance"
else
    fail "regular file branch is missing explicit com.apple.provenance removal"
fi

if grep -Fq 'com.apple.provenance can survive broad xattr' "$SCRIPT_PATH"; then
    pass "source explains why provenance gets explicit handling"
else
    fail "source should document why explicit provenance removal is required"
fi

echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi
