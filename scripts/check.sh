#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
source scripts/macos-env.sh
swiftc -sdk "$QUESTLET_SDK_PATH" -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -parse-as-library -D QUESTLET_CHECKS -I .build/manual -I Sources/CSQLite -L .build/manual -lQuestletCore -Xlinker -rpath -Xlinker @executable_path Tests/QuestletCoreTests/WorkflowTests.swift -o .build/manual/QuestletChecks
.build/manual/QuestletChecks
