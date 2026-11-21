import AppKit
import XCTest
@testable import SeasonArt

final class WinterDecorationsTests: XCTestCase {
    func testГирляндаОграниченаВидимымКраемОкнаFinder() throws {
        let screen = CGRect(x: -800, y: 100, width: 800, height: 600)
        let frame = CGRect(x: 100, y: 100, width: 400, height: 280)
        let overlap = CGRect(x: 200, y: 200, width: 100, height: 220)
        var surface = WindowSurface(id: 42, frame: frame, blockers: [], cover: [overlap],
                                    cornerRadius: 20, cornerExponent: 2.5, isDock: false)
        XCTAssertNil(FinderGarlandLayout(surface: surface, screen: screen))
        surface.isFinder = true
        let layout = try XCTUnwrap(FinderGarlandLayout(surface: surface, screen: screen))
        XCTAssertEqual(layout.frame, CGRect(x: -680, y: 456, width: 360, height: 24))
        XCTAssertEqual(layout.visibleRanges, [0..<80, 180..<360])
    }

    func testСаниПоднимаютсяИОпускаютсяПоПутиЧерезЭкран() {
        let screen = CGRect(x: -800, y: 100, width: 800, height: 600)
        var animation = WinterSleighPass(screen: screen)
        XCTAssertEqual(animation.frame.maxX, screen.minX, accuracy: 0.001)
        let baseline = animation.frame.minY
        animation.advance(.pi / 3.6)
        XCTAssertGreaterThan(animation.frame.minY, baseline + 25)
        animation.advance(.pi / 1.8)
        XCTAssertLessThan(animation.frame.minY, baseline - 25)
        animation.advance(animation.duration)
        XCTAssertTrue(animation.finished)
        XCTAssertGreaterThan(animation.frame.minX, screen.maxX)
    }

    func testСнеговикСмотритНаУказательТолькоПоблизости() {
        let head = CGPoint(x: 20, y: 45)
        let gaze = WinterSnowmanGaze.target(from: head, toward: CGPoint(x: 60, y: 20), headWidth: 28)
        XCTAssertGreaterThan(gaze.x, 0.5)
        XCTAssertLessThan(gaze.y, -0.3)
        XCTAssertEqual(WinterSnowmanGaze.target(from: head, toward: CGPoint(x: 120, y: 45), headWidth: 28), .zero)
    }

    func testОформлениеЁлкиМеняетсяЧерезЭлементыРедактора() throws {
        _ = NSApplication.shared
        var applied: WinterTreeDecorations?
        let editor = WinterTreeEditor(settings: WinterTreeDecorations(), apply: { applied = $0 }, remove: {})
        defer { editor.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = try XCTUnwrap(editor.window?.contentView)
        let tabs = try XCTUnwrap(descendants(content).compactMap { $0 as? NSSegmentedControl }.first {
            $0.segmentCount == 2 && $0.label(forSegment: 1) == "Украшения"
        })
        tabs.selectedSegment = 1
        XCTAssertTrue(tabs.sendAction(tabs.action, to: tabs.target))
        let buttons = descendants(content).compactMap { $0 as? NSButton }
        let candy = try XCTUnwrap(buttons.first { $0.title == "Леденцы" })
        candy.performClick(nil)
        XCTAssertEqual(applied?.ornaments, [.baubles, .lights, .candy])
        candy.performClick(nil)
        XCTAssertEqual(applied?.ornaments, [.baubles, .lights])
    }
}
