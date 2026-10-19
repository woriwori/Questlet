# Questlet

개인 업무 일정과 코멘트를 로컬에서 관리하는 Mac 메뉴바 앱.

## 프로젝트 상태

SwiftUI 네이티브 앱, 로컬 SQLite, 메뉴바 팝오버, 작업 폼·검색·정렬·코멘트, 월간 캘린더, SRD/RP 생성 폼을 구현했다. 외부 연동은 모두 mock이며 사내 구현 삽입 지점은 별도 문서에 정리했다.

## 문서

- [기준 명세](docs/SPEC.md)
- [사내 연동 입력·출력 인터페이스](docs/INTEGRATION-INTERFACES.md)
- [사내 implementation 삽입·mock 교체 가이드](docs/INTEGRATION-GUIDE.md)
- [사내 AI에게 전달할 Jira 연동 구현 프롬프트](docs/prompts/JIRA-INTEGRATION-PROMPT.md)
- [디자인 컨셉과 와이어프레임](docs/DESIGN-CONCEPT.md)
- [월간 캘린더 디자인과 동작](docs/design/CALENDAR.md)
- [검토용 화면 소스](docs/design/dayline-wireframe.html)
- [용어집](GLOSSARY.md)
- [인터뷰와 결정 기록](docs/DESIGN-NOTES.md)
- [날짜 기반 상태](docs/adr/0001-date-derived-status.md)
- [초기 비동기 반영 결정 — 대체됨](docs/adr/0002-local-record-and-async-jira.md)
- [Jira 결과를 기다리는 저장](docs/adr/0003-wait-for-jira-result.md)
- [SwiftUI 기술 선택](docs/adr/0004-native-swiftui-app.md)

## 첫 버전

- SwiftUI 기반 Mac 앱과 로컬 SQLite 저장
- 최초 실행 Jira·emux PAT 설정, macOS 키체인 저장, 톱니바퀴 설정에서 토큰 교체
- 설정에서 확인 후 완료 작업·코멘트 일괄 로컬 삭제
- 제목·선택적인 티켓·날짜 범위를 폼으로 등록·수정
- ToDo / InProgress / Closed 자동 상태 계산
- 원문 코멘트·링크·기록 시각과 로컬 키워드 검색
- 진행 중 기본 탭과 예정·완료 탭, 앱 열기·새 작업·수정 진입을 제공하는 메뉴바 팝오버
- 사용자 저장 시 Jira 결과 대기와 같은 화면의 오류·재시도
- 사내 Jira 호출을 연결할 경계와 모의 연동
- + 생성 화면의 새 작업·SRD 생성·RP 생성 탭
- SRD 문자열 폼과 RP role 다중 선택·PRD 링크 폼, 10초 모의 생성 후 위키 링크 표시

실제 사내 인증 정보나 토큰은 이 폴더에 기록하지 않는다. emux, 채팅, 작업 일정 캘린더, Jira에서 로컬로 가져오는 동기화는 첫 버전에서 제외한다.

## 실행·빌드

macOS 14 이상. 현재 제공 패키지는 Apple Silicon용이다.

```sh
./scripts/build.sh
open dist/Questlet.app
./scripts/check.sh
./scripts/check-ui.sh
```

샘플 데이터는 `open dist/Questlet.app --args --demo`로 연다. 일반 DB와 분리한다. 이미 실행 중이라면 메뉴의 Questlet 종료 후 실행해야 인자가 적용된다.

현재 컴퓨터의 Swift Package Manager는 설치된 프레임워크 심볼 오류로 실행되지 않아 `swiftc` 빌드 스크립트를 제공한다. 스크립트는 호환 SDK인 MacOSX26.5.sdk를 명시한다. 다른 개발 환경에서는 `QUESTLET_SDK_PATH=/사용가능한/SDK/경로 ./scripts/build.sh`로 지정한다. Package.swift도 포함하며 정상 SwiftPM 환경에서는 일반 패키지 빌드·테스트를 사용할 수 있다.

로컬 DB: `~/Library/Application Support/Questlet/questlet.sqlite`. 데모는 하위 `Demo` 폴더다. 창을 닫아도 메뉴바에서 계속 실행하며 앱 메뉴에서 종료한다. 설정에서 mock 성공·실패·결과 불명을 선택하고 Jira browse 주소를 입력할 수 있다. 최초 실행에는 Jira·emux PAT를 입력하고 macOS 키체인에 저장한다. 이후 상단 우측 + 왼쪽의 톱니바퀴 또는 앱 메뉴의 설정에서 개별 PAT를 교체하고 완료 작업을 일괄 로컬 삭제할 수 있다. 현재 mock은 PAT 유효성을 검증하거나 외부로 전송하지 않는다.

검증 결과와 남은 사내 연결 작업은 [구현 보고서](docs/IMPLEMENTATION.md)에 있다.
