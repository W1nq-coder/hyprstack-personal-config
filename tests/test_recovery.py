"""Recovery tests never touch the real session or user home."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / 'home/.local/bin/hyprstack-rollback'


class RecoveryTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hyprstack-recovery-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.repo = self.home / 'repo'
        self.repo.mkdir()
        subprocess.run(['git', 'init', '-b', 'main', str(self.repo)], check=True, capture_output=True)
        (self.repo / 'files.txt').write_text('.local/bin/test-helper\n.config/systemd/user/hyprstack-session.service.d/90-fallback.conf\n')
        subprocess.run(['git', '-C', str(self.repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                        'commit', '-m', 'base'], check=True, capture_output=True)
        self.env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(self.home / '.local/state'))
        self.config = self.home / '.config/hyprstack'
        self.config.mkdir(parents=True)
        (self.config / 'local.lua').write_text('old hardware settings')
        self.overlay = self.home / '.local/share/hyprstack-personal/shell'
        self.overlay.mkdir(parents=True)
        (self.overlay / 'shell.qml').write_text('working shell')
        self.base = self.home / 'base'
        self.base.mkdir()
        (self.base / 'font').write_bytes(b'base font' * 100000)
        (self.overlay / 'inherited').symlink_to(self.base, target_is_directory=True)
        self.helper = self.home / '.local/bin/test-helper'
        self.helper.parent.mkdir(parents=True)
        self.helper.write_text('old executable')
        self.helper.chmod(0o751)
        self.store = self.home / '.local/state/hyprstack-personal/recovery'

    def run_tool(self, *args, success=True):
        result = subprocess.run(['python3', str(TOOL), *args], env=self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def snapshot(self):
        return Path(self.run_tool('create', '--repo', str(self.repo)).stdout.strip())

    def test_restore_exact_files_links_modes_and_remove_added_files(self):
        archive = self.snapshot()
        self.assertLess(archive.stat().st_size, 10000)
        (self.overlay / 'shell.qml').write_text('broken shell')
        (self.overlay / 'added.qml').write_text('new')
        (self.config / 'local.lua').write_text('wrong hardware')
        self.helper.unlink()
        fallback = self.home / '.config/systemd/user/hyprstack-session.service.d/90-fallback.conf'
        fallback.parent.mkdir(parents=True)
        fallback.write_text('new fallback')
        self.run_tool('--no-apply')
        self.assertEqual((self.overlay / 'shell.qml').read_text(), 'working shell')
        self.assertFalse((self.overlay / 'added.qml').exists())
        self.assertEqual((self.config / 'local.lua').read_text(), 'old hardware settings')
        self.assertEqual(self.helper.stat().st_mode & 0o777, 0o751)
        self.assertTrue((self.overlay / 'inherited').is_symlink())
        self.assertFalse(fallback.exists())
        self.assertEqual((self.base / 'font').stat().st_size, 900000)
        self.assertTrue(archive.exists())

    def test_corruption_detected_before_replacing_current_files(self):
        archive = self.snapshot()
        with zipfile.ZipFile(archive) as z:
            entries = {name: z.read(name) for name in z.namelist()}
        key = next(name for name in entries if name.startswith('data/'))
        entries[key] = b'corrupted'
        with zipfile.ZipFile(archive, 'w') as z:
            for name, content in entries.items():
                z.writestr(name, content)
        self.run_tool('--no-apply', success=False)
        self.assertEqual((self.overlay / 'shell.qml').read_text(), 'working shell')

    def test_detect_document_only_update(self):
        archive = self.snapshot()
        self.run_tool('unchanged', '--archive', str(archive))
        (self.overlay / 'added.qml').write_text('changed')
        self.run_tool('unchanged', '--archive', str(archive), success=False)

    def test_keep_two_verified_snapshots(self):
        first = self.snapshot()
        second = self.snapshot()
        third = self.snapshot()
        self.assertFalse(first.exists())
        self.assertTrue(second.exists() and third.exists())
        self.assertEqual(len(list(self.store.glob('*.zip'))), 2)

    def test_restore_refuses_parent_link(self):
        self.snapshot()
        directory = self.home / '.local/bin'
        directory.rename(self.home / 'real-bin')
        directory.symlink_to(self.home / 'real-bin', target_is_directory=True)
        self.run_tool('--no-apply', success=False)
        self.assertEqual(self.helper.read_text(), 'old executable')

    def test_restore_without_graphical_session_starts_saved_service(self):
        self.snapshot()
        commands = self.home / 'commands'
        bindir = self.home / 'bin'
        bindir.mkdir()
        systemctl = bindir / 'systemctl'
        systemctl.write_text('#!/bin/sh\necho "$*" >> "$HOME/commands"\n')
        systemctl.chmod(0o755)
        self.env['PATH'] = str(bindir) + ':' + os.environ['PATH']
        self.env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
        self.run_tool()
        self.assertIn('--user restart hyprstack-session.service', commands.read_text())


class InstallRecoveryTest(unittest.TestCase):
    def test_failed_install_restores_original_config(self):
        with tempfile.TemporaryDirectory(prefix='hyprstack-install-') as directory:
            home = Path(directory)
            config = home / '.config/hyprstack'
            config.mkdir(parents=True)
            (config / 'local.lua').write_text('-- original hardware\n')
            (config / 'shell.json').write_text('{}')
            installed = home / 'base/shell'
            installed.mkdir(parents=True)
            bindir = home / 'bin'
            bindir.mkdir()
            jq = bindir / 'jq'
            jq.write_text('#!/bin/sh\nexit 42\n')
            jq.chmod(0o755)
            env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / '.local/state'),
                       XDG_DATA_HOME=str(home / '.local/share'), XDG_CONFIG_HOME=str(home / '.config'),
                       XDG_CACHE_HOME=str(home / '.cache'), HYPRSTACK_DATA_DIR=str(home / 'base'),
                       PATH=str(bindir) + ':' + os.environ['PATH'])
            result = subprocess.run(['bash', str(ROOT / 'install.sh'), '--no-apply', '--no-wallpapers'],
                                    capture_output=True, text=True, env=env)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((config / 'local.lua').read_text(), '-- original hardware\n')
            self.assertFalse((home / '.local/share/hyprstack-personal/shell').exists())
            self.assertTrue((home / '.local/bin/hyprstack-rollback').exists())


    def test_failed_service_restart_rolls_back_without_live_session(self):
        with tempfile.TemporaryDirectory(prefix='hyprstack-restart-') as directory:
            home = Path(directory)
            repo = home / 'repo'
            repo.mkdir()
            (repo / 'install.sh').write_bytes((ROOT / 'install.sh').read_bytes())
            tool = repo / 'home/.local/bin/hyprstack-rollback'
            tool.parent.mkdir(parents=True)
            tool.write_bytes(TOOL.read_bytes())
            night = tool.with_name('nightlight')
            night.write_text('#!/bin/sh\nexit 0\n')
            night.chmod(0o755)
            rel = '.local/share/hyprstack-personal/shell/shell.qml'
            source = repo / 'home' / rel
            source.parent.mkdir(parents=True)
            source.write_text('new shell')
            (repo / 'files.txt').write_text(rel + '\n.local/bin/nightlight\n')
            subprocess.run(['git', 'init', '-b', 'main', str(repo)], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(repo), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                            'commit', '-m', 'test'], check=True, capture_output=True)
            active = home / rel
            active.parent.mkdir(parents=True)
            active.write_text('working shell')
            config = home / '.config/hyprstack'
            config.mkdir(parents=True)
            (config / 'local.lua').write_text('old config')
            (home / 'base/shell').mkdir(parents=True)
            bindir = home / 'bin'
            bindir.mkdir()
            stubs = {
                'systemctl': '#!/bin/sh\necho "$*" >> "$HOME/service-calls"\n'
                             'if [ "$2" = restart ] && [ ! -e "$HOME/restart-failed" ]; then touch "$HOME/restart-failed"; exit 1; fi\nexit 0\n',
                'hyprctl': '#!/bin/sh\nexit 0\n',
                'pgrep': '#!/bin/sh\nexit 1\n',
            }
            for name, content in stubs.items():
                path = bindir / name
                path.write_text(content)
                path.chmod(0o755)
            env = dict(os.environ, HOME=str(home), XDG_STATE_HOME=str(home / '.local/state'),
                       XDG_DATA_HOME=str(home / '.local/share'), XDG_CONFIG_HOME=str(home / '.config'),
                       XDG_CACHE_HOME=str(home / '.cache'), HYPRSTACK_DATA_DIR=str(home / 'base'),
                       HYPRLAND_INSTANCE_SIGNATURE='test-only', PATH=str(bindir) + ':' + os.environ['PATH'])
            result = subprocess.run(['bash', str(repo / 'install.sh'), '--no-wallpapers'], env=env,
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(active.read_text(), 'working shell', result.stdout + result.stderr)
            self.assertEqual((config / 'local.lua').read_text(), 'old config')
            self.assertEqual((home / 'service-calls').read_text().count('--user restart hyprstack-session.service'), 2)


if __name__ == '__main__':
    unittest.main()
