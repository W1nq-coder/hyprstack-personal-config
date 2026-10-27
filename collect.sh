#!/usr/bin/env bash
# Собрать текущие версии файлов из системы в репозиторий (home/).
# После этого: git add -A && git commit && git push.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
missing=0
while IFS= read -r path; do
    [[ -z $path || $path == \#* ]] && continue
    if [[ -f $HOME/$path ]]; then
        mkdir -p "home/$(dirname "$path")"
        cp -p "$HOME/$path" "home/$path"
    else
        echo "нет файла: ~/$path" >&2
        missing=1
    fi
done < files.txt
# Контрольные суммы оригиналов из установленной оболочки, которые заменены своими
# версиями: install.sh по ним заметит, что обновление HyperStack их изменило.
installed=${HYPRSTACK_DATA_DIR:-$HOME/.local/share/hyprstack}/shell
personal=.local/share/hyprstack-personal/shell/
: > upstream.sha256
while IFS= read -r path; do
    [[ $path == "$personal"* ]] || continue
    rel=${path#"$personal"}
    [[ -f $installed/$rel ]] && printf '%s  %s\n' "$(sha256sum < "$installed/$rel" | cut -d' ' -f1)" "$rel" >> upstream.sha256
done < <(grep -v -E '^(#|$)' files.txt)
echo "Собрано в $(pwd)/home"
exit $missing
