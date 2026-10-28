#!/usr/bin/env bash
# Вернуть мои доработки HyperStack после обновления или переустановки.
#
#   ./install.sh             поставить доработки и применить
#   ./install.sh --personal  то же + мои личные настройки (мониторы, переменные, сочетания,
#                            автозапуск) поверх существующих — для восстановления моей системы
#   ./install.sh --check     только показать, что изменится (ничего не трогает)
#   ./install.sh --no-apply  разложить файлы, но не перезагружать Hyprland и оболочку
#
# Без --personal личные настройки автора (строки «~ » в files.txt) не ставятся,
# а ваши переменные из hypr-vars.lua переносятся в vars.lua.
# Перед заменой отличающиеся файлы сохраняются в
# ~/.local/state/hyprstack-personal-backup/<дата>/ (тот же путь, что и в ~).
set -uo pipefail

REPO=$(dirname "$(readlink -f "$0")")
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
INSTALLED=${HYPRSTACK_DATA_DIR:-$DATA/hyprstack}/shell
PERSONAL=$DATA/hyprstack-personal/shell
PERSONAL_REL=.local/share/hyprstack-personal/shell/
BACKUP=${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack-personal-backup/$(date +%Y%m%d-%H%M%S)
CHECK=0
APPLY=1
MINE=0
for arg in "$@"; do
    case $arg in
        --check) CHECK=1; APPLY=0 ;;
        --no-apply) APPLY=0 ;;
        --personal) MINE=1 ;;
        -h | --help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Неизвестный параметр: $arg" >&2; exit 2 ;;
    esac
done

say() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
do_() { if ((CHECK)); then echo "  [проверка] $*"; else "$@"; fi; }

# Строки files.txt: «путь» или «~ путь» (личный файл).
entries() { grep -v -E '^(#|$)' "$REPO/files.txt"; }
files() { entries | sed 's/^~ //'; }

# ---------- 1. HyperStack и пакеты ----------

[[ -d $INSTALLED ]] || { echo "HyperStack не найден в $INSTALLED. Сначала установите его." >&2; exit 1; }

say "Пакеты"
need=(whisper-cpp ggml-vulkan wtype wl-clipboard pipewire jq ffmpeg curl hyprsunset mpv wf-recorder dolphin github-cli
      satty grim slurp hyprpicker libnotify)
# Графика Intel: драйвер, чтобы запись экрана кодировала видеокарта, а не процессор.
grep -qx "0x8086" /sys/class/drm/card*/device/vendor 2>/dev/null || lspci 2>/dev/null | grep -qi "VGA.*Intel" \
    && need+=(intel-media-driver)
missing=()
for pkg in "${need[@]}"; do pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg"); done
if ((${#missing[@]})); then
    warn "Не установлены: ${missing[*]}"
    echo "  Установить: sudo pacman -S --needed ${missing[*]}"
    if ((!CHECK)) && [[ -t 0 ]]; then
        read -r -p "  Установить сейчас? [y/N] " answer
        [[ $answer == [yYдД]* ]] && sudo pacman -S --needed "${missing[@]}"
    fi
else
    echo "  всё на месте"
fi

# ---------- 2. Личная копия оболочки ----------

# Папка-ссылка на установленную оболочку превращается в настоящую папку со
# ссылками на каждый файл оригинала, чтобы в неё можно было положить свой файл.
materialize() {
    local dir=$1 rel=${1#"$PERSONAL"/} entry
    [[ -L $dir ]] || return 0
    do_ rm "$dir"
    do_ mkdir "$dir"
    for entry in "$INSTALLED/$rel"/* "$INSTALLED/$rel"/.[!.]*; do
        [[ -e $entry ]] && do_ ln -s "$entry" "$dir/$(basename "$entry")"
    done
}

# Во всех настоящих папках личной копии: ссылки на новые файлы из обновления,
# удаление ссылок на исчезнувшие файлы.
refresh_links() {
    local dir rel entry name link
    while IFS= read -r -d '' dir; do
        rel=${dir#"$PERSONAL"}
        rel=${rel#/}
        [[ -d $INSTALLED/$rel ]] || continue
        for entry in "$INSTALLED/$rel"/* "$INSTALLED/$rel"/.[!.]*; do
            [[ -e $entry ]] || continue
            name=$(basename "$entry")
            [[ -e $dir/$name || -L $dir/$name ]] && continue
            echo "  новая ссылка: ${rel:+$rel/}$name"
            do_ ln -s "$entry" "$dir/$name"
        done
        for link in "$dir"/* "$dir"/.[!.]*; do
            if [[ -L $link && ! -e $link ]]; then
                echo "  убрана битая ссылка: ${rel:+$rel/}$(basename "$link")"
                do_ rm "$link"
            fi
        done
    done < <(find "$PERSONAL" -type d -not -path '*/__pycache__*' -print0 2>/dev/null)
}

say "Личная копия оболочки"
if [[ ! -d $PERSONAL ]]; then
    echo "  создаю $PERSONAL"
    do_ mkdir -p "$PERSONAL"
    for entry in "$INSTALLED"/*; do do_ ln -s "$entry" "$PERSONAL/$(basename "$entry")"; done
fi
while IFS= read -r path; do
    [[ $path == "$PERSONAL_REL"* ]] || continue
    rel=${path#"$PERSONAL_REL"}
    dir=$PERSONAL
    IFS=/ read -r -a parts <<<"$(dirname "$rel")"
    for part in "${parts[@]}"; do
        [[ $part == . ]] && continue
        dir=$dir/$part
        materialize "$dir"
    done
done < <(files)
((CHECK)) || refresh_links
((CHECK)) && echo "  (новые и битые ссылки проверяются только при установке)"

# Обновление HyperStack могло изменить оригиналы файлов, которые заменены своими.
if [[ -f $REPO/upstream.sha256 ]]; then
    changed=()
    while read -r sum rel; do
        [[ -f $INSTALLED/$rel ]] || { changed+=("$rel (удалён в оболочке)"); continue; }
        [[ $(sha256sum < "$INSTALLED/$rel" | cut -d' ' -f1) == "$sum" ]] || changed+=("$rel")
    done < "$REPO/upstream.sha256"
    if ((${#changed[@]})); then
        warn "Обновление HyperStack изменило оригиналы файлов, которые у вас заменены своими:"
        printf '    %s\n' "${changed[@]}"
        echo "  Мои версии всё равно будут установлены. Если после этого что-то не работает,"
        echo "  их нужно перенести на новую версию оболочки."
    fi
fi

# ---------- 3. Файлы ----------

say "Файлы"
hv=$HOME/.config/hyprstack/hypr-vars.lua vars=$HOME/.config/hyprstack/vars.lua
# Свои переменные (прежний hypr-vars.lua) переезжают в vars.lua: новый hypr-vars.lua
# читает их оттуда и добавляет к ним настройки мыши и сочетаний.
if ((!MINE)) && [[ -f $hv && ! -e $vars ]] && ! grep -q 'vars.lua' "$hv"; then
    echo "  ваши переменные из hypr-vars.lua перенесены в vars.lua"
    do_ cp -p "$hv" "$vars"
fi
copied=0
while IFS= read -r entry; do
    path=${entry#"~ "}
    src=$REPO/home/$path dst=$HOME/$path
    [[ -f $src ]] || { warn "нет в репозитории: $path"; continue; }
    # Личные настройки автора ставятся только с --personal.
    [[ $entry == "~ "* ]] && ((!MINE)) && continue
    if [[ -f $dst && ! -L $dst ]] && cmp -s "$src" "$dst"; then
        continue
    fi
    echo "  ~/$path"
    if [[ -e $dst || -L $dst ]]; then
        do_ mkdir -p "$BACKUP/$(dirname "$path")"
        do_ cp -P -p "$dst" "$BACKUP/$path"
        do_ rm -f "$dst"
    fi
    do_ mkdir -p "$(dirname "$dst")"
    do_ cp -p "$src" "$dst"
    copied=$((copied + 1))
done < <(entries)
((copied)) || echo "  всё уже совпадает"
((MINE)) || echo "  личные настройки автора (строки «~» в files.txt) пропущены; поставить их: --personal"
# extras.lua (голосовой ввод, ночной режим, кнопка питания) подключается из local.lua.
local_lua=$HOME/.config/hyprstack/local.lua
if ! grep -q 'extras.lua' "$local_lua" 2>/dev/null; then
    echo "  ~/.config/hyprstack/local.lua: подключение extras.lua"
    if ((!CHECK)); then
        [[ -e $local_lua ]] && { mkdir -p "$BACKUP/.config/hyprstack"; cp -p "$local_lua" "$BACKUP/.config/hyprstack/local.lua"; }
        printf '\n-- Voice input, night light and the power key menu (hyprstack-personal-config).\ndofile((os.getenv("XDG_CONFIG_HOME") or os.getenv("HOME") .. "/.config") .. "/hyprstack/extras.lua")\n' >> "$local_lua"
    fi
fi
[[ -d $BACKUP ]] && echo "  прежние версии сохранены в $BACKUP"
for script in dictation nightlight caelestia-session-start; do
    [[ -f $HOME/.local/bin/$script ]] && do_ chmod +x "$HOME/.local/bin/$script"
done

# Настройки оболочки, которые живут в общем shell.json: кнопка ночного режима
# в быстрых переключателях, Dolphin для кнопки «Папка» у записей экрана, список
# приложений и дашборд только по сочетанию клавиш (не выскакивают от мыши у края),
# угловая панель утилит выключена: её карточки на вкладке дашборда «Управление».
shell_json=$HOME/.config/hyprstack/shell.json
if [[ -f $shell_json ]]; then
    patched=$(jq '
        .general.apps.explorer = ["dolphin", "--select"]
        | .launcher.showOnHover = false
        | .dashboard.showOnHover = false
        | .utilities.enabled = false
        | if (.utilities.quickToggles // null) == null or any(.utilities.quickToggles[]; .id == "nightLight") then .
          else .utilities.quickToggles += [{"enabled": true, "id": "nightLight"}] end' "$shell_json")
    if [[ -n $patched && $patched != "$(jq . "$shell_json")" ]]; then
        echo "  ~/.config/hyprstack/shell.json: кнопка ночного режима, Dolphin для записей, список приложений и дашборд"
        if ((!CHECK)); then
            mkdir -p "$BACKUP/.config/hyprstack"
            cp -p "$shell_json" "$BACKUP/.config/hyprstack/shell.json"
            printf '%s\n' "$patched" > "$shell_json.tmp" && chmod 600 "$shell_json.tmp" && mv "$shell_json.tmp" "$shell_json"
        fi
    fi
fi

# ---------- 4. Модель распознавания речи и прочее ----------

say "Голосовой ввод"
model=$HOME/.local/share/whisper-models/ggml-large-v3-turbo-q5_0.bin
if [[ -f $model ]]; then
    echo "  модель на месте"
else
    warn "Нет модели whisper (large-v3-turbo-q5_0, ~550 МБ, с huggingface.co/ggerganov/whisper.cpp)"
    if ((!CHECK)) && [[ -t 0 ]]; then
        read -r -p "  Скачать сейчас? [y/N] " answer
        if [[ $answer == [yYдД]* ]]; then
            mkdir -p "$(dirname "$model")"
            curl -L --fail -o "$model.part" \
                https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin \
                && mv "$model.part" "$model"
        fi
    fi
fi
if ! grep -q -E '^\s*allow_remote_control' "$HOME/.config/kitty/kitty.conf" 2>/dev/null; then
    warn "В kitty выключено удалённое управление: текст будет печататься через wtype."
    echo "  Для вставки напрямую добавьте в ~/.config/kitty/kitty.conf:"
    echo "    allow_remote_control socket-only"
    echo '    listen_on unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}.sock'
fi
if [[ ! -f /etc/systemd/logind.conf.d/50-power-key.conf ]]; then
    warn "Кнопка питания будет выключать ноутбук сразу. Чтобы она открывала меню:"
    echo "    sudo mkdir -p /etc/systemd/logind.conf.d"
    echo "    printf '[Login]\\nHandlePowerKey=ignore\\n' | sudo tee /etc/systemd/logind.conf.d/50-power-key.conf"
    echo "  (действует после перезагрузки)"
fi

# ---------- 5. Применить ----------

((APPLY)) || { say "Готово (без применения)"; exit 0; }

say "Применение"
fallback=$HOME/.config/systemd/user/hyprstack.service.d/90-fallback.conf
[[ -f $fallback ]] && rm -f "$fallback" && echo "  снят аварийный запуск стандартной оболочки"
systemctl --user daemon-reload
systemctl --user enable --now hyprstack-nightlight-schedule.timer >/dev/null 2>&1 && echo "  таймер ночного режима включён"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null && echo "  Hyprland перезагружен"
    errors=$(hyprctl configerrors 2>/dev/null | grep -v -i -E '^(no errors|ok)?$')
    [[ -n $errors ]] && warn "Ошибки конфига Hyprland:" && echo "$errors"
    "$HOME/.local/bin/nightlight" apply

    since=$(date '+%Y-%m-%d %H:%M:%S')
    systemctl --user restart hyprstack.service
    sleep 8
    if pgrep -f "qs --path $PERSONAL" >/dev/null &&
        ! journalctl --user -u hyprstack.service --since "$since" --no-pager -o cat | grep -q -E 'ERROR|Failed to load'; then
        echo "  оболочка перезапущена"
    else
        warn "Оболочка с доработками не запустилась:"
        journalctl --user -u hyprstack.service --since "$since" --no-pager -o cat | grep -E 'ERROR|caused' | head -6
        if [[ -d $BACKUP/$PERSONAL_REL ]]; then
            echo "  Возвращаю прежние файлы оболочки из $BACKUP"
            cp -a "$BACKUP/$PERSONAL_REL." "$PERSONAL/"
        fi
        echo "  Запускаю стандартную оболочку (без доработок)."
        systemctl --user set-environment HYPRSTACK_SHELL_DIR="$INSTALLED"
        mkdir -p "$HOME/.config/systemd/user/hyprstack.service.d"
        printf '[Service]\nEnvironment=HYPRSTACK_SHELL_DIR=%s\n' "$INSTALLED" \
            > "$HOME/.config/systemd/user/hyprstack.service.d/90-fallback.conf"
        systemctl --user daemon-reload
        systemctl --user restart hyprstack.service
        echo "  Когда доработки будут исправлены, удалите"
        echo "  ~/.config/systemd/user/hyprstack.service.d/90-fallback.conf и запустите install.sh снова."
        exit 1
    fi
else
    echo "  Hyprland не запущен: изменения применятся при следующем входе."
fi
say "Готово"
