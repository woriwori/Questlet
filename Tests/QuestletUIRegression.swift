import SwiftUI
import AppKit
import QuestletCore

final class UITestTokenVault: TokenVault, @unchecked Sendable {
    private var tokens = APITokens()
    private let lock = NSLock()
    func load() throws -> APITokens { lock.lock(); defer { lock.unlock() }; return tokens }
    func save(_ tokens: APITokens) throws { lock.lock(); defer { lock.unlock() }; self.tokens = tokens }
}

struct FailingUITokenVault: TokenVault {
    func load() throws -> APITokens { APITokens() }
    func save(_ tokens: APITokens) throws { throw InputError("테스트 저장 실패") }
}

@main struct UIRegression {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = TaskDraft(today: "2026-10-03")
        assert(draft.start == "2026-10-03" && draft.end.isEmpty && !draft.complete)
        let existing = WorkItem(title: "기존 일정", ticket: "", start: "2026-09-01", end: "2026-09-02", today: "2026-10-03")
        assert(TaskDraft(existing).start == "2026-09-01")
        let vault = UITestTokenVault()
        let session = Session(databaseURL: directory.appendingPathComponent("checks.sqlite"), tokenVault: vault)
        assert(session.needsSetup)
        try session.saveTokens(jira: "ui-test-jira", emux: "ui-test-emux")
        assert(!session.needsSetup)
        let secondSession = Session(databaseURL: directory.appendingPathComponent("reload.sqlite"), tokenVault: vault)
        assert(!secondSession.needsSetup)
        let failedSetup = Session(databaseURL: directory.appendingPathComponent("failed.sqlite"), tokenVault: FailingUITokenVault())
        do { try failedSetup.saveTokens(jira: "ui-test-jira", emux: "ui-test-emux"); assertionFailure("저장 실패가 완료로 처리됨") } catch {}
        assert(failedSetup.needsSetup)
        print("First-run, already-configured startup and failed-save checks passed")
        let model = session.model!
        _ = try model.save(id: nil, title: "팝오버 목록 확인", ticket: "", start: model.today, end: model.today)
        let hosting = NSHostingController(rootView: MenuPopover().environmentObject(model).environmentObject(session))
        let size = hosting.sizeThatFits(in: CGSize(width: 340, height: 0))
        print("Popover fitting size: \(size)")
        // Header + tabs alone fit in ~90pt. A task must contribute a visible list region.
        guard size.height >= 150 else { print("FAIL: task list collapsed below tabs"); exit(1) }
        print("Popover layout check passed")
        if CommandLine.arguments.contains("--show") || CommandLine.arguments.contains("--show-settings") || CommandLine.arguments.contains("--show-onboarding") {
            _ = try model.save(id: nil, title: "예정 작업 확인", ticket: "", start: "2099-10-01", end: "2099-10-02")
            _ = try model.save(id: nil, title: "완료 작업 확인", ticket: "", start: "2020-10-01", end: "2020-10-02")
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Questlet 팝오버 검증"
            if CommandLine.arguments.contains("--show-settings") {
                window.title = "Questlet 설정 검증"
                window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(session))
                window.setContentSize(NSSize(width: 520, height: 650))
            } else if CommandLine.arguments.contains("--show-onboarding") {
                try vault.save(APITokens()); session.needsSetup = true
                window.title = "Questlet 최초 설정 검증"
                window.contentViewController = NSHostingController(rootView: TokenConfigurationForm(firstRun: true).environmentObject(session))
                window.setContentSize(NSSize(width: 420, height: 420))
            } else { window.contentViewController = hosting }
            window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.run()
        }
    }
}
