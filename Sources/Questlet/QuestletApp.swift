import SwiftUI
import AppKit
import QuestletCore

enum FormRoute: Identifiable {
    case create, edit(UUID)
    var id: String { switch self { case .create: "create"; case .edit(let id): id.uuidString } }
}
@MainActor final class Session: ObservableObject {
    let integration: IntegrationAssembly
    let model: AppModel?
    let startupError: String?
    @Published var selected: UUID?
    @Published var filter: TaskStatus = .inProgress
    @Published var route: FormRoute?
    @Published var generating = false
    @Published var needsSetup = true
    @Published var credentialError: String?
    @Published var scenario: MockScenario = .success
    @Published var jiraBase = UserDefaults.standard.string(forKey: "jiraBrowseBase") ?? ""
    private var quittingSetup = false
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastDay = Dates.day()
    init(databaseURL: URL? = nil, tokenVault: any TokenVault = KeychainTokenVault()) {
        integration = IntegrationAssembly(tokenVault: tokenVault)
        do { needsSetup = !(try tokenVault.load()).configured }
        catch { credentialError = error.localizedDescription }

        do {
            let url: URL
            if let databaseURL { url = databaseURL }
            else if CommandLine.arguments.contains("--demo") { url = Database.defaultURL.deletingLastPathComponent().appendingPathComponent("Demo/questlet.sqlite") }
            else { url = Database.defaultURL }
            let m = try AppModel(database: Database(url: url), jira: integration.jira)
            if CommandLine.arguments.contains("--demo"), m.tasks.isEmpty {
                let today = m.today, day = Dates.date(today)!
                let end = Dates.day(Dates.calendar.date(byAdding: .day, value: 4, to: day)!)
                let id = try m.save(id: nil, title: "캠페인 수정 버그픽스", ticket: "", start: today, end: end)
                try m.addComment(taskID: id, body: "디자이너가 수정페이지 UX 전달. https://example.com/design")
                _ = try m.save(id: id, title: "캠페인 수정 버그픽스", ticket: "CMGSL-13332", start: today, end: end)
                _ = try m.save(id: nil, title: "검색 필터 상태 유지", ticket: "", start: today, end: end)
                let future = Dates.day(Dates.calendar.date(byAdding: .day, value: 6, to: day)!)
                _ = try m.save(id: nil, title: "배포 검증", ticket: "", start: future, end: future)
            }
            model = m; startupError = nil
            if !needsSetup { m.refresh(resuming: true) }
            selected = m.list(status: .inProgress).first?.id
        } catch { model = nil; startupError = error.localizedDescription }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.tick(); self?.resume() } }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }
    func requestSetupQuit() {
        // The form explicitly dismisses its sheet; terminate only after onDismiss.
        // Keep background refresh blocked while setup is closing without credentials.
        quittingSetup = true
        needsSetup = false
    }
    func setupDidDismiss(terminate: (() -> Void)? = nil) {
        guard quittingSetup else { return }
        if let terminate { terminate() } else { NSApp.terminate(nil) }
    }
    func saveTokens(jira: String, emux: String) throws {
        try integration.tokenVault.update(jira: jira, emux: emux)
        needsSetup = false; credentialError = nil
        model?.refresh(resuming: true)
    }
    func choose(_ task: WorkItem) { filter = task.status; selected = task.id }
    func resume() { if !needsSetup && !quittingSetup { model?.refresh(resuming: true) } }
    func tick() { guard !needsSetup && !quittingSetup else { return }; let day = Dates.day(); if day != lastDay { lastDay = day; model?.refresh() } }
    func openTicket(_ ticket: String) {
        guard let base = Validation.webURL(jiraBase) else { model?.error = "설정에서 사내 Jira browse 주소를 입력하세요. 예: https://회사주소/browse/"; return }
        NSWorkspace.shared.open(base.appendingPathComponent(ticket))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

#if !QUESTLET_UI_CHECKS
@main struct QuestletApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = Session()
    var body: some Scene {
        Window("Questlet", id: "main") {
            Group {
                if let model = session.model { MainWindow().environmentObject(model).environmentObject(session) }
                else { VStack(alignment: .leading, spacing: 14) { Text("Questlet을 열 수 없습니다").font(.title2); Text(session.startupError ?? "알 수 없는 오류"); Text("기존 데이터는 덮어쓰지 않았습니다.").foregroundStyle(.secondary) }.padding(30) }
            }
            .preferredColorScheme(.light)
            .frame(minWidth: 780, minHeight: 672)
            .sheet(isPresented: $session.needsSetup, onDismiss: { session.setupDidDismiss() }) { TokenConfigurationForm(firstRun: true).environmentObject(session).interactiveDismissDisabled() }
        }
        .defaultSize(width: 960, height: 700)
        .commands { CommandGroup(replacing: .newItem) { Button("새로 만들기") { session.route = .create }.keyboardShortcut("n").disabled(session.generating || session.needsSetup) } }
        MenuBarExtra {
            if let model = session.model { MenuPopover().environmentObject(model).environmentObject(session).preferredColorScheme(.light) }
            else { Text(session.startupError ?? "시작 오류").padding() }
        } label: {
            Image(nsImage: MenuBarLogo.image).renderingMode(.original).accessibilityLabel("Questlet")
        }.menuBarExtraStyle(.window)
        Settings { SettingsView().environmentObject(session).preferredColorScheme(.light) }
    }
}

#endif
