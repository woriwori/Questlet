import Foundation

public enum MockScenario: String, CaseIterable, Sendable { case success = "성공", failure = "실패", unknown = "결과 불명" }
public actor MockControl {
    public var scenario: MockScenario = .success
    public init() {}
    public func set(_ value: MockScenario) { scenario = value }
    public func result() -> IntegrationFailure? {
        switch scenario {
        case .success: return nil
        case .failure: return IntegrationFailure(code: .connection, message: "모의 연결 실패. 설정을 성공으로 바꾸고 재시도하세요.")
        case .unknown: return IntegrationFailure(code: .timeout, message: "모의 응답 유실. 원격 반영 여부를 확인할 수 없습니다.", effect: .unknown)
        }
    }
}
public struct MockJiraTicketAdapter: JiraTicketModule {
    public let control: MockControl
    public let delay: UInt64
    public init(control: MockControl = MockControl(), delay: UInt64 = 700_000_000) { self.control = control; self.delay = delay }
    public func execute(_ request: JiraRequest) async -> Result<JiraReceipt, IntegrationFailure> {
        guard !request.ticketKey.isEmpty else { return .failure(IntegrationFailure(code: .invalidInput, message: "티켓이 없습니다.")) }
        do { try await Task.sleep(nanoseconds: delay) } catch { return .failure(IntegrationFailure(code: .cancelled, message: "모의 호출이 취소됐습니다.")) }
        if let error = await control.result() { return .failure(error) }
        return .success(JiraReceipt(requestID: request.requestID, ticketKey: request.ticketKey, simulated: true, remoteCommentID: request.mutation.isComment ? "mock-\(request.requestID)" : nil))
    }
}
private func mockWiki(id: UUID, kind: String, delay: UInt64, control: MockControl) async -> Result<WikiReceipt, IntegrationFailure> {
    do { try await Task.sleep(nanoseconds: delay) } catch { return .failure(IntegrationFailure(code: .cancelled, message: "모의 생성이 취소됐습니다.")) }
    if let failure = await control.result() { return .failure(failure) }
    return .success(WikiReceipt(requestID: id, wikiURL: URL(string: "https://example.com/wiki/mock-\(kind)-\(id.uuidString.lowercased())")!, simulated: true))
}
public struct MockSRDGenerationAdapter: SRDGenerationModule {
    public let control: MockControl; public let delay: UInt64
    public init(control: MockControl = MockControl(), delay: UInt64 = 10_000_000_000) { self.control = control; self.delay = delay }
    public func generate(_ request: SRDRequest) async -> Result<WikiReceipt, IntegrationFailure> {
        guard [request.prd, request.title, request.parentPageLink].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return .failure(IntegrationFailure(code: .invalidInput, message: "모든 SRD 입력을 채우세요.")) }
        return await mockWiki(id: request.requestID, kind: "srd", delay: delay, control: control)
    }
}
public struct MockRPGenerationAdapter: RPGenerationModule {
    public let control: MockControl; public let delay: UInt64
    public init(control: MockControl = MockControl(), delay: UInt64 = 10_000_000_000) { self.control = control; self.delay = delay }
    public func generate(_ request: RPRequest) async -> Result<WikiReceipt, IntegrationFailure> {
        guard !request.roles.isEmpty, Set(request.roles).count == request.roles.count, request.roles.allSatisfy({ !$0.isEmpty }), Validation.webURL(request.prdURL.absoluteString) != nil else { return .failure(IntegrationFailure(code: .invalidInput, message: "role과 PRD 링크를 확인하세요.")) }
        return await mockWiki(id: request.requestID, kind: "rp", delay: delay, control: control)
    }
}
