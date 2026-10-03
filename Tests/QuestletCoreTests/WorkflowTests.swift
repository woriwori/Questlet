import Foundation
import QuestletCore

actor RecordingJira: JiraTicketModule {
    var calls: [JiraRequest] = []
    var failStatus = true
    func execute(_ request: JiraRequest) async -> Result<JiraReceipt, IntegrationFailure> {
        calls.append(request)
        if case .setStatus = request.mutation, failStatus {
            failStatus = false
            return .failure(IntegrationFailure(code: .connection, message: "테스트 실패"))
        }
        return .success(JiraReceipt(requestID: request.requestID, ticketKey: request.ticketKey, simulated: true))
    }
    func categories() -> [String] { calls.map { $0.mutation.category } }
}

@MainActor enum CoreChecks {
    static func idle(_ model: AppModel) async throws {
        for _ in 0..<2000 {
            if !model.snapshot.requests.contains(where: { $0.state == .pending || $0.state == .running }) { return }
            if model.snapshot.requests.contains(where: { $0.state == .failed || $0.state == .unknown }) { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        throw InputError("요청 실행 제한 시간 초과")
    }
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("questlet-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try Database(url: root.appendingPathComponent("state.sqlite"))
        var date = Dates.date("2026-10-03")!
        let jira = RecordingJira()
        let model = try AppModel(database: db, jira: jira, now: { date })
        assert(Dates.status(start: "2026-10-01", end: "2026-10-05", today: "2026-09-30") == .toDo)
        assert(Dates.status(start: "2026-10-01", end: "2026-10-05", today: "2026-10-05") == .inProgress)
        assert(Dates.status(start: "2026-10-01", end: "2026-10-05", today: "2026-10-06") == .closed)
        assert(Dates.status(start: "2026-10-03", end: "2026-10-03", today: "2026-10-03") == .inProgress)
        assert(Dates.date("2026-02-30") == nil)
        assert(Dates.day(ISO8601DateFormatter().date(from: "2026-10-02T15:00:00Z")!) == "2026-10-03")

        let id = try model.save(id: nil, title: " 캠페인 수정 ", ticket: "", start: "2026-10-01", end: "2026-10-05")
        do { _ = try model.save(id: nil, title: "캠페인 수정", ticket: "", start: "2026-10-01", end: "2026-10-05"); assertionFailure("제목 중복 허용") } catch {}
        do { _ = try model.save(id: nil, title: "기간 오류", ticket: "", start: "2026-10-05", end: "2026-10-01"); assertionFailure("잘못된 기간 허용") } catch {}
        try model.addComment(taskID: id, body: "원문  https://example.com/design\n메모")
        assert(model.list(status: .inProgress, query: "example.com").count == 1)
        let stored = try Database(url: db.url).load()
        assert(stored.tasks[0].comments[0].body == "원문  https://example.com/design\n메모")
        assert(stored.tasks[0].comments[0].links.count == 1)
        assert(Dates.timestamp(stored.tasks[0].comments[0].recordedAt) == "2026/10/03 00:00")

        _ = try model.save(id: id, title: "캠페인 수정", ticket: "cmgsl-13332", start: "2026-10-01", end: "2026-10-05")
        model.pump()
        try await idle(model)
        assert(model.work(id)?.ticket == "CMGSL-13332")
        assert(model.snapshot.requests.count == 1 && model.snapshot.requests[0].request.mutation.category == "status")
        assert(!model.busy(id))
        let failedID = model.snapshot.requests[0].id
        model.retry(id); try await idle(model)
        let categories = await jira.categories()
        assert(categories == ["dates", "status", "status"])
        assert(model.snapshot.requests.isEmpty)
        let sent = await jira.calls
        assert(sent[1].requestID == failedID && sent[2].requestID == failedID)
        try model.addComment(taskID: id, body: "연동 뒤 새 원문")
        try await idle(model)
        let afterComment = await jira.categories()
        assert(afterComment == ["dates", "status", "status", "comment"])

        date = Dates.date("2026-10-06")!; model.refresh(); try await idle(model)
        assert(model.work(id)?.status == .closed && model.list(status: .closed, query: "캠페인").count == 1)
        _ = try model.save(id: id, title: "캠페인 수정", ticket: "CMGSL-13332", start: "2026-10-01", end: "2026-10-07")
        try await idle(model); assert(model.work(id)?.status == .inProgress)
        let control = MockControl(); await control.set(.unknown)
        model.jira = MockJiraTicketAdapter(control: control, delay: 0)
        try model.addComment(taskID: id, body: "응답 유실 코멘트"); try await idle(model)
        assert(model.snapshot.requests.first?.state == .unknown)
        let copy = try AppModel(database: Database(url: db.url), jira: model.jira, now: { date }); copy.refresh(resuming: true)
        assert(copy.snapshot.requests.first?.state == .unknown)
        assert(copy.snapshot.requests.first?.id == model.snapshot.requests.first?.id)
        let unknownID = model.snapshot.requests[0].id
        await control.set(.success)
        model.resolveUnknown(unknownID, applied: false); try await idle(model)
        assert(model.snapshot.requests.isEmpty)
        await control.set(.unknown)
        try model.addComment(taskID: id, body: "직접 확인할 코멘트"); try await idle(model)
        model.resolveUnknown(model.snapshot.requests[0].id, applied: true)
        assert(model.snapshot.requests.isEmpty)
        try model.delete(id); assert(model.tasks.isEmpty && model.snapshot.requests.isEmpty)

        await control.set(.success)
        let srd = MockSRDGenerationAdapter(control: control, delay: 0)
        let rp = MockRPGenerationAdapter(control: control, delay: 0)
        let wiki = try await srd.generate(SRDRequest(prd: "문자열 기획", title: "제목", parentPageLink: "부모 문자열")).get()
        assert(wiki.simulated && wiki.wikiURL.absoluteString.contains("mock-srd"))
        let roles = ["a", "b", "c", "d", "e"]
        let rpResult = try await rp.generate(RPRequest(roles: roles, prdURL: URL(string: "https://example.com/prd")!)).get()
        assert(rpResult.simulated)
        if case .success = await rp.generate(RPRequest(roles: ["a", "a"], prdURL: URL(string: "https://example.com/prd")!)) { assertionFailure("role 중복 허용") }
        assert(model.tasks.isEmpty)
    }
}

#if QUESTLET_CHECKS
@main struct Runner {
    static func main() async throws { try await CoreChecks.run(); print("Questlet core checks passed") }
}
#else
import XCTest
final class WorkflowTests: XCTestCase {
    @MainActor func testWorkflow() async throws { try await CoreChecks.run() }
}
#endif
