import SwiftUI
import AppKit
import QuestletCore

struct MainWindow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: Session
    @Environment(\.openSettings) var openSettings
    @State private var query = ""
    @State private var sort: TaskSortField = .title
    @State private var ascending = true
    private var visibleTasks: [WorkItem] { model.list(status: session.filter, query: query, sort: sort, ascending: ascending) }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 0) {
            HStack { Brand(); Spacer(); Text(Dates.timestamp(Date()).prefix(10)).font(.system(size: 12)).foregroundStyle(Palette.secondary); IconButton(symbol: "gearshape", label: "설정", size: 32, glyph: 16) { openSettings() }; IconButton(symbol: "plus", label: "새로 만들기", accent: true, size: 32) { session.route = .create }.disabled(session.needsSetup) }.padding(.horizontal, 24).padding(.top, 18)
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary); TextField("제목, 티켓, 코멘트 검색", text: $query).textFieldStyle(.plain) }.padding(9).background(Palette.quiet, in: RoundedRectangle(cornerRadius: 6)).padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 0) {
                        StatusTabs(value: $session.filter)
                        Spacer(minLength: 0)
                        Menu {
                            Picker("정렬 기준", selection: $sort) {
                                ForEach(TaskSortField.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            Divider()
                            Picker("정렬 방향", selection: $ascending) {
                                Label("오름차순", systemImage: "arrow.up").tag(true)
                                Label("내림차순", systemImage: "arrow.down").tag(false)
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 14))
                                .frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .foregroundStyle(Palette.secondary).handCursor()
                        .help("정렬: \(sort.rawValue) \(ascending ? "오름차순" : "내림차순")")
                        .accessibilityLabel("작업 정렬")
                        .accessibilityValue("\(sort.rawValue) \(ascending ? "오름차순" : "내림차순")")
                    }
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(visibleTasks) { task in TaskRow(task: task) { session.selected = task.id } }
                            if visibleTasks.isEmpty { Text(query.isEmpty ? "이 상태에 해당하는 작업이 없습니다." : "검색 결과가 없습니다.").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.vertical, 30) }
                        }
                    }
                }.padding(12).frame(width: 310).background(Palette.quiet)
                Divider()
                if let task = model.work(session.selected), task.status == session.filter { TaskDetail(task: task) }
                else { VStack { Image(systemName: "note.text").font(.system(size: 30)).padding(.bottom, 10); Text("목록에서 작업을 선택하세요.") }.foregroundStyle(Palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .background(Palette.surface)
        .sheet(item: $session.route) { route in
            switch route {
            case .create: CreationForm().environmentObject(model).environmentObject(session)
            case .edit(let id): if let task = model.work(id) { EditTaskForm(task: task).environmentObject(model).environmentObject(session) }
            }
        }
        .onChange(of: session.filter) { _, value in if model.work(session.selected)?.status != value { session.selected = visibleTasks.first?.id } }
        .onChange(of: query) { _, _ in if !visibleTasks.contains(where: { $0.id == session.selected }) { session.selected = visibleTasks.first?.id } }
        .onReceive(timer) { _ in session.tick() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in session.resume() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in session.tick() }
        .alert("처리하지 못했습니다", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("확인") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}

struct TaskRow: View {
    let task: WorkItem
    var compact = false
    let select: () -> Void
    @EnvironmentObject var session: Session
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: select) { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("\(task.title), 코멘트 \(task.comments.count)개").handCursor()
            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                HStack(alignment: .top) {
                    Text(task.title).font(.system(size: compact ? 12 : 14, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
                    if compact { IconButton(symbol: "pencil", label: "\(task.title) 수정", size: 24, glyph: 13) { session.choose(task); openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true); session.route = .edit(task.id) }.disabled(model.busy(task.id) || session.needsSetup) }
                }
                HStack(spacing: 10) {
                    if task.ticket.isEmpty { Text("티켓 없음").foregroundStyle(Palette.secondary).allowsHitTesting(false) } else { TicketLink(ticket: task.ticket) }
                    CommentCount(count: task.comments.count).allowsHitTesting(false)
                }
                Text("\(Dates.display(task.start)) — \(Dates.display(task.end))").monospacedDigit().foregroundStyle(Palette.secondary).allowsHitTesting(false)
            }.font(.system(size: compact ? 11 : 12)).padding(.horizontal, compact ? 9 : 10).padding(.vertical, compact ? 8 : 12)
        }.background(!compact && session.selected == task.id ? Palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct TaskDetail: View {
    let task: WorkItem
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: Session
    @State private var comment = ""
    @State private var deletion = false
    @State private var resolving: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.title).font(.system(size: 22, weight: .semibold)); CommentCount(count: task.comments.count).font(.system(size: 12)).padding(.top, 6)
                    Spacer(minLength: 4)
                    IconButton(symbol: "pencil", label: "제목 · 티켓 · 기간 수정") { session.route = .edit(task.id) }.disabled(model.busy(task.id) || session.needsSetup)
                    IconButton(symbol: "trash", label: "로컬 작업 삭제") { deletion = true }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { metadata }
                    VStack(alignment: .leading, spacing: 8) { metadata }
                }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Divider()
                syncFeedback
                ForEach(task.comments) { memo in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Dates.timestamp(memo.recordedAt)).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Text(memo.body).font(.system(size: 14)).textSelection(.enabled)
                        ForEach(memo.links, id: \.self) { url in Link(url.absoluteString, destination: url).font(.system(size: 12)).handCursor() }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Palette.quiet, in: RoundedRectangle(cornerRadius: 8))
                }
                if task.comments.isEmpty { Text("남긴 메모가 여기에 쌓입니다.").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("작업 메모나 링크를 남기세요.", text: $comment, axis: .vertical).lineLimit(3...7).textFieldStyle(.plain).font(.system(size: 14)).padding(10).background(Palette.quiet, in: RoundedRectangle(cornerRadius: 6)).accessibilityLabel("작업 메모 입력")
                    HStack { Text(task.ticket.isEmpty ? "로컬에만 저장" : "모의 Jira 연동").font(.system(size: 11)).foregroundStyle(Palette.secondary); Spacer(); Button("추가") { do { try model.addComment(taskID: task.id, body: comment); comment = "" } catch { model.error = error.localizedDescription } }.disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy(task.id)).handCursor() }
                }
            }.padding(24)
        }
        .id(task.id)
        .confirmationDialog("Jira에서 이 요청의 반영 여부를 직접 확인했나요?", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
            Button("이미 반영됨 · 재전송하지 않기") { if let id = resolving { model.resolveUnknown(id, applied: true) }; resolving = nil }
            Button("미반영 확인 · 다시 보내기") { if let id = resolving { model.resolveUnknown(id, applied: false) }; resolving = nil }
            Button("취소", role: .cancel) { resolving = nil }
        }
        .alert("로컬 작업을 삭제할까요?", isPresented: $deletion) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { do { try model.delete(task.id); session.selected = model.list(status: session.filter).first?.id } catch { model.error = error.localizedDescription } }
        } message: { Text("작업과 코멘트를 로컬에서 삭제합니다. Jira 티켓과 이미 반영된 내용은 남습니다. Jira에서는 직접 처리해주세요. 전송 중인 요청은 이미 반영될 수 있습니다.") }
    }
    @ViewBuilder var metadata: some View {
        if task.ticket.isEmpty { Text("티켓 없음") } else { TicketLink(ticket: task.ticket) }
        HStack(spacing: 5) { Circle().fill(Palette.status(task.status)).frame(width: 6, height: 6); Text(task.status.label) }
        Text("\(Dates.display(task.start)) — \(Dates.display(task.end))").monospacedDigit()
    }
    @ViewBuilder var syncFeedback: some View {
        let entries = model.requests(for: task)
        if model.busy(task.id) { HStack { ProgressView().controlSize(.small); Text("로컬에 저장했습니다. 모의 Jira 반영 중…") }.font(.system(size: 12)).foregroundStyle(Palette.secondary) }
        else if let failed = entries.first(where: { $0.state == .failed || $0.state == .unknown }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(failed.state == .unknown ? "로컬에 저장했습니다. Jira 반영 결과 불명." : "로컬에 저장했습니다. Jira 반영 실패.")
                Text(failed.failure?.message ?? "반영하지 못했습니다.")
                if failed.state == .failed { Button("재시도") { model.retry(task.id) }.handCursor() }
                else {
                    Text("중복 반영을 막기 위해 자동 재전송하지 않습니다. Jira에서 확인해주세요.")
                    Button("Jira 확인 결과 입력") { resolving = failed.id }.handCursor()
                }
            }.font(.system(size: 12)).foregroundStyle(Color(hex: 0xaa4545))
        } else { Text(task.feedback).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
    }
}

struct MenuPopover: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: Session
    @Environment(\.openWindow) var openWindow
    @Environment(\.openSettings) var openSettings
    @State private var filter: TaskStatus = .inProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Brand(compact: true); Spacer(); AppOpenButton { show() }; IconButton(symbol: "plus", label: "새로 만들기", accent: true) { show(); session.route = .create }.disabled(session.needsSetup) }.padding(.horizontal, 8)
            StatusTabs(value: $filter)
            ScrollView { LazyVStack(spacing: 2) { ForEach(model.list(status: filter)) { task in TaskRow(task: task, compact: true) { session.choose(task); show() } }; if model.list(status: filter).isEmpty { Text("이 상태에 해당하는 작업이 없습니다.").font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.vertical, 20) } } }.frame(height: min(330, max(64, CGFloat(model.list(status: filter).count) * 84)))
        }.padding(9).frame(width: 340).background(Palette.surface)
        .onAppear { filter = .inProgress; if !session.needsSetup { model.refresh() } }
        .contextMenu { Button("설정…") { openSettings() }; Button("Questlet 종료") { NSApp.terminate(nil) } }
    }
    private func show() { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
}
