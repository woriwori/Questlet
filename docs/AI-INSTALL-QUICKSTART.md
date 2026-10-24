# Questlet 로컬 설치 — AI 퀵가이드

이 문서를 받은 AI는 사용자의 Mac에 Questlet 소스를 빌드·설치하고 결과를 확인한다.
저장소: https://github.com/woriwori/Questlet.git
설치 명령: `bash scripts/install.sh`
기본 설치 위치: `~/Applications/Questlet.app` — 관리자 권한 없이 현재 사용자 계정에 설치한다.

## 1. 소스와 개발 도구 준비

사용자가 전달한 Questlet 저장소가 있으면 그 폴더를 사용한다. 기존 소스의 수정 사항은 유지한다.
소스가 없으면 비어 있는 경로에 복제한다. GitHub 인증이 필요하면 사용자의 기존 인증 수단을 사용한다.

```bash
mkdir -p "$HOME/Developer"
git clone https://github.com/woriwori/Questlet.git "$HOME/Developer/Questlet"
cd "$HOME/Developer/Questlet"
```

이미 해당 경로에 저장소가 있으면 clone 대신 폴더로 이동한다. 별도 파일이나 다른 저장소라면 새 경로를 선택한다.

macOS 14 이상, Apple의 Swift 컴파일러와 macOS SDK가 필요하다. Homebrew나 외부 패키지는 필요 없다.

```bash
sw_vers -productVersion
uname -m
xcrun --find swiftc
```

`xcrun`이 개발 도구를 찾지 못하면 `xcode-select --install`로 Apple Command Line Tools 설치 화면을 연다.
다운로드·설치·약관 승인 화면은 사용자가 직접 완료한 후 위 명령을 다시 확인한다.
전체 Xcode가 설치되어 있다면 그 도구를 사용할 수 있다.

## 2. 빌드·설치·실행

실행 중인 Questlet이 있다면 입력 중인 내용을 저장하고 앱 메뉴의 **Questlet 종료**로 종료한다.
프로세스를 강제로 종료해 초안을 버리지 않는다.
저장소 루트에서 다음 명령을 실행하고 종료 코드 0 및 `설치 완료:` 출력을 확인한다.

```bash
bash scripts/install.sh
```

스크립트는 현재 실행 아키텍처(arm64/x86_64)에 맞춰 빌드하고, 서명을 검사한 앱을 설치한 뒤 연다.
기존 설치를 갱신할 때 앱 번들만 교체한다. 작업 DB와 키체인 PAT는 유지한다.
설치 대상이 다른 파일·앱 또는 심볼릭 링크라면 중단한다. 교체 도중 실패하면 기존 앱을 복원한다.

앱을 실행하지 않고 설치만 하려면:

```bash
bash scripts/install.sh --no-open
```

설치 폴더를 바꾸려면(앱 이름은 `Questlet.app`):

```bash
bash scripts/install.sh --install-dir "$HOME/Applications"
```

## 3. 설치 결과 확인

기본 경로 기준으로 실행한다. 설치 경로를 바꿨다면 확인 경로도 맞춘다.

```bash
test -x "$HOME/Applications/Questlet.app/Contents/MacOS/Questlet"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOME/Applications/Questlet.app/Contents/Info.plist"
codesign --verify --deep --strict "$HOME/Applications/Questlet.app"
```

완료 기준:

- 실행 파일이 존재하고 bundle identifier가 `local.questlet.app`이다.
- `codesign --verify`가 성공한다. 개발용 ad-hoc 서명이며 Developer ID 서명·공증 배포본은 아니다.
- 기본 설치 모드라면 `pgrep -u "$(id -u)" -x Questlet`로 실행 프로세스를 확인한다.
- 화면 접근이 가능하면 Questlet 메인 화면 또는 최초 토큰 설정 화면이 표시되는지 확인한다.
  화면이 잠겼거나 접근 권한이 없으면 파일 설치·프로세스 확인과 UI 미검증을 구분해 보고한다.

macOS 실행 승인이나 키체인 승인이 나타나면 사용자가 직접 처리한다. 시스템 보안 설정을 끄거나
격리 속성을 일괄 제거하는 방식으로 우회하지 않는다.

## 4. 최초 설정과 실제 연동

첫 실행에서 Jira·emux PAT 설정 화면이 나온다. 사용자가 준비한 토큰을 앱의 보안 입력창에 직접 입력한다.
AI는 토큰을 채팅·문서·스크립트·저장소에 기록하지 않는다. 설치 완료와 토큰 설정 완료를 따로 보고한다.

현재 이 저장소의 Jira·SRD·RP 연동은 mock이다. 앱 설치가 실제 사내 API 연결까지 완료한다는 뜻은 아니다.
회사 Jira 링크는 `Sources/Questlet/AppConfiguration.swift`의 `AppConfiguration.jiraBrowseBaseURL`에
코드로 설정하며 기본값은 `nil`이다. 설치만 요청받았다면 이 값을 임의로 채우지 않는다.
실제 API 연결을 요청받으면 `docs/INTEGRATION-GUIDE.md`와 `docs/prompts/JIRA-INTEGRATION-PROMPT.md`를 읽는다.

## 오류가 났을 때

- **실행 중인 앱:** 사용자에게 정상 종료를 요청하고 설치 명령을 다시 실행한다.
- **SDK 경로 오류 또는 컴파일러/SDK 불일치:** `xcrun --sdk macosx --show-sdk-path`와 설치된 SDK를 확인한다.
  사용 가능한 SDK를 확인한 경우에만 명시적으로 지정한다.

  ```bash
  QUESTLET_SDK_PATH="/실제로/설치된/MacOSX.sdk" bash scripts/install.sh
  ```

- **설치 경로 권한 오류:** sudo 대신 사용자가 쓸 수 있는 `--install-dir`을 사용한다.
- **빌드 실패:** 오류 원문과 개발 도구 정보를 보고한다. 실패한 빌드를 설치 성공으로 처리하지 않는다.
- **복원 실패:** 스크립트가 출력한 기존 앱 백업 경로를 보존하고 사용자에게 알린다.
- **최신 소스로 재설치:** 기존 변경을 확인하고 소스 갱신 범위를 사용자 요청에 맞춰 결정한 뒤 같은 설치 명령을 실행한다.

## 사용자에게 남길 결과

설치 경로, 설치한 커밋(`git rev-parse --short HEAD`), 빌드/서명/실행 확인 결과,
최초 토큰 설정의 완료 여부, 남아 있는 오류 또는 UI 미검증 사항을 간단히 보고한다.
