"""Bounded worker commands; no shell, privilege escalation or persistent daemon."""
import os
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from gi.repository import GLib, Gio


def command(argv):
    if not shutil.which(argv[0]):
        raise RuntimeError(f'Не установлен {argv[0]}')
    result = subprocess.run(argv, capture_output=True, text=True, timeout=8,
                            env={**os.environ, 'LC_ALL': 'C'})
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip() or 'Служба недоступна')
    return result.stdout.strip()


class Worker:
    def __init__(self):
        self.pool = ThreadPoolExecutor(max_workers=2)
        self.pending = set()

    def run(self, key, job, callback):
        if key in self.pending:
            return
        self.pending.add(key)
        def done(future):
            try:
                value, error = future.result(), None
            except Exception as exc:
                value, error = None, str(exc)
            def deliver():
                self.pending.discard(key)
                callback(value, error)
                return False
            GLib.idle_add(deliver)
        self.pool.submit(job).add_done_callback(done)


def battery():
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    result = bus.call_sync('org.freedesktop.UPower',
        '/org/freedesktop/UPower/devices/DisplayDevice',
        'org.freedesktop.DBus.Properties', 'GetAll',
        GLib.Variant('(s)', ('org.freedesktop.UPower.Device',)),
        GLib.VariantType.new('(a{sv})'), Gio.DBusCallFlags.NONE, 3000, None)
    data = result.unpack()[0]
    if not data.get('IsPresent'):
        return 'Батарея отсутствует'
    state = {1: 'заряжается', 2: 'разряд', 4: 'заряжена'}.get(data.get('State'), 'статус неизвестен')
    return f"Батарея {data.get('Percentage', 0):.0f}% · {state}"
