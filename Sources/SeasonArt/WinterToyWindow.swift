import AppKit

enum WinterToy: CaseIterable {
    case tree, shovel

    // Кромка лезвия на спрайте в координатах панели.
    static let shovelBlade = CGPoint(x: 59, y: 4)
    static let shovelHalfWidth: CGFloat = 24

    var menuTitle: String {
        switch self {
        case .tree: return "Ёлка"
        case .shovel: return "Лопата для снега"
        }
    }

    var size: CGSize {
        switch self {
        case .tree: return WinterTreeHeight.standard.size
        case .shovel: return CGSize(width: 88, height: 61)
        }
    }

    func draw(in bounds: CGRect) {
        switch self {
        case .tree: WinterTreeArtwork.draw(in: bounds, decorations: WinterTreeDecorations())
        case .shovel: WinterArtwork.shovel?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

}

final class WinterToyWindow: NSPanel {
    var onDragBegan: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    var isDragging: Bool { artwork.dragOffset != nil }
    var showsInScreenshots = false {
        didSet { sharingType = showsInScreenshots ? .readOnly : .none }
    }
    var rotation: CGFloat {
        get { artwork.rotation }
        set { artwork.rotation = newValue }
    }
    private let artwork: WinterToyView

    init(frame: CGRect, interactive: Bool, draw: @escaping (CGRect) -> Void) {
        artwork = WinterToyView(frame: CGRect(origin: .zero, size: frame.size), draw: draw)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = !interactive
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        sharingType = .none
        artwork.autoresizingMask = [.width, .height]
        contentView = artwork
        setFrame(frame, display: false)
    }

    func redrawArtwork() { artwork.needsDisplay = true }

    func updateArtwork(_ draw: @escaping (CGRect) -> Void) {
        artwork.paint = draw
        redrawArtwork()
    }

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        FixedSpace.hold(self)
    }

    override func orderOut(_ sender: Any?) {
        artwork.dragOffset = nil
        super.orderOut(sender)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class WinterToyView: NSView {
    var paint: (CGRect) -> Void
    var dragOffset: CGPoint?
    var rotation: CGFloat = 0 { didSet { needsDisplay = true } }

    init(frame: CGRect, draw: @escaping (CGRect) -> Void) {
        paint = draw
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if rotation != 0 {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.midX, yBy: bounds.midY)
            transform.rotate(byRadians: rotation)
            transform.translateX(by: -bounds.midX, yBy: -bounds.midY)
            transform.concat()
        }
        paint(bounds)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragOffset = event.locationInWindow
        (window as? WinterToyWindow)?.onDragBegan?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window as? WinterToyWindow, let dragOffset else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        window.onDrag?(CGPoint(x: pointer.x - dragOffset.x, y: pointer.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard let window = window as? WinterToyWindow, dragOffset != nil else { return }
        mouseDragged(with: event)
        dragOffset = nil
        window.onDragEnded?()
    }
}

/// Одежда продолжает двигаться после разрушения фигуры. Панель пропускает все клики.
final class WinterAccessoryFlight {
    let window: WinterToyWindow
    private let start: CGPoint
    private let direction: CGFloat
    private var elapsed: CGFloat = 0

    init(rect: CGRect, screenOrigin: CGPoint, direction: CGFloat, draw: @escaping () -> Void) {
        self.direction = direction
        start = CGPoint(x: rect.midX + screenOrigin.x, y: rect.midY + screenOrigin.y)
        let side = hypot(rect.width, rect.height) + 2
        window = WinterToyWindow(frame: CGRect(x: start.x - side / 2, y: start.y - side / 2,
                                              width: side, height: side), interactive: false) { bounds in
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.midX - rect.midX, yBy: bounds.midY - rect.midY)
            transform.concat()
            draw()
        }
    }

    func advance(_ dt: TimeInterval) -> Bool {
        elapsed += CGFloat(dt)
        guard elapsed < 0.82 else {
            window.close()
            return false
        }
        let size = window.frame.size
        let x = start.x + direction * 152 * elapsed - size.width / 2
        let y = start.y + elapsed * (140 - 390 * elapsed) - size.height / 2
        window.setFrameOrigin(CGPoint(x: x, y: y))
        window.rotation = direction * (4.6 * elapsed)
        window.alphaValue = min(1, (0.82 - elapsed) / 0.26)
        return true
    }
}
