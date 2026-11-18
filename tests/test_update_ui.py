"""Exercise updater choices against real temporary Git repositories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

UI = Path(__file__).resolve().parents[1] / 'home/.local/bin/hyprstack-personal-update-ui'


class UpdateTest(unittest.TestCase):
    def scenario(self, answer, divergent=False, dirty=True, ignored=False):
        temp = tempfile.TemporaryDirectory(prefix='hyprstack-updater-')
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        repo = root / 'repo'
        repo.mkdir()
        def git(*args):
            return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.PIPE).decode().strip()
        git('init', '-b', 'main')
        git('config', 'user.name', 'Test')
        git('config', 'user.email', 'test@example.invalid')
        (repo / 'tracked').write_text('original\n')
        installer = repo / 'install.sh'
        installer.write_text('#!/bin/bash\nprintf installed > "$HOME/installed"\n')
        installer.chmod(0o755)
        git('add', '.')
        git('commit', '-m', 'base')
        base = git('rev-parse', 'HEAD')
        git('checkout', '-b', 'target')
        (repo / 'tracked').write_text('upstream\n')
        (repo / 'new-file').write_text('upstream new file\n')
        git('add', '.')
        git('commit', '-m', 'update')
        target = git('rev-parse', 'HEAD')
        git('checkout', 'main')
        git('config', 'branch.main.remote', '.')
        git('config', 'branch.main.merge', 'refs/heads/target')
        if divergent:
            (repo / 'local-commit').write_text('keep\n')
            git('add', '.')
            git('commit', '-m', 'local commit')
            base = git('rev-parse', 'HEAD')
        if dirty:
            (repo / 'tracked').write_text('staged change\n')
            git('add', 'tracked')
            (repo / 'tracked').write_text('unstaged change\n')
            (repo / 'new-file').write_text('my untracked content\n')
        if ignored:
            (repo / '.git/info/exclude').write_text('new-file\n')
            (repo / 'new-file').write_text('ignored personal content\n')
        before = git('status', '--porcelain')
        state = root / 'state/hyprstack-personal'
        state.mkdir(parents=True)
        (state / 'repo').write_text(str(repo))
        env = dict(os.environ, HOME=str(root), XDG_STATE_HOME=str(root / 'state'), TERM='xterm')
        result = subprocess.run(['bash', str(UI)], input=answer, text=True, capture_output=True, env=env)
        return repo, root, state, git, base, target, before, result

    def test_closed_input_never_approves_clean_update(self):
        repo, root, state, git, base, target, before, result = self.scenario('', dirty=False)
        self.assertEqual(git('rev-parse', 'HEAD'), base)
        self.assertFalse((root / 'installed').exists())

    def test_dirty_update_saves_staged_unstaged_and_new_files(self):
        repo, root, state, git, base, target, before, result = self.scenario('yyx')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git('rev-parse', 'HEAD'), target)
        self.assertEqual(git('status', '--porcelain'), '')
        self.assertTrue((root / 'installed').is_file())
        self.assertEqual(git('show', 'stash:tracked'), 'unstaged change')
        self.assertEqual(git('show', 'stash^2:tracked'), 'staged change')
        self.assertEqual(git('show', 'stash^3:new-file'), 'my untracked content')
        self.assertTrue((state / 'saved-changes').is_file())

    def test_cancel_keeps_everything(self):
        repo, root, state, git, base, target, before, result = self.scenario('y\n')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git('rev-parse', 'HEAD'), base)
        self.assertEqual(git('status', '--porcelain'), before)
        self.assertFalse((root / 'installed').exists())
        self.assertFalse((state / 'saved-changes').exists())

    def test_end_of_input_does_not_discard_changes(self):
        repo, root, state, git, base, target, before, result = self.scenario('y')
        self.assertEqual(git('rev-parse', 'HEAD'), base)
        self.assertEqual(git('status', '--porcelain'), before)

    def test_failed_merge_restores_changes(self):
        repo, root, state, git, base, target, before, result = self.scenario('yyx', divergent=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(git('rev-parse', 'HEAD'), base)
        self.assertEqual(git('status', '--porcelain'), before)
        self.assertEqual((repo / 'tracked').read_text(), 'unstaged change\n')
        self.assertEqual((repo / 'new-file').read_text(), 'my untracked content\n')
        self.assertTrue((state / 'last-update.log').is_file())
        self.assertFalse((root / 'installed').exists())

    def test_ignored_file_is_not_overwritten(self):
        repo, root, state, git, base, target, before, result = self.scenario('yyx', ignored=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(git('rev-parse', 'HEAD'), base)
        self.assertEqual((repo / 'new-file').read_text(), 'ignored personal content\n')
        self.assertEqual((repo / 'tracked').read_text(), 'unstaged change\n')

    def test_clean_update_does_not_prompt_about_changes(self):
        repo, root, state, git, base, target, before, result = self.scenario('yx', dirty=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(git('rev-parse', 'HEAD'), target)
        self.assertFalse((state / 'saved-changes').exists())


if __name__ == '__main__':
    unittest.main()
