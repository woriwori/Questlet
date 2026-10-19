import SwiftUI
import AppKit
import QuestletCore

private struct CalendarTaskAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

struct WorkCalendarPanel: View {
    let tasks: [WorkItem]
    let today: String
    let close: () -> Void
    let select: (WorkItem) -> Void
    @State private var month: Date
    @State private var selectedDay: String?
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
                    Button("오늘") { selectedDay = nil; month = Dates.date(today)! }
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
                        let dayTasks = WorkCalendar.tasks(on: day, today: today, from: tasks)
                        CalendarDay(day: day, today: today, tasks: dayTasks, selected: selectedDay == day,
                                    showTasks: { selectedDay = dayTasks.isEmpty || selectedDay == day ? nil : day })
                    } else { Color.clear.frame(height: 58).accessibilityHidden(true) }
                }
            }
        }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 36)
            .frame(width: 600).background(Palette.surface).foregroundStyle(Palette.ink)
            .contentShape(Rectangle()).onTapGesture { selectedDay = nil }
            .overlayPreferenceValue(CalendarTaskAnchor.self) { anchor in
                GeometryReader { geometry in
                    if let anchor, let day = selectedDay {
                        let dayTasks = WorkCalendar.tasks(on: day, today: today, from: tasks)
                        let rect = geometry[anchor]
                        let height = CalendarTaskList.height(for: dayTasks)
                        CalendarTaskList(tasks: dayTasks, today: today) { task in selectedDay = nil; select(task) }
                            .id(day).floatingSurface()
                            .position(x: min(geometry.size.width - 148, max(148, rect.midX)),
                                      y: rect.maxY + height + 8 <= geometry.size.height ? rect.maxY + 8 + height / 2 : max(height / 2 + 8, rect.minY - 8 - height / 2))
                            .onTapGesture {} // Keep clicks in the list's padding inside the tooltip.
                    }
                }
            }
            .onChange(of: month) { _, _ in selectedDay = nil }
    }
}

private struct CalendarDay: View {
    let day: String
    let today: String
    let tasks: [WorkItem]
    let selected: Bool
    let showTasks: () -> Void
    @State private var hovering = false
    private func status(_ task: WorkItem) -> TaskStatus { Dates.status(start: task.start, end: task.end, today: today) }
    private var tooltip: String {
        (tasks.isEmpty ? ["작업 없음"] : tasks.map { "\(status($0).label): \($0.title)" }).joined(separator: "\n")
    }
    var body: some View {
        Button(action: showTasks) {
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
        .onHover { hovering = $0 && !tasks.isEmpty }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                (tasks.isEmpty ? NSCursor.arrow : NSCursor.pointingHand).set()
            case .ended: NSCursor.arrow.set()
            }
        }
        .accessibilityLabel("\(Dates.display(day)), \(tooltip)")
        .accessibilityHint(tasks.isEmpty ? "작업 없음" : "작업 목록 열기")
        .anchorPreference(key: CalendarTaskAnchor.self, value: .bounds) { selected ? $0 : nil }
    }
}

struct CalendarTaskList: View {
    let tasks: [WorkItem]
    let today: String
    let select: (WorkItem) -> Void
    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 4
    static func height(for tasks: [WorkItem]) -> CGFloat {
        let fullHeight = CGFloat(tasks.count) * (rowHeight + rowSpacing) - rowSpacing
        let previewHeight = 3 * (rowHeight + rowSpacing) + rowHeight / 2
        return max(0, min(fullHeight, previewHeight)) + 16
    }
    var body: some View {
        TransientScrollView {
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(tasks) { task in
                    let status = Dates.status(start: task.start, end: task.end, today: today)
                    Button { select(task) } label: {
                        HStack(alignment: .top, spacing: 9) {
                            RoundedRectangle(cornerRadius: 1).fill(Palette.status(status).opacity(0.7))
                                .frame(width: 2, height: task.ticket.isEmpty ? 16 : 28).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                if !task.ticket.isEmpty { Text(task.ticket).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.horizontal, 4).frame(height: Self.rowHeight, alignment: .center).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).handCursor()
                    .accessibilityLabel("\(status.label), \(task.title)\(task.ticket.isEmpty ? "" : ", \(task.ticket)")")
                }
            }
        }.frame(height: Self.height(for: tasks) - 16)
            .padding(8).frame(width: 280).background(Palette.surface).foregroundStyle(Palette.ink)
    }
}
