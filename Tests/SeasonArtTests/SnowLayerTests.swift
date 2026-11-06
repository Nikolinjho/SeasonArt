import XCTest
@testable import SeasonArt

final class SnowLayerTests: XCTestCase {
    private func makeLayer() -> SnowLayer {
        SnowLayer(origin: SIMD2(100, 200), columns: 4, columnWidth: 10,
                  depth: 20, opensAtEdges: true, phases: (0, 0))
    }

    func testIndexIncludesLeftEdgeAndExcludesRightEdge() {
        let layer = makeLayer()

        XCTAssertNil(layer.index(at: 99), "Точка перед левым краем не принадлежит слою")
        XCTAssertEqual(layer.index(at: 100), 0, "Левый край принадлежит первому столбцу")
        XCTAssertEqual(layer.index(at: 139.9), 3, "Точка перед правым краем принадлежит последнему столбцу")
        XCTAssertNil(layer.index(at: 140), "Правый край уже лежит за слоем")
    }

    func testIndexFollowsDisplacedSnowAndResizedSupport() {
        let layer = makeLayer()
        layer.offset = SIMD2(15, -5)

        XCTAssertNil(layer.index(at: 114.9), "Сдвинутый слой освобождает прежнюю область")
        XCTAssertEqual(layer.index(at: 115), 0, "Поиск учитывает смещение снега относительно окна")
        XCTAssertEqual(layer.index(at: 154.9), 3)
        XCTAssertNil(layer.index(at: 155))

        layer.resize(columns: 2)

        XCTAssertEqual(layer.index(at: 134.9), 1, "Последний оставшийся столбец доступен после сужения окна")
        XCTAssertNil(layer.index(at: 135), "Удалённые при сужении столбцы больше не принимают снег")
    }

    func testEdgeDepositAccountsForSnowOutsideSupport() {
        let layer = makeLayer()
        let incomingArea: Float = 80

        let missedArea = layer.deposit(incomingArea, at: 100, wide: false)
        let retainedArea = layer.heights.reduce(0, +) * layer.columnWidth

        XCTAssertGreaterThan(missedArea, 0, "Часть снега у открытого края проходит мимо опоры")
        XCTAssertGreaterThan(retainedArea, 0, "Оставшаяся часть оседает на опоре")
        XCTAssertEqual(retainedArea + missedArea, incomingArea, accuracy: 0.001,
                       "Снег у края сохраняет площадь с учётом части за опорой")
        XCTAssertTrue(layer.heights.allSatisfy { $0 >= 0 }, "Оседание не создаёт отрицательную высоту")
    }
}
