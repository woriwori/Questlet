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
        for scale in [1.0, 2.0] {
            let renderer = ImageRenderer(content: Color.white.frame(width: 40, height: 40).floatingSurface().environment(\.displayScale, scale))
            renderer.scale = scale
            let bitmap = NSBitmapImageRep(cgImage: renderer.cgImage!)
            let corner = bitmap.colorAt(x: 0, y: 0)!.alphaComponent
            let shoulder = bitmap.colorAt(x: 2, y: 0)!.alphaComponent
            let edge = bitmap.colorAt(x: 7, y: 0)!.alphaComponent
            assert(corner < 0.5 && shoulder < 0.5 && edge > 0.9, "Outer edge is not a 6px radius at scale \(scale): \(corner), \(shoulder), \(edge)")
        }
        print("Actual outer-edge pixel checks passed at 1x and 2x (6px)")
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
        var quitCalled = false
        session.setupDidDismiss(terminate: { quitCalled = true })
        assert(!quitCalled) // Saving tokens closes setup without quitting.
        failedSetup.requestSetupQuit()
        assert(!failedSetup.needsSetup)
        failedSetup.setupDidDismiss(terminate: { quitCalled = true })
        assert(quitCalled)
        let nextFailedLaunch = Session(databaseURL: directory.appendingPathComponent("quit-relaunch.sqlite"), tokenVault: FailingUITokenVault())
        assert(nextFailedLaunch.needsSetup) // Quit never saves credentials or completes setup.
        print("First-run, failed-save and dismiss-before-quit checks passed")
        let model = session.model!
        _ = try model.save(id: nil, title: "팝오버 목록 확인", ticket: "", start: model.today, end: model.today)
        let hosting = NSHostingController(rootView: MenuPopover().environmentObject(model).environmentObject(session))
        let size = hosting.sizeThatFits(in: CGSize(width: 340, height: 0))
        print("Popover fitting size: \(size)")
        // Header + tabs alone fit in ~90pt. A task must contribute a visible list region.
        guard size.height >= 150 else { print("FAIL: task list collapsed below tabs"); exit(1) }
        print("Popover layout check passed")
        for (month, expectedHeight) in [("2026-02-01", 364.0), ("2026-10-19", 422.0), ("2026-08-01", 480.0)] {
            let panel = NSHostingController(rootView: WorkCalendarPanel(tasks: model.tasks, today: month, close: {}, select: { _ in }))
            let fitting = panel.sizeThatFits(in: CGSize(width: 600, height: 0))
            assert(abs(fitting.width - 600) < 1 && abs(fitting.height - expectedHeight) < 1, "Calendar has unexpected whitespace: \(fitting)")
        }
        print("Calendar layout: 600pt width, 4/5/6 weeks and 36pt bottom padding passed")
        if let argument = CommandLine.arguments.firstIndex(of: "--render-tooltip"), CommandLine.arguments.count > argument + 1 {
            let samples = [
                ("캠페인 수정 버그픽스", "CMGSL-13332", "2026-10-15"),
                ("검색 필터 상태 유지", "CMGSL-13405", "2026-10-16"),
                ("접근성 검수", "CMGSL-13510", "2026-10-21"),
                ("다음 배포 준비", "CMGSL-13512", "2026-10-22")
            ].map { WorkItem(title: $0.0, ticket: $0.1, start: $0.2, end: "2026-10-29", today: "2026-10-19") }
            let view = NSHostingView(rootView: CalendarTaskList(tasks: samples, today: "2026-10-19", select: { _ in }).floatingSurface().padding(10).background(Palette.quiet).preferredColorScheme(.light))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 208), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            view.displayIfNeeded()
            func scrollViews(in node: NSView) -> [NSScrollView] {
                (node as? NSScrollView).map { [$0] } ?? node.subviews.flatMap { scrollViews(in: $0) }
            }
            let actualScrollViews = scrollViews(in: view)
            if let document = actualScrollViews.first?.documentView, let documentBitmap = document.bitmapImageRepForCachingDisplay(in: document.bounds) {
                // Flush the nested hosting view before capturing the outer snapshot.
                document.cacheDisplay(in: document.bounds, to: documentBitmap)
                let hasText = stride(from: 0, to: documentBitmap.pixelsHigh, by: 8).contains { y in
                    stride(from: 20, to: documentBitmap.pixelsWide, by: 8).contains { x in
                        guard let color = documentBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        return color.alphaComponent > 0.8 && color.redComponent < 0.5
                    }
                }
                assert(hasText, "Scroll document did not render its task names")
            }
            assert(!actualScrollViews.isEmpty && actualScrollViews.allSatisfy { $0.scrollerStyle == .overlay && $0.autohidesScrollers && $0.verticalScroller?.scrollerStyle == .overlay })
            print("Rendered tooltip uses native overlay/auto-hide scrollbars")
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[argument + 1]))
            print("Compact calendar tooltip rendered")
        }
        if let argument = CommandLine.arguments.firstIndex(of: "--render-calendar"), CommandLine.arguments.count > argument + 1 {
            // Render only synthetic tasks in an isolated database; never the user's window/data.
            let calendarModel = try AppModel(database: Database(url: directory.appendingPathComponent("calendar.sqlite")), jira: session.integration.jira, now: { Dates.date("2026-10-19")! })
            for (title, start, end) in [
                ("캠페인 수정 버그픽스", "2026-10-15", "2026-10-23"),
                ("추천 영역 접근성 개선", "2026-10-19", "2026-10-21"),
                ("배포 체크리스트 정리", "2026-10-19", "2026-10-19"),
                ("검색 필터 상태 유지", "2026-10-16", "2026-10-20"),
                ("프로모션 노출 검증", "2026-10-19", "2026-10-22"),
                ("다음 배포 준비", "2026-10-21", "2026-10-29")
            ] { _ = try calendarModel.save(id: nil, title: title, ticket: "", start: start, end: end) }
            session.selected = calendarModel.tasks.first?.id
            let renderingCreation = CommandLine.arguments.contains("--creation")
            if renderingCreation { session.route = .create }
            let preview = ZStack {
                MainWindow().environmentObject(calendarModel).environmentObject(session)
                if !renderingCreation {
                    Color.black.opacity(0.14)
                    WorkCalendarPanel(tasks: calendarModel.tasks, today: "2026-10-19", close: {}, select: { _ in })
                        .floatingSurface()
                }
            }.frame(width: 960, height: 700).preferredColorScheme(.light)
            let view = NSHostingView(rootView: preview)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Calendar preview bitmap unavailable") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Calendar preview PNG unavailable") }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[argument + 1]))
            print("Calendar design preview rendered")
        }
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
