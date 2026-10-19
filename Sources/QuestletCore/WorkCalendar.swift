import Foundation

public struct WorkCalendar {
    public let month: Date
    public init(containing date: Date) {
        month = Dates.calendar.dateInterval(of: .month, for: date)!.start
    }
    public var title: String {
        let parts = Dates.calendar.dateComponents([.year, .month], from: month)
        return "\(parts.year!)년 \(parts.month!)월"
    }
    // Keep only the month's actual weeks so no empty final week adds bottom whitespace.
    public var days: [String?] {
        let offset = Dates.calendar.component(.weekday, from: month) - 1
        let count = Dates.calendar.range(of: .day, in: .month, for: month)!.count
        let cells = ((offset + count + 6) / 7) * 7
        return (0..<cells).map { cell in
            guard cell >= offset, cell < offset + count else { return nil }
            return Dates.day(Dates.calendar.date(byAdding: .day, value: cell - offset, to: month)!)
        }
    }
    public func moving(_ months: Int) -> Date {
        Dates.calendar.date(byAdding: .month, value: months, to: month)!
    }
    public static func tasks(on day: String, today: String, from tasks: [WorkItem]) -> [WorkItem] {
        tasks.filter { $0.start <= day && day <= $0.end && Dates.status(start: $0.start, end: $0.end, today: today) != .closed }
            .sorted { TaskSortField.title.precedes($0, $1, ascending: true) }
    }
}
