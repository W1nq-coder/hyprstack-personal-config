import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch
from gi.repository import GLib
from hyprstack_mobile.config import load
from hyprstack_mobile.backend import Worker


class RegressionTest(unittest.TestCase):
    def test_invalid_preferences(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'settings.json'
            path.write_text('{"wallpaper": 42, "favorites": null, "light": "false"}')
            self.assertEqual(load(path), {})
            path.write_text('{"favorites": ["a", "a", 2, "b", "c", "d", "e"]}')
            self.assertEqual(load(path)['favorites'], ['a', 'b', 'c', 'd', 'e'])
            path.write_text('[]')
            self.assertEqual(load(path), {})

    def test_missing_services_delivered_without_crash(self):
        for service in ('UPower', 'BlueZ', 'NetworkManager', 'MPRIS'):
            with self.subTest(service=service):
                worker = Worker()
                deliveries = []
                def missing():
                    raise RuntimeError(service + ' unavailable')
                with patch.object(GLib, 'idle_add', side_effect=lambda fn: fn()):
                    worker.run(service, missing, lambda value, error: deliveries.append((value, error)))
                    worker.pool.shutdown(wait=True)
                self.assertEqual(deliveries, [(None, service + ' unavailable')])
                self.assertFalse(worker.pending)
