import SwiftUI
import QuestletCore

struct TaskDraft {
    var title = "", ticket = "", start = "", end = ""
    var month = Dates.calendar.date(from: Dates.calendar.dateComponents([.year, .month], from: Date()))!
    init(today: String = Dates.day()) {
        start = today
        month = Dates.calendar.date(from: Dates.calendar.dateComponents([.year, .month], from: Dates.date(today)!))!
    }
    init(_ task: WorkItem) { title = task.title; ticket = task.ticket; start = task.start; end = task.end; month = Dates.calendar.date(from: Dates.calendar.dateComponents([.year, .month], from: Dates.date(task.start)!))! }
    var complete: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !start.isEmpty && !end.isEmpty }
}
struct Field: View {
    let label: String; let placeholder: String
    @Binding var value: String
    var body: some View { VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondary); TextField(placeholder, text: $value).textFieldStyle(.plain).padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line)).accessibilityLabel(label) } }
}
struct TaskFields: View {
    @Binding var draft: TaskDraft
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Field(label: "제목", placeholder: "작업 제목", value: $draft.title)
            Field(label: "Jira 티켓 · 선택", placeholder: "예: CMGSL-13332", value: $draft.ticket)
            Text("작업 기간").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            DateRangePicker(start: $draft.start, end: $draft.end, month: $draft.month)
        }
    }
}
struct DateRangePicker: View {
    @Binding var start: String
    @Binding var end: String
    @Binding var month: Date
    private var calendar: Calendar { Dates.calendar }
    private var cells: [Date?] {
        let beginning = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let offset = calendar.component(.weekday, from: beginning) - 1
        let count = calendar.range(of: .day, in: .month, for: beginning)!.count
        return Array(repeating: nil, count: offset) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: beginning) }
    }
    private var monthTitle: String { let c = calendar.dateComponents([.year, .month], from: month); return "\(c.year!)년 \(c.month!)월" }
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button { start = ""; end = "" } label: { dateBox("시작일", start) }
                    .buttonStyle(.plain).handCursor().accessibilityLabel("시작일 다시 선택")
                Button { end = "" } label: { dateBox("종료일", end) }
                    .buttonStyle(.plain).handCursor().accessibilityLabel("종료일 다시 선택")
            }
            HStack {
                IconButton(symbol: "chevron.left", label: "이전 달") { changeMonth(-1) }
                Spacer(); Text(monthTitle).font(.system(size: 13, weight: .medium)); Spacer()
                IconButton(symbol: "chevron.right", label: "다음 달") { changeMonth(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 3) {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(height: 22) }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = Dates.day(date)
                        let endpoint = key == start || key == end
                        let between = !start.isEmpty && !end.isEmpty && start < key && key < end
                        Button {
                            if start.isEmpty || !end.isEmpty { start = key; end = "" } else { end = key }
                        } label: { Text("\(calendar.component(.day, from: date))").font(.system(size: 13)).frame(maxWidth: .infinity).frame(height: 30).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .background(endpoint ? Palette.accent : between ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: endpoint ? 5 : 0))
                        .foregroundStyle(endpoint ? .white : Palette.ink)
                        .disabled(!start.isEmpty && end.isEmpty && key < start)
                        .accessibilityLabel("\(Dates.display(key))\(key == start ? " 시작일" : key == end ? " 종료일" : "")")
                        .accessibilityAddTraits(endpoint ? .isSelected : [])
                        .handCursor()
                    } else { Color.clear.frame(height: 30) }
                }
            }
        }
    }
    private func changeMonth(_ value: Int) { if let next = calendar.date(byAdding: .month, value: value, to: month) { month = next } }
    private func dateBox(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(label).font(.system(size: 11)).foregroundStyle(Palette.secondary); Text(value.isEmpty ? "선택" : Dates.display(value)).font(.system(size: 13, weight: .medium)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Palette.quiet, in: RoundedRectangle(cornerRadius: 6)) }
}
struct EditTaskForm: View {
    let task: WorkItem
    @State private var draft: TaskDraft
    @State private var error: String?
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: Session
    init(task: WorkItem) { self.task = task; _draft = State(initialValue: TaskDraft(task)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("작업 수정").font(.system(size: 17, weight: .medium)); Spacer(); IconButton(symbol: "xmark", label: "닫기") { session.route = nil } }
            TaskFields(draft: $draft)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            Divider()
            HStack { Spacer(); Button("취소") { session.route = nil }.handCursor(); Button("저장") { save() }.buttonStyle(.borderedProminent).tint(Palette.ink).disabled(!draft.complete || model.busy(task.id)).handCursor() }
        }.padding(22).frame(width: 440).background(Palette.surface)
    }
    private func save() { do { let id = try model.save(id: task.id, title: draft.title, ticket: draft.ticket, start: draft.start, end: draft.end); if let t = model.work(id) { session.choose(t) }; session.route = nil } catch { self.error = error.localizedDescription } }
}
