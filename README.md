# SeasonArt

SeasonArt – локальное macOS-приложение для Никиты: снег, осенние листья, дождь и цветение поверх рабочего стола и окон. Установленная копия: `~/Applications/SeasonArt.app`. Управление находится в строке меню.

Разработка и использование – личные. Основа – Snowhush, снимок `013f36782e5c6d017725aeb4b2173ae329bf0c6e`. Авторство и PolyForm Noncommercial сохранены в [THIRD_PARTY.md](THIRD_PARTY.md) и [LICENSE](LICENSE).

## Запуск и управление

```bash
open "$HOME/Applications/SeasonArt.app"
```

В меню можно выбрать режим, интенсивность, накопление на окнах и показ поверх полноэкранных приложений. Для текущего fullscreen Space включён пункт «Поверх полноэкранных приложений». Без него эффект скрывается после завершения перехода в такой Space.

В режиме «Снег» открой «Зимние игрушки»: создай большой, средний и маленький шар. Перетащи средний на большой, затем маленький сверху – получится снеговик, который можно переносить целиком. Игрушки падают на снег, Dock и видимые края окон, следуют за окном при движении. Лимит – 12 объектов на экран.

«Убрать снег трактором» запускает проход по видимой горизонтальной полке Dock. Машина сдвигает снег и игрушки на пути. При скрытом или боковом Dock команда недоступна. «Убрать зимние игрушки» удаляет все игрушки и машину. После выхода игрушки не сохраняются.

«Сезонные обои…» открывает превью собственной зимней иллюстрации. Кнопка «Применить на всех экранах» сохраняет её в `~/Library/Application Support/SeasonArt/Wallpapers` и устанавливает на рабочий стол. Открытие и закрытие превью ничего не меняют.

«Выбрать обои…» открывает системный диалог для локального изображения. Применение меняет обои всех подключённых экранов. Отмена сохраняет текущие обои. Автозапуск включается отдельным пунктом меню.

## Сборка и обновление

Нужны Apple Silicon, macOS 14+, Swift 5.9+ и существующая локальная code-signing identity в Keychain. Внешних package dependencies нет. На этом Mac используется `Oasis Dev`.

```bash
cd "$HOME/SeasonArt"
SEASONART_SIGN_ID='Oasis Dev' bash Scripts/build.sh
bash Scripts/install.sh
```

Сборка создаёт подписанный `build/SeasonArt.app`. Установка проверяет бандл, сохраняет предыдущую копию в `build/backups/<MSK-stamp>/SeasonArt.app`, останавливает SeasonArt по точному bundle ID и атомарно заменяет установленный бандл. Затем запускает его по постоянному пути. Настройки хранятся отдельно в домене `dev.nikoko.SeasonArt`.

Для возврата передай точный путь из строки `Backup:` последней установки:

```bash
bash Scripts/rollback.sh "$HOME/SeasonArt/build/backups/<MSK-stamp>/SeasonArt.app"
```

Откат также сохраняет заменяемый бандл. Настройки при откате остаются текущими.

## Проверки

```bash
swift test
SEASONART_REQUIRE_BUNDLE=1 python3 -B -m unittest discover -s Tests/Packaging -v
codesign --verify --deep --strict "$HOME/Applications/SeasonArt.app"
```

На этом Mac sandbox терминала скрывает signing identities и мешает проверке доверия локальной подписи. Проверки сборки, упаковки и подписи выполнялись вне sandbox.

[Журнал MVP](docs/verification/local-run.md) и [проверка зимних сцен](docs/verification/winter-scenes.md) содержат результаты и ограничения. Приёмка окон, Mission Control, fullscreen и системного выбора окна завершена. Сон исключён из приёмки по решению пользователя, внешний монитор не проверен из-за отсутствия оборудования. Приватные снимки рабочего стола и логи лежат в игнорируемой папке `docs/verification/artifacts/`.

## Исследование и план

- [План MVP](docs/superpowers/plans/2026-11-06-seasonart-mvp.md).
- [Спецификация](docs/superpowers/specs/2026-11-06-seasonart-mvp-design.md).
- [Контекст наших macOS-разработок](docs/research/2026-11-06-macos-context.md).
- [Открытые реализации](docs/research/reports/2026-11-06-koiart-open-source-context.html).
- [Разбор KoiArt со скриншотами](docs/research/reports/2026-11-06-koiart-analysis.html).

[Исходник зимней иллюстрации и prompt](Resources/Wallpapers/README.md).
