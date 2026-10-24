import SwiftUI
import AppKit

struct CommentEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var enabled
    private let font = NSFont.systemFont(ofSize: 14)

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> OverlayScrollView {
        let scroll = OverlayScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.verticalScroller?.controlSize = .small
        let editor = CommentTextView(frame: .zero)
        editor.font = font
        editor.textColor = .labelColor
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = .width
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("작업 메모 입력")
        editor.string = text
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: OverlayScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? CommentTextView else { return }
        // Leave the live editor's selection and IME composition intact while typing.
        editor.isEditable = enabled
        editor.isSelectable = enabled
        if editor.string != text {
            editor.string = text
            editor.sizeToFit()
            editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
            editor.needsDisplay = true
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: OverlayScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        let bounds = NSAttributedString(string: text + " ", attributes: [.font: font])
            .boundingRect(with: NSSize(width: max(1, width - 20), height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        return CGSize(width: width, height: min(lineHeight * 7, max(lineHeight * 3, ceil(bounds.height))) + 20)
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommentEditor
        init(_ parent: CommentEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? CommentTextView else { return }
            parent.text = editor.string
            editor.needsDisplay = true
        }
    }
}

final class CommentTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            ("작업 메모나 링크를 남기세요." as NSString).draw(at: textContainerOrigin,
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
}
