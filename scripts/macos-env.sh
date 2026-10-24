# Shared SDK selection for local builds and checks. An explicit override wins.
if [[ -z "${QUESTLET_SDK_PATH:-}" ]]; then
    # This SDK also works on Macs whose newest installed SDK needs a newer runtime.
    if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
        QUESTLET_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
    else
        QUESTLET_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
    fi
fi
if [[ ! -d "$QUESTLET_SDK_PATH" ]]; then
    printf 'macOS SDK를 찾을 수 없습니다: %s\n' "$QUESTLET_SDK_PATH" >&2
    exit 1
fi
export QUESTLET_SDK_PATH
