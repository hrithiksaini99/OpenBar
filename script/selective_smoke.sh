#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP_BUNDLE="${OPENBAR_SMOKE_APP:-/Applications/OpenBar.app}"
if [[ ! -x "$APP_BUNDLE/Contents/MacOS/OpenBar" ]]; then
    echo "Install a Debug OpenBar bundle before running the selective smoke test." >&2
    exit 2
fi
if /usr/bin/pgrep -x OpenBar >/dev/null; then
    echo "Quit the running OpenBar instance before the selective smoke test." >&2
    exit 2
fi

VALIDATION_DIR="$ROOT_DIR/general/validation"
PROBE_BUNDLE="$ROOT_DIR/dist/OpenBarProbe.app"
INSTALLED_PROBE=/Applications/OpenBarProbe.app
INSTALLED_PROBE_CREATED=false
READY_FILE="$VALIDATION_DIR/probe-ready.txt"
SMOKE_OUTPUT="$VALIDATION_DIR/selective-smoke.txt"
SMOKE_ERRORS="$VALIDATION_DIR/selective-smoke-stderr.txt"
MENU_LOG="$VALIDATION_DIR/selective-menu-log.ndjson"
MENU_LOG_ERRORS="$VALIDATION_DIR/selective-menu-log-stderr.txt"
PROBE_PID=""
PROBE_LAUNCH_PID=""
LOG_PID=""

cleanup() {
    if [[ -n "$PROBE_PID" ]]; then /bin/kill "$PROBE_PID" 2>/dev/null || true; fi
    if [[ -n "$PROBE_LAUNCH_PID" ]]; then wait "$PROBE_LAUNCH_PID" 2>/dev/null || true; fi
    if [[ -n "$LOG_PID" ]]; then /bin/kill "$LOG_PID" 2>/dev/null || true; wait "$LOG_PID" 2>/dev/null || true; fi
    rm -f "$READY_FILE"
    if [[ "$INSTALLED_PROBE_CREATED" == true ]]; then
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$INSTALLED_PROBE" || true
        rm -rf "$INSTALLED_PROBE"
    fi
}
trap cleanup EXIT INT TERM
mkdir -p "$VALIDATION_DIR" "$PROBE_BUNDLE/Contents/MacOS" "$ROOT_DIR/.build/probe-module-cache"
rm -f "$READY_FILE"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/probe-module-cache" \
SWIFT_MODULECACHE_PATH="$ROOT_DIR/.build/probe-module-cache" \
    xcrun swiftc -parse-as-library "$ROOT_DIR/general/testing/MenuBarProbe.swift" \
        -target "$(uname -m)-apple-macos14.0" -o "$PROBE_BUNDLE/Contents/MacOS/OpenBarProbe"
cat > "$PROBE_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>internal.openbar.probe</string>
<key>CFBundleName</key><string>OpenBarProbe</string>
<key>CFBundleExecutable</key><string>OpenBarProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$PROBE_BUNDLE"
[[ ! -e "$INSTALLED_PROBE" ]] || { echo "Refusing to replace existing probe app." >&2; exit 2; }
/usr/bin/ditto "$PROBE_BUNDLE" "$INSTALLED_PROBE"
INSTALLED_PROBE_CREATED=true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALLED_PROBE"

: > "$SMOKE_OUTPUT"
: > "$SMOKE_ERRORS"
: > "$MENU_LOG"
: > "$MENU_LOG_ERRORS"
/usr/bin/log stream --style ndjson --level debug --predicate \
    'subsystem == "com.apple.menubar"' \
    > "$MENU_LOG" 2> "$MENU_LOG_ERRORS" &
LOG_PID=$!
/usr/bin/open -n -W "$INSTALLED_PROBE" --args --ready-file "$READY_FILE" &
PROBE_LAUNCH_PID=$!
for _ in {1..50}; do
    if [[ -s "$READY_FILE" ]]; then break; fi
    /bin/sleep 0.1
done
if [[ ! -s "$READY_FILE" ]]; then echo "Fixture did not report readiness." >&2; exit 1; fi
PROBE_PID="$(head -n 1 "$READY_FILE")"
if [[ ! "$PROBE_PID" =~ ^[0-9]+$ ]]; then echo "Fixture PID is invalid." >&2; exit 1; fi
/usr/bin/open -n -W --stdout "$SMOKE_OUTPUT" --stderr "$SMOKE_ERRORS" "$APP_BUNDLE" \
    --args --smoke-check --smoke-hidden-bundle internal.openbar.probe
cat "$SMOKE_OUTPUT"
if ! grep -q '^OpenBar native smoke-check passed$' "$SMOKE_OUTPUT"; then
    cat "$SMOKE_ERRORS" >&2
    exit 1
fi
/bin/sleep 0.2
/bin/kill "$LOG_PID" 2>/dev/null || true
wait "$LOG_PID" 2>/dev/null || true
LOG_PID=""

# The system logging format is private too. Only a complete three-phase count
# sequence is treated as an oracle; successful activation alone proves less.
python3 - "$SMOKE_OUTPUT" "$MENU_LOG" <<'PY'
import datetime
import json
import re
import sys

stages = {}
for line in open(sys.argv[1], encoding="utf-8"):
    match = re.match(r"STAGE: (\S+) (probe-\S+)", line)
    if match:
        stages[match[2]] = datetime.datetime.fromisoformat(match[1].replace("Z", "+00:00"))
counts = {"visible": [], "hidden": [], "restored": []}
for line in open(sys.argv[2], encoding="utf-8"):
    try:
        entry = json.loads(line)
        normalized = re.sub(r'([+-]\d{2})(\d{2})$', r'\1:\2', entry["timestamp"].replace("Z", "+00:00"))
        timestamp = datetime.datetime.fromisoformat(normalized)
    except (ValueError, KeyError, TypeError):
        continue
    message = entry.get("eventMessage", "")
    match = re.search(r'MenuBar\.trailingItems\.count.*?["\x27]count["\x27]\s*:\s*(\d+)', message)
    if not match:
        match = re.search(r"trailingItems\s*(?:count\s*)?[:=]\s*(\d+)", message)
    if not match:
        continue
    # The fixture and OpenBar emit their initial count before the visible marker.
    # The last count preceding hide-begin is therefore the unrestricted baseline.
    for phase, start, end in (("visible", None, "probe-hide-begin"),
                              ("hidden", "probe-hide-begin", "probe-restore-begin"),
                              ("restored", "probe-restore-begin", "probe-complete")):
        if end in stages and (start is None or start in stages and stages[start] <= timestamp) and timestamp < stages[end]:
            counts[phase].append(int(match[1]))
if not all(counts.values()):
    print("UNVERIFIED: native activation succeeded; system logs did not expose a complete item-count oracle.")
else:
    visible, hidden, restored = (counts[phase][-1] for phase in ("visible", "hidden", "restored"))
    print(f"ORACLE: visible={visible}, hidden={hidden}, restored={restored}")
    if visible - hidden == 1 and restored == visible:
        print("PASS: system item counts confirm the fixture hid and reappeared.")
    else:
        print("FAIL: item counts do not confirm exactly one hidden and restored fixture.", file=sys.stderr)
        sys.exit(1)
PY
