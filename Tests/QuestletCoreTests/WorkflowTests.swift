import Foundation
import QuestletCore
import Security

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
        let leapMonth = WorkCalendar(containing: Dates.date("2028-02-10")!)
        assert(leapMonth.days.count == 35 && leapMonth.days.compactMap { $0 }.count == 29)
        assert(leapMonth.days[2] == "2028-02-01" && leapMonth.days[30] == "2028-02-29")
        let december = WorkCalendar(containing: Dates.date("2026-12-31")!)
        assert(Dates.day(december.moving(1)) == "2027-01-01")
        assert(Dates.day(december.moving(-1)) == "2026-11-01")
        let spanning = WorkItem(title: "월 경계 작업", start: "2026-09-30", end: "2026-10-02", today: "2026-10-19")
        assert(spanning.status == .closed)
        for day in ["2026-09-30", "2026-10-01", "2026-10-02"] {
            assert(WorkCalendar.tasks(on: day, today: "2026-10-01", from: [spanning]).map(\.id) == [spanning.id])
        }
        for day in ["2026-09-29", "2026-10-03"] { assert(WorkCalendar.tasks(on: day, today: "2026-10-01", from: [spanning]).isEmpty) }
        assert(WorkCalendar(containing: Dates.date("2026-02-01")!).days.first! == "2026-02-01")
        assert(WorkCalendar.tasks(on: "2026-10-01", today: "2026-10-19", from: []).isEmpty)
        assert(WorkCalendar.tasks(on: "2026-10-01", today: "2026-10-19", from: [spanning]).isEmpty)
        assert(WorkCalendar(containing: Dates.date("2026-02-01")!).days.count == 28)
        assert(WorkCalendar(containing: Dates.date("2026-08-01")!).days.count == 42)
        let active = WorkItem(title: "진행 작업", start: "2026-10-15", end: "2026-10-23", today: "2026-10-19")
        var planned = WorkItem(title: "예정 작업", start: "2026-10-21", end: "2026-10-29", today: "2026-10-19")
        planned.status = .closed // Stored status can be stale; classify from dates and today.
        let overlapping = WorkCalendar.tasks(on: "2026-10-21", today: "2026-10-19", from: [active, planned, spanning])
        assert(Set(overlapping.map(\.id)) == Set([active.id, planned.id]))
        assert(WorkCalendar.tasks(on: "2026-10-24", today: "2026-10-19", from: [active, planned]).map(\.id) == [planned.id])
        assert(WorkCalendar.tasks(on: "2026-10-29", today: "2026-10-29", from: [planned]).count == 1)
        assert(WorkCalendar.tasks(on: "2026-10-29", today: "2026-10-30", from: [planned]).isEmpty)
        print("Calendar 4/5/6 weeks, leap year, month navigation, active/planned overlap and Closed exclusion passed")
        let sortDB = try Database(url: root.appendingPathComponent("sort.sqlite"))
        var sortData = Snapshot()
        sortData.tasks = [
            WorkItem(title: "Zulu", ticket: "CMG-10", start: "2026-10-01", end: "2026-10-09", today: "2026-10-04"),
            WorkItem(title: "alpha", ticket: "CMG-2", start: "2026-10-02", end: "2026-10-08", today: "2026-10-04"),
            WorkItem(title: "Delta", start: "2026-10-03", end: "2026-10-07", today: "2026-10-04"),
            WorkItem(title: "Bravo", start: "2026-10-03", end: "2026-10-07", today: "2026-10-04")
        ]
        try sortDB.save(sortData)
        let sortedModel = try AppModel(database: sortDB, jira: RecordingJira())
        let expected: [TaskSortField: [String]] = [
            .title: ["alpha", "Bravo", "Delta", "Zulu"],
            .start: ["Zulu", "alpha", "Bravo", "Delta"],
            .end: ["Bravo", "Delta", "alpha", "Zulu"],
            .ticket: ["Bravo", "Delta", "alpha", "Zulu"]
        ]
        for field in TaskSortField.allCases {
            assert(sortedModel.list(status: .inProgress, sort: field).map(\.title) == expected[field]!)
            assert(sortedModel.list(status: .inProgress, sort: field, ascending: false).map(\.title) == Array(expected[field]!.reversed()))
        }
        assert(sortedModel.list(status: .inProgress).map(\.title) == expected[.title]!)
        assert(sortedModel.list(status: .inProgress, query: "CMG", sort: .ticket).map(\.title) == ["alpha", "Zulu"])
        assert(sortedModel.list(status: .closed, sort: .ticket).isEmpty)
        let unchangedSortData = try sortDB.load()
        assert(unchangedSortData.tasks.map(\.id) == sortData.tasks.map(\.id))
        print("Sidebar sorting: all fields/directions, missing IDs, numeric IDs, search and default passed")
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
        try tokenVaultChecks()
        try bulkCleanupChecks(root: root)
    }
    static func tokenVaultChecks() throws {
        let service = "local.questlet.tests.\(UUID())"
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let vault = KeychainTokenVault(service: service)
        let initial = try vault.load(); assert(!initial.configured)
        do { try vault.update(jira: "test-jira", emux: ""); assertionFailure("첫 설정에서 emux 누락 허용") } catch {}
        let unchanged = try vault.load(); assert(!unchanged.configured)
        try vault.update(jira: " test-jira-first ", emux: "test-emux-first")
        let reloaded = KeychainTokenVault(service: service)
        let loaded = try reloaded.load(); assert(loaded.configured)
        try reloaded.update(jira: "test-jira-rotated", emux: "")
        let changed = try vault.load()
        assert(changed.jira == "test-jira-rotated" && changed.emux == "test-emux-first")
        try reloaded.update(jira: "", emux: "test-emux-rotated")
        let changedAgain = try vault.load()
        assert(changedAgain.jira == "test-jira-rotated" && changedAgain.emux == "test-emux-rotated")
        print("Keychain initial setup, reload and PAT rotation checks passed")
    }
    static func bulkCleanupChecks(root: URL) throws {
        let db = try Database(url: root.appendingPathComponent("bulk.sqlite"))
        var closed = WorkItem(title: "삭제 완료", ticket: "TEST-1", start: "2026-10-01", end: "2026-10-02", today: "2026-10-03")
        closed.comments = [Comment(body: "함께 삭제할 메모", recordedAt: Dates.date("2026-10-02")!)]
        var stale = WorkItem(title: "오늘 재계산", start: "2026-10-01", end: "2026-10-02", today: "2026-10-02")
        stale.status = .inProgress
        let active = WorkItem(title: "종료일 당일은 유지", start: "2026-10-01", end: "2026-10-03", today: "2026-10-03")
        let future = WorkItem(title: "예정 유지", start: "2026-10-04", end: "2026-10-05", today: "2026-10-03")
        var saved = Snapshot(); saved.tasks = [closed, stale, active, future]
        var running = PendingRequest(taskID: closed.id, request: JiraRequest(ticketKey: "TEST-1", mutation: .setStatus(.closed)), automatic: false)
        running.state = .running
        let pending = PendingRequest(taskID: closed.id, request: JiraRequest(ticketKey: "TEST-1", mutation: .setDates(startDate: closed.start, endDate: closed.end)), automatic: false)
        saved.requests = [running, pending]
        try db.save(saved)
        let model = try AppModel(database: db, jira: RecordingJira(), now: { Dates.date("2026-10-03")! })
        let removed = try model.deleteClosed()
        assert(removed == 2 && model.tasks.map { $0.id } == [active.id, future.id])
        assert(model.snapshot.requests.count == 1 && model.snapshot.requests[0].state == .running)
        let persisted = try Database(url: db.url).load()
        assert(persisted.tasks.flatMap { $0.comments }.isEmpty && persisted.tasks.count == 2)
        let again = try model.deleteClosed(); assert(again == 0)
        print("Bulk Closed cleanup, date boundary and persistence checks passed")
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
