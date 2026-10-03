import Foundation
import QuestletCore

// INTEGRATION-SEAM: 사내 호출 implementation은 여기 세 메서드에 넣는다.
// docs/INTEGRATION-INTERFACES.md의 입력/출력/unknown 계약을 유지한다.
// 인증/host/필드 설정은 생성자에 주입한다. 운영 토큰은 소스나 일반 DB에 넣지 않는다.
struct CompanyJiraTicketAdapter: JiraTicketModule {
    func execute(_ request: JiraRequest) async -> Result<JiraReceipt, IntegrationFailure> {
        // TODO(company): mutation switch -> 날짜 필드 / transition / 원문 코멘트 호출.
        // 응답 유실 시 반영 여부 확인; 확인 불가하면 unknown. requestID만으로 중복 방지를 가정하지 말 것.
        .failure(IntegrationFailure(code: .configuration, message: "사내 Jira implementation이 아직 연결되지 않았습니다."))
    }
}
struct CompanySRDGenerationAdapter: SRDGenerationModule {
    func generate(_ request: SRDRequest) async -> Result<WikiReceipt, IntegrationFailure> {
        // TODO(company): prd/title/parentPageLink -> 회사 생성 입력, 완료된 wikiURL 반환.
        .failure(IntegrationFailure(code: .configuration, message: "사내 SRD implementation이 아직 연결되지 않았습니다."))
    }
}
struct CompanyRPGenerationAdapter: RPGenerationModule {
    func generate(_ request: RPRequest) async -> Result<WikiReceipt, IntegrationFailure> {
        // TODO(company): roles 전체와 prdURL -> 회사 생성 입력, 완료된 wikiURL 하나 반환.
        .failure(IntegrationFailure(code: .configuration, message: "사내 RP implementation이 아직 연결되지 않았습니다."))
    }
}
