import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

MODULE = Path(__file__).resolve().parents[2] / 'Scripts' / 'installation.py'


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(MODULE.exists(), 'Отсутствует реализация безопасной установки')
        spec = importlib.util.spec_from_file_location('installation', MODULE)
        self.installation = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.installation)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'build' / 'SeasonArt.app'
        self.destination = self.root / 'Applications' / 'SeasonArt.app'
        self.backups = self.root / 'build' / 'backups'
        for bundle, value in [(self.source, 'new'), (self.destination, 'old')]:
            bundle.mkdir(parents=True)
            (bundle / 'version').write_text(value)
        self.stops = []

    def validate(self, bundle):
        if (bundle / 'version').read_text() == 'bad':
            raise ValueError('invalid signature or identity')

    def install(self, **kwargs):
        return self.installation.install(self.source, self.destination, self.backups,
                                         validate=self.validate,
                                         stop=lambda: self.stops.append('stop'),
                                         register=lambda path: None, **kwargs)

    def test_success_keeps_previous_bundle_in_backup(self):
        backup = self.install()
        self.assertEqual((backup / 'version').read_text(), 'old')
        self.assertEqual((self.destination / 'version').read_text(), 'new')
        self.assertEqual(self.stops, ['stop'])

    def test_invalid_source_does_not_stop_or_replace(self):
        (self.source / 'version').write_text('bad')
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(self.stops, [])
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_partial_copy_preserves_previous_bundle(self):
        def broken_copy(source, target):
            target.mkdir()
            raise OSError('copy failed')
        with self.assertRaises(OSError):
            self.install(copy=broken_copy)
        self.assertEqual(self.stops, [])
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_swap_failure_preserves_previous_bundle(self):
        with self.assertRaises(OSError):
            self.install(exchange=lambda a, b: (_ for _ in ()).throw(OSError('swap failed')))
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_failed_post_install_verification_restores_previous_bundle(self):
        original = self.validate
        def validate(path):
            original(path)
            if path == self.destination and (path / 'version').read_text() == 'new':
                raise ValueError('post-install failed')
        self.validate = validate
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_stop_failure_preserves_previous_bundle(self):
        with self.assertRaises(RuntimeError):
            self.installation.install(self.source, self.destination, self.backups,
                validate=self.validate, stop=lambda: (_ for _ in ()).throw(RuntimeError('still running')),
                register=lambda path: None)
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_rollback_registration_failure_preserves_current_install(self):
        backup = self.install()
        def register(path):
            raise RuntimeError('registration failed')
        with self.assertRaises(RuntimeError):
            self.installation.install(backup, self.destination, self.backups,
                validate=self.validate, stop=lambda: None, register=register)
        self.assertEqual((self.destination / 'version').read_text(), 'new')
        self.assertEqual((backup / 'version').read_text(), 'old')

    def test_rollback_rejects_outside_traversal_and_symlinks(self):
        backup = self.install()
        for candidate in [self.source, self.backups / '..' / 'SeasonArt.app']:
            with self.assertRaises(ValueError):
                self.installation.rollback_source(candidate, self.backups)
        alias = self.backups / 'alias'
        alias.symlink_to(backup.parent, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.installation.rollback_source(alias / 'SeasonArt.app', self.backups)
        self.assertEqual(self.installation.rollback_source(backup, self.backups), backup)

    def test_invalid_staged_copy_does_not_stop_or_replace(self):
        def corrupt_copy(source, target):
            shutil.copytree(source, target)
            (target / 'version').write_text('bad')
        with self.assertRaises(ValueError):
            self.install(copy=corrupt_copy)
        self.assertEqual(self.stops, [])
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_backup_copy_failure_does_not_stop_or_replace(self):
        def fail_backup(source, target):
            if target.parent.parent == self.backups:
                raise OSError('backup copy failed')
            return shutil.copytree(source, target)
        with self.assertRaises(OSError):
            self.install(copy=fail_backup)
        self.assertEqual(self.stops, [])
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_restore_failure_retains_adjacent_old_bundle_and_backup(self):
        exchanges = []
        def exchange(left, right):
            exchanges.append(True)
            if len(exchanges) == 2:
                raise OSError('restore failed')
            self.installation.atomic_exchange(left, right)
        def register(path):
            raise RuntimeError('registration failed')
        with self.assertRaisesRegex(RuntimeError, 'Automatic restore failed'):
            self.installation.install(self.source, self.destination, self.backups,
                validate=self.validate, stop=lambda: None, register=register, exchange=exchange)
        retained = list(self.destination.parent.glob('.SeasonArt-install-*/SeasonArt.app'))
        self.assertEqual(len(retained), 1)
        self.assertEqual((retained[0] / 'version').read_text(), 'old')
        backups = list(self.backups.glob('*/SeasonArt.app'))
        self.assertEqual((backups[0] / 'version').read_text(), 'old')

    def test_first_install_failure_leaves_no_install(self):
        shutil.rmtree(self.destination)
        def register(path):
            raise RuntimeError('registration failed')
        with self.assertRaises(RuntimeError):
            self.installation.install(self.source, self.destination, self.backups,
                validate=self.validate, stop=lambda: None, register=register)
        self.assertFalse(self.destination.exists())

    def test_cli_rejects_destination_override(self):
        script = MODULE.parent / 'install.sh'
        result = subprocess.run(['bash', str(script), str(self.destination)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No destination override', result.stderr)
        self.assertEqual((self.destination / 'version').read_text(), 'old')

    def test_launch_failure_reports_install_without_claiming_rollback(self):
        self.assertTrue(hasattr(self.installation, 'launch_application'), 'Нет отдельного запуска установленного приложения')
        def failed_run(command, **options):
            self.assertEqual(command, ['/usr/bin/open', '-g', str(self.destination)])
            raise subprocess.CalledProcessError(1, command, stderr='LaunchServices unavailable')
        with self.assertRaisesRegex(RuntimeError, 'Приложение установлено, но не запущено.*LaunchServices unavailable'):
            self.installation.launch_application(self.destination, run=failed_run)
        self.assertEqual((self.destination / 'version').read_text(), 'old')


if __name__ == '__main__':
    unittest.main()
