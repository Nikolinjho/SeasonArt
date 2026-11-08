import XCTest
@testable import SeasonArt

final class PreferencesTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        suiteNames.removeAll()
        Preferences.configure(defaults: .standard)
        super.tearDown()
    }

    private func makeProfile() -> (String, UserDefaults) {
        let name = "SeasonArtTests.\(UUID().uuidString)"
        suiteNames.append(name)
        return (name, UserDefaults(suiteName: name)!)
    }

    func testModeAndIntensitySurviveReopeningProfile() {
        let (name, defaults) = makeProfile()
        Preferences.configure(defaults: defaults)
        Preferences.registerDefaults()
        Preferences.mode = .blossom
        Preferences.snowfall = .heavy
        defaults.synchronize()

        Preferences.configure(defaults: UserDefaults(suiteName: name)!)
        Preferences.registerDefaults()

        XCTAssertEqual(Preferences.mode, .blossom, "Режим должен сохраняться после открытия профиля")
        XCTAssertEqual(Preferences.snowfall, .heavy, "Интенсивность должна сохраняться после открытия профиля")
    }

    func testПропускСнегаУСтрокиМенюВключёнПоУмолчаниюИСохраняется() {
        let (name, defaults) = makeProfile()
        Preferences.configure(defaults: defaults)
        Preferences.registerDefaults()
        XCTAssertTrue(Preferences.skipSnowNearMenuBar)
        Preferences.skipSnowNearMenuBar = false
        defaults.synchronize()
        Preferences.configure(defaults: UserDefaults(suiteName: name)!)
        Preferences.registerDefaults()
        XCTAssertFalse(Preferences.skipSnowNearMenuBar)
    }

    func testNewProfileDoesNotInheritOtherProfileSettings() {
        let (_, first) = makeProfile()
        Preferences.configure(defaults: first)
        Preferences.registerDefaults()
        Preferences.mode = .rain
        Preferences.snowfall = .off
        Preferences.behindWindows = true

        let (_, second) = makeProfile()
        Preferences.configure(defaults: second)
        Preferences.registerDefaults()

        XCTAssertEqual(Preferences.mode, .snow, "Новый профиль начинает со снега")
        XCTAssertNotEqual(Preferences.snowfall, .off, "Новый профиль не наследует выключенные осадки")
        XCTAssertFalse(Preferences.behindWindows, "Настройки окон из другого профиля не наследуются")
    }

    func testAllModesAndIntensityOptionsPersist() {
        let (_, defaults) = makeProfile()
        Preferences.configure(defaults: defaults)
        for mode: Mode in [.snow, .rain, .autumn, .blossom, .fireflies, .starfall] {
            Preferences.mode = mode
            XCTAssertEqual(Preferences.mode, mode, "Каждый режим должен сохраняться")
        }
        for intensity in Snowfall.allCases {
            Preferences.snowfall = intensity
            XCTAssertEqual(Preferences.snowfall, intensity, "Каждая интенсивность должна сохраняться")
        }
    }

    func testLoginFailureExplainsSystemErrorWithoutRegisteringService() {
        let error = NSError(domain: "SeasonArtTests", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Нет разрешения системы"])
        let alert = AppDelegate.loginErrorAlert(error)
        XCTAssertEqual(alert.messageText, "Не удалось изменить автозапуск", "Ошибка должна быть видна пользователю")
        XCTAssertTrue(alert.informativeText.contains(error.localizedDescription), "Диалог должен объяснять причину ошибки")
    }
}
