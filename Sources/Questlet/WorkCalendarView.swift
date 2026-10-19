import SwiftUI
import QuestletCore

struct WorkCalendarSheet: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        WorkCalendarPanel(tasks: model.tasks, today: model.today, close: { dismiss() }) { task in
            session.choose(task); dismiss()
        }
    }
}

struct WorkCalendarPanel: View {
    let tasks: [WorkItem]
    let today: String
    let close: () -> Void
    let select: (WorkItem) -> Void
    @State private var month: Date
    private var calendar: WorkCalendar { WorkCalendar(containing: month) }
    init(tasks: [WorkItem], today: String, close: @escaping () -> Void, select: @escaping (WorkItem) -> Void) {
        self.tasks = tasks; self.today = today; self.close = close; self.select = select
        _month = State(initialValue: Dates.date(today)!)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(calendar.title).font(.system(size: 18, weight: .semibold))
                Spacer()
                HStack(spacing: 7) {
                    Button("오늘") { month = Dates.date(today)! }
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .frame(width: 42, height: 25).background(Palette.quiet, in: RoundedRectangle(cornerRadius: 5))
                        .buttonStyle(.plain).handCursor()
                    HStack(spacing: 0) {
                        IconButton(symbol: "chevron.left", label: "이전 달", size: 27, glyph: 13) { month = calendar.moving(-1) }
                        IconButton(symbol: "chevron.right", label: "다음 달", size: 27, glyph: 13) { month = calendar.moving(1) }
                        IconButton(symbol: "xmark", label: "캘린더 닫기", size: 27, glyph: 13, action: close).keyboardShortcut(.cancelAction)
                    }
                }
            }.frame(height: 28).padding(.bottom, 18)
            HStack(spacing: 0) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { day in
                    Text(day).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .padding(.leading, 6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(height: 14).padding(.bottom, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(Array(calendar.days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        CalendarDay(day: day, today: today, tasks: WorkCalendar.tasks(on: day, today: today, from: tasks), select: select)
                    } else { Color.clear.frame(height: 58).accessibilityHidden(true) }
                }
            }
        }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 36)
            .frame(width: 600).background(Palette.surface).foregroundStyle(Palette.ink)
    }
}

private struct CalendarDay: View {
    let day: String
    let today: String
    let tasks: [WorkItem]
    let select: (WorkItem) -> Void
    @State private var hovering = false
    @State private var showingTasks = false
    private func status(_ task: WorkItem) -> TaskStatus { Dates.status(start: task.start, end: task.end, today: today) }
    private var tooltip: String {
        (tasks.isEmpty ? ["작업 없음"] : tasks.map { "\(status($0).label): \($0.title)" }).joined(separator: "\n")
    }
    var body: some View {
        Button { if !tasks.isEmpty { showingTasks = true } } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(Int(day.suffix(2))!)).font(.system(size: 12, weight: day == today ? .semibold : .regular))
                    .foregroundStyle(day == today ? .white : Palette.ink)
                    .frame(width: 25, height: 24, alignment: day == today ? .center : .leading)
                    .background(day == today ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .padding(.leading, day == today ? 3 : 6).padding(.top, 5).padding(.bottom, 5)
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.status(.inProgress).opacity(0.14))
                        .frame(height: 7).opacity(tasks.contains { status($0) == .inProgress } ? 1 : 0)
                    RoundedRectangle(cornerRadius: 2).fill(Palette.status(.toDo).opacity(0.17))
                        .frame(height: 7).opacity(tasks.contains { status($0) == .toDo } ? 1 : 0)
                }.padding(.leading, 6).padding(.trailing, 10)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 58).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .background(hovering ? Palette.quiet : .clear, in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .topLeading) { Rectangle().fill(Palette.line).frame(height: 0.75).padding(.trailing, 4).allowsHitTesting(false) }
        .onHover { hovering = $0 }.handCursor().help(tooltip)
        .accessibilityLabel("\(Dates.display(day)), \(tooltip)")
        .accessibilityHint(tasks.isEmpty ? "작업 없음" : "작업 목록 열기")
        .popover(isPresented: $showingTasks) {
            CalendarTaskList(tasks: tasks, today: today) { task in
                showingTasks = false; select(task)
            }
        }
    }
}

struct CalendarTaskList: View {
    let tasks: [WorkItem]
    let today: String
    let select: (WorkItem) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(tasks) { task in
                    let status = Dates.status(start: task.start, end: task.end, today: today)
                    Button { select(task) } label: {
                        HStack(alignment: .top, spacing: 9) {
                            RoundedRectangle(cornerRadius: 1).fill(Palette.status(status).opacity(0.7))
                                .frame(width: 2, height: task.ticket.isEmpty ? 16 : 28).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                if !task.ticket.isEmpty { Text(task.ticket).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).handCursor()
                    .accessibilityLabel("\(status.label), \(task.title)\(task.ticket.isEmpty ? "" : ", \(task.ticket)")")
                }
            }
        }.frame(height: min(240, max(0, CGFloat(tasks.reduce(0) { $0 + ($1.ticket.isEmpty ? 28 : 44) }) - 4)))
            .padding(8).frame(width: 280).background(Palette.surface).foregroundStyle(Palette.ink)
    }
}
