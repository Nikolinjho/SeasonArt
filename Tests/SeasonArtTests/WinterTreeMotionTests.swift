import CoreGraphics
import XCTest
@testable import SeasonArt

final class WinterTreeMotionTests: XCTestCase {
    func testСкоростьУдараНеЗависитОтЧастотыКадров() throws {
        for fps in [30.0, 60.0, 120.0] {
            var motion = WinterTreeMotion()
            motion.drop()
            var height: CGFloat = 200
            var impact: CGFloat?
            for _ in 0..<Int(fps) {
                let step = motion.fall(from: height, toward: 40, dt: 1 / fps)
                height = step.height
                if let value = step.impact {
                    impact = value
                    break
                }
            }
            XCTAssertEqual(height, 40, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(impact), 632.456, accuracy: 0.01)
            XCTAssertFalse(motion.isFalling)
        }
    }

    func testОтскокИПошатываниеЗатухают() {
        var motion = WinterTreeMotion()
        motion.drop()
        _ = motion.fall(from: 100, toward: 0, dt: 0.4)
        motion.advanceSpring(dt: 0.09)
        XCTAssertGreaterThan(motion.lift, 1)
        XCTAssertGreaterThan(motion.lean, 0.01)
        motion.advanceSpring(dt: 0.1)
        XCTAssertLessThan(motion.lean, 0)
        motion.advanceSpring(dt: 0.8)
        XCTAssertEqual(motion.lean, 0)
        XCTAssertEqual(motion.lift, 0)
        XCTAssertFalse(motion.isMoving)
    }
}
