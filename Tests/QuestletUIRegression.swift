import SwiftUI
import AppKit
import QuestletCore

@main struct UIRegression {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = TaskDraft(today: "2026-10-03")
        assert(draft.start == "2026-10-03" && draft.end.isEmpty && !draft.complete)
        let existing = WorkItem(title: "기존 일정", ticket: "", start: "2026-09-01", end: "2026-09-02", today: "2026-10-03")
        assert(TaskDraft(existing).start == "2026-09-01")
        let session = Session(databaseURL: directory.appendingPathComponent("checks.sqlite"))
        let model = session.model!
        _ = try model.save(id: nil, title: "팝오버 목록 확인", ticket: "", start: model.today, end: model.today)
        let hosting = NSHostingController(rootView: MenuPopover().environmentObject(model).environmentObject(session))
        let size = hosting.sizeThatFits(in: CGSize(width: 340, height: 0))
        print("Popover fitting size: \(size)")
        // Header + tabs alone fit in ~90pt. A task must contribute a visible list region.
        guard size.height >= 150 else { print("FAIL: task list collapsed below tabs"); exit(1) }
        print("Popover layout check passed")
        if CommandLine.arguments.contains("--show") {
            _ = try model.save(id: nil, title: "예정 작업 확인", ticket: "", start: "2099-10-01", end: "2099-10-02")
            _ = try model.save(id: nil, title: "완료 작업 확인", ticket: "", start: "2020-10-01", end: "2020-10-02")
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Questlet 팝오버 검증"
            window.contentViewController = hosting
            window.center(); window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.run()
        }
    }
}
