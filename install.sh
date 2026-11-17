#!/usr/bin/env bash
# Вернуть мои доработки HyperStack после обновления или переустановки.
#
#   ./install.sh             поставить доработки и применить
#   ./install.sh --personal  то же + мои личные настройки (мониторы, переменные, сочетания,
#                            автозапуск) поверх существующих — для восстановления моей системы
#   ./install.sh --check     только показать, что изменится (ничего не трогает)
#   ./install.sh --no-apply  разложить файлы, но не перезагружать Hyprland и оболочку
#   ./install.sh --no-wallpapers  не скачивать коллекцию обоев (~1 ГБ)
#
# Без --personal личные настройки автора (строки «~ » в files.txt) не ставятся,
# а ваши переменные из hypr-vars.lua переносятся в vars.lua.
# Перед заменой создаётся компактная копия оболочки и настроек.
# Откат: ~/.local/bin/hyprstack-rollback. Хранятся две последние сжатые копии.
set -Eeuo pipefail

REPO=$(dirname "$(readlink -f "$0")")
DATA=${XDG_DATA_HOME:-$HOME/.local/share}
INSTALLED=${HYPRSTACK_DATA_DIR:-$DATA/hyprstack}/shell
PERSONAL=$DATA/hyprstack-personal/shell
PERSONAL_REL=.local/share/hyprstack-personal/shell/
BACKUP=${TMPDIR:-/tmp}/hyprstack-install-$$
RECOVERY=""
CHECK=0
APPLY=1
MINE=0
WALLPAPERS=1
for arg in "$@"; do
    case $arg in
        --check) CHECK=1; APPLY=0 ;;
        --no-apply) APPLY=0 ;;
        --personal) MINE=1 ;;
        --no-wallpapers) WALLPAPERS=0 ;;
        -h | --help) sed -n '2,16p' "$0"; exit 0 ;;
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

# Снимок создаётся до первой замены файлов. Резервная копия обязательна.
# Временные несжатые копии удаляются при выходе; постоянно остаются два сжатых снимка.
finish_install() {
    local result=$?
    trap - EXIT
    set +e
    if ((result != 0)) && [[ -n $RECOVERY ]]; then
        warn "Установка не завершилась. Возвращаю прежнюю оболочку."
        local restore_args=(--archive "$RECOVERY")
        ((APPLY)) || restore_args+=(--no-apply)
        python3 "$HOME/.local/bin/hyprstack-rollback" "${restore_args[@]}" \
            || warn "Автооткат не завершён. Выполните: hyprstack-rollback"
    fi
    [[ -d $BACKUP ]] && rm -rf -- "$BACKUP"
    exit "$result"
}
trap finish_install EXIT
if ((!CHECK)); then
    safety_state=${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack-personal
    mkdir -p "$safety_state" "$HOME/.local/bin"
    exec 8>"$safety_state/install.lock"
    flock -n 8 || { warn "Другая установка уже выполняется"; exit 1; }
    shell_unit=hyprstack.service
    systemctl --user cat hyprstack-session.service >/dev/null 2>&1 && shell_unit=hyprstack-session.service
    # Use the service that actually owns the current shell when both names exist.
    qs_pid=$(pgrep -x qs | head -1 || true)
    if [[ -n $qs_pid ]]; then
        running_unit=$(sed -n 's#.*/\(hyprstack[^/]*\.service\)$#\1#p' "/proc/$qs_pid/cgroup" 2>/dev/null | head -1)
        case $running_unit in hyprstack.service | hyprstack-session.service) shell_unit=$running_unit ;; esac
    fi
    # Recovery tool remains available even after rollback of a first installation.
    install -m 755 "$REPO/home/.local/bin/hyprstack-rollback" "$HOME/.local/bin/hyprstack-rollback"
    say "Резервная копия перед установкой"
    RECOVERY=$(python3 "$HOME/.local/bin/hyprstack-rollback" create --repo "$REPO" --unit "$shell_unit") \
        || { warn "Копия не создана: установка отменена до замены файлов"; exit 1; }
    echo "  Если экран перестанет работать: Ctrl+Alt+F3, войдите и выполните ~/.local/bin/hyprstack-rollback"
fi

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
    return 0
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
if ((!CHECK)); then refresh_links; fi
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
# В Hyprland 0.56 нет hl.dsp.group.lock_active(): сочетание «заблокировать группу» ломает загрузку конфига.
keybinds_lua=$HOME/.config/hypr/hyprland/keybinds.lua
if grep -q 'hl.dsp.group.lock_active()' "$keybinds_lua" 2>/dev/null; then
    echo "  ~/.config/hypr/hyprland/keybinds.lua: group.lock_active() -> group.lock()"
    if ((!CHECK)); then
        mkdir -p "$BACKUP/.config/hypr/hyprland"; cp -p "$keybinds_lua" "$BACKUP/.config/hypr/hyprland/keybinds.lua"
        sed -i 's/hl\.dsp\.group\.lock_active()/hl.dsp.group.lock()/' "$keybinds_lua"
    fi
fi
[[ -n $RECOVERY ]] && echo "  резервная копия: $RECOVERY"
for script in dictation nightlight hyprstack-personal-update hyprstack-personal-update-ui hyprstack-greeter-sync caelestia-session-start; do
    [[ -f $HOME/.local/bin/$script ]] && do_ chmod +x "$HOME/.local/bin/$script"
done

# Закрытые права: здесь история уведомлений (чужие сообщения), настройки и состояние. Если домашняя
# папка открыта другим пользователям компьютера, они не должны это читать.
for d in "$HOME/.config/hyprstack" "${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack-personal" "${XDG_CACHE_HOME:-$HOME/.cache}/hyprstack"; do
    [[ -d $d ]] && do_ chmod 700 "$d"
done
notifs=${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack/notifs.json
[[ -f $notifs ]] && do_ chmod 600 "$notifs"

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

# Запоминаем, где лежит этот клон, чтобы уведомления об обновлениях находили его сами.
if ((!CHECK)); then
    upd_state=${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack-personal
    mkdir -p "$upd_state"
    printf '%s\n' "$REPO" > "$upd_state/repo"
    if ((MINE)); then : > "$upd_state/personal"; else rm -f "$upd_state/personal"; fi
fi

# ---------- 4. Модель распознавания речи и прочее ----------

say "Голосовой ввод"
models_dir=$HOME/.local/share/whisper-models
# Видеопамять дискретной карты в МБ (NVIDIA или AMD); 0 — встроенная графика или нет данных.
vram_mb() {
    local mb=0 f
    if command -v nvidia-smi >/dev/null; then
        mb=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | sort -n | tail -n1)
    fi
    for f in /sys/class/drm/card*/device/mem_info_vram_total; do
        [[ -r $f ]] && (($(<"$f") / 1048576 > ${mb:-0})) && mb=$(($(<"$f") / 1048576))
    done
    [[ $mb =~ ^[0-9]+$ ]] && echo "$mb" || echo 0
}
# fetch_model ФАЙЛ SHA256 URL — скачать только по https; подменённый или битый файл не ставится.
fetch_model() {
    local file=$models_dir/$1
    mkdir -p "$models_dir"
    if curl -L --fail --proto '=https' --proto-redir '=https' -o "$file.part" "$3" &&
        [[ $(sha256sum < "$file.part" | cut -d' ' -f1) == "$2" ]]; then
        mv "$file.part" "$file"
    else
        rm -f "$file.part"
        warn "$1 не скачан или его контрольная сумма не совпала: файл удалён"
    fi
}
# Контрольные суммы — из Hugging Face (LFS oid файлов).
hf=https://huggingface.co/ggerganov/whisper.cpp/resolve/main
if (($(vram_mb) >= 4000)); then
    # Видеокарта с 4+ ГБ: turbo без сжатия, точнее. (Полная large-v3 проверена: чаще выдумывает текст.)
    model=(ggml-large-v3-turbo.bin 1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69 "$hf/ggml-large-v3-turbo.bin" "large-v3-turbo, ~1,6 ГБ")
else
    # Встроенная графика: сжатая turbo, в 3 раза легче.
    model=(ggml-large-v3-turbo-q5_0.bin 394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2 "$hf/ggml-large-v3-turbo-q5_0.bin" "large-v3-turbo-q5_0, ~550 МБ")
fi
vad=(ggml-silero-v6.2.0.bin 2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987
    https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin "Silero VAD — вырезает тишину и шум, ~1 МБ")
for m in model vad; do
    declare -n item=$m
    if [[ -f $models_dir/${item[0]} ]]; then
        echo "  ${item[0]} на месте"
        continue
    fi
    warn "Нет ${item[0]} (${item[3]}, с huggingface.co)"
    if ((!CHECK)) && [[ -t 0 ]]; then
        read -r -p "  Скачать сейчас? [y/N] " answer
        [[ $answer == [yYдД]* ]] && fetch_model "${item[0]}" "${item[1]}" "${item[2]}"
    fi
    unset -n item
done
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

# ---------- 5. Обои ----------

# Снимок локальной коллекции хранится в Releases этого репозитория.
say "Обои"
if ((!WALLPAPERS)); then
    echo "  пропущено (--no-wallpapers)"
else
    wallpaper_args=()
    ((CHECK)) && wallpaper_args+=(--check)
    bash "$REPO/download-wallpapers.sh" "${wallpaper_args[@]}" \
        || warn "Не удалось скачать обои; повторите: $REPO/download-wallpapers.sh"
fi

# ---------- 6. Применить ----------

# Документальное обновление не требует перезапуска графического сеанса.
if ((APPLY)) && [[ -n $RECOVERY ]] && python3 "$HOME/.local/bin/hyprstack-rollback" unchanged --archive "$RECOVERY"; then
    say "Готово: установленные файлы не изменились, перезапуск не требуется"
    exit 0
fi

((APPLY)) || { say "Готово (без применения)"; exit 0; }

say "Применение"
# shell_unit выбран до снимка; откат запустит ту же службу.
fallback=$HOME/.config/systemd/user/$shell_unit.d/90-fallback.conf
[[ -f $fallback ]] && rm -f "$fallback" && echo "  снят аварийный запуск стандартной оболочки"
systemctl --user daemon-reload
systemctl --user enable --now hyprstack-nightlight-schedule.timer >/dev/null 2>&1 && echo "  таймер ночного режима включён"
# Тема экрана входа (noctalia-greeter) следует за темой HyperStack.
if [[ -x /usr/bin/noctalia-greeter-apply-appearance ]]; then
    systemctl --user enable hyprstack-greeter-sync.service hyprstack-greeter-sync.path >/dev/null 2>&1
    systemctl --user start hyprstack-greeter-sync.path >/dev/null 2>&1
    echo "  тема экрана входа будет следовать за темой HyperStack"
    if [[ ! -f ${XDG_STATE_HOME:-$HOME/.local/state}/hyprstack-personal/greeter-passwordless ]]; then
        if [[ -t 0 ]]; then
            read -r -p "  Разрешить синхронизацию темы экрана входа без пароля (нужен sudo)? [y/N] " answer
            [[ $answer == [yYдД]* ]] && "$HOME/.local/bin/hyprstack-greeter-sync" --enable
        else
            echo "  Чтобы это заработало, один раз выполните в терминале: hyprstack-greeter-sync --enable"
        fi
    fi
fi
systemctl --user enable hyprstack-personal-update.service >/dev/null 2>&1   # проверка сразу при входе
systemctl --user enable --now hyprstack-personal-update.timer >/dev/null 2>&1 && echo "  проверка обновлений включена (раз в 2 минуты)"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl reload >/dev/null && echo "  Hyprland перезагружен"
    errors=$(hyprctl configerrors 2>/dev/null | grep -v -i -E '^(no errors|ok)?$' || true)
    if [[ -n $errors ]]; then
        warn "Ошибки конфига Hyprland:"; echo "$errors"
        exit 1
    fi
    "$HOME/.local/bin/nightlight" apply

    since=$(date '+%Y-%m-%d %H:%M:%S')
    old_pid=$(systemctl --user show "$shell_unit" -p MainPID --value)
    systemctl --user restart "$shell_unit"
    sleep 8
    new_pid=$(systemctl --user show "$shell_unit" -p MainPID --value)
    # Оболочка должна быть именно новым процессом, а не прежним, пережившим перезапуск.
    if [[ $new_pid =~ ^[1-9][0-9]*$ && $new_pid != "$old_pid" ]] && systemctl --user is-active --quiet "$shell_unit" &&
        pgrep -f "qs --path $PERSONAL" >/dev/null &&
        ! journalctl --user -u "$shell_unit" --since "$since" --no-pager -o cat | grep -q -E 'ERROR|Failed to load'; then
        echo "  оболочка перезапущена; ручной откат: ~/.local/bin/hyprstack-rollback"
    else
        warn "Оболочка с доработками не запустилась:"
        journalctl --user -u "$shell_unit" --since "$since" --no-pager -o cat | grep -E 'ERROR|caused' | head -6
        echo "  Прежняя версия будет восстановлена из сжатой резервной копии."
        exit 1
    fi
else
    echo "  Hyprland не запущен: изменения применятся при следующем входе."
fi
say "Готово"
