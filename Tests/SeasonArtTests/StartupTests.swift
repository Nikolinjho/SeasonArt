import XCTest
@testable import SeasonArt

final class StartupTests: XCTestCase {
    func testFirstInstanceCanLaunch() {
        XCTAssertTrue(StartupGuard.shouldLaunch(currentPID: 100, peers: []), "Первая копия должна запускаться")
    }

    func testCurrentProcessDoesNotBlockItself() {
        XCTAssertTrue(StartupGuard.shouldLaunch(currentPID: 100, peers: [(100, true)]), "Текущий процесс не считается второй копией")
    }

    func testFinishedInstanceBlocksLaunchRegardlessOfPID() {
        XCTAssertFalse(StartupGuard.shouldLaunch(currentPID: 100, peers: [(200, true)]), "Уже запущенная копия сохраняет свои оверлеи")
        XCTAssertFalse(StartupGuard.shouldLaunch(currentPID: 200, peers: [(100, true)]), "PID не влияет на приоритет запущенной копии")
    }

    func testSimultaneousInstancesChooseOneWinner() {
        let peers: [(pid: Int32, finishedLaunching: Bool)] = [(100, false), (200, false)]
        XCTAssertTrue(StartupGuard.shouldLaunch(currentPID: 100, peers: peers), "При одновременном старте выигрывает меньший PID")
        XCTAssertFalse(StartupGuard.shouldLaunch(currentPID: 200, peers: peers), "Вторая копия должна завершиться до создания оверлеев")
    }

    func testUnavailableMetalExplainsStartupFailure() {
        let alert = AppDelegate.startupErrorAlert(.metalUnavailable)
        XCTAssertEqual(alert.messageText, "Не удалось запустить SeasonArt")
        XCTAssertTrue(alert.informativeText.contains("Metal"), "Диалог должен объяснить, почему эффекты недоступны")
        XCTAssertEqual(alert.buttons.first?.title, "Закрыть")
    }

    func testUnavailableScenesExplainStartupFailure() {
        let alert = AppDelegate.startupErrorAlert(.scenesUnavailable)
        XCTAssertEqual(alert.messageText, "Не удалось запустить SeasonArt")
        XCTAssertTrue(alert.informativeText.contains("эффекты"), "Диалог должен объяснить ошибку создания сцен")
        XCTAssertEqual(alert.buttons.first?.title, "Закрыть")
    }
}
