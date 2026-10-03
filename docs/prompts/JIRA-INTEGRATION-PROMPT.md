# Questlet 사내 Jira 연동 구현 프롬프트

이 문서 전체를 사내 AI에게 전달하거나, Questlet 저장소에서 이 파일을 읽고 아래 지시를 수행하도록 요청한다. 작업 루트는 이 저장소이며 개인 Mac의 절대 경로에 의존하지 않는다.

## 목표와 범위

Questlet의 Jira mock을 실제 사내 Jira 직접 호출로 교체해 주세요. 사용자는 사내 컴퓨터에서 Jira 직접 호출이 되는 것을 확인했으며, 이때 사용하는 토큰은 사내 emux의 Jira MCP 토큰과 같습니다. **토큰의 출처가 같다는 사실만으로 HTTP 인증 형식을 추정하지 말고**, 사내에서 검증된 호출 방법을 확인해 사용하세요.

앱은 SwiftUI 기반 macOS 앱입니다. 작업·코멘트·미처리 요청은 로컬 SQLite에 저장합니다. 이번 작업은 기존 Jira 티켓의 시작일·종료일·상태 변경과 원문 코멘트 추가입니다. SRD/RP는 계속 mock으로 두세요. emux·AI 해석·새 MCP 서버 없이 직접 Jira 호출을 연결하고, 현재 폼·목록·팝오버 디자인과 날짜 기반 상태 규칙을 유지하세요.

실제 회사 호출 구현까지 진행하세요. 설계나 TODO 추가만으로 끝내지 말고, 확보된 연결 정보로 구현·주입·검증을 완료하세요. 필요한 회사 정보가 없으면 아래 확인 단계에서 누락된 항목만 한 번에 질문하고, 그동안 비밀값이 필요 없는 adapter와 테스트 작업을 진행하세요.

## 1. 기존 계약과 호출 흐름 읽기

먼저 다음 파일을 읽고 실제 코드와 계약을 확인하세요.

| 파일 | 확인할 내용 |
| --- | --- |
| docs/SPEC.md | 등록·수정·코멘트·상태·실패·삭제 동작의 기준 |
| docs/INTEGRATION-INTERFACES.md | 입력·출력·부분 성공·결과 불명 계약 |
| docs/INTEGRATION-GUIDE.md | 사내 구현 삽입 지점과 오류 변환 |
| Sources/QuestletCore/IntegrationInterfaces.swift | JiraTicketModule, JiraRequest, JiraMutation, JiraReceipt, IntegrationFailure |
| Sources/QuestletCore/AppModel.swift | 로컬 저장 → 요청 영속화 → run → jira.execute → 결과 기록, retry/resolveUnknown/refresh |
| Sources/QuestletCore/MockAdapters.swift | 기존 mock과 실패 시나리오 |
| Sources/Questlet/Integrations/CompanyAdapters.swift | CompanyJiraTicketAdapter.execute의 구현 골격 |
| Sources/Questlet/IntegrationAssembly.swift | jira adapter 주입; srd/rp 주입은 mock 유지 |
| Sources/Questlet/QuestletApp.swift, Sources/Questlet/TaskViews.swift | 설정, Jira browse 링크, 모의 연동 안내 문구 |
| Tests/QuestletCoreTests/WorkflowTests.swift, scripts/check.sh, scripts/check-ui.sh | 기존 검증과 빌드 방법 |

완료 기준: 날짜·상태·코멘트 요청이 각각 어디서 만들어지고, 실패해도 어떤 로컬 정보가 남는지 실제 코드에서 확인했습니다.

## 2. 사내 연결 정보 확인

사내 API 문서, 이미 성공한 호출 예제, 접근 가능한 Jira 메타데이터를 우선 확인하세요. 이 저장소에는 실제 host·인증 방식·필드 ID·transition ID가 없습니다. 다음 항목을 확인된 값으로 설정할 수 있어야 합니다.

- 실제 API base URL과 호출 규격, Jira 배포 형태·API 버전.
- 인증 헤더 형식과 토큰을 읽을 승인된 로컬 저장 위치. 필요하면 사내 네트워크·프록시·인증서 구성.
- 시작일·종료일 필드 식별자와 입력 형식, 대상 프로젝트/티켓에서 편집 가능 여부.
- 내부 ToDo / InProgress / Closed가 대응하는 Jira 상태 식별자와 허용 전환. 실제 Swift enum case는 소스에서 확인합니다.
- 코멘트 본문 형식과 코멘트 ID·요청 결과를 확인하는 방법, 중복 방지 지원 여부.
- 직접 열 때 사용할 Jira browse 주소와 **수정해도 되는 테스트 티켓**.

토큰 값은 사용자가 사내 컴퓨터의 승인된 로컬 자격 정보 저장소에 직접 설정하도록 안내하세요. 소스·일반 SQLite·커밋·문서·로그에 토큰을 넣지 마세요. 진단 메시지도 인증 헤더와 비밀값을 제외합니다. 날짜·상태 설정은 adapter에 주입하고, 자격 정보는 사내 저장 방식에 맞춘 provider로 읽으세요. 회사 값이 없으면 실행 시 설명 가능한 configuration 실패를 반환하세요.

완료 기준: 실제 연결 설정과 각 mutation의 Jira 대응을 확인했거나, 확인 불가 항목을 명시했습니다. 예시 티켓 CMGSL-13332는 테스트 허가가 아닙니다. 실제 쓰기 검증은 사용자가 지정한 테스트 티켓으로만 수행하세요.

## 3. 실제 adapter 구현과 연결

CompanyJiraTicketAdapter가 기존 `JiraTicketModule.execute`를 구현하도록 채우세요. 앱이 전달하는 requestID·ticketKey·mutation은 고정된 요청 입력입니다. 성공 시 같은 requestID와 ticketKey를 담은 JiraReceipt를 반환하고, 실제 반영이 확인된 결과만 simulated=false로 표시하세요. 코멘트 ID를 얻을 수 있으면 remoteCommentID로 반환하세요.

| mutation | 구현할 동작 |
| --- | --- |
| setDates | 입력 yyyy-MM-dd를 확인한 회사 필드 형식으로 변환하고 두 날짜를 반영·확인합니다. 시간대 변환으로 날짜를 이동시키지 마세요. 일부 필드만 반영된 경우 전체 성공으로 처리하지 말고 현재 원격값을 확인해 두 필드를 목표값으로 수렴시킵니다. |
| setStatus | 앱의 내부 상태를 Jira 목표 상태에 매핑합니다. 이미 목표 상태이면 성공입니다. 현재 티켓에 허용된 transition을 확인해 실행하고 목표 상태를 확인합니다. 프로젝트나 현재 상태에 따라 transition ID가 달라질 수 있으므로 이를 임의의 고정 숫자로 가정하지 마세요. 허용되지 않는 전환은 unsupportedTransition으로 설명합니다. |
| appendComment | body 원문을 회사가 받는 형식으로 변환해 의미·줄바꿈·링크를 보존합니다. 요약하지 않습니다. 요청 결과를 확인하고, 안전하게 같은 요청임을 식별할 수 있는 경우 중복을 방지합니다. 같은 본문이라는 이유만으로 별개의 코멘트를 합치지 마세요. |

기본 HTTP 호출에는 Foundation URLSession을 우선 사용하고, 회사에 이미 정해진 호출 도구가 있으면 그 규격에 맞추세요. 인증·HTTP/스크립트 호출·필드/상태 매핑·응답 변환은 adapter 내부에서 처리합니다. UI에 회사 응답 JSON이나 transition 조회 절차를 노출하지 마세요.

구현이 준비되면 IntegrationAssembly의 `jira`만 CompanyJiraTicketAdapter로 바꾸세요. 테스트에서 MockJiraTicketAdapter를 주입하는 구조는 유지합니다. 실제 모드에서 TaskViews의 “모의 Jira” 문구와 SettingsView의 “현재 모든 외부 연동은 mock” 안내를 정확하게 바꾸고, mock 시나리오 설정이 SRD/RP에만 적용됨을 표시하세요. 티켓 링크는 기존 browse 설정을 사용합니다.

완료 기준: 앱의 기존 저장·수정·코멘트 경로가 실제 adapter를 호출하며, SRD/RP는 기존 mock을 호출합니다. 네트워크 대기 중 UI는 응답하고 앱은 실제 Jira 결과를 상세 화면에 표시합니다.

## 4. 저장·오류·재시도 동작 보존

기준 계약은 INTEGRATION-INTERFACES.md입니다. 특히 다음 동작을 검증하세요.

- 로컬 변경과 Jira 요청은 원자적으로 저장됩니다. 폼은 로컬 저장 성공 후 닫히고 상세 화면에서 Jira 결과를 기다립니다. Jira 실패 때문에 로컬 변경을 롤백하지 않습니다.
- 날짜와 상태는 별도 요청입니다. 날짜 성공 후 상태가 실패했다면 재시도는 실패한 상태 요청만 처리합니다. 같은 티켓의 요청 순서와 미전송 일정·상태 병합은 AppModel이 관리합니다.
- 요청 전 실패·확인된 미반영은 notApplied, 전송 후 원격 효과를 확인할 수 없는 경우는 unknown입니다. 응답 유실·취소·응답 파싱 실패를 무조건 미반영으로 취급하지 마세요. 코드·사용자 메시지·필요한 retryAfterSeconds를 함께 반환합니다.
- 재시도는 기존 requestID를 유지합니다. requestID가 있다는 것 자체는 Jira의 멱등성 보장이 아닙니다. 날짜·상태는 현재 원격값을 확인해 목표값으로 수렴시키고, 코멘트는 회사의 확인/중복 방지 수단이 없으면 unknown으로 남겨 자동 중복 추가를 막습니다.
- 앱 재시작 시 미처리 요청을 복구합니다. 결과 불명 코멘트는 중단하고 기존 사용자 확인 흐름을 유지합니다. 앱 내부의 자동 재시도와 adapter 내부 재시도가 겹쳐 코멘트 쓰기를 반복하지 않도록 하세요.
- 티켓 없는 작업은 로컬에만 저장합니다. 로컬 삭제는 Jira 티켓이나 코멘트를 삭제하지 않습니다. 삭제된 작업이 늦은 응답으로 다시 생기지 않아야 합니다.
- 날짜 기반 상태는 한국 날짜 기준이며 종료일 당일까지 진행 중입니다. 종료일 연장으로 완료 → 진행 중 전환이 발생해도 로컬 변경은 유지하고, Jira가 이를 허용하지 않으면 반영 실패를 표시합니다.

필요한 변경은 실제 연동 경계와 관련 안내에 한정하세요. 기존 protocol 변경이 꼭 필요하다면 어떤 회사 규격 때문에 필요한지 설명하고 호출자·문서·테스트를 함께 갱신하세요.

완료 기준: 성공·미반영 실패·결과 불명이 서로 구분되며 코멘트가 응답 유실 때문에 자동으로 중복 등록되지 않습니다.

## 5. 검증과 인계

1. 기존 핵심·UI 회귀 검사를 실행하세요. 빌드 SDK 경로가 사내 컴퓨터와 다르면 설치된 Swift와 호환되는 SDK를 QUESTLET_SDK_PATH로 지정하세요. 도구 실패와 코드 실패를 구분합니다.
2. adapter의 HTTP 경계에서 응답을 제어하는 테스트를 추가해 실제 필드 매핑, 인증/권한 오류, transition 조회·이미 목표 상태, 제한 시간·응답 유실, 코멘트 결과 확인을 검증하세요. 로그에 토큰을 출력하는 테스트는 만들지 않습니다.
3. 지정된 테스트 티켓에서 앱으로 날짜 수정·상태 반영·원문 코멘트 추가·티켓 링크 열기를 수행하고 Jira에서 실제 값과 코멘트 개수를 확인하세요. 코멘트 중복 여부, 날짜 성공/상태 실패 후 재시도, 미처리 요청 재시작 복구도 확인합니다. 실제 쓰기 대상이 없으면 이 단계만 미검증으로 명시합니다.
4. README와 INTEGRATION-GUIDE에 비밀값 없이 사내 설정 방법·수정한 파일·호출 경로·실행 방법을 정리하세요. 실제 검증 결과와 남은 제한은 IMPLEMENTATION.md에 기록합니다.
5. 최종 응답은 구현 내용, 필요한 로컬 설정, 실행한 검증, 실제 Jira 확인 결과, 미검증 항목을 구분해 보고하세요. 모의 성공을 실연동 성공으로 보고하지 마세요.

완료 기준: 실제 adapter가 연결된 실행 가능한 앱과 검증 결과, 재현 가능한 설정 안내가 있습니다. 회사 구현·설정의 외부 GitHub push는 별도 사용자 요청과 사내 정책에 따라 처리합니다. 이번 작업 지시만으로 회사 비밀정보를 외부 저장소에 전송하지 않습니다.
