# 사내 implementation 삽입 가이드

작성일: 2026-10-03. 입력·출력의 기준은 [INTEGRATION-INTERFACES.md](INTEGRATION-INTERFACES.md), 동작의 기준은 [SPEC.md](SPEC.md)다.

## 실제 파일과 교체 지점

네이티브 앱과 영속 저장·요청 실행을 구현했다. `docs/design/dayline-wireframe.html`은 검토용 시안이다. 실제 연결은 아래 Swift 코드에 넣는다.

| 실제 경로 | 책임 / 삽입 위치 |
| --- | --- |
| Sources/QuestletCore/IntegrationInterfaces.swift | 세 protocol과 입력·출력·실패 계약 |
| Sources/QuestletCore/MockAdapters.swift | Jira 700ms, SRD/RP 10초 mock과 성공·실패·결과 불명 시나리오 |
| Sources/Questlet/Integrations/CompanyAdapters.swift | **실제 사내 호출을 넣을 세 메서드**. TODO(company) 검색 |
| Sources/Questlet/IntegrationAssembly.swift | **mock을 Company adapter로 교체할 세 주입값**. INTEGRATION-ASSEMBLY 검색 |
| Sources/QuestletCore/AppModel.swift | SQLite 저장, Jira 요청 순서·부분 성공·실패·복구·재시도. run → jira.execute |
| Sources/Questlet/CreationForm.swift | SRD/RP 입력과 생성 대기·결과. generate → srd.generate / rp.generate |
| Sources/Questlet/Resources/RoleOptions.json | role 선택지 추가. UI 변경 불필요 |
| Sources/QuestletCore/Database.swift | 작업과 요청을 하나의 SQLite 트랜잭션으로 저장 |

## 삽입 순서

1. CompanyAdapters.swift의 세 메서드를 채운다. 필요한 host·필드 설정·자격 정보는 adapter 생성자로 받는다. endpoint와 인증 방식은 회사 계약을 확인하고 정한다.
2. IntegrationAssembly.swift의 `jira`, `srd`, `rp` concrete 타입만 Company adapter로 바꾼다. 한 기능씩 mock과 혼합할 수 있다. UI와 DB는 protocol만 호출한다.
3. 정상 응답을 JiraReceipt 또는 WikiReceipt로 변환한다. 입력 requestID를 그대로 반환하고 실제 성공이면 simulated=false로 한다.
4. 오류는 IntegrationFailure로 변환한다. 응답이 없다는 이유만으로 notApplied를 반환하지 않는다. 효과를 확인할 수 없으면 unknown이다.
5. `./scripts/check.sh`로 핵심 흐름을 검증한 뒤 사내 테스트 티켓·위키에서 필드·상태·코멘트·링크를 확인한다.

```swift
// IntegrationAssembly.swift — 사내 구현을 완성한 후 교체
var jira: any JiraTicketModule { CompanyJiraTicketAdapter() }
var srd: any SRDGenerationModule { CompanySRDGenerationAdapter() }
var rp: any RPGenerationModule { CompanyRPGenerationAdapter() }
// 회사 설정/자격 정보가 필요하면 위 생성자와 adapter에 인자를 추가한다.
```

현재 Company adapter는 configuration 실패를 반환하는 삽입용 골격이다. 실제 호출 코드를 채우기 전에 주입값만 바꾸면 성공하지 않는다. 운영 토큰은 소스·문서·일반 DB에 기록하지 말고 사내 자격 정보 저장 방식에 맞춘다.

UI에서 보이는 “모의 Jira” 안내도 실연동 연결 시 변경한다. `rg '모의 Jira|모의 연동' Sources/Questlet`로 찾을 수 있다. 연결 여부를 위한 별도 공통 framework는 필요하지 않다.

## 기능별 실제 implementation

### Jira

CompanyJiraTicketAdapter.execute의 `request.mutation`을 switch한다.

| 입력 | 회사 implementation에서 할 일 |
| --- | --- |
| setDates | yyyy-MM-dd를 회사 시작/종료 필드에 맞게 변환해 기존 ticketKey에 반영. 두 날짜의 성공 확인 |
| setStatus | 내부 상태를 회사 워크플로의 목표 상태에 대응. 이미 목표 상태면 성공. 필요한 transition 조회·실행·확인 |
| appendComment | body 원문을 회사 코멘트 형식으로 변환. 이미 전달한 요청인지 확인하고 한 번 추가. 가능하면 원격 코멘트 ID 반환 |

호출자는 상태 ID, transition ID, Jira 문서 형식, HTTP 응답을 알 필요가 없다. 동작 확인에 여러 요청이 필요해도 execute 안에서 마친다.

앱의 로컬 저장과 미처리 요청을 만드는 위치는 유지한다. Jira가 실패해도 로컬 변경을 롤백하지 않는다. 날짜와 상태는 별도 요청이므로 성공한 날짜를 상태 실패 때문에 다시 보내지 않는다. 원격 확인이 불가능한 코멘트 결과를 단순 실패로 바꿔 재전송하지 않는다.

Jira 티켓 링크는 변경 interface의 반환값에 의존하지 않는다. 앱 설정의 회사 Jira browse 주소와 정규화된 티켓 키로 만든다. 티켓이 없는 작업의 로컬 저장에도 Jira 연결이 필요해서는 안 된다.

### SRD

CompanySRDGenerationAdapter.generate에서 prd·title·parentPageLink를 회사 생성 입력으로 변환한다. 부모 페이지 ID가 필요하면 링크에서 해석하거나 회사 조회를 수행한다. 템플릿·문서 본문 생성은 이 implementation에 둔다. 완료 응답의 페이지 ID/URL을 WikiReceipt.wikiURL로 변환한다.

회사 호출이 job ID만 반환한다면 generate 안에서 해당 job 완료를 확인한 뒤 최종 위키 링크를 반환한다. UI에 job polling 구조를 추가하지 않는다. 제한 시간이나 취소가 있더라도 원격 생성이 취소됐다고 가정하지 않는다.

### RP

CompanyRPGenerationAdapter.generate에서 roles 배열 전체와 prdURL을 회사 입력으로 변환한다. role별 내부 단계가 필요하면 이 implementation에서 처리하고 최종 위키 링크 하나를 반환한다. 모든 선택 role이 반영된 생성 결과가 확인되기 전 성공으로 반환하지 않는다.

role 선택지 추가는 RoleOptions.json 데이터 변경으로 처리한다. 생성 interface나 chip 로직을 수정하지 않는다. 회사에서 모르는 role이면 invalidInput 또는 회사 실패를 사용자 메시지로 변환한다. role 목록을 자동으로 원격 조회하는 기능은 현재 요청 범위에 없다.

## 오류 변환과 재시도

| 회사에서 관찰한 상황 | 앱에 반환 |
| --- | --- |
| 인증·권한 실패 | authentication / permission + 확인된 effect |
| 날짜 필드/위키 설정 누락 | configuration + notApplied, 요청 전 검사 가능할 때 |
| 허용되지 않는 Jira 전환 | unsupportedTransition + notApplied |
| 요청 전 연결 실패 | connection + notApplied |
| 요청 후 응답 유실·확인 불가 | timeout 또는 connection + unknown |
| 성공 응답이나 위키 URL 해석 실패 | invalidResponse + unknown |
| 서버가 거절하고 변경 없음이 확인됨 | remoteFailure 또는 rateLimited + notApplied |

전송 단계와 원격 확인 결과를 기준으로 effect를 정한다. status code만으로 미반영을 단정하지 않는다. SRD/RP도 생성 부작용이 있으므로 응답 유실 시 자동 재생성하지 않는다. 회사가 제공하는 요청 ID/중복 방지/결과 조회 기능이 있으면 adapter 내부에서 활용한다. 지원이 없으면 결과 불명을 그대로 돌려준다.

## 현재 웹 시안에서 찾는 위치

`docs/design/dayline-wireframe.html`에 다음 검색 표식을 주석으로 남긴다. 줄 번호 대신 함수·표식을 쓰면 이후 UI 편집으로 줄이 바뀌어도 찾을 수 있다.

| 검색 표식 | 현재 함수/데이터 | 현재 역할 | 네이티브 코드 대응 위치 |
| --- | --- | --- | --- |
| INTEGRATION-SEAM: JIRA | reflectTask | 700ms 후 모의 결과·화면 갱신 | AppModel.run → JiraTicketModule.execute |
| INTEGRATION-SEAM: WIKI | mockWikiApi | SRD/RP 공통 10초 대기·예시 URL | 각 mock generate와 각 Company adapter |
| INTEGRATION-CALL: WIKI | generateWiki의 await | 폼 입력을 mock에 넘기고 링크 표시 | CreationForm.generate → srd.generate / rp.generate |
| INTEGRATION-CONFIG: ROLES | roleOptions | 초기 후보 데이터 | RoleOptions.json 주입 |

현재 mockWikiApi의 payload는 시안 내부 값이다. 사내 요청으로 그대로 POST하지 않는다. 네이티브에서는 SRDRequest 또는 RPRequest로 변환한다. 특히 시안의 `prd` 문자열은 RP에서는 검증된 `prdURL`, SRD에서는 그대로 `prd`에 대응한다. `parent`는 parentPageLink, `roles`는 선택 ID 배열이다. `query`, `active`, `role-query`는 UI 전용이라 전달하지 않는다.

현재 reflectTask는 작업 객체 전체를 직접 갱신하는 시안 함수다. 이를 그대로 Company adapter의 interface로 사용하지 않는다. 네이티브 호출에는 고정된 ticketKey·mutation·requestID만 전달하고 반환 결과를 호출자가 저장·표시한다.

## 사내 연결 전에 확보할 정보

- Jira: 실제 host/호출 방법, 인증 방식, 시작·종료 필드, 세 내부 상태의 대응·허용 전환, 코멘트 형식·반영 확인 방법.
- SRD: 생성 호출 방법, PRD 해석, 부모 링크→페이지 식별 방식, 제목/템플릿 처리, 최종 위키 링크 반환 방식.
- RP: role ID의 회사 대응, PRD URL 입력 형식, 여러 role 처리 방식, 최종 링크 반환 방식.
- 공통: 제한 시간·비동기 job 규격 여부, 중복 방지 또는 요청 결과 조회 지원 여부.

위 정보는 adapter 설정과 implementation을 채우기 위한 것이다. 토큰 자체를 이 문서에 기록하지 않는다. 실제 연결 후에는 계약과 검증 결과를 함께 갱신한다.
