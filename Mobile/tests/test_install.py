import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('manage', Path(__file__).resolve().parents[1]/'scripts/manage.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.state = self.home/'.local/state/hyprstack-mobile'
        self.state.mkdir(parents=True)
        self.desktop = self.home/'.local/share/applications/io.github.W1nqCoder.HyprstackMobile.desktop'

    def test_roundtrip_original_and_user_data(self):
        self.desktop.parent.mkdir(parents=True)
        self.desktop.write_text('original')
        user = self.home/'.config/hyprstack-mobile/settings.json'
        user.parent.mkdir(parents=True)
        user.write_text('{"favorites": []}')
        m.install(self.home, self.state, True)
        self.desktop.write_text('edited after installation')
        m.rollback(self.home, self.state)
        self.assertEqual(self.desktop.read_text(), 'original')
        self.assertTrue(user.exists())
        self.assertEqual((self.state/'preserved'/self.desktop.relative_to(self.home)).read_text(), 'edited after installation')
        self.assertFalse((self.home/'.config/autostart/io.github.W1nqCoder.HyprstackMobile.desktop').exists())
        m.rollback(self.home, self.state)

    def test_existing_install_rejected(self):
        m.install(self.home, self.state)
        with self.assertRaises(RuntimeError):
            m.install(self.home, self.state)

    def test_symlink_rejected(self):
        (self.home/'.local/share').mkdir(parents=True)
        (self.home/'.local/share/hyprstack-mobile').symlink_to('/tmp', target_is_directory=True)
        with self.assertRaises(RuntimeError):
            m.install(self.home, self.state)

    def test_interrupted_install_can_rollback(self):
        original = m.atomic
        def broken(path, data, mode=0o600):
            if path.name == 'app.py':
                raise OSError('simulated interruption')
            original(path, data, mode)
        with patch.object(m, 'atomic', broken), self.assertRaises(OSError):
            m.install(self.home, self.state)
        m.rollback(self.home, self.state)
        self.assertFalse(self.desktop.exists())

    def test_low_space(self):
        with patch.object(m.shutil, 'disk_usage', return_value=type('Usage', (), {'free': 0})()):
            with self.assertRaises(RuntimeError):
                m.install(self.home, self.state)
