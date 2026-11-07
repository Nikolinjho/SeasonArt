import XCTest
import AppKit
@testable import SeasonArt

final class WinterSceneTests: XCTestCase {
    private func surface(_ id: CGWindowID = 1, x: CGFloat = 100, y: CGFloat = 200, width: CGFloat = 300, blockers: [CGRect] = []) -> WindowSurface {
        WindowSurface(id: id, frame: CGRect(x: x, y: y - 100, width: width, height: 100), blockers: blockers, cover: [], cornerRadius: 0, cornerExponent: 2.5, isDock: false)
    }

    private func update(_ surfaces: [WindowSurface], parked: Set<CGWindowID> = [], elsewhere: Set<CGWindowID> = []) -> WindowUpdate {
        WindowUpdate(surfaces: surfaces, interval: 0.1, parked: parked, elsewhere: elsewhere, sliding: false, slideVelocity: 0)
    }

    private func settle(_ scene: WinterScene) {
        for _ in 0..<300 { scene.step(dt: 1.0 / 60) }
    }

    func testFallsOnHighestVisibleSurfaceAndSleeps() throws {
        let scene = WinterScene(width: 800, height: 600)
        scene.updateWindows(update([surface(1, y: 200), surface(2, y: 300)]))
        _ = scene.create(.large, at: CGPoint(x: 200, y: 500))
        settle(scene)
        let ball = try XCTUnwrap(scene.objects.first)
        XCTAssertEqual(ball.support, 2, "Шар должен лежать на самой высокой доступной опоре")
        XCTAssertEqual(ball.frame.minY, 300, accuracy: 0.01)
        XCTAssertFalse(scene.isMoving, "Неподвижной сцене не нужен непрерывный таймер")
    }

    func testBlockerPreventsLandingOnHiddenWindowEdge() {
        let scene = WinterScene(width: 800, height: 600)
        scene.updateWindows(update([surface(blockers: [CGRect(x: 100, y: 180, width: 300, height: 80)])]))
        _ = scene.create(.small, at: CGPoint(x: 200, y: 400))
        settle(scene)
        XCTAssertNil(scene.objects[0].support, "Перекрытый край окна не служит опорой")
        XCTAssertEqual(scene.objects[0].frame.minY, 0, accuracy: 0.01)
    }

    func testSnowHeightAndLargeTimeStep() {
        let scene = WinterScene(width: 800, height: 600)
        scene.surfaceHeight = { _, _ in 30 }
        _ = scene.create(.medium, at: CGPoint(x: 200, y: 500))
        scene.step(dt: 100)
        XCTAssertGreaterThan(scene.objects[0].center.y, 490, "После паузы шаг ограничен")
        settle(scene)
        XCTAssertEqual(scene.objects[0].frame.minY, 30, accuracy: 0.01)
    }

    func testWindowMovementClosureAndParking() {
        let scene = WinterScene(width: 800, height: 600)
        scene.updateWindows(update([surface()]))
        _ = scene.create(.large, at: CGPoint(x: 200, y: 400))
        settle(scene)
        scene.updateWindows(update([surface(x: 150, y: 230)]))
        XCTAssertEqual(scene.objects[0].center, CGPoint(x: 250, y: 258), "Шар следует за окном")
        scene.updateWindows(update([], elsewhere: [1]))
        XCTAssertTrue(scene.objects[0].parked)
        settle(scene)
        XCTAssertEqual(scene.objects[0].center.y, 258)
        scene.updateWindows(update([], parked: [1]))
        XCTAssertTrue(scene.objects[0].parked)
        scene.updateWindows(update([surface(x: 150, y: 230)]))
        XCTAssertFalse(scene.objects[0].parked)
        scene.updateWindows(update([]))
        settle(scene)
        XCTAssertNil(scene.objects[0].support, "После закрытия окна шар падает на землю")
        XCTAssertEqual(scene.objects[0].frame.minY, 0, accuracy: 0.01)
    }

    func testParkedSurfaceCannotCatchOtherObjects() {
        let scene = WinterScene(width: 800, height: 600)
        scene.updateWindows(update([surface()]))
        _ = scene.create(.large, at: CGPoint(x: 200, y: 400))
        settle(scene)
        scene.updateWindows(update([], elsewhere: [1]))
        _ = scene.create(.small, at: CGPoint(x: 250, y: 400))
        settle(scene)
        XCTAssertTrue(scene.objects[0].parked)
        XCTAssertFalse(scene.isMoving, "Припаркованная игрушка не требует анимации")
        XCTAssertNil(scene.objects[1].support, "Невидимое окно не ловит новые шары")
        XCTAssertEqual(scene.objects[1].frame.minY, 0, accuracy: 0.01)
    }

    func testResizeClampsSupportAndScreen() {
        let scene = WinterScene(width: 800, height: 600)
        scene.updateWindows(update([surface()]))
        _ = scene.create(.large, at: CGPoint(x: 380, y: 400))
        settle(scene)
        scene.updateWindows(update([surface(width: 100)]))
        XCTAssertLessThanOrEqual(scene.objects[0].frame.maxX, 200, "При сужении окна шар остаётся над опорой")
        scene.resize(width: 150, height: 400)
        XCTAssertLessThanOrEqual(scene.objects[0].frame.maxX, 150)
        settle(scene)
        XCTAssertNil(scene.objects[0].support, "Опора вне границ экрана отпускает шар")
    }

    func testHeightResizeDetachesSupportThatCannotKeepObjectVisible() {
        for supportY: CGFloat in [220, 300] {
            let scene = WinterScene(width: 800, height: 600)
            scene.updateWindows(update([surface(y: supportY)]))
            _ = scene.create(.large, at: CGPoint(x: 200, y: 500))
            settle(scene)
            XCTAssertEqual(scene.objects[0].support, 1)
            scene.resize(width: 800, height: 250)
            XCTAssertNil(scene.objects[0].support, "Опора без места для фигуры отпускает шар")
            XCTAssertTrue(scene.isMoving, "После уменьшения высоты шар продолжает падение")
            XCTAssertLessThanOrEqual(scene.objects[0].frame.maxY, 250, "Шар остаётся в видимой области")
            scene.updateWindows(update([surface(y: supportY)]))
            settle(scene)
            XCTAssertNil(scene.objects[0].support, "Недоступная по высоте опора не захватывает шар повторно")
            XCTAssertEqual(scene.objects[0].frame.minY, 0, accuracy: 0.01)
        }
    }

    func testOrderedAssemblyKeepsBaseIdentityAndFrame() throws {
        let scene = WinterScene(width: 800, height: 600)
        let base = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 200, y: 28)))
        settle(scene)
        for size in [WinterBallSize.medium, .small] {
            let y = try XCTUnwrap(scene.objects.first).frame.maxY + size.radius
            let id = try XCTUnwrap(scene.create(size, at: CGPoint(x: 400, y: 400)))
            scene.beginDragging(id, at: CGPoint(x: 400, y: 400))
            scene.drag(id, to: CGPoint(x: 200, y: y), dt: 0.1)
            scene.endDragging(id, idleTime: 0.2)
        }
        XCTAssertEqual(scene.objects.count, 1, "Сборка удаляет отдельные шары")
        XCTAssertEqual(scene.objects[0].id, base)
        XCTAssertEqual(scene.objects[0].radii, [28, 21, 14])
        XCTAssertTrue(scene.objects[0].isSnowman)
        XCTAssertEqual(scene.objects[0].frame, CGRect(x: 172, y: 0, width: 56, height: 115.5),
                       "Шары слегка перекрываются в местах соединения, основание остаётся на опоре")
    }

    func testМаленькийШарНаБольшомОбразуетСтопку() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 200, y: 28))
        let id = try XCTUnwrap(scene.create(.small, at: CGPoint(x: 200, y: 70)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 70))
        scene.endDragging(id)
        XCTAssertEqual(scene.objects.count, 1, "Любые два размера образуют стопку")
        let medium = try XCTUnwrap(scene.create(.medium, at: CGPoint(x: 240, y: 77)))
        scene.beginDragging(medium, at: CGPoint(x: 240, y: 77))
        scene.endDragging(medium)
        XCTAssertEqual(scene.objects.count, 2, "Слишком далёкий шар не притягивается к стеку")
    }

    func testDragOffsetHeldGravityAndThrowCap() throws {
        let scene = WinterScene(width: 800, height: 600)
        let id = try XCTUnwrap(scene.create(.large, at: CGPoint(x: 200, y: 300)))
        scene.beginDragging(id, at: CGPoint(x: 210, y: 310))
        scene.drag(id, to: CGPoint(x: 610, y: 510), dt: 0.001)
        XCTAssertEqual(scene.objects[0].center, CGPoint(x: 600, y: 500), "Захват сохраняет смещение указателя")
        scene.step(dt: 1)
        XCTAssertEqual(scene.objects[0].center.y, 500, "Удерживаемый шар не падает")
        scene.endDragging(id)
        let velocity = scene.objects[0].velocity
        XCTAssertLessThanOrEqual(hypot(velocity.dx, velocity.dy), 900.001, "Бросок ограничен по полной скорости")
    }

    func testRepeatedCaptureDoesNotMergeBeforeRelease() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(.large, at: CGPoint(x: 200, y: 28))
        let id = try XCTUnwrap(scene.create(.medium, at: CGPoint(x: 200, y: 77)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 77))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 77))
        XCTAssertEqual(scene.objects.count, 2, "Повторный захват не завершает перетаскивание")
        scene.endDragging(id)
        scene.endDragging(id)
        XCTAssertEqual(scene.objects.count, 1, "Повторное отпускание не дублирует сборку")
    }

    func testLimitClearAndVehiclePush() throws {
        let scene = WinterScene(width: 800, height: 600)
        for _ in 0..<WinterScene.maximumObjects { XCTAssertNotNil(scene.create(.small, at: CGPoint(x: 100, y: 14))) }
        XCTAssertNil(scene.create(.small, at: .zero), "Предохранительный лимит учитывает все игрушки")
        let id = try XCTUnwrap(scene.objects.first?.id)
        scene.beginDragging(id, at: CGPoint(x: 100, y: 14))
        scene.removeAll()
        scene.drag(id, to: .zero, dt: 0.1)
        XCTAssertTrue(scene.objects.isEmpty)
        XCTAssertFalse(scene.isMoving)
        _ = scene.create(.large, at: CGPoint(x: 50, y: 28))
        _ = scene.create(.small, at: CGPoint(x: 400, y: 14))
        scene.shoveObjects(in: CGRect(x: 0, y: 0, width: 100, height: 80), by: -100)
        XCTAssertEqual(scene.objects.count, 1, "Отвал удаляет только полностью вытолкнутые объекты")
        XCTAssertEqual(scene.objects[0].center.x, 400)
    }
    func testФактическиеРадиусыИНекорректнаяГеометрия() throws {
        let scene = WinterScene(width: 800, height: 600)
        for radius: CGFloat in [6, 9.25, 18.5, 29.75, 36] {
            XCTAssertNotNil(scene.create(radius: radius, at: CGPoint(x: 200, y: 200)))
            XCTAssertEqual(scene.objects.last?.radii, [radius])
            XCTAssertEqual(scene.objects.last?.frame.width, radius * 2)
        }
        for radius: CGFloat in [0, -1, 5.99, 36.01, .nan, .infinity] {
            XCTAssertNil(scene.create(radius: radius, at: .zero))
        }
        XCTAssertNil(scene.create(radius: 14, at: CGPoint(x: CGFloat.nan, y: 20)))
        XCTAssertEqual(WinterBallSize.allCases.map(\.radius), [14, 21, 28])
    }

    func testЛюбыеТриРадиусаСохраняютОснованиеИПерекрытие() throws {
        for radii: [CGFloat] in [[6, 17.25, 36], [14, 14, 14], [36, 9.5, 23.75], [36, 36, 36]] {
            let scene = WinterScene(width: 800, height: 600)
            let base = try XCTUnwrap(scene.create(radius: radii[0], at: CGPoint(x: 200, y: radii[0])))
            settle(scene)
            for radius in radii.dropFirst() {
                let top = try XCTUnwrap(scene.objects.first).frame.maxY
                let id = try XCTUnwrap(scene.create(radius: radius, at: CGPoint(x: 200, y: top + radius)))
                scene.beginDragging(id, at: CGPoint(x: 200, y: top + radius))
                scene.endDragging(id, idleTime: 0.2)
                XCTAssertEqual(scene.objects.count, 1)
                XCTAssertEqual(scene.objects[0].isSnowman, scene.objects[0].radii.count == 3)
            }
            let object = try XCTUnwrap(scene.objects.first)
            XCTAssertEqual(object.id, base)
            XCTAssertEqual(object.radii, radii)
            XCTAssertEqual(object.frame.minY, 0)
            XCTAssertEqual(object.frame.width, try XCTUnwrap(radii.max()) * 2)
            for index in 1..<3 {
                XCTAssertEqual(object.ballFrames[index - 1].maxY - object.ballFrames[index].minY,
                               min(radii[index - 1], radii[index]) * 0.3, accuracy: 0.0001)
            }
        }
    }

    func testНетКонтактаПоВертикалиШарыНеСоединяются() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 9.5, at: CGPoint(x: 200, y: 9.5))
        let id = try XCTUnwrap(scene.create(radius: 31.25, at: CGPoint(x: 200, y: 100)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 100))
        scene.endDragging(id)
        XCTAssertEqual(scene.objects.count, 2)
    }

    func testУкрашенияМасштабируютсяПоСвоимШарам() throws {
        let small = WinterObject(id: UUID(), radii: [6, 6, 6], center: CGPoint(x: 100, y: 6),
                                 velocity: .zero, support: nil, parked: false, isDragged: false)
        let large = WinterObject(id: UUID(), radii: [36, 36, 36], center: CGPoint(x: 100, y: 36),
                                 velocity: .zero, support: nil, parked: false, isDragged: false)
        let a = try XCTUnwrap(small.decoration)
        let b = try XCTUnwrap(large.decoration)
        XCTAssertEqual(b.eyes[0].width / a.eyes[0].width, 6, accuracy: 0.001)
        XCTAssertEqual(b.buttons[0].width / a.buttons[0].width, 6, accuracy: 0.001)
        XCTAssertEqual(b.scarf[0].width / a.scarf[0].width, 6, accuracy: 0.001)
        let mixed = WinterObject(id: UUID(), radii: [36, 6, 18], center: CGPoint(x: 100, y: 36),
                                 velocity: .zero, support: nil, parked: false, isDragged: false)
        let details = try XCTUnwrap(mixed.decoration)
        XCTAssertEqual(details.eyes[0].width / a.eyes[0].width, 3, accuracy: 0.001)
        XCTAssertEqual(details.buttons[0].width, a.buttons[0].width)
        XCTAssertEqual(details.buttons[2].width, b.buttons[2].width)
        XCTAssertTrue(details.eyes.allSatisfy { mixed.ballFrames[2].contains($0) })
        XCTAssertTrue(details.buttons.prefix(2).allSatisfy { mixed.ballFrames[1].contains($0) })
    }

    func testМаленькиеШарыЧерезЗазорНеПритягиваются() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 6, at: CGPoint(x: 200, y: 6))
        let id = try XCTUnwrap(scene.create(radius: 6, at: CGPoint(x: 200, y: 33)))
        scene.beginDragging(id, at: CGPoint(x: 200, y: 33))
        scene.endDragging(id)
        XCTAssertEqual(scene.objects.count, 2, "Зазор больше диаметра маленького шара не считается контактом")
    }

    func testКонтактРазрешаетПерекрытиеГотовогоСтыкаКрупныхШаров() throws {
        let scene = WinterScene(width: 800, height: 600)
        _ = scene.create(radius: 36, at: CGPoint(x: 200, y: 36))
        let point = CGPoint(x: 200, y: 72 + 36 - 36 * 0.3)
        let id = try XCTUnwrap(scene.create(radius: 36, at: point))
        scene.beginDragging(id, at: point)
        scene.endDragging(id)
        XCTAssertEqual(scene.objects.count, 1)
        XCTAssertEqual(scene.objects[0].radii, [36, 36])
    }

}
