# Мои доработки HyperStack

Личные изменения оболочки HyperStack (Hyprland 0.56, конфиг на Lua):

- **Сочетания клавиш**: изменение любого сочетания, добавление своих сочетаний для запуска
  приложений или команд, удаление. Хранятся в `~/.config/hyprstack/keybinds.json`,
  применяет `keybinds-ui.lua`.
- **Мышь и тачпад**: страница настроек как в KDE Plasma (скорость, ускорение, режим для левши,
  прокрутка, касания, способ клика, вкл/выкл тачпада, отключение при наборе и при подключённой
  мыши, жест смены рабочего стола). Хранятся в `~/.config/hyprstack/input.json`,
  применяет `input-ui.lua`.

Папка `home/` повторяет домашний каталог.

## Восстановление

Нужен установленный HyperStack и личная копия шелла в `~/.local/share/hyprstack-personal/shell`
(остальные её файлы — ссылки на `~/.local/share/hyprstack/shell`).

```sh
cp -r home/. ~/
hyprctl reload
systemctl --user restart hyprstack.service
```

## Откат

Удалить строки хуков `input-ui.lua` и `keybinds-ui.lua` из `~/.config/hyprstack/hypr-vars.lua`
(или файлы `input.json` и `keybinds.json`), затем `hyprctl reload`.
