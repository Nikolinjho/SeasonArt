# SeasonArt 0.1.6

9 ноября 2026, MSK. Версия 0.1.6, build 7. Релиз объединяет метель, снег по контурам иконок и бейджей Dock, сохранение сугроба при наведении, положение снега над Dock или под ним и повреждения снежков.

## Проверки

- `swift test --disable-sandbox`: 280 тестов, 0 ошибок, без пропусков. Лог: `/tmp/seasonart-release-0.1.6-tests.log`.
- `SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh`: код 0. Лог: `/tmp/seasonart-release-0.1.6-build.log`.
- `SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v`: 19 тестов, OK. Лог: `/tmp/seasonart-release-0.1.6-packaging.log`.
- Архив `build/releases/0.1.6/SeasonArt-0.1.6-macOS-arm64.zip` распакован. `codesign --verify --deep --strict` для распакованного приложения завершился с кодом 0.
- Версия и build распакованного приложения совпадают с исходными метаданными. Его бинарник побайтово совпадает с `build/SeasonArt.app`.
- SHA-256 бинарника: `77eead0edf706354e3e99f4ac0f8be54683ad2745a3b9576153022293f00517d`.
- `shasum -a 256 -c SeasonArt-0.1.6-macOS-arm64.zip.sha256`: OK.
- Контрольные суммы Swift-исходников и Info.plist после сборки совпали с сохранённым снимком.

## Ограничения

Редкая полоса снега над строкой ввода Codex остаётся открытым багом. Временная диагностика `SnowSheddingTrace` и её вызовы исключены из релизных исходников. Локальная копия и прежний diff сохранены в игнорируемом каталоге `docs/verification/artifacts/release-0.1.6/`.

Нативные проверки предыдущих сборок описаны в `dock-hover-jump.md` и `dock-badge-snow.md`. Нового управления указателем при подготовке релиза не было. Живая приёмка снега на бейджах, Sequoia и внешний монитор остаются непроверенными. Установленная копия приложения и настройки при подготовке архива не менялись.
