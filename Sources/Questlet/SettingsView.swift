import SwiftUI
import AppKit
import QuestletCore

struct TokenConfigurationForm: View {
    let firstRun: Bool
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var jira = ""
    @State private var emux = ""
    @State private var message: String?
    @State private var error: String?
    private var enteredJira: Bool { !jira.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var enteredEmux: Bool { !emux.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if firstRun {
                Brand()
                Text("연동 토큰 설정").font(.system(size: 18, weight: .semibold))
                Text("처음 한 번 Jira와 emux PAT를 설정하세요. 이후 상단의 설정에서 교체할 수 있습니다.").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            } else {
                Text("연동 토큰").font(.system(size: 14, weight: .semibold))
                Text(session.needsSetup ? "두 PAT를 설정해주세요." : "토큰이 저장되어 있습니다. 변경할 PAT만 입력하세요.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            tokenField("Jira PAT", value: $jira)
            tokenField("emux PAT", value: $emux)
            Text(firstRun ? "PAT는 이 Mac의 키체인에 저장됩니다." : "빈 항목은 기존 값을 유지합니다. 만료되거나 인증이 실패하면 새 토큰으로 교체하세요.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Text("현재 연동은 mock이며, 토큰의 유효성은 실제 API 연결 후 확인됩니다.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if let error = error ?? session.credentialError { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            if let message { Text(message).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
            HStack {
                if firstRun { Button("앱 종료") { session.requestSetupQuit(); dismiss() }.handCursor() }
                Spacer()
                Button(firstRun ? "설정 완료" : "토큰 업데이트") {
                    do {
                        try session.saveTokens(jira: jira, emux: emux)
                        // Existing tokens are never populated into editable fields.
                        jira = ""; emux = ""; error = nil
                        message = "토큰을 업데이트했습니다. Jira 반영에 실패한 작업은 해당 작업에서 재시도하세요."
                    } catch { self.error = error.localizedDescription; message = nil }
                }.buttonStyle(.borderedProminent).tint(Palette.ink)
                    .disabled(firstRun || session.needsSetup ? !(enteredJira && enteredEmux) : !(enteredJira || enteredEmux)).handCursor()
            }
        }.padding(firstRun ? 24 : 0).frame(width: firstRun ? 420 : nil).background(Palette.surface)
            .onDisappear { jira = ""; emux = "" }
    }
    private func tokenField(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            SecureField(firstRun ? "PAT 입력" : "새 PAT 입력 · 비워두면 기존 값 유지", text: value)
                .textFieldStyle(.plain).padding(9).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line)).accessibilityLabel(label)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var session: Session
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("설정").font(.system(size: 20, weight: .semibold))
                TokenConfigurationForm(firstRun: false)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Jira 티켓 링크").font(.system(size: 14, weight: .semibold))
                    TextField("https://회사주소/browse/", text: $session.jiraBase).textFieldStyle(.roundedBorder).accessibilityLabel("Jira browse 주소")
                        .onChange(of: session.jiraBase) { _, value in UserDefaults.standard.set(value, forKey: "jiraBrowseBase") }
                    Text("티켓 링크를 여는 주소입니다. 실제 API 주소와 인증 방식은 사내 adapter에서 설정합니다.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Divider()
                if let model = session.model { ClosedCleanup(model: model) }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("모의 연동").font(.system(size: 14, weight: .semibold))
                    Picker("모의 응답", selection: $session.scenario) { ForEach(MockScenario.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        .onChange(of: session.scenario) { _, value in Task { await session.integration.control.set(value) } }
                    Text("현재 Jira·SRD·RP는 모두 mock이며 실제 변경은 수행하지 않습니다.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                if let model = session.model { Text("로컬 DB: \(model.database.url.path)").textSelection(.enabled).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            }.padding(24)
        }.frame(width: 520, height: 650).background(Palette.surface)
            .onAppear { if !session.needsSetup { session.model?.refresh() } }
    }
}

struct ClosedCleanup: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject var session: Session
    @State private var confirming = false
    @State private var message: String?
    @State private var error: String?
    private var count: Int { model.tasks.filter { Dates.status(start: $0.start, end: $0.end, today: model.today) == .closed }.count }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("완료 작업 정리").font(.system(size: 14, weight: .semibold))
            Text("완료 작업 \(count)개와 해당 코멘트를 이 Mac에서 삭제합니다.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Button("완료 작업 모두 삭제", role: .destructive) { confirming = true }.disabled(count == 0).handCursor()
            if let message { Text(message).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }.alert("완료 작업 \(count)개를 로컬에서 삭제할까요?", isPresented: $confirming) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                do {
                    let removed = try model.deleteClosed()
                    if model.work(session.selected) == nil { session.selected = model.list(status: session.filter).first?.id }
                    message = "완료 작업 \(removed)개를 로컬에서 삭제했습니다."; error = nil
                } catch { self.error = error.localizedDescription; message = nil }
            }
        } message: {
            Text("작업과 코멘트를 로컬에서 삭제합니다. Jira 티켓과 이미 반영된 내용은 남습니다. Jira에서는 직접 처리해주세요. 전송 중인 요청은 이미 반영될 수 있습니다.")
        }
    }
}
