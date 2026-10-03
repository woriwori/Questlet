import Foundation
import QuestletCore

// INTEGRATION-ASSEMBLY: 사내 구현 후 아래 세 adapter만 교체한다. UI/DB는 바꾸지 않는다.
struct IntegrationAssembly {
    let control = MockControl()
    let tokenVault: any TokenVault
    init(tokenVault: any TokenVault = KeychainTokenVault()) { self.tokenVault = tokenVault }
    var jira: any JiraTicketModule { MockJiraTicketAdapter(control: control) }
    var srd: any SRDGenerationModule { MockSRDGenerationAdapter(control: control) }
    var rp: any RPGenerationModule { MockRPGenerationAdapter(control: control) }
    // 예: var jira: any JiraTicketModule { CompanyJiraTicketAdapter(/* 회사 설정, tokenVault 주입 */) }
    var roles: [String] {
        guard let url = Bundle.module.url(forResource: "RoleOptions", withExtension: "json"),
              let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Array(NSOrderedSet(array: values)) as? [String] ?? []
    }
}
