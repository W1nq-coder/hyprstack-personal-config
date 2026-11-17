#!/usr/bin/env bash
# Скачать локальную коллекцию Dashboard, в том числе в уже существующую папку.
set -Eeuo pipefail
REPO=$(dirname "$(readlink -f "$0")")
CHECK=0
case ${1:-} in
    --check) CHECK=1 ;;
    '') ;;
    *) echo 'Использование: ./download-wallpapers.sh [--check]' >&2; exit 2 ;;
esac
pics=$(xdg-user-dir PICTURES 2>/dev/null || true)
[[ -n $pics && $pics != "$HOME" ]] || pics=$HOME/Pictures
wp=${HYPRSTACK_WALLPAPERS_DIR:-$pics/Wallpapers}
old=$pics/vyrx-wallpapers
if [[ ! -e $wp && -d $old ]]; then
    if ((CHECK)); then
        echo "  [проверка] подключить $old -> $wp"
    else
        mkdir -p "$(dirname "$wp")"
        ln -s "$old" "$wp"
    fi
fi
if python3 - "$REPO/wallpapers-manifest.json" "$wp" <<'PY'
import json, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text())
root = Path(sys.argv[2])
sys.exit(0 if all((root / f['path']).is_file() for f in manifest['files']) else 1)
PY
then
    echo "  коллекция уже на месте: $wp"
    exit 0
fi
url=https://github.com/W1nq-coder/hyprstack-personal-config/releases/download/wallpapers-2026-11-17/wallpapers.tar
echo "  скачать коллекцию (490 обоев, ~1 ГБ) в $wp; существующие файлы сохраняются"
((CHECK)) && exit 0
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
curl --fail --location --retry 3 --output "$tmp/wallpapers.tar" "$url"
expected=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["archive_sha256"])' "$REPO/wallpapers-manifest.json")
printf '%s  %s\n' "$expected" "$tmp/wallpapers.tar" | sha256sum --check --status
mkdir -p "$tmp/unpacked" "$wp"
tar --extract --file "$tmp/wallpapers.tar" --directory "$tmp/unpacked" --no-same-owner --no-same-permissions
cp -R --no-clobber "$tmp/unpacked/." "$wp/"
echo "  готово: $wp"
