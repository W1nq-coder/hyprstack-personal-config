# Установка

Требуется уже установленный postmarketOS ARM64 с Phosh. Установка ОС — независимый процесс; этот проект не прошивает телефон.
Статус 0.1: предварительная реализация, GUI/ARM64/телефон ещё не прошли приёмку.

Проверьте пакеты в репозиториях вашей версии pmOS:

```sh
sudo apk add python3 py3-gobject3 gtk4.0
# Необязательные интеграции, ставьте только нужные:
sudo apk add networkmanager-cli bluez wireplumber brightnessctl playerctl gnome-control-center
```

Имена базовых GTK/GI пакетов проверены в Alpine v3.23 aarch64. Наличие остальных проверяйте `apk search -x ИМЯ`; не меняйте версии уже работающих системных служб ради приложения.

После получения каталога исходников:

```sh
cd Mobile
./scripts/check-device.sh
./scripts/check-dependencies.sh
./scripts/install.sh --autostart
~/.local/share/hyprstack-mobile/scripts/run.sh
```

Установка без `--autostart` создаёт только пункт меню. Root запрещён. Требуется 30 MiB свободного места (зависимости apk дополнительно). Установщик проверяет ARM64, postmarketOS, Phosh и GI; никаких пакетов сам не скачивает. Каталоги установки фиксированы относительно HOME, XDG переопределения для установленных desktop entries пока не поддерживаются. Настройки приложения учитывают XDG_CONFIG_HOME.

Журнал и резервные копии: `~/.local/state/hyprstack-mobile/manifest.json`. Повторная установка отклоняется: перед обновлением завершите приложение, выполните rollback, затем install. Права системных устройств не меняются; ошибка brightnessctl означает необходимость проверить штатную конфигурацию устройства, а не запускать GUI через sudo.

Альтернатива — APK из `docs/DEVELOPMENT.md`. Не смешивайте APK и пользовательскую установку. APK удаляется через `sudo apk del hyprstack-mobile`; пользовательские скрипты управляют только пользовательской установкой.
