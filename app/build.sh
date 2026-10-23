#!/bin/bash
# Builds "ProPresenter Voice Remote.app" and installs it in /Applications.
# Run again after changing voice_remote.py: the app carries its own copy.
set -euo pipefail
cd "$(dirname "$0")"

NAME="ProPresenter Voice Remote"
OUT="build/$NAME.app"
DEST="/Applications/$NAME.app"

rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
swiftc -O -o "$OUT/Contents/MacOS/VoiceRemote" main.swift
cp ../voice_remote.py "$OUT/Contents/Resources/"

# App icon: every size macOS asks for, cut from the 1024 px master.
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) icon/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ProPresenter Voice Remote</string>
    <key>CFBundleDisplayName</key><string>ProPresenter Voice Remote</string>
    <key>CFBundleIdentifier</key><string>com.paulclifford.propresenter-voice-remote</string>
    <key>CFBundleExecutable</key><string>VoiceRemote</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>ProPresenter Voice Remote listens for commands like "next slide" to control ProPresenter.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS remembers the microphone permission.
codesign --force --deep --sign - --options runtime --entitlements entitlements.plist "$OUT"

rm -rf "$DEST"
cp -R "$OUT" "$DEST"
echo "Installed $DEST"
