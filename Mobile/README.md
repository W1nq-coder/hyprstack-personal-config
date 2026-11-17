# Hyprstack Mobile

Мобильный домашний экран и дашборд в стиле Hyprstack для Linux-смартфонов.
Самостоятельный проект внутри `Mobile/`: postmarketOS, Phosh, Wayland, GTK4.
Не является Android-приложением или прошивкой. Лицензия GPL-3.0-only.

## Статус

**Разработка, GUI MVP ещё не прошёл приёмку.** Код и модульные тесты доступны;
запуск графического окна в среде агента блокируется доступом к display.
ARM64 и физический Redmi Note 9S не проверены. Реализация функции не означает
подтверждение её работы на телефоне.

## Возможности

- Код часов/даты, поиска и запуска приложений через Gio, док избранных.
- Палитры Catppuccin Mocha/Latte из Hyprstack, отключаемые анимации.
- Адаптивная сетка 1–8 столбцов, док с переносом строк, прокрутка страниц.
- Интеграции UPower, nmcli, bluetoothctl, wpctl, brightnessctl, playerctl.
- VPN через переход в штатные настройки, обработка отсутствующих служб.
- Пользовательская установка, необязательный автозапуск и откат с сохранением данных.

Модульные тесты проверяют расчёты компоновки, обработку ошибок и установку/откат.
GUI-функции требуют отдельной проверки: [результаты](docs/TEST_RESULTS.md).

## Устройства и требования

Цель — Redmi Note 9S / curtana (xiaomi-miatoll), ARM64, 1080×2400.
Другие смартфоны предусмотрены архитектурой, но не сертифицированы тестами.
Установка требует уже работающего postmarketOS и Phosh, Python 3, PyGObject,
GTK4 и минимум 30 MiB свободного места без учёта зависимостей.
Разработка ведётся на CachyOS. Корневой установщик Desktop не запускайте для Mobile.

## Установка и запуск

Получите основной репозиторий и перейдите в мобильный каталог:

```sh
git clone https://github.com/W1nq-coder/hyprstack-personal-config.git
cd hyprstack-personal-config/Mobile
sudo apk add python3 py3-gobject3 gtk4.0
./scripts/check-dependencies.sh
./scripts/install.sh --autostart
~/.local/share/hyprstack-mobile/scripts/run.sh
```

Сам установщик запускается **без sudo**. Дополнительные CLI и ограничения:
[INSTALL.md](docs/INSTALL.md). Установка ОС — отдельный процесс; прошивки в проекте нет.
Для запуска из исходников в графической сессии: `./scripts/run.sh`.

## Удаление и откат

Закройте приложение, затем:

```sh
./scripts/rollback.sh
# Без исходников:
~/.local/share/hyprstack-mobile/scripts/uninstall.sh
```

Настройки и пользовательские данные сохраняются. [Восстановление через SSH](docs/RECOVERY.md).
Установщик не меняет настольную конфигурацию Hyprstack, PAM, ядро или разделы.

## Разработка на CachyOS

```sh
sudo pacman -S --needed python python-gobject gtk4 make
cd Mobile # из корня репозитория
make check
./scripts/run.sh
./scripts/test-responsive.sh
```

Запускать из терминала графической сессии. Smoke успешен только при коде 0 и
строке `SMOKE OK`. [Сборка исходников и Alpine APK](docs/DEVELOPMENT.md).
GitHub Actions находится в корневом `.github/workflows/mobile.yml` и реагирует на изменения Mobile.

## Адаптивность и ограничения

Компоновка выбирается по фактическому размеру окна, без настройки под модель телефона.
Расчёты проверены для 320×640, 360×800, 393×873, 412×915, 540×1200, 800×360.
HiDPI обслуживает GTK/Wayland. Реальные дробный масштаб, поворот и экранная клавиатура
ещё требуют GUI/аппаратной приёмки. [Аудит](docs/RESPONSIVE_AUDIT.md).

Phosh сохраняет штатные панели, уведомления, PIN и системные жесты.
Глубокая стилизация lockscreen и отдельный ночной режим не реализованы.
Подписки на события служб и измерения энергопотребления — следующий этап.
[Roadmap](docs/ROADMAP.md), [архитектура](docs/ARCHITECTURE.md),
[проверки телефона](docs/DEVICE_SUPPORT.md).

## Авторы и источники

Проект W1nq-coder. Дизайн основан на
[Hyprstack](https://github.com/hase9awa/hyprstack-shell) и
[personal config](https://github.com/W1nq-coder/hyprstack-personal-config).
Целевая система: [postmarketOS](https://postmarketos.org/),
[сборка Redmi Note 9S](https://github.com/asidko/redmi-note-9s-postmarketos).
Авторство палитр и лицензии: [THIRD_PARTY.md](THIRD_PARTY.md).
Исходный локальный мобильный репозиторий сохранён отдельно; перенесён снимок
его коммита `52eefc21755299519253c2cdfb98e207d68a5448`.
