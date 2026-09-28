#!/usr/bin/env bash
# Export tests/ and tx-source/ at a given tag, branch or commit into tests-src/, so the tests can be
# pinned to an IG release independently of the version of the job's own scripts.
#
#   jenkins/checkout-tests.sh [REF]    REF defaults to $TESTS_REF; blank uses the job's own HEAD
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REF="${1:-${TESTS_REF:-}}"
DEST="$REPO_ROOT/tests-src"

cd "$REPO_ROOT"
if [[ -z "$REF" ]]; then
    commit=$(git rev-parse HEAD)
elif git fetch --quiet --no-tags origin "$REF" 2>/dev/null; then
    commit=$(git rev-parse FETCH_HEAD)
else
    commit=$(git rev-parse --verify "$REF^{commit}")
fi

rm -rf "$DEST"
mkdir -p "$DEST"
git archive "$commit" tests tx-source | tar -x -C "$DEST"
echo "[checkout-tests.sh] tests and tx-source from ${REF:-HEAD} ($(git log -1 --format='%h %ad' --date=short "$commit")) in $DEST"
