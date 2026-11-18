"""The guard is independent of QML; simulate timer and confirmation outcomes."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader('guard', str(ROOT / 'home/.local/bin/hyprstack-update-guard'))
spec = importlib.util.spec_from_loader(loader.name, loader)
guard = importlib.util.module_from_spec(spec)
loader.exec_module(guard)


class GuardTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        for key, value in [('STATE', self.root), ('PENDING', self.root / 'pending.json')]:
            p = patch.object(guard, key, value)
            p.start()
            self.addCleanup(p.stop)
        self.archive = self.root / 'snapshot.zip'
        self.archive.write_bytes(b'snapshot')
        self.commands = []
        self.answer = 'keep'
        self.fail_timer = False
        self.fail_restore = False

    def fake_run(self, *args, **kwargs):
        args = list(map(str, args))
        self.commands.append(args)
        if args[0] == 'systemd-run' and self.fail_timer:
            raise subprocess.CalledProcessError(1, args)
        if '--archive' in args and self.fail_restore:
            raise subprocess.CalledProcessError(1, args)
        if args[0] == 'notify-send' and self.answer == 'timeout':
            raise subprocess.TimeoutExpired(args, 60)
        return subprocess.CompletedProcess(args, 0, self.answer)

    def arm(self):
        with contextlib.redirect_stdout(io.StringIO()):
            guard.arm(self.archive)
        return guard.read()['token']

    def test_timer_runs_outside_installer_and_keep_cancels(self):
        with patch.object(guard, 'run', self.fake_run), patch.object(guard, 'cancel_timer') as cancel:
            token = self.arm()
            self.assertIn('--on-active=120s', self.commands[0])
            self.assertIn('rollback', self.commands[0])
            self.assertTrue(guard.confirm(token))
            self.assertFalse(guard.PENDING.exists())
            cancel.assert_called_once()
            self.assertFalse(any('--archive' in cmd for cmd in self.commands))

    def test_gray_screen_notification_timeout_rolls_back(self):
        self.answer = 'timeout'
        with patch.object(guard, 'run', self.fake_run), patch.object(guard, 'cancel_timer'):
            token = self.arm()
            self.assertFalse(guard.confirm(token))
            self.assertTrue(any('--archive' in cmd for cmd in self.commands))
            self.assertFalse(guard.PENDING.exists())

    def test_timer_can_restore_without_notification_or_installer(self):
        with patch.object(guard, 'run', self.fake_run), patch.object(guard, 'cancel_timer'):
            token = self.arm()
            guard.restore(token)
            self.assertFalse(guard.confirm(token))
            self.assertEqual(sum('--archive' in cmd for cmd in self.commands), 1)

    def test_failed_timer_arming_does_not_leave_pending(self):
        self.fail_timer = True
        with patch.object(guard, 'run', self.fake_run):
            with self.assertRaises(subprocess.CalledProcessError):
                self.arm()
        self.assertFalse(guard.PENDING.exists())

    def test_failed_restore_remains_recoverable_after_login(self):
        self.fail_restore = True
        with patch.object(guard, 'run', self.fake_run), patch.object(guard, 'cancel_timer'):
            token = self.arm()
            with self.assertRaises(subprocess.CalledProcessError):
                guard.restore(token)
            self.assertTrue(guard.PENDING.exists())
            item = guard.read()
            item['deadline'] = time.time() - 1
            guard.PENDING.write_text(json.dumps(item))
            self.fail_restore = False
            guard.restore(expired_only=True)
            self.assertFalse(guard.PENDING.exists())

    def test_old_token_cannot_confirm_or_restore_new_update(self):
        with patch.object(guard, 'run', self.fake_run), patch.object(guard, 'cancel_timer'):
            self.arm()
            guard.restore('old-token')
            self.assertFalse(guard.confirm('old-token'))
            self.assertTrue(guard.PENDING.exists())
            self.assertFalse(any('--archive' in cmd for cmd in self.commands))


if __name__ == '__main__':
    unittest.main()
