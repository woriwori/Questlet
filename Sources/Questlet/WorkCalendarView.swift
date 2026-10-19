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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(calendar.title).font(.system(size: 18, weight: .semibold))
                Spacer()
                Button("오늘") { month = Dates.date(today)! }.buttonStyle(.bordered).controlSize(.small).handCursor()
                IconButton(symbol: "chevron.left", label: "이전 달") { month = calendar.moving(-1) }
                IconButton(symbol: "chevron.right", label: "다음 달") { month = calendar.moving(1) }
                IconButton(symbol: "xmark", label: "캘린더 닫기", action: close).keyboardShortcut(.cancelAction)
            }
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { day in
                        Text(day).font(.system(size: 11)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
                    }
                }.padding(.bottom, 4)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(Array(calendar.days.enumerated()), id: \.offset) { _, day in
                        if let day {
                            CalendarDay(day: day, today: today, tasks: WorkCalendar.tasks(on: day, from: tasks), select: select)
                        } else { Color.clear.frame(height: 54).accessibilityHidden(true) }
                    }
                }
            }
            HStack(spacing: 6) {
                Circle().fill(Palette.status(.inProgress)).frame(width: 5, height: 5)
                Text("날짜별 진행 작업").font(.system(size: 11))
                Spacer()
                Text("올려서 이름 확인 · 눌러서 목록 보기").font(.system(size: 11))
            }.foregroundStyle(Palette.secondary)
        }.padding(24).frame(width: 600).background(Palette.surface).foregroundStyle(Palette.ink)
    }
}

private struct CalendarDay: View {
    let day: String
    let today: String
    let tasks: [WorkItem]
    let select: (WorkItem) -> Void
    @State private var hovering = false
    @State private var showingTasks = false
    private var tooltip: String {
        ([Dates.display(day)] + (tasks.isEmpty ? ["진행 작업 없음"] : tasks.map { "• \($0.title)" })).joined(separator: "\n")
    }
    var body: some View {
        Button { if !tasks.isEmpty { showingTasks = true } } label: {
            VStack(spacing: 4) {
                Text(String(Int(day.suffix(2))!)).font(.system(size: 12, weight: day == today ? .semibold : .regular))
                    .foregroundStyle(day == today ? .white : Palette.ink)
                    .frame(width: 24, height: 24).background(day == today ? Palette.accent : .clear, in: Circle())
                HStack(spacing: 4) {
                    Circle().fill(Palette.status(.inProgress)).frame(width: 5, height: 5)
                    Text("\(tasks.count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                }.foregroundStyle(Palette.secondary).opacity(tasks.isEmpty ? 0 : 1)
            }.frame(maxWidth: .infinity).frame(height: 54).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .background(hovering ? Palette.selected : Palette.quiet.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }.handCursor().help(tooltip)
        .accessibilityLabel("\(Dates.display(day)), 진행 작업 \(tasks.count)개")
        .accessibilityHint(tasks.isEmpty ? "진행 작업 없음" : "작업 목록 열기")
        .popover(isPresented: $showingTasks) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Dates.display(day)).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tasks) { task in
                            Button { showingTasks = false; select(task) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                    if !task.ticket.isEmpty { Text(task.ticket).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8).contentShape(Rectangle())
                            }.buttonStyle(.plain).handCursor()
                        }
                    }
                }.frame(height: min(240, CGFloat(tasks.count) * 64))
            }.padding(16).frame(width: 280).background(Palette.surface)
        }
    }
}
