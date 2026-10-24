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
        func scrollViews(in node: NSView) -> [NSScrollView] {
            (node as? NSScrollView).map { [$0] } ?? node.subviews.flatMap { scrollViews(in: $0) }
        }
        let roleScroll = NSHostingView(rootView: TransientScrollView(revealRect: CGRect(x: 0, y: 160, width: 1, height: 32)) {
            VStack(spacing: 0) { ForEach(0..<6) { index in Text("cmg_role_\(index)").frame(height: 32) } }
        }.frame(width: 240, height: 112))
        let roleWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 112), styleMask: [.borderless], backing: .buffered, defer: false)
        roleWindow.contentView = roleScroll
        roleScroll.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let roleNative = scrollViews(in: roleScroll)[0]
        assert(roleNative.scrollerStyle == .overlay && roleNative.autohidesScrollers && roleNative.verticalScroller?.controlSize == .small)
        assert(roleNative.contentView.bounds.minY > 0 && roleNative.contentView.bounds.maxY >= 192, "Keyboard candidate was not revealed: \(roleNative.contentView.bounds)")
        print("Role candidates: thin auto-hide overlay scrollbar and offscreen keyboard selection reveal passed")
        let settingsHost = NSHostingView(rootView: SettingsView().environmentObject(session))
        let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        settingsWindow.contentView = settingsHost
        settingsHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let settingsScrolls = scrollViews(in: settingsHost)
        assert(!settingsScrolls.isEmpty && settingsScrolls.allSatisfy { $0.scrollerStyle == .overlay && $0.autohidesScrollers && $0.verticalScroller?.controlSize == .small })
        assert((settingsScrolls[0].documentView?.frame.height ?? 0) > 0, "Settings content failed to lay out")
        print("Settings content/environment and thin auto-hide overlay scrollbar passed")
        assert(AppConfiguration.jiraBrowseBaseURL == nil)
        session.openTicket("CMGSL-123")
        assert(model.error == "Jira 티켓 링크가 아직 연결되지 않았습니다.")
        model.error = nil
        let settingsPopupHost = NSHostingView(rootView: MainWindow().environmentObject(model).environmentObject(session).frame(width: 780, height: 672).preferredColorScheme(.light))
        let settingsPopupWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 672), styleMask: [.borderless], backing: .buffered, defer: false)
        settingsPopupWindow.contentView = settingsPopupHost
        let originalWindowCount = NSApp.windows.count
        session.showingSettings = true
        settingsPopupHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        assert(NSApp.windows.count == originalWindowCount, "Opening settings created a separate window")
        let panelSize = NSHostingController(rootView: SettingsView().environmentObject(session)).sizeThatFits(in: CGSize(width: 520, height: 600))
        assert(panelSize.width == 520 && panelSize.height == 600)
        if let index = CommandLine.arguments.firstIndex(of: "--render-settings"), CommandLine.arguments.count > index + 1 {
            for scroll in scrollViews(in: settingsPopupHost) {
                if let document = scroll.documentView, let bitmap = document.bitmapImageRepForCachingDisplay(in: document.bounds) { document.cacheDisplay(in: document.bounds, to: bitmap) }
            }
            let bitmap = settingsPopupHost.bitmapImageRepForCachingDisplay(in: settingsPopupHost.bounds)!
            settingsPopupHost.cacheDisplay(in: settingsPopupHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        session.showingSettings = false
        print("Settings opens inside MainWindow without a new window; 520x600 panel and nil Jira URL checks passed")
        let sidebarSession = Session(databaseURL: directory.appendingPathComponent("sidebar.sqlite"), tokenVault: vault)
        let sidebarModel = sidebarSession.model!
        for index in 1...100 {
            _ = try sidebarModel.save(id: nil, title: String(format: "스크롤 점검 %03d", index), ticket: "", start: sidebarModel.today, end: sidebarModel.today)
        }
        let sidebarHost = NSHostingView(rootView: MainWindow().environmentObject(sidebarModel).environmentObject(sidebarSession).frame(width: 780, height: 672).preferredColorScheme(.light))
        let sidebarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 672), styleMask: [.borderless], backing: .buffered, defer: false)
        sidebarWindow.contentView = sidebarHost
        sidebarHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let sidebarScroll = scrollViews(in: sidebarHost)[0]
        guard let sidebarDocument = sidebarScroll.documentView else { fatalError("Sidebar scroll document missing") }
        assert(sidebarDocument.frame.height > sidebarScroll.contentView.bounds.height * 5)
        sidebarScroll.contentView.scroll(to: NSPoint(x: 0, y: sidebarDocument.frame.height - sidebarScroll.contentView.bounds.height))
        sidebarScroll.reflectScrolledClipView(sidebarScroll.contentView)
        sidebarHost.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        assert(sidebarScroll.contentView.bounds.origin.y > 0)
        if let index = CommandLine.arguments.firstIndex(of: "--render-sidebar"), CommandLine.arguments.count > index + 1 {
            let bitmap = sidebarHost.bitmapImageRepForCachingDisplay(in: sidebarHost.bounds)!
            sidebarHost.cacheDisplay(in: sidebarHost.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        sidebarScroll.contentView.scroll(to: .zero)
        sidebarScroll.reflectScrolledClipView(sidebarScroll.contentView)
        assert(sidebarScroll.contentView.bounds.origin.y == 0)
        print("Actual sidebar with 100 tasks scrolls to bottom and back to top")
        if CommandLine.arguments.contains("--show-sidebar") {
            NSApp.setActivationPolicy(.regular)
            sidebarWindow.styleMask = [.titled, .closable, .resizable]
            sidebarWindow.title = "Questlet E2E · 테스트 작업 100개"
            sidebarWindow.center(); sidebarWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.run()
        }
        var commentDraft = "first"
        let commentBinding = Binding(get: { commentDraft }, set: { commentDraft = $0 })
        let commentHost = NSHostingView(rootView: CommentEditor(text: commentBinding).frame(width: 400))
        let commentWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 140), styleMask: [.borderless], backing: .buffered, defer: false)
        commentWindow.contentView = commentHost
        commentHost.layoutSubtreeIfNeeded()
        let commentScroll = scrollViews(in: commentHost)[0]
        let editor = commentScroll.documentView as! CommentTextView
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.insertNewline(nil)
        assert(editor.string == "first\n" && commentDraft == "first\n", "Return failed to insert a newline")
        editor.insertText((1...20).map { "line \($0)" }.joined(separator: "\n"), replacementRange: editor.selectedRange())
        commentHost.layoutSubtreeIfNeeded()
        editor.sizeToFit()
        commentScroll.layoutSubtreeIfNeeded()
        assert(editor.frame.height > commentScroll.contentView.bounds.height, "Long comment did not overflow")
        let initialOrigin = commentScroll.contentView.bounds.origin.y
        commentScroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        commentScroll.reflectScrolledClipView(commentScroll.contentView)
        editor.scrollRangeToVisible(NSRange(location: editor.string.utf16.count, length: 0))
        assert(commentScroll.contentView.bounds.origin.y > 0, "Long comment cannot scroll to its end: \(initialOrigin)")
        print("Comment editor: Return inserts newline, updates binding and long text scrolls internally")
        let form = NSHostingController(rootView: CreationForm().environmentObject(model).environmentObject(session))
        let formSize = form.sizeThatFits(in: CGSize(width: 440, height: 672))
        form.view.frame.size = formSize
        form.view.layoutSubtreeIfNeeded()
        assert(formSize.height > 0 && formSize.height <= 672 && scrollViews(in: form.view).isEmpty, "Creation form exceeds the minimum window or added scrolling")
        print("Creation form uses its full content height without a scroll container: \(formSize.height)pt")
        let main = NSHostingController(rootView: MainWindow().environmentObject(model).environmentObject(session).frame(minWidth: 780, minHeight: 672))
        main.view.frame.size = CGSize(width: 780, height: 672)
        main.view.layoutSubtreeIfNeeded()
        let closedSize = main.sizeThatFits(in: CGSize(width: 780, height: 672))
        session.route = .create
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        main.view.layoutSubtreeIfNeeded()
        let openSize = main.sizeThatFits(in: CGSize(width: 780, height: 672))
        assert(closedSize == openSize && openSize.height == 672, "Opening creation changed main layout: \(closedSize) -> \(openSize)")
        session.route = nil
        print("Minimum 672pt main layout stays unchanged when creation opens")
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
            for count in 1...4 {
                let expected: CGFloat = count < 4 ? CGFloat(count * 44 - 4 + 16) : 168
                assert(CalendarTaskList.height(for: Array(samples.prefix(count))) == expected)
            }
            let view = NSHostingView(rootView: CalendarTaskList(tasks: samples, today: "2026-10-19", select: { _ in }).floatingSurface().padding(10).background(Palette.quiet).preferredColorScheme(.light))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 208), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            view.displayIfNeeded()
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
            let scroll = actualScrollViews[0]
            assert(abs(scroll.contentView.bounds.height - 152) < 1, "Tooltip must show 3 rows plus half of row 4")
            assert(abs((scroll.documentView?.frame.height ?? 0) - 172) < 1, "Tooltip rows have unexpected heights")
            print("Tooltip: 152pt viewport, 172pt document, 3.5 rows, overlay/auto-hide scrollbars passed")
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
            let renderingComment = CommandLine.arguments.contains("--comment")
            if renderingCreation { session.route = .create }
            let preview = ZStack {
                MainWindow().environmentObject(calendarModel).environmentObject(session)
                if !renderingCreation && !renderingComment {
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
            if renderingComment {
                func findEditor(_ node: NSView) -> CommentTextView? {
                    if let editor = node as? CommentTextView { return editor }
                    return node.subviews.compactMap { findEditor($0) }.first
                }
                guard let editor = findEditor(view), let scroll = editor.enclosingScrollView else { fatalError("Comment editor missing from actual MainWindow") }
                func capture(_ suffix: String) throws {
                    view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let path = URL(fileURLWithPath: CommandLine.arguments[argument + 1]).deletingPathExtension().path + suffix + ".png"
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                }
                editor.insertText("첫 번째 줄: 코멘트 입력 확인", replacementRange: editor.selectedRange())
                editor.insertNewline(nil)
                editor.insertText("두 번째 줄: Enter로 줄바꿈", replacementRange: editor.selectedRange())
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                assert(editor.string.contains("확인\n두 번째"))
                try capture("-newline")
                editor.insertNewline(nil)
                editor.insertText((3...18).map { String(format: "%02d번째 줄: 긴 코멘트 내부 스크롤 확인", $0) }.joined(separator: "\n"), replacementRange: editor.selectedRange())
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                view.layoutSubtreeIfNeeded()
                assert(editor.frame.height > scroll.contentView.bounds.height, "Actual main-window editor did not overflow")
                scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
                try capture("-scroll-top")
                editor.scrollRangeToVisible(NSRange(location: editor.string.utf16.count, length: 0))
                assert(scroll.contentView.bounds.origin.y > 0, "Actual main-window editor cannot scroll")
                try capture("-scroll-bottom")
                print("Actual MainWindow rendered: newline and internal scroll at top/bottom; no user data or desktop captured")
                return
            }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Calendar preview bitmap unavailable") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Calendar preview PNG unavailable") }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[argument + 1]))
            print("Calendar design preview rendered")
            if CommandLine.arguments.contains("--show-main") {
                NSApp.setActivationPolicy(.regular)
                let interactive = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 672), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                interactive.title = "Questlet UI Check"
                interactive.contentView = NSHostingView(rootView: MainWindow().environmentObject(calendarModel).environmentObject(session).preferredColorScheme(.light))
                interactive.center(); interactive.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                NSApp.run()
            }
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
                window.setContentSize(NSSize(width: 520, height: 600))
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
