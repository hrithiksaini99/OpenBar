#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
/usr/bin/pkill -x OpenBar >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/build-app.sh" debug
"$ROOT_DIR/scripts/install-app.sh"
mkdir -p "$ROOT_DIR/general/validation"
OUTPUT="$ROOT_DIR/general/validation/native-smoke.txt"
ERROR_OUTPUT="$ROOT_DIR/general/validation/native-smoke-stderr.txt"
: > "$OUTPUT"
: > "$ERROR_OUTPUT"
/usr/bin/open -n -W --stdout "$OUTPUT" --stderr "$ERROR_OUTPUT" /Applications/OpenBar.app --args --smoke-check
cat "$OUTPUT"
if ! rg -q '^OpenBar native smoke-check passed$' "$OUTPUT"; then
    cat "$ERROR_OUTPUT" >&2
    exit 1
fi
