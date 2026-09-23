#!/bin/bash
# Builds Meridian.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Meridian"

APP=build/Meridian.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Meridian"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: build the .icns from the 1024px master (regenerate that with scripts/make-icon.swift).
ICONSET=.build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Meridian || true
    # Sync into place rather than delete + copy: macOS may refuse to remove the existing bundle folder.
    mkdir -p /Applications/Meridian.app
    rsync -a --delete "$APP/" /Applications/Meridian.app/
    touch /Applications/Meridian.app  # nudge Finder to pick up icon changes
    open /Applications/Meridian.app
    echo "Installed to /Applications/Meridian.app"
fi
