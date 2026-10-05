#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/dist/OpenBar.app"
DESTINATION=/Applications/OpenBar.app
[[ -d "$SOURCE" ]] || { echo "Build OpenBar before installing." >&2; exit 1; }
if [[ -e "$DESTINATION" ]]; then
    IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$IDENTIFIER" == internal.openbar.app ]] || { echo "Refusing to replace a different app at $DESTINATION" >&2; exit 1; }
fi
/usr/bin/codesign --verify --strict "$SOURCE"
/usr/bin/ditto "$SOURCE" "$DESTINATION"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DESTINATION"
/usr/bin/codesign --verify --strict "$DESTINATION"
echo "Installed $DESTINATION"
