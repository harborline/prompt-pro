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

if head -n 1 "$SCRIPT_PATH" | grep -Fq '#!/bin/zsh'; then
    pass "script pins the packaging shell to /bin/zsh"
else
    fail "script should pin the packaging shell to /bin/zsh"
fi

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

if grep -Fq '/usr/bin/xattr -cr "$bundle_path"' "$SCRIPT_PATH"; then
    pass "script recursively clears provenance attributes from bundle roots"
else
    fail "script should recursively clear bundle-root extended attributes"
fi

if grep -Fq '/usr/bin/xattr -d "com.apple.provenance" "$bundled_path"' "$SCRIPT_PATH"; then
    pass "regular file branch explicitly removes com.apple.provenance"
else
    fail "regular file branch is missing explicit com.apple.provenance removal"
fi

if grep -Fq 'com.apple.provenance can survive some per-file' "$SCRIPT_PATH"; then
    pass "source explains why provenance gets explicit handling"
else
    fail "source should document why explicit provenance removal is required"
fi

if grep -Fq '/bin/zsh -f -c' "$SCRIPT_PATH"; then
    pass "script uses a zsh final pass for stubborn provenance attributes"
else
    fail "script should use zsh for the final provenance cleanup pass"
fi

if grep -Fq 'setopt TYPESET_SILENT' "$SCRIPT_PATH"; then
    pass "script prevents zsh local declarations from polluting captured paths"
else
    fail "script should silence zsh typeset output"
fi

if grep -Fq 'productbuild \' "$SCRIPT_PATH"; then
    pass "script owns final productbuild package creation"
else
    fail "script should own final productbuild package creation"
fi

if grep -Fq '/usr/libexec/productutil \' "$SCRIPT_PATH"; then
    pass "script validates package metadata with productutil"
else
    fail "script should validate package metadata with productutil"
fi

if grep -Fq 'nonstandard-paths' "$SCRIPT_PATH"; then
    pass "script rejects nonstandard package paths"
else
    fail "script should reject nonstandard package paths"
fi

if grep -Fq 'pkgutil --expand-full "$pkg_path"' "$SCRIPT_PATH"; then
    pass "script independently expands the package payload to verify symlinks"
else
    fail "script should independently verify symlinks from the expanded payload"
fi

if grep -Fq 'assert_bundle_metadata_free "$PACKAGE_APP"' "$SCRIPT_PATH"; then
    pass "script verifies the package root is metadata-free before productbuild"
else
    fail "script should verify package-root metadata before productbuild"
fi

if grep -Fq 'rsync -a "$app_bundle/" "$PACKAGE_APP/"' "$SCRIPT_PATH"; then
    pass "script copies the package root without ditto-created provenance attributes"
else
    fail "script should copy the package root with rsync to avoid provenance attributes"
fi

if grep -Fq 'xcrun altool' "$SCRIPT_PATH"; then
    fail "script must not pre-create App Store Connect buildUploads with altool validation"
else
    pass "script avoids altool validation before upload"
fi

echo ""
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi
