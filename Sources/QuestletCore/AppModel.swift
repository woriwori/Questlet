import Foundation
import Combine

@MainActor public final class AppModel: ObservableObject {
    @Published public private(set) var snapshot: Snapshot
    @Published public var error: String?
    public let database: Database
    public var jira: any JiraTicketModule
    private var activeTickets = Set<String>()
    private let now: () -> Date
    public init(database: Database, jira: any JiraTicketModule, now: @escaping () -> Date = Date.init) throws {
        self.database = database; self.jira = jira; self.now = now
        snapshot = try database.load()
    }
    public var today: String { Dates.day(now()) }
    public var tasks: [WorkItem] { snapshot.tasks }
    public func work(_ id: UUID?) -> WorkItem? { snapshot.tasks.first { $0.id == id } }
    public func list(status: TaskStatus, query: String = "") -> [WorkItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tasks.filter { task in
            task.status == status && (needle.isEmpty || ([task.title, task.ticket] + task.comments.map { $0.body }).joined(separator: " ").lowercased().contains(needle))
        }.sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
    }
    public func requests(for task: WorkItem) -> [PendingRequest] { snapshot.requests.filter { $0.taskID == task.id && $0.request.ticketKey == task.ticket } }
    public func busy(_ id: UUID) -> Bool {
        guard let task = work(id) else { return false }
        let entries = requests(for: task)
        if entries.contains(where: { $0.state == .running }) { return true }
        if let first = snapshot.requests.first(where: { $0.request.ticketKey == task.ticket }), first.state == .failed || first.state == .unknown { return false }
        return entries.contains { $0.state == .pending }
    }
    private func commit(_ value: Snapshot) throws { try database.save(value); snapshot = value }
    private func append(_ mutation: JiraMutation, task: WorkItem, automatic: Bool, to next: inout Snapshot) {
        guard !task.ticket.isEmpty else { return }
        if !mutation.isComment {
            next.requests.removeAll { $0.taskID == task.id && $0.request.ticketKey == task.ticket && $0.state != .running && $0.state != .unknown && $0.request.mutation.category == mutation.category }
        }
        next.requests.append(PendingRequest(taskID: task.id, request: JiraRequest(ticketKey: task.ticket, mutation: mutation), automatic: automatic))
    }
    @discardableResult public func save(id: UUID?, title: String, ticket: String, start: String, end: String) throws -> UUID {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ticket = ticket.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        try Validation.task(title: title, ticket: ticket, start: start, end: end, excluding: id, tasks: tasks)
        if let id, work(id) == nil { throw InputError("삭제된 작업은 수정할 수 없습니다.") }
        if let id, busy(id) { throw InputError("Jira 반영 중입니다. 잠시 기다려주세요.") }
        let old = work(id)
        var task = old ?? WorkItem(title: title, ticket: ticket, start: start, end: end, today: today)
        task.title = title; task.ticket = ticket; task.start = start; task.end = end
        task.status = Dates.status(start: start, end: end, today: today)
        var next = snapshot
        if old?.ticket != ticket {
            next.requests.removeAll { $0.taskID == task.id && $0.state != .running }
        }
        let datesChanged = old == nil || old?.ticket != ticket || old?.start != start || old?.end != end
        if datesChanged { append(.setDates(startDate: start, endDate: end), task: task, automatic: false, to: &next) }
        if datesChanged || old?.status != task.status { append(.setStatus(task.status), task: task, automatic: false, to: &next) }
        task.feedback = ticket.isEmpty ? "로컬에 저장했습니다." : next.requests.contains(where: { $0.taskID == task.id && $0.request.ticketKey == ticket }) ? "로컬에 저장했습니다. Jira 반영 대기 중…" : old?.feedback ?? "로컬에 저장했습니다."
        if let index = next.tasks.firstIndex(where: { $0.id == task.id }) { next.tasks[index] = task } else { next.tasks.append(task) }
        try commit(next); pump(); return task.id
    }
    public func addComment(taskID: UUID, body: String) throws {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InputError("메모를 입력하세요.") }
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { throw InputError("작업이 없습니다.") }
        guard !busy(taskID) else { throw InputError("Jira 반영 중입니다.") }
        let comment = Comment(body: body, recordedAt: now())
        var next = snapshot; next.tasks[index].comments.append(comment)
        let task = next.tasks[index]
        append(.appendComment(localCommentID: comment.id, body: body), task: task, automatic: false, to: &next)
        next.tasks[index].feedback = task.ticket.isEmpty ? "로컬에 저장했습니다." : "로컬에 저장했습니다. Jira 반영 대기 중…"
        try commit(next); pump()
    }
    public func delete(_ id: UUID) throws {
        var next = snapshot
        next.tasks.removeAll { $0.id == id }
        // 전송 중 요청은 결과를 정리할 때까지 유지한다. 늦은 응답은 작업을 생성하지 않는다.
        next.requests.removeAll { $0.taskID == id && $0.state != .running }
        try commit(next)
    }
    public func refresh(resuming: Bool = false) {
        do {
            var next = snapshot
            if resuming {
                for i in next.requests.indices {
                    if next.requests[i].state == .running && !activeTickets.contains(next.requests[i].request.ticketKey) {
                        if next.requests[i].request.mutation.isComment {
                            next.requests[i].state = .unknown
                            next.requests[i].failure = IntegrationFailure(code: .connection, message: "앱 종료 중 코멘트 반영 결과가 유실됐습니다. Jira에서 확인하세요.", effect: .unknown)
                        } else { next.requests[i].state = .pending }
                    }
                    if next.requests[i].automatic && next.requests[i].state == .failed && [.connection, .rateLimited].contains(next.requests[i].failure?.code) {
                        next.requests[i].state = .pending
                    }
                }
                next.requests.removeAll { entry in !next.tasks.contains(where: { $0.id == entry.taskID }) }
            }
            for i in next.tasks.indices {
                let calculated = Dates.status(start: next.tasks[i].start, end: next.tasks[i].end, today: today)
                if calculated != next.tasks[i].status {
                    next.tasks[i].status = calculated
                    let task = next.tasks[i]
                    append(.setStatus(calculated), task: task, automatic: true, to: &next)
                }
            }
            try commit(next); pump()
        } catch { self.error = error.localizedDescription }
    }
    public func retry(_ taskID: UUID) {
        do {
            var next = snapshot
            for i in next.requests.indices where next.requests[i].taskID == taskID && next.requests[i].state == .failed {
                next.requests[i].state = .pending
            }
            try commit(next); pump()
        } catch { self.error = error.localizedDescription }
    }
    public func resolveUnknown(_ requestID: UUID, applied: Bool) {
        do {
            var next = snapshot
            guard let index = next.requests.firstIndex(where: { $0.id == requestID && $0.state == .unknown }) else { return }
            let taskID = next.requests[index].taskID
            if let taskIndex = next.tasks.firstIndex(where: { $0.id == taskID }) { next.tasks[taskIndex].feedback = applied ? "사용자가 Jira 반영을 확인했습니다." : "미반영을 확인했습니다. Jira 재전송 대기 중…" }
            if applied { next.requests.remove(at: index) }
            else { next.requests[index].state = .pending; next.requests[index].failure = nil }
            try commit(next); pump()
        } catch { self.error = error.localizedDescription }
    }
    public func pump() {
        for ticket in Set(snapshot.requests.map { $0.request.ticketKey }) where !activeTickets.contains(ticket) {
            guard let first = snapshot.requests.first(where: { $0.request.ticketKey == ticket }), first.state == .pending else { continue }
            activeTickets.insert(ticket)
            Task { await run(ticket) }
        }
    }
    private func run(_ ticket: String) async {
        defer { activeTickets.remove(ticket) }
        while let entry = snapshot.requests.first(where: { $0.request.ticketKey == ticket }), entry.state == .pending {
            do {
                var started = snapshot
                guard let index = started.requests.firstIndex(where: { $0.id == entry.id }) else { return }
                started.requests[index].state = .running
                try commit(started)
                if let wait = entry.failure?.retryAfterSeconds, wait > 0 { try await Task.sleep(nanoseconds: UInt64(min(wait, 3600)) * 1_000_000_000) }
                let result = await jira.execute(entry.request)
                var finished = snapshot
                guard let requestIndex = finished.requests.firstIndex(where: { $0.id == entry.id }) else { continue }
                let taskIndex = finished.tasks.firstIndex(where: { $0.id == entry.taskID })
                if taskIndex == nil || finished.tasks[taskIndex!].ticket != ticket {
                    finished.requests.remove(at: requestIndex)
                } else {
                    switch result {
                    case .success(let receipt):
                        guard receipt.requestID == entry.id, receipt.ticketKey == ticket else {
                            finished.requests[requestIndex].state = .unknown
                            finished.requests[requestIndex].failure = IntegrationFailure(code: .invalidResponse, message: "Jira 응답의 요청 정보가 일치하지 않습니다.", effect: .unknown)
                            try commit(finished); return
                        }
                        finished.requests.remove(at: requestIndex)
                        finished.tasks[taskIndex!].feedback = receipt.simulated ? "로컬에 저장했습니다. 모의 Jira 반영 완료." : "로컬에 저장했습니다. Jira 반영 완료."
                    case .failure(let failure):
                        finished.requests[requestIndex].state = failure.effect == .unknown ? .unknown : .failed
                        finished.requests[requestIndex].failure = failure
                        finished.tasks[taskIndex!].feedback = failure.effect == .unknown ? "로컬에 저장했습니다. Jira 반영 결과 불명." : "로컬에 저장했습니다. Jira 반영 실패."
                    }
                }
                try commit(finished)
            } catch { self.error = error.localizedDescription; return }
        }
    }
}
