# Third-party code

SeasonArt includes macOS source code from [Snowhush](https://github.com/mbezruchko/Snowhush), authored by Mykhailo Bezruchko.

- Upstream commit: `013f36782e5c6d017725aeb4b2173ae329bf0c6e`.
- Imported paths: `Sources/Snowhush` (stored locally as `Sources/SeasonArt`), `Resources/Info.plist`, and `LICENSE`.
- License: PolyForm Noncommercial License 1.0.0. The complete, unchanged license and required notices are preserved in [LICENSE](LICENSE).
- Local modifications: the source directory is renamed to `Sources/SeasonArt`. SeasonArt adds a dependency-free Swift package and uses its own bundle identity, version, welcome text, menu and accessibility labels. Sparkle and its update feed, the upstream sponsor menu, and automatic copying to Applications are removed. The upstream copyright is preserved. SeasonArt also adds packaging checks, a pinned import script, an upstream receipt, and project documentation for personal use.

Keep this notice and `LICENSE` with any local application bundle. Record subsequent changes to the imported code here.

The local controls now offer four Russian-language modes and translated intensity and behavior settings. Automatic Halloween activation and its timer/menu control are disabled. Login registration remains an explicit menu action and reports failures in a native dialog. Licensing information and required notices are included as bundled documents. Preferences support injected isolated profiles for persistence tests, while production uses its own standard bundle domain. The minimal welcome text is translated into Russian.

An explicit “Выбрать обои…” menu action now accepts a single local PNG, JPEG, HEIC, or TIFF image, validates it, and asks macOS to apply it to each connected display. Cancellation leaves the desktop unchanged. Per-display failures are reported in a native alert. Images are neither copied into the project nor applied automatically at launch or display connection. Generated temporary images and injected apply operations cover validation, cancellation, and partial failures without changing the test machine’s desktop.

Local installation scripts now stage and strictly verify the signed SeasonArt bundle before stopping only its own bundle identity. Installation and rollback use an atomic macOS bundle exchange, retain timestamped backups, and restore the previous bundle after verification or registration failures. They target only `~/Applications/SeasonArt.app`, preserve preferences and privacy permissions, and do not enable login launch. Transaction tests use isolated temporary directories.

## Box2D

Snowball physics uses [Box2D](https://github.com/erincatto/box2d) v3.1.0 by Erin Catto, vendored unchanged in `Sources/CBox2D` (`include/box2d`, `src`). Archive SHA-256: `7fac19801485efb31ee3745b2284d9d4601f9e8138a3383a7b0df6d788ea5785`. License: MIT, preserved in [Sources/CBox2D/LICENSE](Sources/CBox2D/LICENSE). The only addition is `include/module.modulemap` for Swift Package Manager.
