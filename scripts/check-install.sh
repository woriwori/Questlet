#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_root="$(mktemp -d "${TMPDIR:-/tmp}/questlet-install-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
install_dir="$test_root/Applications with spaces"
app="$install_dir/Questlet.app"

bash scripts/install.sh --no-open --install-dir "$install_dir"
test -x "$app/Contents/MacOS/Questlet"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = local.questlet.app
codesign --verify --deep --strict "$app"
printf old > "$app/reinstall-marker"
bash scripts/install.sh --no-open --install-dir "$install_dir"
test ! -e "$app/reinstall-marker"
codesign --verify --deep --strict "$app"

mkdir -p "$test_root/occupied"
printf keep > "$test_root/occupied/Questlet.app"
if bash scripts/install.sh --no-open --install-dir "$test_root/occupied" > "$test_root/occupied.log" 2>&1; then
    printf 'FAIL: unrelated target was accepted\n' >&2; exit 1
fi
test "$(cat "$test_root/occupied/Questlet.app")" = keep
if bash scripts/install.sh --unknown > "$test_root/options.log" 2>&1; then exit 1; fi
if QUESTLET_SDK_PATH="$test_root/missing-sdk" bash scripts/build.sh > "$test_root/sdk.log" 2>&1; then exit 1; fi

# Fail only the staged-new-app rename, so the real installer must restore its backup.
mkdir -p "$test_root/bin"
cat > "$test_root/bin/mv" <<'FAIL_MV'
#!/bin/bash
case "$1" in */.questlet-install.*/Questlet.app) exit 91 ;; esac
exec /bin/mv "$@"
FAIL_MV
chmod +x "$test_root/bin/mv"
printf restore > "$app/rollback-marker"
if PATH="$test_root/bin:$PATH" bash scripts/install.sh --no-open --install-dir "$install_dir" > "$test_root/rollback.log" 2>&1; then
    printf 'FAIL: injected install failure was ignored\n' >&2; exit 1
fi
test "$(cat "$app/rollback-marker")" = restore
rm "$app/rollback-marker"
codesign --verify --deep --strict "$app"
printf 'Installer checks passed: real build/install, spaces in path, reinstall, unrelated-target protection, SDK override and rollback. App launch was skipped.\n'
