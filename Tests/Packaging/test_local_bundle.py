import hashlib
import os
import plistlib
import stat
import subprocess
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class LocalBundleTests(unittest.TestCase):
    def test_local_identity_and_no_update_feed(self):
        """Локальное приложение имеет своё имя и не подключает обновления."""
        with (ROOT / "Resources/Info.plist").open("rb") as source:
            info = plistlib.load(source)

        self.assertEqual(info["CFBundleIdentifier"], "dev.nikoko.SeasonArt")
        self.assertEqual(info["CFBundleExecutable"], "SeasonArt")
        self.assertFalse([key for key in info if key.startswith("SU")])
        manifest = (ROOT / "Package.swift").read_text()
        self.assertNotIn("Sparkle", manifest)
        self.assertNotIn(".package(", manifest)


    def test_identity_requires_an_exact_unique_keychain_match(self):
        """Подпись требует точного уникального имени или отпечатка из Keychain."""
        first = "A" * 40
        second = "B" * 40
        with tempfile.TemporaryDirectory() as directory:
            security = Path(directory) / "security"
            security.write_text(f"""#!/bin/bash
cat <<EOF
  1) {first} "Local Dev"
  2) {second} "Duplicate"
  3) {first} "Duplicate"
  3 valid identities found
EOF
""")
            security.chmod(0o755)
            security_control = subprocess.run([str(security)], capture_output=True, text=True)
            self.assertEqual(security_control.returncode, 0, security_control.stderr)
            self.assertEqual(len(security_control.stdout.splitlines()), 4)
            self.assertIn(f'  1) {first} "Local Dev"', security_control.stdout.splitlines())
            for requested, expected in (("Local Dev", first), (first.lower(), first),
                                        ("", None), ("-", None), ("Local", None),
                                        ("Duplicate", None)):
                with self.subTest(identity=requested):
                    environment = dict(os.environ, SEASONART_SIGN_ID=requested,
                                       PATH=directory + os.pathsep + os.environ["PATH"])
                    result = subprocess.run(["bash", str(ROOT / "Scripts/sign.sh"), "--check-identity"],
                                            env=environment, capture_output=True, text=True)
                    if expected:
                        self.assertEqual(result.returncode, 0, result.stderr)
                        self.assertEqual(result.stdout.strip(), expected)
                    else:
                        self.assertNotEqual(result.returncode, 0)

    def test_invalid_identity_preserves_bundle_before_compiling(self):
        """Неизвестная подпись блокирует компиляцию и сохраняет готовую сборку."""
        bundle = ROOT / "build/SeasonArt.app"

        def snapshot():
            return {str(path.relative_to(bundle)): hashlib.sha256(path.read_bytes()).hexdigest()
                    for path in bundle.rglob("*") if path.is_file()}

        before = snapshot()
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "swift-called"
            swift = Path(directory) / "swift"
            swift.write_text("""#!/bin/bash
touch "$SEASONART_TEST_MARKER"
exit 99
""")
            swift.chmod(0o755)
            environment = dict(os.environ, SEASONART_SIGN_ID="SeasonArt nonexistent identity 000000",
                               SEASONART_TEST_MARKER=str(marker),
                               PATH=directory + os.pathsep + os.environ["PATH"])
            control = subprocess.run([str(swift)], env=environment,
                                     capture_output=True, text=True)
            self.assertEqual(control.returncode, 99, control.stderr)
            self.assertTrue(marker.is_file(), "Контрольный запуск Swift должен создавать маркер")
            marker.unlink()
            result = subprocess.run(["bash", str(ROOT / "Scripts/build.sh")],
                                    env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("No valid signing identity", result.stderr)
            self.assertFalse(marker.exists(), "Компиляция не должна запускаться")
        self.assertEqual(snapshot(), before)

    def test_built_bundle_contract(self):
        """Готовая сборка содержит исполняемый файл, метаданные и лицензии."""
        bundle = ROOT / "build/SeasonArt.app"
        if not bundle.exists() and os.environ.get("SEASONART_REQUIRE_BUNDLE") != "1":
            self.skipTest("Для проверки сборки запусти Scripts/build.sh")
        self.assertTrue(bundle.is_dir(), "Обязательная сборка build/SeasonArt.app отсутствует")
        executable = bundle / "Contents/MacOS/SeasonArt"
        self.assertTrue(executable.is_file())
        self.assertTrue(executable.stat().st_mode & stat.S_IXUSR)
        with (bundle / "Contents/Info.plist").open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(info["CFBundleIdentifier"], "dev.nikoko.SeasonArt")
        self.assertEqual(info["CFBundleExecutable"], executable.name)
        self.assertEqual(info["CFBundlePackageType"], "APPL")
        self.assertTrue(info["LSUIElement"])
        self.assertEqual(info["LSMinimumSystemVersion"], "14.0")
        self.assertFalse([key for key in info if key.startswith("SU")])
        self.assertFalse(list(bundle.rglob("*Sparkle*")))
        for name in ("LICENSE", "THIRD_PARTY.md"):
            self.assertEqual((bundle / "Contents/Resources" / name).read_bytes(),
                             (ROOT / name).read_bytes())
        verified = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)],
                                  capture_output=True, text=True)
        self.assertEqual(verified.returncode, 0, verified.stderr)

    def test_bundled_wallpaper_survives_packaging(self):
        """Зимняя иллюстрация входит в бандл без изменения исходных байтов."""
        if not (ROOT / "build/SeasonArt.app").exists() and os.environ.get("SEASONART_REQUIRE_BUNDLE") != "1":
            self.skipTest("Для проверки сборки запусти Scripts/build.sh")
        source = ROOT / "Resources/Wallpapers/winter-lake-v1.png"
        bundled = ROOT / "build/SeasonArt.app/Contents/Resources/Wallpapers/winter-lake-v1.png"
        self.assertTrue(source.is_file(), "Исходное изображение должно существовать")
        self.assertTrue(bundled.is_file(), "Галерея должна работать из установленного приложения")
        self.assertEqual(bundled.read_bytes(), source.read_bytes())
        self.assertEqual(source.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")


if __name__ == "__main__":
    unittest.main()
