import XCTest
@testable import SeasonArt

final class DockColumnMapTests: XCTestCase {
    private let map = DockColumnMap(body: 100...400, presentation: 60...460,
                                    restCenters: [150, 250, 350], presentedCenters: [140, 300, 420])

    func testЦентрИконкиОстаётсяНадТойЖеИконкой() throws {
        let map = try XCTUnwrap(map)
        XCTAssertEqual(map.base(atPresented: 300), 250, accuracy: 0.001, "Снег над увеличенной иконкой берётся с неё же")
        XCTAssertEqual(map.base(atPresented: 60), 100, accuracy: 0.001)
        XCTAssertEqual(map.base(atPresented: 460), 400, accuracy: 0.001)
        XCTAssertEqual(map.base(atPresented: 220), 200, accuracy: 0.001, "Между иконками отображение линейно")
    }

    func testПересэмплированиеПереноситСугробСИконкой() throws {
        let map = try XCTUnwrap(map)
        // 30 колонок по 10 pt на корпусе 100...400, сугроб только над второй иконкой.
        var values = [Float](repeating: 0, count: 60)
        for i in 14...15 { values[i] = 20 }
        map.resample(&values, count: 30)
        let presentedColumn: Float = 400 / 30
        let peak = (0..<30).max { values[$0] < values[$1] }!
        let x = 60 + (Float(peak) + 0.5) * presentedColumn
        XCTAssertEqual(x, 300, accuracy: presentedColumn, "Вершина сугроба остаётся над увеличенной иконкой")
    }

    func testБезСнимкаПокояОтображенияНет() {
        XCTAssertNil(DockColumnMap(body: 100...400, presentation: 60...460, restCenters: [150, 250],
                                   presentedCenters: [140, 300, 420]))
    }
}
