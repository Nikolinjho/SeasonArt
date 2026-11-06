# Контекст SeasonArt

## Назначение

SeasonArt – приложение для личного использования Никитой на macOS. Планируется локальная разработка и локальная установка. Платежи, лицензирование пользователей, сервер, аналитика и публичная поставка не входят в задачу.

## Предшествующее исследование

- [Разбор KoiArt](/Users/itsnikoko/SeasonArt/docs/research/reports/2026-11-06-koiart-analysis.html).
- [Открытые реализации и собственная база macOS](/Users/itsnikoko/SeasonArt/docs/research/reports/2026-11-06-koiart-open-source-context.html).
- Снимки прочитанных репозиториев: `/Users/itsnikoko/SeasonArt/docs/research/reports/assets/2026-11-06-koiart-sources`.

Исследование выполнено 6 ноября 2026 года. Чужие приложения не запускались, показатели производительности не воспроизводились.

## Ближайшие реализации

| Проект | Проверенный снимок | Применимость |
|---|---|---|
| [Snowhush](https://github.com/mbezruchko/Snowhush) | `013f36782e5c6d017725aeb4b2173ae329bf0c6e` | Swift, AppKit, Metal. Снег, дождь, листья и сакура. Собственная физика накопления, карта окон и режимы питания |
| [Snowfall](https://github.com/BarredEwe/Snowfall) | `1d3b65a7d873ffb1bff7727bcdb927eb19002702` | SwiftUI, AppKit, Metal compute shaders. Компактнее, но карта окон ограничена одним прямоугольником |
| [Vortex](https://github.com/twostraws/Vortex) | `c9efc55beaf0837a8806f06615085365a3257b6d` | Пресеты частиц на SwiftUI Canvas. Не содержит интеграцию с геометрией чужих окон |
| [MacSnow](https://gitlab.com/heroyik/macsnow) | Прочитан main, SHA не фиксировался | Пример AppKit/SpriteKit. Собственная ограничительная лицензия, не выбирать исходники основой клона |

У текущего Snowhush лицензия PolyForm Noncommercial. Личная модификация для некоммерческого использования соответствует выбранному назначению, текст и обязательные уведомления должны сохраняться. У старого тега `v0.6.1`, коммит `4539daf04d477ac32d110ed5f5468d6255dde916`, отдельно подтверждена MIT. У Snowfall Apache-2.0, у Vortex MIT.

Локальный характер SeasonArt снимает прежнее требование готовить коммерческую поставку. Сам по себе он не требует переписывать существующую физику и интеграцию с окнами.

## Собственная база

### Oasis

Каталог `/Users/itsnikoko/oasis`, проверенный HEAD `ba094db`, [репозиторий](https://github.com/Nikolinjho/oasis).

- `app/Sources/Oasis/NotchPanel.swift` – прозрачный NSPanel, пропуск кликов, уровни окна и Spaces.
- `app/Sources/Oasis/IslandWindowController.swift` – локальные и глобальные события мыши, реальное состояние кнопок, управление фокусом.
- `app/Sources/Oasis/FullscreenMonitor.swift` – реакция на Space, активное приложение и смену экранов.
- `app/Sources/IslandSources/Screen/FullscreenWindows.swift` – координаты AppKit и CoreGraphics.
- `app/Sources/IslandSources/Power/PowerSource.swift` – источник состояния питания.
- `app/Scripts/bundle.sh`, `app/Scripts/install.sh` – локальная сборка и одна установленная копия.

Текущий пакет требует macOS 26. Его нельзя целиком подключить к продукту с заявленной macOS 14 без проверки доступности API. Оригинальный код MIT, сторонние звуки и ассеты имеют отдельные права.

### Speakey, бывший Keyboop

Каталог `/Users/itsnikoko/speakey`, проверенный HEAD `fec242a`, [репозиторий](https://github.com/Nikolinjho/speakey).

- `Sources/Speakey/NotchIsland.swift` – геометрия экрана и порядок настройки уровня панели.
- `Sources/Speakey/VoiceIndicator.swift` – нативный визуальный индикатор.
- `Sources/Speakey/Permissions.swift` – выдача и повторная проверка разрешений.
- `scripts/sign-speakey-app.sh` – постоянная подпись, отсутствие автоматического перехода на ad-hoc.

Использовать отдельный bundle ID SeasonArt. Сохранение доступа у Speakey после подписанных обновлений не доказывает готовность нового приложения. Повторную выдачу разрешений проверять на SeasonArt отдельно.

### Keep You Mac Up

Каталог `/Users/itsnikoko/keepyouawake`, проверенный HEAD `7acc8f1`, [репозиторий](https://github.com/Nikolinjho/keep-you-mac-up).

Полезен опыт локальной поставки и завершения фоновой работы. Низкоуровневое управление крышкой и запретом сна SeasonArt не требуется.

## Практические ограничения

- Один работающий экземпляр и одна установленная копия уменьшают путаницу LaunchServices.
- Локальная подпись с постоянной идентичностью предпочтительнее смены ad-hoc при каждой сборке.
- Команда планирования не запускает сборку, установку или изменение других приложений.
- Сверять текущие исходники с памятью. В Memora есть исторические статусы, которые не описывают актуальный HEAD.

## Треды для проверки поведения

- [Snowfall #3](https://github.com/BarredEwe/Snowfall/issues/3) – неверная привязка накопления к монитору.
- [Snowfall #5](https://github.com/BarredEwe/Snowfall/issues/5) – fullscreen.
- [Snowhush #65](https://github.com/mbezruchko/Snowhush/issues/65) – системный скриншот выбирает слой эффектов.
- [Snowhush #51](https://github.com/mbezruchko/Snowhush/pull/51) – снег на миниатюрах Mission Control.
- [Snowhush #84](https://github.com/mbezruchko/Snowhush/pull/84) – остаточный снег после переноса Dock между экранами.

Открытый PR не считать частью зафиксированной версии. Указанные исправления проверять по составу выбранного снимка и живому поведению.
