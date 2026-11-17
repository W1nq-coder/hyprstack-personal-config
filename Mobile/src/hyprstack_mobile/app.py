"""Ordinary GTK window: Phosh retains session, lock and edge gestures."""
import datetime
import json
import os
from pathlib import Path
import sys
import gi
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, Gdk, Gio, GLib, Pango
from .backend import Worker, command, battery
from .layout import choose, TEST_SIZES
from .responsive import ResponsiveBin

ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home()/'.config'))/'hyprstack-mobile/settings.json'


def load_config():
    from .config import load
    return load(CONFIG)


class Mobile(Gtk.Application):
    def __init__(self, smoke=False, size=(360, 800)):
        super().__init__(application_id='io.github.W1nqCoder.HyprstackMobile',
                         flags=Gio.ApplicationFlags.NON_UNIQUE if smoke else Gio.ApplicationFlags.DEFAULT_FLAGS)
        self.size = size
        self.smoke = smoke
        self.config = load_config()
        self.worker = Worker()
        self.failed = False
        self.connect('activate', self.checked_activate)

    def checked_activate(self, *_):
        try:
            self.activate()
        except Exception:
            import traceback
            traceback.print_exc()
            self.failed = True
            self.quit()

    def button(self, text, callback):
        b = Gtk.Button()
        b.set_child(Gtk.Label(label=text, wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR, max_width_chars=18))
        b.connect('clicked', lambda _: callback())
        return b

    def message(self, text):
        self.status.set_text(text)
        self.status.set_tooltip_text(text)

    def execute(self, argv):
        self.worker.run('action', lambda: command(argv),
                        lambda value, error: (self.message(error or value or 'Готово'), self.refresh()))

    def save(self):
        try:
            CONFIG.parent.mkdir(parents=True, exist_ok=True)
            tmp = CONFIG.with_suffix('.tmp')
            tmp.write_text(json.dumps(self.config, ensure_ascii=False))
            tmp.replace(CONFIG)
        except OSError as exc:
            self.message(str(exc))

    def theme(self):
        mode = 'light' if self.config.get('light') else 'dark'
        p = json.loads((ROOT/'themes/tokens/catppuccin.json').read_text())['modes'][mode]
        surface = p['palette']['surface0']
        css = f'''window {{ background: #{p['background']}; color: #{p['foreground']}; }}
        button, entry {{ min-height: 44px; min-width: 44px; border-radius: 18px; }}
        button {{ background: #{surface}; color: #{p['foreground']}; padding: 6px; }}
        button:hover {{ background: #{p['accent']}; color: #{p['background']}; }}
        .clock {{ font-size: 3em; font-weight: 300; color: #{p['accent']}; }}
        .card {{ background: #{surface}; border-radius: 24px; padding: 16px; }}
        .title {{ font-size: 1.3em; font-weight: bold; }}'''
        self.css.load_from_data(css.encode())
        Gtk.Settings.get_default().set_property('gtk-enable-animations', not self.config.get('reduce_motion', False))

    def toggle(self, key):
        self.config[key] = not self.config.get(key, False)
        self.save()
        self.theme()

    def activate(self, *_):
        if self.get_active_window():
            self.get_active_window().present()
            return
        self.win = Gtk.ApplicationWindow(application=self, title='Hyprstack Mobile')
        self.win.set_default_size(*self.size)
        self.css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), self.css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.theme()
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for side in ('top', 'bottom', 'start', 'end'):
            getattr(root, 'set_margin_'+side)(12)
        self.root = root
        self.layout_state = None
        self.responsive = ResponsiveBin(root, self.adapt)
        self.win.set_child(self.responsive)
        self.connect('shutdown', lambda *_: self.responsive.release())
        header = Gtk.Box(spacing=8)
        title = Gtk.Label(label='Hyprstack', xalign=0, hexpand=True, ellipsize=Pango.EllipsizeMode.END)
        title.add_css_class('title')
        header.append(title)
        header.append(self.button('Закрыть', self.win.close))
        root.append(header)
        self.stack = Gtk.Stack(vexpand=True, transition_type=Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        root.append(self.stack)
        home = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.clock = Gtk.Label(css_classes=['clock'])
        self.date = Gtk.Label(wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR)
        self.battery_label = Gtk.Label(label='Батарея: чтение…', wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR)
        for w in (self.clock, self.date, self.battery_label):
            home.append(w)
        wallpaper = self.config.get('wallpaper')
        if wallpaper and Path(wallpaper).is_file():
            pic = Gtk.Picture.new_for_filename(wallpaper)
            pic.set_size_request(-1, 100)
            pic.set_can_shrink(True)
            home.append(pic)
        self.search = Gtk.SearchEntry(placeholder_text='Поиск приложений')
        self.search.connect('search-changed', lambda _: self.grid.invalidate_filter())
        home.append(self.search)
        self.grid = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,
                                min_children_per_line=1, max_children_per_line=8,
                                row_spacing=8, column_spacing=8, homogeneous=True)
        self.grid.set_filter_func(lambda child: self.search.get_text().casefold() in child.get_child().search_name)
        self.dock = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, min_children_per_line=1, max_children_per_line=8, homogeneous=True, row_spacing=8, column_spacing=8)
        self.populate()
        home.append(self.grid)
        home.append(self.dock)
        scroll = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.set_child(home)
        viewport = scroll.get_child()
        if isinstance(viewport, Gtk.Viewport):
            viewport.set_scroll_to_focus(True)
        self.home_scroll = scroll
        self.stack.add_titled(scroll, 'home', 'Приложения')
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.readouts = {}
        self.cards = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, min_children_per_line=1, max_children_per_line=4, homogeneous=True, row_spacing=8, column_spacing=8)
        panel.append(self.cards)
        queries = {'Wi-Fi': ['nmcli', 'radio', 'wifi'], 'Bluetooth': ['bluetoothctl', 'show'],
                   'Громкость': ['wpctl', 'get-volume', '@DEFAULT_AUDIO_SINK@'],
                   'Яркость': ['brightnessctl', '-c', 'backlight', 'get'],
                   'Музыка': ['playerctl', 'metadata', '--format', '{{artist}} — {{title}}']}
        self.queries = queries
        for name in queries:
            label = Gtk.Label(label=f'{name}: …', xalign=0, wrap=True, max_width_chars=35)
            self.readouts[name] = label
            label.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
            label.add_css_class('card')
            self.cards.append(label)
        actions = [
            ('Wi-Fi вкл', ['nmcli','radio','wifi','on']), ('Wi-Fi выкл', ['nmcli','radio','wifi','off']),
            ('Bluetooth вкл', ['bluetoothctl','power','on']), ('Bluetooth выкл', ['bluetoothctl','power','off']),
            ('Громче', ['wpctl','set-volume','-l','1.0','@DEFAULT_AUDIO_SINK@','5%+']),
            ('Тише', ['wpctl','set-volume','@DEFAULT_AUDIO_SINK@','5%-']),
            ('Ярче', ['brightnessctl','-c','backlight','set','5%+']),
            ('Темнее', ['brightnessctl','-c','backlight','-n','set','5%-']),
            ('⏮', ['playerctl','previous']), ('⏯', ['playerctl','play-pause']), ('⏭', ['playerctl','next']),
            ('VPN / сети', ['gnome-control-center','network']), ('Настройки', ['gnome-control-center'])]
        flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE, max_children_per_line=4, min_children_per_line=1, homogeneous=True)
        self.actions_grid = flow
        import shutil
        for name, argv in actions:
            b = self.button(name, lambda a=argv: self.execute(a))
            b.set_sensitive(bool(shutil.which(argv[0])))
            flow.append(b)
        panel.append(flow)
        panel.append(self.button('Светлая / тёмная', lambda: self.toggle('light')))
        panel.append(self.button('Включить / отключить анимации', lambda: self.toggle('reduce_motion')))
        panel.append(self.button('Обновить состояние', self.refresh))
        panel.append(Gtk.Label(label='Ночной режим и уведомления: штатная панель Phosh', wrap=True))
        sc = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        sc.set_child(panel)
        self.stack.add_titled(sc, 'controls', 'Управление')
        nav = Gtk.Box(spacing=8, homogeneous=True)
        for name, label in [('home','Домой'), ('controls','Управление')]:
            nav.append(self.button(label, lambda n=name: self.stack.set_visible_child_name(n)))
        root.append(nav)
        self.status = Gtk.Label(wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR, max_width_chars=28, lines=2, ellipsize=Pango.EllipsizeMode.END)
        root.append(self.status)
        swipe = Gtk.GestureSwipe()
        swipe.connect('swipe', self.swipe)
        header.add_controller(swipe)  # Only header; no interception of Phosh screen edges.
        self.tick()
        self.refresh()
        GLib.timeout_add_seconds(30, self.tick)
        GLib.timeout_add_seconds(60, self.refresh)
        self.win.present()
        if self.smoke:
            GLib.timeout_add_seconds(3, self.smoke_done)

    def adapt(self, width, height):
        font = self.root.get_pango_context().get_font_description()
        scale = font.get_size() / Pango.SCALE / 11 if font else 1.0
        state = choose(width, height, scale)
        if state == self.layout_state:
            return
        self.layout_state = state
        for side in ('top', 'bottom', 'start', 'end'):
            getattr(self.root, 'set_margin_' + side)(state.margin)
        self.root.set_spacing(6 if state.short else 12)
        for grid, columns in ((self.grid, state.columns), (self.dock, state.columns),
                              (self.cards, state.card_columns), (self.actions_grid, state.card_columns)):
            grid.set_max_children_per_line(columns)
        self.clock.set_visible(not state.short)
        # GtkViewport scroll-to-focus keeps SearchEntry reachable with the OSK.

    def smoke_done(self):
        try:
            assert self.win.get_mapped(), 'window not mapped'
            assert self.clock.get_text(), 'clock empty'
            self.stack.set_visible_child_name('controls')
            assert self.stack.get_visible_child_name() == 'controls'
            self.stack.set_visible_child_name('home')
            # Empty application catalogs are valid on minimal installations.
            assert self.win.get_width() >= 1
            assert self.layout_state is not None
            for widget in (self.grid, self.dock, self.search):
                assert widget.get_width() <= self.responsive.get_width(), 'horizontal overflow'
            assert self.root.measure(Gtk.Orientation.HORIZONTAL, -1)[0] <= self.size[0], 'minimum width exceeds test size'
            print(f'SMOKE OK: mapped GTK window {self.win.get_width()}x{self.win.get_height()}, clock, dashboard')
        except Exception:
            import traceback
            traceback.print_exc()
            self.failed = True
        finally:
            self.quit()
        return False

    def swipe(self, gesture, vx, vy):
        if abs(vx) > abs(vy) and abs(vx) > 100:
            self.stack.set_visible_child_name('controls' if vx < 0 else 'home')

    def populate(self):
        for app in sorted(Gio.AppInfo.get_all(), key=lambda a: a.get_display_name().casefold()):
            if not app.should_show():
                continue
            b = self.button('', lambda a=app: self.launch(a))
            b.search_name = app.get_display_name().casefold()
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
            icon = Gtk.Image.new_from_gicon(app.get_icon()) if app.get_icon() else Gtk.Image.new_from_icon_name('application-x-executable')
            icon.set_pixel_size(32)
            box.append(icon)
            box.append(Gtk.Label(label=app.get_display_name(), ellipsize=3, max_width_chars=8, width_chars=1))
            b.set_child(box)
            long = Gtk.GestureLongPress()
            long.connect('pressed', lambda g,x,y,a=app,w=b: self.context(a,w))
            b.add_controller(long)
            self.grid.append(b)
        self.refresh_dock()

    def refresh_dock(self):
        while self.dock.get_first_child():
            self.dock.remove(self.dock.get_first_child())
        apps = {app.get_id(): app for app in Gio.AppInfo.get_all() if app.should_show()}
        for app_id in self.config.get('favorites', []):
            app = apps.get(app_id)
            if app is None:
                continue
            button = self.button('', lambda a=app: self.launch(a))
            button.set_tooltip_text(app.get_display_name())
            button.set_child(Gtk.Label(label=app.get_display_name(), ellipsize=3, max_width_chars=8, width_chars=1))
            self.dock.append(button)

    def context(self, app, widget):
        pop = Gtk.Popover(autohide=True)
        pop.set_parent(widget)
        def favorite():
            ids = self.config.get('favorites', [])
            if app.get_id() in ids:
                ids.remove(app.get_id())
            elif app.get_id():
                ids = ids + [app.get_id()]
            self.config['favorites'] = ids
            self.save()
            pop.popdown()
            self.refresh_dock()
            self.message('Избранное сохранено')
        pop.set_child(self.button('Добавить / убрать из дока', favorite))
        pop.connect('closed', lambda p: p.unparent())
        pop.popup()

    def launch(self, app):
        try:
            app.launch([], Gdk.Display.get_default().get_app_launch_context())
        except GLib.Error as exc:
            self.message(str(exc))

    def tick(self):
        now = datetime.datetime.now()
        self.clock.set_text(now.strftime('%H:%M'))
        self.date.set_text(now.strftime('%A, %d %B'))
        return True

    def refresh(self):
        self.worker.run('battery', battery, lambda v,e: self.battery_label.set_text(v if not e else 'UPower недоступен'))
        for name, argv in self.queries.items():
            self.worker.run(name, lambda a=argv: command(a),
                lambda v,e,n=name: self.readouts[n].set_text(f'{n}: {(e or v)[:150]}'))
        return True


def main():
    if os.geteuid() == 0:
        raise SystemExit('Не запускайте интерфейс от root')
    if not Gtk.init_check() or Gdk.Display.get_default() is None:
        raise SystemExit('GTK: нет доступа к графическому дисплею')
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--smoke-test', action='store_true')
    parser.add_argument('--size', choices=TEST_SIZES, default='360x800')
    args = parser.parse_args()
    app = Mobile(args.smoke_test, tuple(map(int, args.size.split('x'))))
    result = app.run([sys.argv[0]])
    return 1 if app.failed else result
