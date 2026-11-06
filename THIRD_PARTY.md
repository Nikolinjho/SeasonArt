# Third-party code

SeasonArt includes macOS source code from [Snowhush](https://github.com/mbezruchko/Snowhush), authored by Mykhailo Bezruchko.

- Upstream commit: `013f36782e5c6d017725aeb4b2173ae329bf0c6e`.
- Imported paths: `Sources/Snowhush` (stored locally as `Sources/SeasonArt`), `Resources/Info.plist`, and `LICENSE`.
- License: PolyForm Noncommercial License 1.0.0. The complete, unchanged license and required notices are preserved in [LICENSE](LICENSE).
- Local modifications: the source directory is renamed to `Sources/SeasonArt`. SeasonArt adds a dependency-free Swift package and uses its own bundle identity, version, welcome text, menu and accessibility labels. Sparkle and its update feed, the upstream sponsor menu, and automatic copying to Applications are removed. The upstream copyright is preserved. SeasonArt also adds packaging checks, a pinned import script, an upstream receipt, and project documentation for personal use.

Keep this notice and `LICENSE` with any local application bundle. Record subsequent changes to the imported code here.

The local controls now offer four Russian-language modes and translated intensity and behavior settings. Automatic Halloween activation and its timer/menu control are disabled. Login registration remains an explicit menu action and reports failures in a native dialog. A SeasonArt About dialog credits the upstream author and links the bundled notices. Preferences support injected isolated profiles for persistence tests, while production uses its own standard bundle domain. The minimal welcome text is translated into Russian.
