#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
case "$MODE" in run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;; *) echo "usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;; esac
cd "$ROOT_DIR"
/usr/bin/pkill -x OpenBar >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/build-app.sh" debug
"$ROOT_DIR/scripts/install-app.sh"
APP_BUNDLE=/Applications/OpenBar.app
case "$MODE" in
    run) /usr/bin/open -n "$APP_BUNDLE" ;;
    --debug|debug) /usr/bin/lldb -- "$APP_BUNDLE/Contents/MacOS/OpenBar" ;;
    --logs|logs)
        /usr/bin/open -n "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate 'process == "OpenBar"'
        ;;
    --telemetry|telemetry)
        /usr/bin/open -n "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate 'subsystem == "internal.openbar.app"'
        ;;
    --verify|verify)
        /usr/bin/open -n "$APP_BUNDLE"
        sleep 1
        /usr/bin/pgrep -x OpenBar >/dev/null
        echo "OpenBar launch verified"
        ;;
esac
