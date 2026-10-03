import Foundation

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case inProgress = "InProgress", toDo = "ToDo", closed = "Closed"
    public var label: String { switch self { case .inProgress: "진행 중"; case .toDo: "예정"; case .closed: "완료" } }
}

public enum Dates {
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }
    public static func day(_ date: Date = Date()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let d = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), self.day(d) == day else { return nil }
        return d
    }
    public static func display(_ day: String) -> String { day.replacingOccurrences(of: "-", with: "/") }
    public static func timestamp(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy/MM/dd HH:mm"; return f.string(from: date)
    }
    public static func status(start: String, end: String, today: String) -> TaskStatus {
        today < start ? .toDo : today > end ? .closed : .inProgress
    }
}

public struct Comment: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let body: String
    public let recordedAt: Date
    public let links: [URL]
    public init(body: String, recordedAt: Date = Date()) {
        self.body = body; self.recordedAt = recordedAt
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        self.links = detector?.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap { $0.url }.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") } ?? []
    }
}

public struct WorkItem: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var title: String
    public var ticket: String
    public var start: String
    public var end: String
    public var status: TaskStatus
    public var comments: [Comment] = []
    public var feedback: String = "로컬에 저장했습니다."
    public init(title: String, ticket: String = "", start: String, end: String, today: String = Dates.day()) {
        self.title = title; self.ticket = ticket; self.start = start; self.end = end
        self.status = Dates.status(start: start, end: end, today: today)
    }
}

public enum RequestState: String, Codable, Sendable { case pending, running, failed, unknown }
public struct PendingRequest: Identifiable, Codable, Sendable {
    public var id: UUID { request.requestID }
    public let taskID: UUID
    public var request: JiraRequest
    public var state: RequestState = .pending
    public var automatic: Bool
    public var failure: IntegrationFailure?
    public init(taskID: UUID, request: JiraRequest, automatic: Bool) {
        self.taskID = taskID; self.request = request; self.automatic = automatic
    }
}

public struct Snapshot: Codable, Sendable {
    public var version = 1
    public var tasks: [WorkItem] = []
    public var requests: [PendingRequest] = []
    public init() {}
}

public struct InputError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public enum Validation {
    public static func task(title: String, ticket: String, start: String, end: String, excluding: UUID?, tasks: [WorkItem]) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw InputError("제목을 입력하세요.") }
        guard Dates.date(start) != nil, Dates.date(end) != nil, start <= end else { throw InputError("유효한 시작일과 종료일을 선택하세요.") }
        let others = tasks.filter { $0.id != excluding }
        if others.contains(where: { $0.title.lowercased() == title.lowercased() }) { throw InputError("동일한 제목의 작업이 있습니다.") }
        if !ticket.isEmpty, let existing = others.first(where: { $0.ticket == ticket }) { throw InputError("이미 등록된 티켓입니다: \(existing.title) (\(Dates.display(existing.start)) — \(Dates.display(existing.end)))") }
    }
    public static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
