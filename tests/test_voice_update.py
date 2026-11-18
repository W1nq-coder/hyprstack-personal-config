"""Model updates use temporary homes and fake network/recognizer executables."""
import hashlib
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
LOADER = importlib.machinery.SourceFileLoader('voice_update', str(ROOT / 'home/.local/bin/hyprstack-voice-update'))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
voice = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(voice)


class VoiceUpdateTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name, relative in [('STATE', 'state/voice'), ('RUNTIME', 'runtime'),
                               ('MODELS', 'models'), ('CONFIG', 'config/voice')]:
            value = self.root / relative
            value.parent.mkdir(parents=True, exist_ok=True)
            patcher = patch.object(voice, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        voice.STATE.mkdir()
        voice.RUNTIME.mkdir()
        self.original = 'MODEL="/old/q5.bin"\nLANGUAGE="en"\nSOURCE="mic"\nMODE="hold"\n'
        voice.CONFIG.write_text(self.original)
        self.current = {'model': '/old/q5.bin', 'vadModel': '/old/vad.bin', 'language': 'en',
                        'useGpu': False, 'threads': 2}
        self.manifest = {'version': 'test', 'name': 'Test model', 'files': []}
        for name, data in [('model.bin', b'model'), ('vad.bin', b'vad')]:
            self.manifest['files'].append({'name': name, 'size': len(data),
                                          'sha256': hashlib.sha256(data).hexdigest(), 'url': name})
        self.config_patch = patch.object(voice, 'settings', return_value=self.current)
        self.config_patch.start()
        self.addCleanup(self.config_patch.stop)
        self.status = 'idle'
        self.bad_hash = False
        self.bad_load = False
        self.change_during_test = False
        self.commands = []

    def fake_run(self, args, **kwargs):
        args = list(map(str, args))
        self.commands.append(args)
        if args[0] == 'curl':
            path = Path(args[args.index('-o') + 1])
            path.write_bytes(b'wrong' if self.bad_hash else {'model.bin': b'model', 'vad.bin': b'vad'}[args[-1]])
        elif args[0] == 'whisper-cli':
            self.assertIn('--no-gpu', args)
            self.assertEqual(args[args.index('-l') + 1], 'en')
            if self.change_during_test:
                voice.CONFIG.write_text('MODEL="/user/choice.bin"\n')
            if self.bad_load:
                raise subprocess.CalledProcessError(1, args)
        elif args[-1] == 'status':
            return subprocess.CompletedProcess(args, 0, json.dumps({'state': self.status}))
        return subprocess.CompletedProcess(args, 0, '')

    def install(self, answer='y'):
        with patch('builtins.input', return_value=answer), patch.object(voice, 'run', self.fake_run):
            voice.install(self.manifest)

    def test_verified_models_switch_atomically_preserve_settings_and_rollback(self):
        self.install()
        content = voice.CONFIG.read_text()
        self.assertIn('LANGUAGE="en"', content)
        self.assertIn('SOURCE="mic"', content)
        self.assertIn('MODE="hold"', content)
        self.assertIn(str(voice.MODELS / 'model.bin'), content)
        self.assertEqual((voice.STATE / 'accepted').read_text(), 'test')
        self.assertEqual((voice.MODELS / 'model.bin').read_bytes(), b'model')
        with patch('builtins.input', return_value='y'), patch.object(voice, 'run', self.fake_run):
            voice.rollback()
        self.assertEqual(voice.CONFIG.read_text(), self.original)
        self.assertTrue((voice.MODELS / 'model.bin').exists())

    def test_decline_does_not_download_or_change_config(self):
        self.install('n')
        self.assertEqual(self.commands, [])
        self.assertEqual(voice.CONFIG.read_text(), self.original)

    def test_bad_checksum_keeps_old_model(self):
        self.bad_hash = True
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(voice.CONFIG.read_text(), self.original)
        self.assertFalse((voice.MODELS / 'model.bin').exists())
        self.assertFalse(any(x[0] == 'whisper-cli' for x in self.commands))

    def test_model_load_failure_keeps_old_model(self):
        self.bad_load = True
        with self.assertRaises(subprocess.CalledProcessError):
            self.install()
        self.assertEqual(voice.CONFIG.read_text(), self.original)
        self.assertFalse((voice.MODELS / 'model.bin').exists())

    def test_active_recording_is_not_interrupted(self):
        self.status = 'recording'
        with self.assertRaises(ValueError):
            self.install()
        self.assertFalse(any(x[-1] == 'server-stop' for x in self.commands))
        self.assertEqual(voice.CONFIG.read_text(), self.original)

    def test_concurrent_settings_edit_is_preserved(self):
        self.change_during_test = True
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual(voice.CONFIG.read_text(), 'MODEL="/user/choice.bin"\n')

    def test_user_model_is_never_replaced_by_download(self):
        voice.MODELS.mkdir()
        (voice.MODELS / 'model.bin').write_bytes(b'custom')
        with self.assertRaises(ValueError):
            self.install()
        self.assertEqual((voice.MODELS / 'model.bin').read_bytes(), b'custom')
        self.assertEqual(voice.CONFIG.read_text(), self.original)

    def test_later_manual_selection_is_not_overridden(self):
        self.assertTrue(voice.pending(self.manifest, self.current))
        (voice.STATE / 'accepted').write_text('test')
        self.assertFalse(voice.pending(self.manifest, self.current))

    def test_quotes_in_paths_are_shell_safe(self):
        path = "a'b$HOME`date`"
        content = voice.set_paths('', path, 'vad')
        actual = subprocess.check_output(['bash', '-c', content + '\nprintf "%s" "$MODEL"'], text=True)
        self.assertEqual(actual, path)


if __name__ == '__main__':
    unittest.main()
