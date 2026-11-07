import AppKit
import XCTest
@testable import SeasonArt

final class WinterSnowmanArmsTests: XCTestCase {
    private func object(_ radii: [CGFloat]) -> WinterObject {
        WinterObject(id: UUID(), radii: radii, center: CGPoint(x: 150, y: 50), velocity: .zero,
                     support: nil, parked: false, isDragged: false)
    }

    func testВеткиЕстьТолькоУГотовогоСнеговика() {
        for radii: [CGFloat] in [[28], [28, 21]] {
            let ball = object(radii)
            XCTAssertTrue(ball.arms.isEmpty)
            XCTAssertEqual(ball.presentationFrame, ball.frame)
        }
        XCTAssertFalse(object([28, 21, 14]).arms.isEmpty)
    }

    func testВеткиВмещаютсяВОкноПриЛюбомРазмереСреднегоШара() {
        _ = NSApplication.shared
        for radii: [CGFloat] in [[28, 21, 14], [6, 36, 6], [36, 6, 36]] {
            let model = object(radii)
            let body = model.frame
            let screen = CGRect(x: -800, y: 120, width: 800, height: 600)
            let window = WinterObjectWindow(object: model, screenFrame: screen)
            defer { window.close() }
            let expected = model.presentationFrame.offsetBy(dx: screen.minX, dy: screen.minY)
            XCTAssertEqual(window.frame.minX, expected.minX, accuracy: 1)
            XCTAssertEqual(window.frame.minY, expected.minY, accuracy: 1)
            XCTAssertEqual(window.frame.width, expected.width, accuracy: 1)
            XCTAssertEqual(window.frame.height, expected.height, accuracy: 1)
            XCTAssertEqual(model.frame, body, "Декоративные ветки не расширяют физические столкновения")
            for point in model.arms.flatMap({ $0 }) {
                XCTAssertTrue(model.drawingBounds.insetBy(dx: model.armLineWidth / 2, dy: model.armLineWidth / 2).contains(point),
                              "Ветка со скруглённым концом не обрезается краем окна")
            }
            XCTAssertFalse(window.isVisible)
            XCTAssertFalse(window.canBecomeKey)
        }
    }
}
