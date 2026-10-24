#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/macos-env.sh
QUESTLET_ARCH="$(uname -m)"
mkdir -p .build/manual dist
FLAGS=(-sdk "$QUESTLET_SDK_PATH" -target "$QUESTLET_ARCH-apple-macosx14.0" -swift-version 5 -parse-as-library)
swiftc "${FLAGS[@]}" -emit-module -emit-library -module-name QuestletCore -I Sources/CSQLite Sources/QuestletCore/*.swift -emit-module-path .build/manual/QuestletCore.swiftmodule -Xlinker -install_name -Xlinker @rpath/libQuestletCore.dylib -o .build/manual/libQuestletCore.dylib
swiftc "${FLAGS[@]}" -D QUESTLET_STANDALONE -I .build/manual -I Sources/CSQLite -L .build/manual -lQuestletCore -Xlinker -rpath -Xlinker @executable_path Sources/Questlet/*.swift Sources/Questlet/Integrations/*.swift -o .build/manual/Questlet
APP=dist/Questlet.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/manual/Questlet .build/manual/libQuestletCore.dylib "$APP/Contents/MacOS/"
cp Sources/Questlet/Resources/* "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.questlet.app</string><key>CFBundleName</key><string>Questlet</string><key>CFBundleExecutable</key><string>Questlet</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.1.0</string><key>CFBundleVersion</key><string>1</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/><key>CFBundleIconFile</key><string>Questlet</string>
</dict></plist>
PLIST
swiftc -sdk "$QUESTLET_SDK_PATH" scripts/render-app-icon.swift -o .build/manual/render-app-icon
.build/manual/render-app-icon Sources/Questlet/Resources/questlet-header.png .build/questlet-app-icon.png
mkdir -p .build/Questlet.iconset
for size in 16 32 128 256 512; do
 sips -z "$size" "$size" .build/questlet-app-icon.png --out ".build/Questlet.iconset/icon_${size}x${size}.png" >/dev/null
 double=$((size*2))
 sips -z "$double" "$double" .build/questlet-app-icon.png --out ".build/Questlet.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/Questlet.iconset -o "$APP/Contents/Resources/Questlet.icns"
codesign --force --deep --sign - "$APP"
printf 'Built %s/%s\n' "$PWD" "$APP"
