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
    // Six fixed weeks keep the sheet from resizing while browsing months.
    public var days: [String?] {
        let offset = Dates.calendar.component(.weekday, from: month) - 1
        let count = Dates.calendar.range(of: .day, in: .month, for: month)!.count
        return (0..<42).map { cell in
            guard cell >= offset, cell < offset + count else { return nil }
            return Dates.day(Dates.calendar.date(byAdding: .day, value: cell - offset, to: month)!)
        }
    }
    public func moving(_ months: Int) -> Date {
        Dates.calendar.date(byAdding: .month, value: months, to: month)!
    }
    public static func tasks(on day: String, from tasks: [WorkItem]) -> [WorkItem] {
        tasks.filter { $0.start <= day && day <= $0.end }
            .sorted { TaskSortField.title.precedes($0, $1, ascending: true) }
    }
}
