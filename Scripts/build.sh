#!/bin/bash
set -euo pipefail

seasonart_root="$(cd "$(dirname "$0")/.." && pwd)"
seasonart_build="$seasonart_root/build"
seasonart_staging="$seasonart_build/.SeasonArt-staging.app"
seasonart_ready="$seasonart_build/SeasonArt.app"
seasonart_previous="$seasonart_build/.SeasonArt-previous.app"

# Проверка подписи предшествует компиляции и изменениям готового приложения.
bash "$seasonart_root/Scripts/sign.sh" --check-identity >/dev/null
[[ ! -e "$seasonart_previous" ]] || { printf '%s\n' 'Previous bundle backup already exists; inspect build/.SeasonArt-previous.app.' >&2; exit 1; }
mkdir -p "$seasonart_build"
cleanup() {
    rm -rf "$seasonart_staging"
    if [[ -e "$seasonart_previous" && ! -e "$seasonart_ready" ]]; then
        mv "$seasonart_previous" "$seasonart_ready"
    fi
}
trap cleanup EXIT
rm -rf "$seasonart_staging"
cd "$seasonart_root"
swift build --configuration release --arch arm64
seasonart_binary_dir="$(swift build --configuration release --arch arm64 --show-bin-path)"
mkdir -p "$seasonart_staging/Contents/MacOS" "$seasonart_staging/Contents/Resources"
cp "$seasonart_binary_dir/SeasonArt" "$seasonart_staging/Contents/MacOS/SeasonArt"
cp "$seasonart_root/Resources/Info.plist" "$seasonart_staging/Contents/Info.plist"
cp "$seasonart_root/LICENSE" "$seasonart_root/THIRD_PARTY.md" "$seasonart_staging/Contents/Resources/"
bash "$seasonart_root/Scripts/sign.sh" "$seasonart_staging"
if [[ -e "$seasonart_ready" ]]; then
    mv "$seasonart_ready" "$seasonart_previous"
fi
mv "$seasonart_staging" "$seasonart_ready"
rm -rf "$seasonart_previous"
printf 'Built and signed %s\n' "$seasonart_ready"
