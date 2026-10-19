import SwiftUI
import AppKit
import QuestletCore

enum CreationTab: String, CaseIterable { case task = "새 작업", srd = "SRD 생성", rp = "RP 생성" }
struct CreationForm: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var session: Session
    @State private var tab: CreationTab = .task
    @State private var draft = TaskDraft()
    @State private var srdPRD = ""
    @State private var srdTitle = ""
    @State private var parent = ""
    @State private var rpPRD = ""
    @State private var lastInput: [String]?
    @State private var roles: [String] = []
    @State private var error: String?
    @State private var receipt: WikiReceipt?
    @State private var unknown = false
    @State private var requestID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("새로 만들기").font(.system(size: 17, weight: .medium)); Spacer(); IconButton(symbol: "xmark", label: "닫기") { session.route = nil }.disabled(session.generating) }
            HStack(spacing: 3) { ForEach(CreationTab.allCases, id: \.self) { value in Button { tab = value; error = nil; receipt = nil; unknown = false; requestID = UUID() } label: { Text(value.rawValue).font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 7).contentShape(Rectangle()) }.buttonStyle(.plain).background(tab == value ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 5)).accessibilityAddTraits(tab == value ? .isSelected : []).disabled(session.generating).handCursor() } }
            ViewThatFits(in: .vertical) {
                formContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { formContent }.defaultScrollAnchor(.top)
            }
            Divider()
            HStack {
                Spacer()
                Button(receipt == nil ? "취소" : "닫기") { session.route = nil }.disabled(session.generating).handCursor()
                if receipt == nil {
                    Button(tab == .task ? "저장" : "생성") { if tab == .task { saveTask() } else { Task { await generate() } } }.buttonStyle(.borderedProminent).tint(Palette.ink).disabled(!complete || session.generating || unknown).handCursor()
                }
            }
        }.padding(22).frame(width: 440).background(Palette.surface).interactiveDismissDisabled(session.generating)
        .onDisappear { session.generating = false }
    }
    private var formContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                switch tab {
                case .task: TaskFields(draft: $draft)
                case .srd:
                    Field(label: "PRD", placeholder: "PRD 입력", value: $srdPRD)
                    Field(label: "제목", placeholder: "위키 제목", value: $srdTitle)
                    Field(label: "상위 페이지 링크", placeholder: "상위 페이지 링크 입력", value: $parent)
                case .rp:
                    RolePicker(options: session.integration.roles, selected: $roles)
                    Field(label: "PRD", placeholder: "https://…", value: $rpPRD)
                }
            }.disabled(session.generating || receipt != nil)
            if session.generating { HStack { ProgressView().controlSize(.small); Text("생성 중…").font(.system(size: 12)) } }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            if let receipt {
                VStack(alignment: .leading, spacing: 8) {
                    Text(receipt.simulated ? "모의 생성 완료 · 실제 위키는 생성되지 않았습니다." : "생성 완료").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Text(receipt.wikiURL.absoluteString).font(.system(size: 13)).textSelection(.enabled)
                    HStack { Button("링크 복사") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(receipt.wikiURL.absoluteString, forType: .string) }.handCursor(); if !receipt.simulated { Link("위키 열기", destination: receipt.wikiURL).handCursor() } }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.quiet, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    private var complete: Bool {
        switch tab {
        case .task: draft.complete
        case .srd: [srdPRD, srdTitle, parent].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .rp: !roles.isEmpty && Validation.webURL(rpPRD) != nil
        }
    }
    private func saveTask() {
        do { let id = try model.save(id: nil, title: draft.title, ticket: draft.ticket, start: draft.start, end: draft.end); if let t = model.work(id) { session.choose(t) }; session.route = nil } catch { self.error = error.localizedDescription }
    }
    private func generate() async {
        guard complete, !session.generating, !unknown else { return }
        let input = tab == .srd ? [srdPRD, srdTitle, parent] : roles + [rpPRD]
        if lastInput != input { requestID = UUID(); lastInput = input }
        session.generating = true; error = nil
        let result: Result<WikiReceipt, IntegrationFailure>
        // INTEGRATION-CALL: WIKI — 회사 adapter는 IntegrationAssembly에서 교체한다.
        if tab == .srd {
            result = await session.integration.srd.generate(SRDRequest(requestID: requestID, prd: srdPRD.trimmingCharacters(in: .whitespacesAndNewlines), title: srdTitle.trimmingCharacters(in: .whitespacesAndNewlines), parentPageLink: parent.trimmingCharacters(in: .whitespacesAndNewlines)))
        } else {
            result = await session.integration.rp.generate(RPRequest(requestID: requestID, roles: roles, prdURL: Validation.webURL(rpPRD)!))
        }
        session.generating = false
        switch result {
        case .success(let value):
            guard value.requestID == requestID, Validation.webURL(value.wikiURL.absoluteString) != nil else { unknown = true; error = "생성 응답을 확인할 수 없습니다. 사내 위키에서 확인해주세요."; return }
            receipt = value
        case .failure(let value): unknown = value.effect == .unknown; error = value.message + (unknown ? " 사내 위키에서 생성 여부를 확인해주세요. 자동 재생성하지 않습니다." : "")
        }
    }
}

struct RolePicker: View {
    let options: [String]
    @Binding var selected: [String]
    @State private var query = ""
    @State private var active = 0
    private var candidates: [String] { options.filter { !selected.contains($0) && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines))) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("role").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 6) {
                if !selected.isEmpty { ChipLayout { ForEach(selected, id: \.self) { role in HStack(spacing: 4) { Text(role).font(.system(size: 12)); Button { selected.removeAll { $0 == role } } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).accessibilityLabel("\(role) 제거").handCursor() }.padding(5).background(Palette.selected, in: RoundedRectangle(cornerRadius: 4)) } } }
                RoleSearchField(text: $query, choose: { chooseActive() }, removeLast: { if !selected.isEmpty { selected.removeLast() } }, move: { delta in if !candidates.isEmpty { active = (active + delta + candidates.count) % candidates.count } }).frame(height: 22)
            }.padding(8).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line))
            if !candidates.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) { ForEach(Array(candidates.enumerated()), id: \.element) { index, role in Button { select(role) } label: { Text(role).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).frame(height: 32).padding(.horizontal, 7).contentShape(Rectangle()) }.buttonStyle(.plain).background(active == index ? Palette.selected : Color.clear, in: RoundedRectangle(cornerRadius: 4)).id(index).handCursor() } }
                    }.frame(height: min(CGFloat(candidates.count) * 32, 112)).scrollIndicators(.visible)
                    .onChange(of: active) { _, value in proxy.scrollTo(value, anchor: .center) }
                }.padding(4).background(Palette.quiet, in: RoundedRectangle(cornerRadius: 6))
            }
        }.onChange(of: query) { _, _ in active = 0 }
    }
    private func select(_ role: String) { if !selected.contains(role) { selected.append(role) }; query = ""; active = 0 }
    private func chooseActive() { guard !candidates.isEmpty else { return }; select(candidates[min(active, candidates.count - 1)]) }
}

// Native NSTextField handles IME/text editing; delegate intercepts only selection commands.
struct RoleSearchField: NSViewRepresentable {
    @Environment(\.isEnabled) private var enabled
    @Binding var text: String
    let choose: () -> Void; let removeLast: () -> Void; let move: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(); field.isBordered = false; field.drawsBackground = false
        field.placeholderString = "cmg 또는 valley 검색"; field.font = .systemFont(ofSize: 13)
        field.delegate = context.coordinator; field.setAccessibilityLabel("role 검색")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) { context.coordinator.parent = self; field.isEnabled = enabled; if field.stringValue != text { field.stringValue = text } }
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RoleSearchField
        init(_ parent: RoleSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) { if let field = notification.object as? NSTextField { parent.text = field.stringValue } }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch NSStringFromSelector(commandSelector) {
            case "insertNewline:": parent.choose(); return true
            case "moveDown:": parent.move(1); return true
            case "moveUp:": parent.move(-1); return true
            case "deleteBackward:" where parent.text.isEmpty: parent.removeLast(); return true
            default: return false
            }
        }
    }
}

struct ChipLayout: Layout {
    var spacing: CGFloat = 5
    private func positions(_ subviews: Subviews, width: CGFloat) -> ([CGPoint], CGSize) {
        var points: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0; var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; row = max(row, size.height)
        }
        return (points, CGSize(width: width, height: y + row))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { positions(subviews, width: proposal.width ?? 390).1 }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let points = positions(subviews, width: bounds.width).0
        for (index, view) in subviews.enumerated() { view.place(at: CGPoint(x: bounds.minX + points[index].x, y: bounds.minY + points[index].y), proposal: .unspecified) }
    }
}
