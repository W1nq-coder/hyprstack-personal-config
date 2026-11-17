# Исследование и совместимость

Дата: 2026-11-17. Среда разработки: CachyOS x86_64, Python 3.14, GTK 4.
Все три удалённых git clone предприняты, но DNS github.com недоступен в sandbox.
Два репозитория клонированы из существующих локальных Git-копий без изменения оригиналов:

- [Hyprstack](https://github.com/hase9awa/hyprstack-shell), `522fccaaf2d2faf05282185526a62e8cb1275852`.
- [Personal](https://github.com/W1nq-coder/hyprstack-personal-config), `36d5de0dd23b988bef455cc6c44bbcde5211b26a`.
- [Device](https://github.com/asidko/redmi-note-9s-postmarketos): через GitHub connector прочитаны README (`d8a066bb737a5ba97e887377adf026c4fbeace28`) и download.sh (`fcff8f0c372f7061e28f08a0a4c66be9a65aef82`). Полного клона нет. Репозиторий содержит инструкции/загрузчик образов; код в проект не переносился, скрипты не исполнялись. README указывает v25.12, systemd-v25.12, xiaomi-miatoll/curtana. Это сведения автора сборки, не аппаратная проверка.

## Реальные источники дизайна

| Исходный файл / каталог Hyprstack | Назначение | Перенос |
|---|---|---|
| shell/services/Colours.qml | M3-роли, прозрачность, чтение схем | CSS локального GTK provider |
| shell/services/ThemeSchemes.qml | каталог тем, Python helper | две локальные палитры |
| shell/assets/schemes/presets.json | именованные RGB | Catppuccin Mocha/Latte без изменения цветов |
| shell/assets/schemes/SOURCES.md | происхождение палитр | THIRD_PARTY.md |
| shell/modules/bar, dashboard, launcher | панели, карточки, поиск | GTK Box/FlowBox/Stack |
| shell/modules/dashboard/Media.qml | QtQuick, M3Shapes, сервисы | playerctl/MPRIS |
| shell/modules/nexus, notifications, lock | настройки, уведомления, блокировка | настройки приложения; остальное Phosh |
| shell/plugin/src/Hyprstack/Config/anim.cpp | Qt easing / токены анимаций | GTK Stack, отключаемые анимации |
| personal/home/.config/hyprstack/shell.json | масштаб 1, прозрачность ~0.971 | мобильные размеры; непрозрачные карточки |
| personal/home/.local/share/hyprstack-personal/shell/services/NightLight.qml | Qt/Quickshell ночной режим | не запускается под Phosh |

Выбрана существующая Catppuccin из каталога, а не утверждение о текущей активной теме пользователя. QtQuick, Quickshell.Io, Hyprstack.Config, Hyprstack.Images и Hyprland IPC не являются Phosh API. Их код и конфигурации не устанавливаются.

## Стек и системные функции

| Компонент | Проверенный интерфейс | Статус |
|---|---|---|
| Python/PyGObject/GTK4 | локальный импорт GI; Alpine v3.23 aarch64 [GTK](https://pkgs.alpinelinux.org/package/v3.23/community/aarch64/gtk4.0), [GI](https://pkgs.alpinelinux.org/package/v3.23/main/aarch64/py3-gobject3) | зависимости доступны; ARM64 сборка ещё не запускалась |
| Приложения | Gio.AppInfo, desktop entries | реализация; нужна GUI-проверка |
| Батарея | [UPower Device](https://upower.freedesktop.org/docs/Device.html), DisplayDevice Properties.GetAll | только чтение; неизвестные состояния не вызывают shutdown |
| Wi-Fi | [nmcli radio wifi](https://networkmanager.dev/docs/api/latest/nmcli.html) | наличие CLI проверяется, ошибки службы отображаются |
| Bluetooth | bluetoothctl show / power | BlueZ CLI установлен на ПК; устройство не проверено |
| Звук | [wpctl](https://pipewire.pages.freedesktop.org/wireplumber/man/wpctl.html) get-volume/set-volume | лимит 100%, штатные права PipeWire |
| Яркость | brightnessctl -c backlight | CLI help проверен, доступ udev/logind зависит от системы |
| Музыка | playerctl metadata / play-pause / previous / next | необязательная зависимость, на ПК отсутствует |
| VPN | gnome-control-center network | переход к штатным настройкам, собственного VPN клиента нет |
| Ночной режим | штатный Phosh | отдельный переключатель не реализован |
| Сеть/время/батарея в верхней панели | штатный Phosh | сохранены, не дублируется системная панель |

## Phosh и границы CSS

Изучена [документация классов Phosh](https://world.pages.gitlab.gnome.org/phosh/phosh/) и [рекомендации приложениям](https://world.pages.gitlab.gnome.org/Phosh/phosh/app-dev.html).
Phosh использует GTK3 и layer surfaces; выбранное GTK4 приложение — самостоятельное окно Wayland. CSS процесса не стилизует чужие окна.
[Lockscreen](https://world.pages.gitlab.gnome.org/phosh/phosh/class.Lockscreen.html) имеет CSS node `phosh-lockscreen`, часы, PIN и расширяемые страницы; опубликованный API version 0 не обещает стабильный ABI для всех версий pmOS.
Через CSS можно менять поверхности, цвета и размеры существующих виджетов. Изменение структуры home/lockscreen, логики жестов и расположения PIN требует версионного расширения или патча. CSS не создаёт системных переключателей.

В 0.1 нет глобального GTK CSS, изменений PAM, shell plugins, layer-shell, замены домашней панели или новой аутентификации. Следующий этап — закрепить точную версию Phosh телефона, исследовать её stylesheet и проверить небольшой opt-in CSS, затем отдельный пакет плагина при необходимости.
