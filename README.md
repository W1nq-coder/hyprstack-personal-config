# Доработки для HyperStack

Дополнения к оболочке [HyperStack](https://github.com/hase9awa/hyprstack-shell) для Hyprland 0.56
(конфиг на Lua): голосовой ввод с локальным распознаванием речи, ночной режим, редактор сочетаний
клавиш, настройки мыши и тачпада, индикатор записи экрана. Всё встраивается в родные настройки
и панели оболочки. Проверено на CachyOS, ноутбук с графикой Intel.

**English:** add-ons for the [HyperStack](https://github.com/hase9awa/hyprstack-shell) Hyprland shell:
local voice dictation (whisper.cpp, Vulkan), night light (hyprsunset) with schedule, keyboard shortcut
editor, mouse & touchpad settings page, screen recording indicator. UI is in Russian and English.
Install: `git clone https://github.com/W1nq-coder/hyprstack-personal-config.git && cd hyprstack-personal-config && ./install.sh`

## Быстрая установка

Нужен установленный HyperStack. Затем:

```sh
sudo pacman -S --needed whisper-cpp ggml-vulkan wtype wl-clipboard jq ffmpeg curl \
  hyprsunset mpv wf-recorder dolphin
git clone https://github.com/W1nq-coder/hyprstack-personal-config.git ~/hyprstack-personal-config
cd ~/hyprstack-personal-config
./install.sh --check   # посмотреть, что изменится
./install.sh
```

`install.sh` не трогает ваши мониторы, сочетания и прочие личные настройки: ваши переменные из
`hypr-vars.lua` он переносит в `vars.lua`, а к `local.lua` только добавляет подключение `extras.lua`.
Заменённые файлы сохраняются в `~/.local/state/hyprstack-personal-backup/<дата>/`.
Для голосового ввода скрипт предложит скачать модель распознавания (~550 МБ).

## Что здесь есть

- **Сочетания клавиш** (Настройки → Сочетания клавиш): изменение любого сочетания карандашиком,
  проверка конфликтов, свои сочетания для запуска приложений и команд.
  Хранятся в `~/.config/hyprstack/keybinds.json`, применяет `keybinds-ui.lua`.
- **Мышь и тачпад** (Настройки → Мышь и тачпад): скорость, ускорение, прокрутка, касания, жесты.
  Хранятся в `~/.config/hyprstack/input.json`, применяет `input-ui.lua`.
- **Кнопка питания** открывает меню сеанса оболочки (бинд в `extras.lua`).
- **Голосовой ввод** — Super+Shift+D. Распознавание локально (whisper.cpp на графике Intel через Vulkan),
  текст вставляется в активное окно. Режимы «нажать/нажать» и «удерживать», язык, модель, микрофон, звуки —
  в Настройки → Голосовой ввод. Скрипт `~/.local/bin/dictation`, настройки `~/.config/hyprstack-dictation/config`.
- **Ночной режим** — тёплый оттенок экрана (hyprsunset). Кнопка с луной в быстрых переключателях,
  Super+Shift+N — вкл/выкл, Super+Alt+= / Super+Alt+− — теплее/холоднее, расписание (по умолчанию 21:00–7:00)
  в Настройки → Ночной режим. Скрипт `~/.local/bin/nightlight`, настройки `~/.config/hyprstack/nightlight.json`.
- **Записи экрана**: плашка «Запись · 0:12» внизу экрана во время записи (клик — остановить),
  кнопка «Папка» открывает Dolphin с выделенным файлом, просмотр в mpv, понятные даты в списке.
- **Яркость и затемнение** (`Brightness.qml`, `brightness.py`, `dimming.lua`, `display-tuning.lua`).

Папка `home/` повторяет домашний каталог, список файлов — `files.txt`.
Личная копия оболочки (`~/.local/share/hyprstack-personal/shell`) содержит только изменённые файлы,
остальное в ней — ссылки на установленную оболочку `~/.local/share/hyprstack/shell`.

## Установка с нуля (моя система целиком)

Команды можно копировать и вставлять по порядку. Основа — CachyOS, при установке выбран Hyprland
(установщик сам ставит драйверы Intel, `hyprland`, `kitty`, `dolphin`, `alacritty`, `btop` и т.п.).

### 1. HyperStack

Зависимости (из [официальной инструкции](https://github.com/hase9awa/hyprstack-shell/blob/main/INSTALL.md#arch)):

```sh
sudo pacman -Syu --needed base-devel git cmake ninja pkgconf gettext \
  hyprland quickshell nlohmann-json qt6-base qt6-declarative qt6-shadertools \
  qt6-svg qt6-imageformats qt6-wayland qt5ct qt6ct libqalculate lm_sensors \
  pixman libdrm libinput systemd-libs wayland libxkbcommon pango cairo \
  python python-pillow kitty firefox fuzzel btop pavucontrol \
  wl-clipboard cliphist grim slurp wf-recorder swappy libnotify \
  brightnessctl networkmanager pipewire pipewire-pulse wireplumber \
  polkit libcap hyprlock hyprpicker xdg-utils xdg-user-dirs libxml2 adwaita-icon-theme dbus \
  glib2 gsettings-desktop-schemas xdg-desktop-portal-gtk
```

Сборка (без `sudo`):

```sh
git clone https://github.com/hase9awa/hyprstack-shell.git ~/hyprstack-shell
cd ~/hyprstack-shell
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DCMAKE_INSTALL_DATADIR="$HOME/.local/share"
cmake --build build --parallel 2
cmake --install build
```

Дальше — шаг «3. Конфигурация» из официальной инструкции `~/hyprstack-shell/INSTALL.md`.

### 2. Пакеты для моих доработок

Голосовой ввод, ночной режим, записи экрана, GitHub:

```sh
sudo pacman -S --needed whisper-cpp ggml-vulkan wtype wl-clipboard jq ffmpeg curl \
  hyprsunset mpv wf-recorder dolphin github-cli
```

### 3. Программы, шрифты и инструменты, которые я ставил дополнительно

```sh
sudo pacman -S --needed hyprpaper swaybg ttf-jetbrains-mono-nerd ttf-material-symbols-variable \
  papirus-icon-theme qt6ct xcb-util-cursor archlinux-xdg-menu file-roller \
  firefox firefox-i18n-ru discord telegram-desktop \
  neovim yazi go python-pip nodejs npm rust paru yay
```

Из AUR:

```sh
yay -S --needed visual-studio-code-bin yandex-music incy-bin
```

Вручную:
- **Happ** — пакет `Happ.linux.x64.pkg.tar.zst` с сайта Happ: `sudo pacman -U ./Happ.linux.x64.pkg.tar.zst`;
- **AppImage-программы** (deckcraft, effectcraft, filmcraft, gridcraft, lightcraft, pdfcraft, photocraft,
  wordcraft) — скачать в `~/Applications`.

### 4. Модель распознавания речи (~550 МБ)

```sh
mkdir -p ~/.local/share/whisper-models
curl -L -o ~/.local/share/whisper-models/ggml-large-v3-turbo-q5_0.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
```

### 5. Кнопка питания открывает меню вместо выключения

```sh
sudo mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandlePowerKey=ignore\n' | sudo tee /etc/systemd/logind.conf.d/50-power-key.conf
```

Действует после перезагрузки.

### 6. kitty: вставка голосового текста напрямую

Добавить в `~/.config/kitty/kitty.conf` и открыть kitty заново:

```
allow_remote_control socket-only
listen_on unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}.sock
```

### 7. Доработки и мои личные настройки

```sh
git clone https://github.com/W1nq-coder/hyprstack-personal-config.git ~/hyprstack-personal-config
cd ~/hyprstack-personal-config
./install.sh --personal
```

`--personal` ставит и мои личные настройки (мониторы, переменные, сочетания, автозапуск —
строки с `~` в `files.txt`) поверх имеющихся. Без него ставятся только сами доработки.

## После обновления или переустановки HyperStack

```sh
cd ~/hyprstack-personal-config
git pull
./install.sh --check               # посмотреть, что изменится (ничего не трогает)
./install.sh                       # у себя: ./install.sh --personal
```

`install.sh`:
1. проверяет пакеты и предлагает доустановить недостающие
   (`whisper-cpp ggml-vulkan wtype wl-clipboard jq ffmpeg hyprsunset mpv wf-recorder dolphin` и др.);
2. восстанавливает личную копию оболочки: подключает новые файлы из обновления, убирает битые ссылки;
3. предупреждает, если обновление изменило оригиналы файлов, которые заменены своими версиями
   (тогда эти файлы, возможно, нужно перенести на новую версию);
4. раскладывает файлы (личные настройки — только с `--personal`); отличающиеся прежние версии сохраняет в
   `~/.local/state/hyprstack-personal-backup/<дата>/`;
5. добавляет в `shell.json` кнопку ночного режима и Dolphin для записей экрана;
6. предлагает скачать модель распознавания речи (~550 МБ), если её нет;
7. перезагружает Hyprland и оболочку. Если оболочка с доработками не запустилась,
   возвращает прежние файлы и запускает стандартную оболочку, чтобы не остаться без панели.

Не хранится в репозитории (install.sh подскажет, если нужно):
- модель whisper `~/.local/share/whisper-models/ggml-large-v3-turbo-q5_0.bin`;
- `/etc/systemd/logind.conf.d/50-power-key.conf` с `HandlePowerKey=ignore` (нужен sudo);
- две строки удалённого управления в `~/.config/kitty/kitty.conf` (для вставки голосового текста в kitty).

## Сохранить новые изменения в репозиторий

```sh
cd ~/hyprstack-personal-config
./collect.sh          # копирует текущие версии файлов из files.txt в home/
git add -A && git commit -m "Описание изменений" && git push
```

Новый файл сначала добавьте строкой в `files.txt`.

## Откат

- Вернуть файлы как были до `install.sh`: скопировать их из `~/.local/state/hyprstack-personal-backup/<дата>/` в `~`.
- Запустить стандартную оболочку без доработок: удалить
  `~/.config/systemd/user/hyprstack.service.d/20-personal-shell.conf` и
  `~/.config/systemd/user/hyprstack-session.service.d/10-personal-shell.conf`, затем
  `systemctl --user daemon-reload && systemctl --user restart hyprstack.service`.
- Отключить голосовой ввод, ночной режим или бинд кнопки питания: удалить соответствующий блок
  в `~/.config/hyprstack/extras.lua` (или строку с `extras.lua` в `local.lua` — тогда все три)
  и выполнить `hyprctl reload`; для ночного режима ещё
  `nightlight off && systemctl --user disable --now hyprstack-nightlight-schedule.timer`.

## Лицензия

GPL-3.0, как и у [HyperStack](https://github.com/hase9awa/hyprstack-shell): часть файлов —
изменённые файлы этой оболочки.
