import AppKit

@MainActor
final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        level = .mainMenu
        isReleasedWhenClosed = false
    }

    func apply(levelMode: OverlayLevelMode) {
        switch levelMode {
        case .normal:
            level = .mainMenu
        case .fullscreenFriendly:
            level = .floating
        case .aboveMenu:
            level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        }
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
