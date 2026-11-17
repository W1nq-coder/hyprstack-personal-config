#!/usr/bin/env python3
"""User-only transactional deployment; recoverable journal precedes every write."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + '.hyprstack-tmp')
    if temp.exists() or temp.is_symlink():
        raise RuntimeError(f'Временный файл уже существует: {temp}')
    with temp.open('xb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    temp.chmod(mode)
    temp.replace(path)


def safe(home, path):
    if '..' in path.parts or not path.is_relative_to(home):
        raise RuntimeError(f'Путь за пределами HOME: {path}')
    for part in [path, *path.parents]:
        if part == home:
            break
        if part.is_symlink():
            raise RuntimeError(f'Символическая ссылка не поддерживается: {part}')


def check_device():
    if platform.machine() not in ('aarch64', 'arm64'):
        raise RuntimeError('Установка требует ARM64; для разработки используйте scripts/run.sh')
    release = Path('/etc/os-release').read_text()
    if 'postmarketos' not in release.lower() and not Path('/etc/postmarketos-release').exists():
        raise RuntimeError('Не обнаружен postmarketOS')
    if not shutil.which('phosh'):
        raise RuntimeError('Не обнаружен Phosh')


def check_dependencies():
    subprocess.run([sys.executable, '-c',
        "import gi; gi.require_version('Gtk','4.0'); from gi.repository import Gtk, Gio"], check=True)
    for tool in ('nmcli', 'bluetoothctl', 'wpctl', 'brightnessctl', 'playerctl', 'gnome-control-center'):
        print(f'{tool}: {shutil.which(tool) or "не установлен (соответствующая функция недоступна)"}')


def install(home, state, autostart=False):
    if (state/'manifest.json').exists():
        raise RuntimeError('Установка уже существует: сначала rollback.sh (обновление пока вручную)')
    if shutil.disk_usage(home).free < 30 * 1024 * 1024:
        raise RuntimeError('Требуется минимум 30 MiB свободного места')
    target = home/'.local/share/hyprstack-mobile'
    files = {}
    for folder in ('src', 'themes', 'scripts'):
        for source in sorted((ROOT/folder).rglob('*')):
            if source.is_file() and '__pycache__' not in source.parts:
                files[target/source.relative_to(ROOT)] = (source.read_bytes(), 0o755 if source.suffix == '.sh' else 0o644)
    for name in ('LICENSE', 'THIRD_PARTY.md'):
        files[target/name] = ((ROOT/name).read_bytes(), 0o644)
    # Desktop Exec escaping, not shell evaluation.
    executable = str(target/'scripts/run.sh')
    escaped = executable.replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
    desktop = ('[Desktop Entry]\nType=Application\nName=Hyprstack Mobile\n'
               f'Exec="{escaped}"\nIcon=applications-system\nTerminal=false\nCategories=Utility;\n').encode()
    files[home/'.local/share/applications/io.github.W1nqCoder.HyprstackMobile.desktop'] = (desktop, 0o644)
    if autostart:
        files[home/'.config/autostart/io.github.W1nqCoder.HyprstackMobile.desktop'] = (desktop, 0o644)
    entries = []
    for path, (data, mode) in files.items():
        safe(home, path)
        if path.exists() and not path.is_file():
            raise RuntimeError(f'Не обычный файл: {path}')
        old = path.read_bytes() if path.exists() else None
        entries.append({'path': str(path.relative_to(home)), 'sha256': digest(data),
                        'old': old.hex() if old is not None else None,
                        'mode': path.stat().st_mode & 0o777 if old is not None else None})
    atomic(state/'manifest.json', json.dumps(entries).encode())
    for path, (data, mode) in files.items():
        atomic(path, data, mode)
    for entry in entries:
        assert digest((home/entry['path']).read_bytes()) == entry['sha256']
    print('Установлено. Запуск: ' + str(target/'scripts/run.sh'))
    print('Автозапуск: ' + ('включён' if autostart else 'выключен; включение: install.sh --autostart при первой установке'))


def rollback(home, state):
    manifest = state/'manifest.json'
    if not manifest.exists():
        print('Активной установки нет')
        return
    entries = json.loads(manifest.read_text())
    for entry in reversed(entries):
        path = home/entry['path']
        safe(home, path)
        old = bytes.fromhex(entry['old']) if entry['old'] is not None else None
        current = path.read_bytes() if path.exists() else None
        if current == old or (current is not None and old is not None and digest(current) == digest(old)):
            continue
        if current is not None and digest(current) != entry['sha256']:
            # Preserve changes made after deployment before restoring original.
            recovery = state/'preserved'/entry['path']
            if recovery.exists():
                if recovery.read_bytes() != current:
                    raise RuntimeError(f'Конфликт сохранённой копии: {recovery}')
            else:
                atomic(recovery, current)
        if old is None:
            if path.exists():
                path.unlink()
        else:
            atomic(path, old, entry['mode'])
    manifest.rename(state/'last-rollback.json')
    print(f'Откат выполнен. Настройки приложения сохранены. Журнал и изменённые файлы: {state}')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['install', 'rollback', 'uninstall', 'device', 'dependencies'])
    p.add_argument('--autostart', action='store_true')
    args = p.parse_args()
    if os.geteuid() == 0:
        raise RuntimeError('Запускайте от обычного пользователя, без sudo')
    if args.action == 'device':
        return check_device()
    if args.action == 'dependencies':
        return check_dependencies()
    home = Path.home().absolute()
    state = home/'.local/state/hyprstack-mobile'
    safe(home, state)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    safe(home, state/'lock')
    with (state/'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        safe(home, state/'manifest.json')
        if args.action == 'install':
            check_device()
            check_dependencies()
            install(home, state, args.autostart)
        else:
            rollback(home, state)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'Ошибка: {exc}', file=sys.stderr)
        sys.exit(1)
