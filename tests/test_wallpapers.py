"""Exercise the wallpaper downloader without network or desktop changes."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class WallpapersTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copy2(REPO / 'download-wallpapers.sh', self.root)
        self.archive = self.root / 'fixture.tar'
        self.files = {'calm/one.jpg': b'one', 'others/two.png': b'two'}
        with tarfile.open(self.archive, 'w') as archive:
            for name, content in self.files.items():
                info = tarfile.TarInfo(name)
                info.size = len(content)
                archive.addfile(info, io.BytesIO(content))
        self.manifest = {
            'archive_sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest(),
            'files': [{'path': name} for name in self.files],
        }
        self.write_manifest()
        binaries = self.root / 'bin'
        binaries.mkdir()
        curl = binaries / 'curl'
        curl.write_text('#!/bin/bash\nwhile (($#)); do\n'
                        'if [[ $1 == --output ]]; then cp "$FIXTURE" "$2"; exit; fi\n'
                        'shift\ndone\nexit 1\n')
        curl.chmod(0o755)
        self.target = self.root / 'destination'
        self.env = dict(os.environ, PATH=f'{binaries}:{os.environ["PATH"]}',
                        FIXTURE=str(self.archive), HYPRSTACK_WALLPAPERS_DIR=str(self.target))

    def write_manifest(self):
        (self.root / 'wallpapers-manifest.json').write_text(json.dumps(self.manifest))

    def run_download(self, *args):
        return subprocess.run(['bash', str(self.root / 'download-wallpapers.sh'), *args],
                              env=self.env, capture_output=True, text=True)

    def test_download_and_preserve_existing(self):
        (self.target / 'calm').mkdir(parents=True)
        (self.target / 'calm/one.jpg').write_bytes(b'custom')
        result = self.run_download()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.target / 'calm/one.jpg').read_bytes(), b'custom')
        self.assertEqual((self.target / 'others/two.png').read_bytes(), b'two')
        self.archive.unlink()  # A repeated run must not download again.
        self.assertEqual(self.run_download().returncode, 0)

    def test_bad_checksum_does_not_install(self):
        self.manifest['archive_sha256'] = '0' * 64
        self.write_manifest()
        self.assertNotEqual(self.run_download().returncode, 0)
        self.assertFalse(self.target.exists())

    def test_check_does_not_create_files(self):
        self.archive.unlink()
        self.assertEqual(self.run_download('--check').returncode, 0)
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
