import unittest
from unittest.mock import patch
import subprocess
from hyprstack_mobile.backend import command

class BackendTest(unittest.TestCase):
    def test_absent_command(self):
        with patch('shutil.which', return_value=None), self.assertRaises(RuntimeError):
            command(['absent'])

    def test_command_is_not_shell(self):
        with patch('shutil.which', return_value='/usr/bin/tool'), patch('subprocess.run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, 'ok\n', '')
            self.assertEqual(command(['tool', '$(false);']), 'ok')
            self.assertEqual(run.call_args.args[0], ['tool', '$(false);'])
            self.assertNotIn('shell', run.call_args.kwargs)
            self.assertEqual(run.call_args.kwargs['timeout'], 8)

    def test_service_failure(self):
        with patch('shutil.which', return_value='/usr/bin/tool'), patch('subprocess.run') as run:
            run.return_value = subprocess.CompletedProcess([], 1, '', 'permission denied')
            with self.assertRaisesRegex(RuntimeError, 'permission denied'):
                command(['tool'])
