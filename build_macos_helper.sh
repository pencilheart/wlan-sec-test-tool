#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
    echo "This helper requires macOS." >&2
    exit 1
fi
/usr/bin/xcrun --find swiftc >/dev/null
stage="$(mktemp -d "./.wlan-helper-build.XXXXXX")"
trap 'rm -rf -- "$stage"' EXIT
app="$stage/WLAN Scan Helper.app"
mkdir -p "$app/Contents/MacOS"
cp WLANScanHelper-Info.plist "$app/Contents/Info.plist"
/usr/bin/xcrun swiftc -module-cache-path "$stage/module-cache" WLANScanHelper.swift -o "$app/Contents/MacOS/WLANScanHelper" -framework AppKit -framework CoreLocation -framework CoreWLAN
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
if [[ -e "WLAN Scan Helper.app" ]]; then
    mv "WLAN Scan Helper.app" "$stage/previous.app"
fi
if ! mv "$app" "WLAN Scan Helper.app"; then
    [[ ! -e "$stage/previous.app" ]] || mv "$stage/previous.app" "WLAN Scan Helper.app"
    exit 1
fi
echo "Built WLAN Scan Helper.app. Start the tool and click Scan to request permission."
