import plistlib
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
