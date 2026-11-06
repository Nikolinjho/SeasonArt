import AppKit

final class WinterObjectWindow: NSPanel {
    var dragBegan: ((CGPoint) -> Void)?
    var dragged: ((CGPoint, TimeInterval) -> Void)?
    var dragEnded: (() -> Void)?
    var showsInScreenshots = false {
        didSet { sharingType = showsInScreenshots ? .readOnly : .none }
    }

    init(object: WinterObject, screenFrame: CGRect) {
        let frame = object.frame.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sharingType = .none
        contentView = WinterObjectView(object: object)
        setFrame(frame, display: false)
    }

    func display(object: WinterObject, screenFrame: CGRect) {
        (contentView as? WinterObjectView)?.display(object: object)
        let next = object.frame.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        if next.size != frame.size {
            setFrame(next, display: false)
        } else if next.origin != frame.origin {
            setFrameOrigin(next.origin)
        }
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        FixedSpace.hold(self)
    }

    override func orderOut(_ sender: Any?) {
        (contentView as? WinterObjectView)?.endDrag()
        super.orderOut(sender)
    }

    override func close() {
        (contentView as? WinterObjectView)?.endDrag()
        super.close()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
