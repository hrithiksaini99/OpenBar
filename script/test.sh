#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# XCTest is shipped with full Xcode, not the standalone Command Line Tools.
# Select it for this command only; never change the machine's xcode-select.
source "$ROOT_DIR/scripts/toolchain.sh"
swift test "$@"
