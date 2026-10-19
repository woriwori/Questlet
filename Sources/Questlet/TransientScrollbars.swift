import SwiftUI
import AppKit

// Own the NSScrollView so AppKit cannot replace these local overlay scrollbars with legacy ones.
struct TransientScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let revealRect: CGRect?
    init(revealRect: CGRect? = nil, @ViewBuilder content: () -> Content) {
        self.revealRect = revealRect; self.content = content()
    }
    func makeCoordinator() -> Coordinator { Coordinator(content) }
    func makeNSView(context: Context) -> OverlayScrollView {
        let scroll = OverlayScrollView()
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.verticalScroller?.controlSize = .small
        scroll.documentView = context.coordinator.host
        scroll.contentHeight = { [weak coordinator = context.coordinator] width in
            guard let coordinator else { return 0 }
            coordinator.resize(width)
            return coordinator.host.fittingSize.height
        }
        return scroll
    }
    func updateNSView(_ scroll: OverlayScrollView, context: Context) {
        context.coordinator.content = content
        context.coordinator.update()
        scroll.needsLayout = true
        if context.coordinator.lastRevealRect != revealRect {
            context.coordinator.lastRevealRect = revealRect
            if let revealRect {
                DispatchQueue.main.async { [weak scroll] in
                    scroll?.layoutSubtreeIfNeeded()
                    scroll?.documentView?.scrollToVisible(revealRect)
                }
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: OverlayScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 280, height: proposal.height ?? 10)
    }
    final class Coordinator {
        var content: Content
        var lastRevealRect: CGRect?
        var width: CGFloat = 280
        let host: NSHostingView<AnyView>
        init(_ content: Content) {
            self.content = content
            host = NSHostingView(rootView: AnyView(content.frame(width: 280, alignment: .leading)))
            host.appearance = NSAppearance(named: .aqua)
        }
        func update() { host.rootView = AnyView(content.frame(width: width, alignment: .leading)) }
        func resize(_ value: CGFloat) {
            if abs(width - value) > 0.5 { width = value; update() }
        }
    }
}

final class OverlayScrollView: NSScrollView {
    var contentHeight: ((CGFloat) -> CGFloat)?
    override var scrollerStyle: NSScroller.Style {
        get { super.scrollerStyle }
        set { super.scrollerStyle = .overlay }
    }
    override func layout() {
        super.layout()
        guard let documentView, let contentHeight, contentView.bounds.width > 0 else { return }
        let width = contentView.bounds.width
        let size = CGSize(width: width, height: max(contentView.bounds.height, contentHeight(width)))
        if abs(documentView.frame.width - size.width) > 0.5 || abs(documentView.frame.height - size.height) > 0.5 {
            documentView.setFrameSize(size)
        }
        documentView.layoutSubtreeIfNeeded()
    }
}
