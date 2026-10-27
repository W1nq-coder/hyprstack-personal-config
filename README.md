# Мои доработки HyperStack

Личные изменения оболочки HyperStack (Hyprland 0.56, конфиг на Lua, CachyOS).

## Что здесь есть

- **Сочетания клавиш** (Настройки → Сочетания клавиш): изменение любого сочетания карандашиком,
  проверка конфликтов, свои сочетания для запуска приложений и команд.
  Хранятся в `~/.config/hyprstack/keybinds.json`, применяет `keybinds-ui.lua`.
- **Мышь и тачпад** (Настройки → Мышь и тачпад): скорость, ускорение, прокрутка, касания, жесты.
  Хранятся в `~/.config/hyprstack/input.json`, применяет `input-ui.lua`.
- **Кнопка питания** открывает меню сеанса оболочки (бинд в `local.lua`).
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

## После обновления или переустановки HyperStack

```sh
cd ~/hyprstack-personal-config     # или: git clone https://github.com/W1nq-coder/hyprstack-personal-config.git
git pull
./install.sh --check               # посмотреть, что изменится (ничего не трогает)
./install.sh
```

`install.sh`:
1. проверяет пакеты и предлагает доустановить недостающие
   (`whisper-cpp ggml-vulkan wtype wl-clipboard jq ffmpeg hyprsunset mpv wf-recorder dolphin` и др.);
2. восстанавливает личную копию оболочки: подключает новые файлы из обновления, убирает битые ссылки;
3. предупреждает, если обновление изменило оригиналы файлов, которые заменены своими версиями
   (тогда эти файлы, возможно, нужно перенести на новую версию);
4. раскладывает файлы; отличающиеся прежние версии сохраняет в
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
- Отключить голосовой ввод или ночной режим: удалить соответствующий блок в конце
  `~/.config/hyprstack/local.lua` и выполнить `hyprctl reload`; для ночного режима ещё
  `nightlight off && systemctl --user disable --now hyprstack-nightlight-schedule.timer`.
