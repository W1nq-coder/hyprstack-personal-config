# Проверки 2026-11-17

Среда: CachyOS x86_64, системный Python 3.14, импорт Gtk 4. Проект не устанавливался в рабочую сессию пользователя.

| Проверка | Результат |
|---|---|
| compileall src/scripts | PASS |
| sh -n всех .sh | PASS |
| unittest: 8 тестов | PASS |
| installer roundtrip в TemporaryDirectory | PASS, оригинальный desktop восстановлен |
| данные пользователя после удаления | PASS, сохранены |
| изменённый установленный файл | PASS, сохранён в preserved перед восстановлением |
| прерванная установка | PASS, journal позволяет откат |
| повторная установка / symlink / нехватка места | PASS, отказ |
| запуск GUI smoke | BLOCKED: Gtk не имеет доступа к графическому display |
| отдельная D-Bus сессия | BLOCKED: bind socket Operation not permitted |
| GitHub | get_repo вернул 404; gh/Git DNS недоступен, создание не выполнено |
| Alpine abuild / ARM64 | NOT RUN |
| GitHub Actions | NOT RUN, workflow подготовлен |
| физический curtana | NOT RUN |

Ошибка графического окружения выдаёт ненулевой код. Наличие кода не считается прохождением smoke. Нет утверждений об измеренных RSS/FPS/CPU, работе системных переключателей или блокировки телефона.

Source archive воспроизводится из одного HEAD через git archive + gzip -n; build/alpine содержит APKBUILD с вычисленной SHA512. Это подготовка сборки, не собранный APK.

## Продолжение разработки

Исходное состояние: чистое дерево, HEAD 2f92f25; существующие изменения не удалялись.

- GTK 4.24 / PyGObject импортируются. WAYLAND_DISPLAY=wayland-1, XDG_RUNTIME_DIR=/run/user/1000, но Gdk.Display.get_default() возвращает None. Наличие переменных не доказывает доступ к compositor.
- Обычный `scripts/run.sh` и `--smoke-test`: код 1, «GTK: нет доступа к графическому дисплею». GUI **BLOCKED**.
- 10 unittest: PASS; compileall и sh -n: PASS. Новые regression tests проверяют некорректные типы настроек и доставку ошибок UPower/BlueZ/NetworkManager/MPRIS из worker. Службы в этих тестах имитированы; реальные переключения не проверялись.
- Исправлены: типы settings.json до передачи Path/GTK; live dock с сокращением длинных подписей; smoke гарантированно завершается при провале assertion, пустой каталог приложений допустим.
- Добавлен выбор логического окна 360×800, 540×1200, 320×640. Расчёт scale 3/2 проверен арифметически; компоновка, поиск, жесты, OSK и dock визуально **NOT RUN**.
- abuild и qemu-aarch64 отсутствуют; Docker установлен, доступ к socket запрещён. ARM64 APK **NOT RUN**. Команды нативной сборки и ручной GUI-приёмки добавлены в DEVELOPMENT.md.

Готовность реально работающего GUI MVP всё ещё требует внешнего запуска по инструкции. Аппаратные проверки, оценка нагрузки и системных интеграций не засчитываются.

## Responsive implementation

- `make check`: 17 тестов, 15 PASS, 2 SKIP (GTK measurement без display). Включены прежние проверки установки/отката, новых зависимостей нет.
- Расчётные размеры PASS: 360×800, 540×1200, 393×873, 412×915, 320×640, 800×360. Проверены режимы, пределы бюджета ширины, поворот, коэффициенты шрифта 1/1.5/2, ширина от 240 px.
- Compileall, shell syntax и git diff --check: PASS.
- `scripts/test-responsive.sh`: остановка на первом размере, код 1 «GTK: нет доступа к графическому дисплею». Ни один визуальный размер не засчитан.
- Реальная геометрия дока с длинными именами и увеличенным шрифтом: отдельные GTK tests подготовлены, но SKIP. Live resize, поиск с OSK, fractional scaling и физическое устройство: NOT RUN.

Адаптивность теперь реализована в allocation callback GTK, а не только через стартовые размеры. Это не подтверждает визуальную приёмку; требуется запуск GUI matrix в доступной графической среде.

## Перенос в основной репозиторий

Мобильный снимок 52eefc2 перенесён в Mobile/; исходный локальный репозиторий сохранён.
В каталоге Mobile успешно выполнен make check: 15 PASS, 2 GTK SKIP.
В корне основного репозитория: 14 настольных unittest PASS. Всего 29 PASS, 2 SKIP.
Установка/откат проверены в TemporaryDirectory из нового расположения, не на телефоне;
полная пользовательская установка на CachyOS не выполнялась (ARM64/pmOS guard сохранён).
Compileall, sh -n мобильных скриптов/APKBUILD и bash -n настольного install.sh: PASS.
Корневой install.sh, files.txt и Desktop-код не изменены.

CI перенесён в .github/workflows/mobile.yml основного репозитория, working-directory=Mobile,
paths ограничен Mobile/** и самим workflow; прежнего корневого CI не было.
Архив теперь собирается из Git tree HEAD:Mobile, без Desktop и без дополнительного уровня Mobile/.
Alpine abuild, ARM64, GUI и физический Redmi: NOT RUN. Первичный fetch заблокирован DNS github.com.

Проверка архива выявила пустой архив при git archive HEAD:Mobile из подкаталога.
Исправлено: git -C с корнем репозитория. Повторная проверка должна содержать
38 мобильных файлов без Desktop. Push после интеграционного коммита не прошёл:
Could not resolve host: github.com. YAML просмотрен вручную, YAML parser отсутствует;
GitHub Actions не запускался. Шаблонная проверка секретов совпадений не нашла,
новых файлов больше 1 MiB нет. Это не исчерпывающий security audit.
