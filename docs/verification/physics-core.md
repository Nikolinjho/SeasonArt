# Ядро физики

10 ноября 2026, MSK. Ветка `feat/physics-core`, спека `docs/superpowers/specs/2026-11-10-physics-core-design.md`.

## Проверки

- `swift test` с доступом к WindowServer и Metal: 310 тестов, 0 ошибок.
- `SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh`: код 0, `codesign --verify --deep --strict build/SeasonArt.app` прошёл.
- `SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging`: 19 тестов, OK.
- Замер release, 64 шара, медиана шага: падение 1,48 → 0,08 мс, покой 1,51 → 0,015 мс (master против ветки, одинаковый сценарий, временный тест удалён).

## Новые регрессии

- `WinterTimeTests`: догонка длинного кадра, предел 0,25 с, стоимость покоя.
- `WinterContactTests`: шар в руке не проходит насквозь, свободное место при создании, шар сверху без места, смещённый шар лежит спокойно, сильно смещённый скатывается с вращением.
- `DockColumnMapTests`: снег над увеличенной иконкой берётся с неё же.
- `DockGroundDisplacementTests.testОтодвинутыйСнегНеСтекаетОбратноПодDock`.
- `SnowRelaxTimingTests`: склон оседает одинаково при 30 и 60 кадрах.

## Ограничения

Живое наведение на Dock, лепка и перетаскивание в установленном приложении не проверялись. Установка не выполнялась. Приземление хлопьев на полку во время увеличения считается в обычной раскладке.
