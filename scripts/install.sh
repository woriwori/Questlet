#!/bin/bash
set -euo pipefail

fail() { printf '설치 중단: %s\n' "$*" >&2; exit 1; }
usage() {
    cat <<'HELP'
사용법: ./scripts/install.sh [--no-open] [--install-dir DIRECTORY]
소스를 빌드하고 ~/Applications/Questlet.app에 설치한 뒤 실행합니다.
  --no-open                 설치만 하고 실행하지 않습니다.
  --install-dir DIRECTORY  설치 폴더를 지정합니다. 앱 이름은 Questlet.app입니다.
  --help                   이 도움말을 표시합니다.
기존 작업 DB와 키체인 토큰은 유지합니다. sudo는 사용하지 않습니다.
HELP
}
install_dir="${HOME:?HOME is required}/Applications"
open_after_install=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-open) open_after_install=false; shift ;;
        --install-dir) [[ $# -ge 2 && -n "$2" ]] || fail '--install-dir 뒤에 폴더를 지정하세요.'; install_dir="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; fail "알 수 없는 옵션: $1" ;;
    esac
done
[[ "$(uname -s)" == Darwin ]] || fail 'macOS에서 실행하세요.'
[[ "$(id -u)" != 0 ]] || fail 'sudo 없이 로그인한 사용자로 실행하세요.'
macos_version="$(sw_vers -productVersion)"
[[ "${macos_version%%.*}" -ge 14 ]] || fail 'macOS 14 이상이 필요합니다.'
case "$(uname -m)" in arm64|x86_64) ;; *) fail '지원 대상은 Apple Silicon 또는 Intel Mac입니다.' ;; esac
xcrun --find swiftc >/dev/null 2>&1 || fail 'Apple 개발 도구가 필요합니다. xcode-select --install 실행 후 설치를 완료하고 다시 실행하세요.'

mkdir -p "$install_dir"
install_dir="$(cd "$install_dir" && pwd -P)"
target="$install_dir/Questlet.app"
[[ ! -L "$target" ]] || fail "앱 경로가 심볼릭 링크입니다: $target"
if [[ -e "$target" ]]; then
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null || true)"
    [[ "$bundle_id" == local.questlet.app ]] || fail "다른 파일이나 앱이 있어 덮어쓰지 않습니다: $target"
fi
for app_pid in $(pgrep -u "$(id -u)" -x Questlet || true); do
    running_path="$(ps -p "$app_pid" -o comm= || true)"
    if [[ "$open_after_install" == true || "$running_path" == "$target/Contents/MacOS/Questlet" ]]; then
        fail '실행 중인 Questlet을 앱 메뉴 > Questlet 종료로 종료한 뒤 다시 실행하세요. 입력 중인 내용은 먼저 저장하세요.'
    fi
done

repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"
printf 'Questlet 빌드 중…\n'
bash "$repo_root/scripts/build.sh"
staging="$(mktemp -d "$install_dir/.questlet-install.XXXXXX")"
cleanup() {
    local result=$?
    trap - EXIT
    if [[ "$result" -ne 0 && -d "$staging/previous.app" && ! -e "$target" ]]; then
        mv "$staging/previous.app" "$target" || printf '기존 앱 복구 필요: %s\n' "$staging/previous.app" >&2
    fi
    # Retain the backup if restoration failed.
    if [[ ! -d "$staging/previous.app" || -e "$target" ]]; then rm -rf "$staging"; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$repo_root/dist/Questlet.app" "$staging/Questlet.app"
codesign --verify --deep --strict "$staging/Questlet.app"
if [[ -e "$target" ]]; then mv "$target" "$staging/previous.app"; fi
mv "$staging/Questlet.app" "$target"
codesign --verify --deep --strict "$target"
printf '설치 완료: %s\n' "$target"
if [[ "$open_after_install" == true ]]; then
    open "$target" || fail "앱 설치는 완료됐지만 자동 실행에 실패했습니다. Finder에서 직접 여세요: $target"
    printf '앱 열기를 요청했습니다. 최초 토큰 설정 화면은 사용자가 직접 완료하세요.\n'
fi
