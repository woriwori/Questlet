#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/macos-env.sh
swiftc -sdk "$QUESTLET_SDK_PATH" -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -parse-as-library -D QUESTLET_STANDALONE -D QUESTLET_UI_CHECKS -I .build/manual -I Sources/CSQLite -L .build/manual -lQuestletCore -Xlinker -rpath -Xlinker @executable_path Sources/Questlet/*.swift Sources/Questlet/Integrations/*.swift Tests/QuestletUIRegression.swift -o .build/manual/QuestletUIRegression
mkdir -p .build/UIRegression.app/Contents/MacOS .build/UIRegression.app/Contents/Resources
cp .build/manual/QuestletUIRegression .build/manual/libQuestletCore.dylib .build/UIRegression.app/Contents/MacOS/
cp Sources/Questlet/Resources/* .build/UIRegression.app/Contents/Resources/
cp dist/Questlet.app/Contents/Info.plist .build/UIRegression.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable QuestletUIRegression" .build/UIRegression.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.questlet.ui-checks" .build/UIRegression.app/Contents/Info.plist
codesign --force --deep --sign - .build/UIRegression.app
.build/UIRegression.app/Contents/MacOS/QuestletUIRegression "$@"
