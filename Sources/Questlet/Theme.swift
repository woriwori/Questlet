import SwiftUI
import AppKit
import QuestletCore

enum Palette {
    static let sheetCornerRadius: CGFloat = 6
    static let popoverCornerRadius: CGFloat = 4
    static let surface = Color(hex: 0xfcfcfc), quiet = Color(hex: 0xf4f5f6)
    static let line = Color(hex: 0xe5e7e9), ink = Color(hex: 0x282d33), secondary = Color(hex: 0x6e747c)
    static let selected = Color(hex: 0xedf1f4), accent = Color(hex: 0x56729a)
    static func status(_ value: TaskStatus) -> Color { switch value { case .inProgress: Color(hex: 0x4f89bc); case .toDo: Color(hex: 0xbd913d); case .closed: Color(hex: 0x579578) } }
}
extension Color {
    init(hex: Int) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
}
extension View {
    func handCursor() -> some View { onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } } }
}
struct Brand: View {
    var compact = false
    var body: some View { HStack(spacing: compact ? 3 : 4) { Image(nsImage: NSImage(contentsOf: Bundle.module.url(forResource: "questlet-header", withExtension: "png")!)!).resizable().scaledToFit().frame(width: compact ? 32 : 34, height: compact ? 32 : 34); Text("Questlet").font(.system(size: compact ? 15 : 20, weight: .semibold)) }.foregroundStyle(Palette.ink) }
}
struct IconButton: View {
    let symbol: String; let label: String; var accent = false; var size: CGFloat = 28; var glyph: CGFloat = 14
    let action: () -> Void
    var body: some View { Button(action: action) { Image(systemName: symbol).font(.system(size: glyph)).frame(width: size, height: size).contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(accent ? .white : Palette.secondary).background(accent ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6)).help(label).accessibilityLabel(label).handCursor() }
}
struct StatusTabs: View {
    @Binding var value: TaskStatus
    var body: some View { HStack(spacing: 2) { ForEach(TaskStatus.allCases, id: \.self) { status in Button { value = status } label: { HStack(spacing: 5) { Circle().fill(Palette.status(status)).frame(width: 6, height: 6); Text(status.label).font(.system(size: 12)) }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle()) }.buttonStyle(.plain).background(value == status ? Palette.line : .clear, in: RoundedRectangle(cornerRadius: 5)).accessibilityAddTraits(value == status ? .isSelected : []).handCursor() } } }
}
struct TicketLink: View {
    let ticket: String
    @EnvironmentObject var session: Session
    var body: some View { Button { session.openTicket(ticket) } label: { HStack(spacing: 2) { Text(ticket); Image(systemName: "arrow.up.right").font(.system(size: 10)) }.contentShape(Rectangle()) }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help("Jira 티켓 열기").accessibilityLabel("\(ticket) Jira 티켓 열기").handCursor() }
}
struct CommentCount: View {
    let count: Int
    var body: some View { HStack(spacing: 4) { Image(systemName: "bubble").font(.system(size: 10)); Text("\(count)") }.foregroundStyle(Palette.secondary).accessibilityLabel("코멘트 \(count)개") }
}

// Matches the approved app-window glyph; external ticket links keep their arrow glyph.
struct AppOpenButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            AppWindowGlyph().stroke(Palette.secondary, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14).frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.line, lineWidth: 1))
        .help("앱 열기").accessibilityLabel("앱 열기").handCursor()
    }
}
struct AppWindowGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.width / 24, y = rect.height / 24
        path.addRoundedRect(in: CGRect(x: 2*x, y: 4*y, width: 20*x, height: 16*y), cornerSize: CGSize(width: 2*x, height: 2*y))
        for position in [6.0, 10.0, 14.0] { path.addEllipse(in: CGRect(x: (position-0.5)*x, y: 7.5*y, width: x, height: y)) }
        return path
    }
}

// Use the same notebook/pencil artwork as the app header, sized for NSStatusItem.
// Original rendering preserves the light paper and blue pencil instead of filling the silhouette.
enum MenuBarLogo {
    static let image: NSImage = {
        let image = NSImage(contentsOf: Bundle.module.url(forResource: "questlet-header", withExtension: "png")!)!
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = false
        return image
    }()
}
