# 사내 연동 인터페이스

작성일: 2026-10-03. 기준: SPEC.md. `codebase-design`의 module·interface·seam·adapter 원칙으로 정리했다.

이 문서는 **앱이 호출하는 인터페이스**다. 사내 HTTP endpoint나 회사 서버의 요청 JSON을 정의하는 문서는 아니다. 회사 규격은 adapter에서 이 입력·출력으로 변환한다. 네이티브 계약은 Sources/QuestletCore/IntegrationInterfaces.swift에 구현되어 있다. 앱은 이 protocol을 통해 mock을 호출한다. 교체 위치와 구현 순서는 [연동 가이드](INTEGRATION-GUIDE.md)에 있다.

## 세 module의 역할

| Module | 앱의 입력 | 앱이 받는 출력 | 호출하는 곳 |
| --- | --- | --- | --- |
| JiraTicketModule | 기존 티켓 키 + 날짜 설정 / 상태 설정 / 원문 코멘트 추가 요청 | 요청별 반영 확인 또는 실패·결과 불명 | 로컬 저장 후 미처리 요청 실행, 자동 상태 갱신, 재시도 |
| SRDGenerationModule | PRD 문자열 + 제목 + 상위 페이지 링크 문자열 | 생성된 위키 URL 또는 실패·결과 불명 | SRD 생성 탭의 생성 버튼 |
| RPGenerationModule | 선택한 role ID 목록 + PRD URL | 생성된 위키 URL 또는 실패·결과 불명 | RP 생성 탭의 생성 버튼 |

각 module은 하나의 작은 interface를 제공한다. mock adapter와 사내 adapter가 같은 seam을 채운다. HTTP 호출, 인증, 회사 필드 ID, 상태 전환 조회, 문서 템플릿·부모 페이지 해석은 사내 implementation에 모은다. UI가 회사의 원시 응답을 파싱하거나 여러 HTTP 단계를 직접 조합하지 않는다.

세 module을 하나의 `execute(kind, [String: Any])`로 합치지 않는다. 입력이 서로 다르므로 타입으로 구분하면 Jira 변경 요청이 위키 생성에 잘못 전달되는 일을 막을 수 있다. 각 module의 외부 interface는 한 메서드면 충분하다.

## 공통 계약

- 비동기로 실행한다. UI 스레드를 막지 않는다. 결과는 호출자에게 반환하고 adapter가 UI나 로컬 DB를 직접 수정하지 않는다. 외부 시스템을 변경하는 동작 자체는 module의 의도된 효과다.
- `requestID`는 앱이 만드는 UUID 문자열이다. 동일한 미처리 요청을 재시도할 때 유지한다. 새 요청이나 변경된 입력에는 새 ID를 사용한다. 서버가 이 ID를 이해한다고 가정하지 않는다.
- 성공 결과의 `simulated`를 반드시 확인한다. mock은 true, 실제 반영이 확인된 사내 adapter는 false다. UI는 mock 결과를 실제 생성·반영 완료로 표시하지 않는다.
- 실제 endpoint, 인증 정보, 제한 시간은 adapter의 설정·주입된 자격 정보로 받는다. 토큰은 요청 데이터에 넣지 않는다. Jira 토큰은 Keychain을 기본으로 하며 소스·일반 DB·로그에 기록하지 않는다.
- 취소나 제한 시간 초과는 원격 동작의 취소를 보장하지 않는다. 외부 효과가 불명확하면 `unknown`으로 반환한다. timeout을 무조건 미반영 실패로 바꾸지 않는다.
- HTTP 상태 코드와 원시 응답은 implementation 내부에서 해석한다. 호출자에게는 아래 정규화된 실패를 반환한다. 사용자 메시지에는 토큰이나 원시 응답 전체를 넣지 않는다.

```swift
import Foundation

enum IntegrationErrorCode: String, Sendable {
    case invalidInput, authentication, permission, notFound
    case unsupportedTransition, configuration, connection
    case rateLimited, timeout, cancelled, invalidResponse, remoteFailure
}

enum RemoteEffect: String, Sendable {
    case notApplied // 원격에 미반영임을 확인함
    case unknown    // 반영됐을 수 있으나 확인하지 못함
}

struct IntegrationFailure: Error, Sendable {
    let code: IntegrationErrorCode
    let message: String
    let effect: RemoteEffect
    let retryAfterSeconds: Int? // 서버가 알려준 경우만 사용
}
```

`effect`와 `code`는 독립적이다. 연결 실패도 요청 전 실패면 notApplied, 전송 후 응답 유실이면 unknown이다. 인증·설정·입력 오류는 원인을 고친 뒤 재시도한다. 일시적 실패라도 unknown이면 자동으로 재전송하지 않는다. 동일 ID만으로 중복 방지가 보장되지는 않는다.

## JiraTicketModule

**Jira 티켓을 새로 만드는 기능은 아니다.** 이미 존재하는 티켓의 날짜·상태·원문 코멘트만 변경한다. Jira 제목 변경, 티켓 삭제, 로컬로 전체 가져오기는 제공하지 않는다. 성공 여부 확인을 위한 제한된 원격 조회는 adapter 내부에서 가능하지만 이를 양방향 동기화로 확대하지 않는다.

### 입력과 출력

```swift
enum TaskStatus: String, Codable, Sendable {
    case toDo = "ToDo"
    case inProgress = "InProgress"
    case closed = "Closed"
}

enum JiraMutation: Codable, Sendable {
    case setDates(startDate: String, endDate: String)
    case setStatus(TaskStatus)
    case appendComment(localCommentID: UUID, body: String)
}

struct JiraRequest: Codable, Sendable {
    let requestID: UUID
    let ticketKey: String
    let mutation: JiraMutation
}

struct JiraReceipt: Sendable {
    let requestID: UUID
    let ticketKey: String
    let simulated: Bool
    let remoteCommentID: String? // 코멘트 응답에 ID가 있는 경우
}

protocol JiraTicketModule: Sendable {
    func execute(_ request: JiraRequest) async
        -> Result<JiraReceipt, IntegrationFailure>
}
```

| 필드 | 규칙 |
| --- | --- |
| ticketKey | 필수. 주변 공백 제거·대문자 정규화. 예: CMGSL-13332. 티켓이 없으면 이 interface를 호출하지 않음 |
| setDates.startDate / endDate | 한국 시간의 달력 날짜를 ISO `yyyy-MM-dd` 문자열로 전달. 유효한 날짜이며 start ≤ end. 하루 작업 허용. 표시 형식 yyyy/MM/dd와 구분 |
| setStatus | 앱이 날짜로 계산한 내부 상태. 회사 status/transition ID를 보내지 않음 |
| appendComment.localCommentID | 로컬 코멘트의 안정적인 식별자. 재시도해도 바꾸지 않음 |
| appendComment.body | 비어 있지 않은 원문. 링크 포함 그대로 전달. 요약이나 기록 시각 접두사를 추가하지 않음 |
| requestID | 미처리 요청 식별자. 날짜 요청과 상태 요청은 서로 다른 ID |

성공은 요청한 **한 변경**이 확인됐다는 뜻이다. 상태가 이미 목표 상태면 성공으로 반환한다. 회사 status 조회·필드 매핑·필요한 전환 수행은 adapter가 책임진다. 허용되지 않는 전환은 unsupportedTransition이다. 원격 코멘트 ID가 없는 회사 규격에서도 성공 확인은 가능하므로 remoteCommentID는 선택적이다.

날짜의 시작·종료 필드는 가능하면 한 번의 회사 요청으로 변경한다. 회사 규격상 두 번 호출해야 한다면 일부 성공 후 나머지가 실패할 수 있다. adapter는 원격 값을 확인해 미완료 부분만 처리하고, 한 쌍의 날짜가 모두 확인되기 전에는 성공을 반환하지 않는다. 확인할 수 없는 부분 성공은 unknown이다.

### 호출 흐름과 순서

1. 앱이 폼을 검증하고 상태를 계산한다.
2. 로컬 작업 변경과 미처리 Jira 요청을 하나의 로컬 저장 단위로 확정한다.
3. 유효한 등록·수정 폼을 닫고 상세에서 처리 중을 표시한다.
4. 티켓별로 한 번에 하나의 요청을 실행한다. 일정 반영은 setDates 다음 setStatus 순서다. 각 결과를 독립적으로 기록한다.
5. 모든 필요한 요청이 성공해야 전체 Jira 반영 완료다. 날짜만 성공하면 날짜 요청을 재실행하지 않고 상태 요청만 재시도한다.

| 트리거 | 생성할 요청 |
| --- | --- |
| 티켓이 있는 새 작업 등록 | setDates + setStatus |
| 기간 수정 | setDates + 필요한 setStatus |
| 날짜 경과·실행·잠자기 복귀로 상태 변경 | setStatus |
| 코멘트 추가 | appendComment 한 건. 기존 코멘트를 다시 묶어 보내지 않음 |
| 제목만 수정 | Jira 요청 없음 |
| 티켓 추가·변경 | 새 티켓에 현재 날짜·상태 반영. 과거 코멘트 복제 없음 |
| 티켓 제거·로컬 삭제 | 미전송 요청 취소. Jira 삭제 요청 없음 |
| 사용자 재시도 | 실패한 미처리 요청만, 동일 requestID로 실행 |

티켓별 순서·미처리 요청 병합·삭제·재실행 복구는 앱의 저장/실행 흐름이 책임진다. 아직 전송하지 않은 날짜·상태 변경만 최신 값으로 합친다. 코멘트는 각각 유지한다. 시작된 요청의 ticketKey와 입력은 고정한다. 응답으로 현재 작업을 다시 생성하거나 사용자가 바꾼 티켓 연결을 덮어쓰지 않는다.

코멘트 요청을 재시도할 때 adapter는 기존 반영 여부를 확인하거나 회사가 지원하는 중복 방지 수단을 사용해야 한다. 대응 수단이 없고 이전 결과가 unknown이면 자동 추가를 중단한다. 이 확인은 같은 execute 안에서 처리해 호출자에게 별도 조회 메서드를 요구하지 않는다.

### 데이터 예시

아래는 사람이 이해하기 위한 중립 표현이다. Swift Codable의 자동 출력이나 사내 HTTP body 형식을 지정하지 않는다.

```json
{
  "requestID": "11111111-1111-4111-8111-111111111111",
  "ticketKey": "CMGSL-13332",
  "mutation": {
    "kind": "setDates",
    "startDate": "2026-10-01",
    "endDate": "2026-10-07"
  }
}
```

상태 요청은 별도 requestID와 `{ "kind": "setStatus", "status": "InProgress" }`를 사용한다. 코멘트 요청은 `{ "kind": "appendComment", "localCommentID": "…", "body": "디자이너가 UX 전달. https://…" }`를 사용한다.

## SRDGenerationModule

```swift
struct SRDRequest: Sendable {
    let requestID: UUID
    let prd: String
    let title: String
    let parentPageLink: String
}

struct WikiReceipt: Sendable {
    let requestID: UUID
    let wikiURL: URL
    let simulated: Bool
}

protocol SRDGenerationModule: Sendable {
    func generate(_ request: SRDRequest) async
        -> Result<WikiReceipt, IntegrationFailure>
}
```

세 필드 모두 주변 공백 제거 후 필수 문자열이다. `prd`는 URL로 제한하지 않는다. `parentPageLink`도 앱 interface에서는 문자열이며 회사 규격에 필요한 페이지 ID 변환·검증은 adapter에서 한다. 앱에서 문서 본문이나 템플릿 ID를 추가로 요구하지 않는다.

사용자가 SRD 탭에서 생성하면 입력을 고정해 한 번 호출한다. 폼은 계속 열어 두고 생성 중 표시·중복 제출 방지를 제공한다. 성공하면 같은 폼에 wikiURL을 표시하고 사용자가 닫는다. 결과를 작업이나 로컬 DB에 저장하지 않는다.

```json
{
  "requestID": "22222222-2222-4222-8222-222222222222",
  "prd": "기획서 내용 또는 링크",
  "title": "캠페인 수정 SRD",
  "parentPageLink": "https://example.com/wiki/parent"
}
```

## RPGenerationModule

```swift
struct RPRequest: Sendable {
    let requestID: UUID
    let roles: [String]
    let prdURL: URL
}

protocol RPGenerationModule: Sendable {
    func generate(_ request: RPRequest) async
        -> Result<WikiReceipt, IntegrationFailure>
}
```

- roles는 선택된 role ID 배열이다. 최소 한 개이며 중복 없이 선택 순서를 유지한다. 초기 ID는 cmg_self_service, cmg_reco_valley, cmg_bada, cmg_wing_card다.
- role 목록은 확장 가능한 설정 데이터다. enum 네 case나 `count ≤ 4` 규칙으로 구현하지 않는다. 후보 검색·chip·3.5행 스크롤은 UI의 역할이고 생성 요청에는 검색어나 후보 목록을 보내지 않는다. 임의 role 입력은 허용하지 않는다.
- prdURL은 http/https 절대 URL이며 host가 있어야 한다. 표시용 문자열을 그대로 dictionary에 넣기보다 폼 문자열을 검증해 URL로 변환한다.
- 한 번 선택한 role 배열 전체를 한 번의 generate 호출로 전달한다. role마다 앱이 따로 요청하지 않는다. 출력은 사용자 요청대로 위키 링크 하나다. 사내 구현이 내부적으로 여러 단계를 수행하더라도 최종 확인된 링크를 반환한다.
- UI 대기·완료·저장하지 않는 정책은 SRD와 같다.

```json
{
  "requestID": "33333333-3333-4333-8333-333333333333",
  "roles": ["cmg_self_service", "cmg_reco_valley"],
  "prdURL": "https://example.com/prd/123"
}
```

## 위키 생성 결과와 오류

```json
{
  "requestID": "22222222-2222-4222-8222-222222222222",
  "wikiURL": "https://example.com/wiki/mock-srd-123",
  "simulated": true
}
```

wikiURL은 화면에서 열 수 있는 http/https 절대 URL이어야 한다. 성공 응답인데 링크가 없거나 형식이 잘못됐으면 invalidResponse다. 문서가 이미 생성됐을 수 있으므로 effect는 unknown으로 보고 자동으로 다시 생성하지 않는다. 응답의 회사 전용 필드 이름·문서 ID·경로는 adapter에서 URL로 변환한다.

확인된 미생성 실패는 입력을 유지하고 재시도를 제공한다. 요청 전송 후 결과 불명은 “생성 여부를 확인할 수 없습니다”로 표시하며 자동 재시도하지 않는다. 사내 adapter가 requestID로 기존 결과를 찾거나 중복 생성을 막을 수 있을 때만 같은 요청을 안전하게 다시 실행한다. 지원하지 않으면 사용자가 사내 위키에서 확인하도록 안내한다. 현재 첫 버전에는 생성 이력과 재실행 후 복구가 없다.

## Mock 계약과 확인할 행동

| Adapter | 기본 행동 | 성공 표시 |
| --- | --- | --- |
| MockJiraTicketAdapter | 네트워크 없이 짧은 비동기 대기. 요청별 성공 반환. 테스트에서는 실패·결과 불명·부분 성공을 주입할 수 있게 구현 | simulated=true |
| MockSRDGenerationAdapter | 입력 검증 후 약 10초 비동기 대기, 예시 위키 URL 하나 반환 | simulated=true |
| MockRPGenerationAdapter | role 배열·PRD URL 검증 후 약 10초 비동기 대기, 예시 위키 URL 하나 반환 | simulated=true |

현재 웹 시안의 Jira 지연은 700ms, 위키 생성 지연은 10초다. 네이티브 mock도 동일한 interface를 만족하게 구현한다. mock에 운영 URL·토큰이 필요해서는 안 된다. 실패는 숨은 무작위 확률 대신 검증 시나리오로 지정한다. 실제 10초 대기는 UI 확인에 쓰고 자동 검증에서는 제어 가능한 대기로 시간을 줄일 수 있다.

검증은 이 interface를 통해 입력 전달, 성공·실패·unknown 구분, simulated 표시, 원문 보존, 날짜/상태 별도 성공 기록, 중복 방지, SRD/RP URL 결과를 확인한다. 사내 HTTP 구조를 UI 테스트가 알아야 한다면 회사 implementation이 seam 밖으로 새어 나온 것이다.
