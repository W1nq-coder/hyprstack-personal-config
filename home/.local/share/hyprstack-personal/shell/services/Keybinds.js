.pragma library

// Personal overlay: adds editing support (see KeybindsPage.qml, Keybinds.qml, ~/.config/hyprstack/keybinds-ui.lua).

function keyName(value) {
    var names = {SUPER_L: "Super", SUPER_R: "Super", Super_L: "Super", Super_R: "Super", Alt_L: "Alt", Alt_R: "Alt",
        Return: "Enter", Escape: "Esc",
        Space: "Space", space: "Space", Period: ".", Comma: ",", Minus: "−", Equal: "=",
        Backslash: "\\", Page_Up: "Page Up", Page_Down: "Page Down", Prior: "Page Up", Next: "Page Down",
        mouse_down: "Wheel down",
        mouse_up: "Wheel up", "mouse:272": "Left mouse button", "mouse:273": "Right mouse button",
        "mouse:274": "Middle mouse button", XF86MonBrightnessUp: "Brightness up",
        XF86MonBrightnessDown: "Brightness down", XF86AudioRaiseVolume: "Volume up",
        XF86AudioLowerVolume: "Volume down", XF86AudioMute: "Mute audio", XF86AudioMicMute: "Mute microphone",
        XF86AudioPlay: "Play", XF86AudioPause: "Pause", XF86AudioNext: "Next track",
        XF86AudioPrev: "Previous track", XF86AudioStop: "Stop media", XF86PowerOff: "Power button"};
    return names[value] || value;
}

var MODMASK = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"], [2, "CAPS"], [16, "MOD2"], [32, "MOD3"], [128, "MOD5"]];
var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5"];
var MOD_ALIASES = {SUPER: "SUPER", WIN: "SUPER", LOGO: "SUPER", MOD4: "SUPER", META: "SUPER",
    CTRL: "CTRL", CONTROL: "CTRL", ALT: "ALT", MOD1: "ALT", SHIFT: "SHIFT", CAPS: "CAPS",
    MOD2: "MOD2", MOD3: "MOD3", MOD5: "MOD5"};
var MOD_LABELS = {SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift", CAPS: "Caps Lock",
    MOD2: "Mod2", MOD3: "Mod3", MOD5: "Mod5"};

function asList(value) {
    if (typeof value === "string") return value.trim() ? [value] : [];
    if (Array.isArray(value)) return value.filter(v => typeof v === "string" && v.trim());
    if (value && typeof value === "object") // Lua arrays decoded as objects {"1": ...}
        return Object.keys(value).sort((a, b) => a - b).map(k => value[k]).filter(v => typeof v === "string" && v.trim());
    return [];
}

// "SUPER + ctrl + q" → {mods: ["SUPER","CTRL"], key: "q"}; key keeps its spelling.
function parseChord(chord) {
    var parts = chord.split("+").map(p => p.trim()).filter(p => p.length);
    var mods = [], key = "";
    for (var i = 0; i < parts.length; i++) {
        var alias = MOD_ALIASES[parts[i].toUpperCase()];
        if (alias && i < parts.length - 1) {
            if (!mods.includes(alias)) mods.push(alias);
        } else {
            key = parts[i];
        }
    }
    mods.sort((a, b) => MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b));
    return {mods: mods, key: key};
}

function normaliseParts(mods, key) {
    return mods.slice().sort((a, b) => MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b)).join("+") + "|" + key.toLowerCase();
}

// Comparable identity of a chord (key names are matched case-insensitively by Hyprland).
function normalise(chord) {
    var p = parseChord(chord);
    return normaliseParts(p.mods, p.key);
}

function hyprMods(bind) {
    var mods = [];
    for (var pair of MODMASK)
        if (bind.modmask & pair[0]) mods.push(pair[1]);
    return mods;
}

function normaliseBind(bind) {
    return normaliseParts(hyprMods(bind), bind.key || "code:" + bind.keycode);
}

function displayChord(chord) {
    var p = parseChord(chord);
    var keys = p.mods.map(m => MOD_LABELS[m]);
    var key = keyName(p.key);
    if (key && !keys.includes(key)) keys.push(key);
    return keys.join(" + ");
}

// ---- Recording -----------------------------------------------------------------

var MODIFIER_SYMS = /^(Shift_[LR]|Control_[LR]|Alt_[LR]|Meta_[LR]|Super_[LR]|Hyper_[LR]|ISO_Level\d_\w+|Caps_Lock|Num_Lock|Mode_switch)$/;

function modifierFor(sym) {
    if (/^Shift_/.test(sym)) return "SHIFT";
    if (/^Control_/.test(sym)) return "CTRL";
    if (/^(Alt|Meta)_/.test(sym)) return "ALT";
    if (/^(Super|Hyper)_/.test(sym)) return "SUPER";
    return "";
}

// Key name written to the config: the first-layout (us) keysym, so the shortcut
// works the same with any active layout. Letters are upper case like the defaults.
function configKey(sym) {
    if (/^[a-z]$/.test(sym)) return sym.toUpperCase();
    if (/^[a-z]+$/.test(sym)) return sym.charAt(0).toUpperCase() + sym.slice(1);
    return sym;
}

function keysymFor(scanCode) {
    return KEYSYMS[scanCode] || "";
}

function qtModifiers(flags) {
    var mods = [];
    if (flags & 0x10000000) mods.push("SUPER"); // Qt.MetaModifier
    if (flags & 0x04000000) mods.push("CTRL");
    if (flags & 0x08000000) mods.push("ALT");
    if (flags & 0x02000000) mods.push("SHIFT");
    return mods;
}

function buildChord(mods, key) {
    var ordered = MOD_ORDER.filter(m => mods.includes(m));
    return ordered.concat([key]).join(" + ");
}

function liveText(mods) {
    var ordered = MOD_ORDER.filter(m => mods.includes(m));
    return ordered.map(m => MOD_LABELS[m]).concat(["…"]).join(" + ");
}

// ---- Model -----------------------------------------------------------------------
// A "slot" is one bind as the shell creates it: submap + description + original chord.
// ~/.config/hyprstack/keybinds-ui.lua reports every slot (keybind-slots.json) and
// binds the shell's action to the chords stored for that slot in keybinds.json.

function splitDescription(raw) {
    var split = raw.indexOf(": ");
    return {category: split >= 0 ? raw.slice(0, split) : "Custom", action: split >= 0 ? raw.slice(split + 2) : raw};
}

function slotParts(slot) {
    var parts = slot.split("\t");
    return {submap: parts[0] || "", description: parts[1] || "", chord: parts.slice(2).join("\t")};
}

// Binds that only make sense as they are (internal helpers, modifier releases).
function editableBind(bind) {
    return !!bind.description && !(bind.release && bind.non_consuming) && bind.submap !== "hyprstack-keyrecord";
}

// slots: [{slot, default, chord, submap, description}]
function slotIndex(slots) {
    var byChord = new Map(), defaults = {};
    for (var item of slots || []) {
        if (!item || typeof item.slot !== "string") continue;
        if (defaults[item.slot] === undefined) defaults[item.slot] = item["default"];
        if (!item.chord) continue; // slot currently without a shortcut
        var key = (item.submap || "") + "\t" + (item.description || "") + "\t" + normalise(item.chord);
        if (!byChord.has(key)) byChord.set(key, []);
        if (!byChord.get(key).includes(item.slot)) byChord.get(key).push(item.slot);
    }
    return {byChord: byChord, defaults: defaults};
}

function effectiveValue(slot, defaults, overrides) {
    if (Object.prototype.hasOwnProperty.call(overrides, slot)) return asList(overrides[slot]);
    return defaults[slot] !== undefined ? [defaults[slot]] : [];
}

function sameList(a, b) {
    var x = asList(a).map(normalise).sort(), y = asList(b).map(normalise).sort();
    return x.length === y.length && x.every((v, i) => v === y[i]);
}

// ---- Custom shortcuts (added in Settings) -------------------------------------------
// Stored in keybinds.json "custom": [{id, chord, name, icon, command}] and bound by
// keybinds-ui.lua with the description "Custom: <name>". Chips use the name "custom:<id>".

var CUSTOM_PREFIX = "custom:";

function isCustomName(name) {
    return typeof name === "string" && name.indexOf(CUSTOM_PREFIX) === 0;
}

function customId(name) {
    return isCustomName(name) ? name.slice(CUSTOM_PREFIX.length) : "";
}

function newCustomId(existing) {
    var ids = (existing || []).map(item => item.id);
    var id;
    do {
        id = "c" + Date.now().toString(36) + Math.floor(Math.random() * 1679616).toString(36);
    } while (ids.includes(id));
    return id;
}

function customList(value) {
    if (!Array.isArray(value)) return [];
    return value.filter(item => item && typeof item.id === "string" && typeof item.chord === "string"
        && item.chord.trim() && typeof item.command === "string" && item.command.trim());
}

// Display name for a command typed by hand: the program's file name.
function commandName(command) {
    var first = String(command || "").trim().split(/\s+/)[0] || "";
    return first.replace(/^['"]|['"]$/g, "").split("/").pop();
}

// model: {slots: [...], overrides: {slot: [chords]}, custom: [...]}
function fromHyprland(values, model) {
    if (!Array.isArray(values)) throw new Error("Expected a list of bindings");
    model = model || {};
    var overrides = model.overrides || {};
    var custom = customList(model.custom);
    var customClaimed = new Set();
    var index = slotIndex(model.slots);
    var defaults = index.defaults;
    var claimed = new Set();

    var groups = new Map();
    function group(category, action, submap, mouse) {
        var identity = category + "\n" + action + "\n" + (submap || "") + "\n" + !!mouse;
        if (!groups.has(identity)) groups.set(identity, {key: identity, category: category, action: action,
            shortcuts: [], chips: [], vars: [], modified: false, submap: submap || "", mouse: !!mouse});
        return groups.get(identity);
    }
    function customGroup(item) {
        var identity = CUSTOM_PREFIX + item.id;
        if (!groups.has(identity)) groups.set(identity, {key: identity, category: "Custom", action: item.name || commandName(item.command),
            shortcuts: [], chips: [], vars: [], modified: false, submap: "", mouse: false,
            customId: item.id, icon: item.icon || "", command: item.command});
        return groups.get(identity);
    }
    function addSlot(entry, slot) {
        if (!entry.vars.includes(slot)) entry.vars.push(slot);
        if (Object.prototype.hasOwnProperty.call(overrides, slot)) entry.modified = true;
    }

    for (var bind of values) {
        if (bind.submap === "hyprstack-keyrecord") continue; // recording helper
        if (!bind.submap && (bind.description || "").indexOf("Custom: ") === 0) {
            var own = custom.find(item => !customClaimed.has(item.id)
                && bind.description === "Custom: " + (item.name || item.command) && normalise(item.chord) === normaliseBind(bind));
            if (own) {
                customClaimed.add(own.id);
                var ce = customGroup(own);
                var label0 = displayChord(own.chord);
                ce.shortcuts.push(label0);
                ce.chips.push({label: label0, chord: normalise(own.chord), name: CUSTOM_PREFIX + own.id, index: 0});
                continue;
            }
        }
        var raw = bind.description || ((bind.dispatcher === "__lua" ? "Custom shortcut" : bind.dispatcher)
            + (bind.dispatcher === "__lua" || !bind.arg ? "" : " " + bind.arg));
        var parts = splitDescription(raw);
        var keys = hyprMods(bind).map(m => MOD_LABELS[m]);
        var key = keyName(bind.key || "code:" + bind.keycode);
        if (!keys.includes(key)) keys.push(key);
        var shortcut = keys.join(" + ");
        var entry = group(parts.category, parts.action, bind.submap, bind.mouse);
        if (entry.shortcuts.includes(shortcut)) continue;
        entry.shortcuts.push(shortcut);

        var chord = normaliseBind(bind);
        var slot = "", position = -1;
        if (editableBind(bind)) {
            var candidates = index.byChord.get((bind.submap || "") + "\t" + bind.description + "\t" + chord) || [];
            for (var candidate of candidates) {
                var list = effectiveValue(candidate, defaults, overrides);
                var at = list.findIndex(c => normalise(c) === chord);
                if (at >= 0 && !claimed.has(candidate + "#" + at)) {
                    slot = candidate;
                    position = at;
                    break;
                }
            }
        }
        if (slot) {
            claimed.add(slot + "#" + position);
            addSlot(entry, slot);
        }
        entry.chips.push({label: shortcut, chord: chord, name: slot, index: position});
    }

    // Edited slots whose chords Hyprland does not report yet, or that have no shortcut.
    for (var edited of Object.keys(overrides)) {
        var info = slotParts(edited);
        if (!info.description || info.submap === "hyprstack-keyrecord") continue;
        var parts2 = splitDescription(info.description);
        var list2 = asList(overrides[edited]);
        var missing = list2.map((c, i) => ({chord: c, index: i})).filter(item => !claimed.has(edited + "#" + item.index));
        if (!missing.length && list2.length) continue;
        var entry2 = Array.from(groups.values()).find(e => e.category === parts2.category && e.action === parts2.action
            && e.submap === info.submap) || group(parts2.category, parts2.action, info.submap, false);
        addSlot(entry2, edited);
        for (var item2 of missing) {
            var label = displayChord(item2.chord);
            entry2.shortcuts.push(label);
            entry2.chips.push({label: label, chord: normalise(item2.chord), name: edited, index: item2.index});
        }
        if (!list2.length)
            entry2.chips.push({label: "", chord: "", name: edited, index: 0, empty: true});
    }

    // Custom shortcuts Hyprland does not report yet (saved, reload pending).
    for (var item3 of custom) {
        if (customClaimed.has(item3.id)) continue;
        var ce3 = customGroup(item3);
        var label3 = displayChord(item3.chord);
        ce3.shortcuts.push(label3);
        ce3.chips.push({label: label3, chord: normalise(item3.chord), name: CUSTOM_PREFIX + item3.id, index: 0});
    }

    var order = ["Shell","Applications","Windows","Workspaces","Capture","Clipboard","Media","Session","Custom"];
    return Array.from(groups.values()).sort((a,b) => {
        var ai = order.indexOf(a.category), bi = order.indexOf(b.category);
        return (ai < 0 ? order.length : ai) - (bi < 0 ? order.length : bi)
            || a.category.localeCompare(b.category) || a.action.localeCompare(b.action, undefined, {numeric:true})
            || a.submap.localeCompare(b.submap);
    });
}

// Shortcuts in the same submap using `chord`, except the one being edited.
// Returns [{entry, name, index}] where name is "" for binds that cannot be edited.
function conflicts(entries, chord, editing) {
    var id = normalise(chord);
    var submap = editing && editing.submap || "";
    var found = [];
    for (var entry of entries) {
        if ((entry.submap || "") !== submap) continue;
        for (var chip of entry.chips) {
            if (chip.empty || chip.chord !== id) continue;
            if (editing && chip.name === editing.name && chip.index === editing.index) continue;
            found.push({entry: entry, name: chip.name, index: chip.index, label: chip.label});
        }
    }
    return found;
}

// Value to store: always a list ([] = no shortcut).
function packValue(list) {
    return asList(list);
}

// ---- Search & translation (unchanged behaviour) --------------------------------------

function matches(entry, query, translate) {
    if (query.includes("+")) {
        var chord = query.toLowerCase().replace(/\s+/g, "");
        return [...entry.shortcuts, ...entry.shortcuts.map(value => translateShortcut(value, translate))].some(value => {
            var candidate = value.toLowerCase().replace(/\s+/g, "");
            return chord.endsWith("+") ? candidate.startsWith(chord) : candidate === chord;
        });
    }
    var text = [entry.category, entry.action, translate(entry.category), translate(entry.action),
        entry.submap, ...entry.shortcuts, ...entry.shortcuts.map(value => translateShortcut(value, translate))]
        .join(" ").toLowerCase().replace(/ё/g,"е");
    return query.trim().toLowerCase().replace(/ё/g,"е").split(/\s+/).every(token => text.includes(token));
}

// Compositor descriptions append workspace numbers and directions at runtime.
function translateDescription(text, translate) {
    var match = text.match(/^(.*) (\d+|left|right|up|down|l|r|u|d)$/);
    if (match) {
        var key = match[1] + " %1";
        var translated = translate(key);
        if (translated !== key) return translated.replace("%1", translate(match[2]));
    }
    return translate(text);
}

function translateShortcut(text, translate) {
    return text.split(" + ").map(value => translate(value)).join(" + ");
}

// Strings added by this overlay are missing from the compiled translations.
var RU = {
    "Edit shortcut": "Изменить сочетание",
    "Add shortcut": "Назначить сочетание",
    "Press a key combination… (Esc to cancel)": "Нажмите сочетание клавиш… (Esc — отмена)",
    "Cancel": "Отмена",
    "This shortcut is already in use: %1": "Это сочетание уже используется: «%1»",
    "Show": "Показать",
    "Record another": "Записать другое",
    "Replace": "Заменить",
    "It belongs to a system shortcut and cannot be reassigned here.": "Это системное сочетание, его нельзя переназначить здесь.",
    "Modified": "Изменено",
    "Reset to default": "Сбросить к значению по умолчанию",
    "No shortcut": "Без сочетания",
    "Saving…": "Сохранение…",
    "Unable to save the shortcut": "Не удалось сохранить сочетание",
    "Power button": "Кнопка питания",
    "Custom": "Свои",
    "Add shortcut…": "Добавить сочетание",
    "New shortcut": "Новое сочетание",
    "Shortcut": "Сочетание клавиш",
    "Not set": "Не задано",
    "Record": "Записать",
    "Action": "Действие",
    "Application": "Приложение",
    "Command": "Своя команда",
    "Search applications": "Поиск приложений",
    "No applications found": "Приложения не найдены",
    "Loading applications…": "Загрузка списка приложений…",
    "Command to run, e.g. firefox --private-window": "Команда для запуска, например firefox --private-window",
    "Name (optional)": "Название (необязательно)",
    "Save": "Сохранить",
    "Delete": "Удалить",
    "Delete shortcut": "Удалить сочетание",
    "Resolve the conflict first": "Сначала решите конфликт с другим сочетанием",
    "Choose an application or enter a command": "Выберите приложение или введите команду",
    "Record a key combination": "Запишите сочетание клавиш",
    "It is one of your shortcuts. Change or delete it first.": "Это одно из ваших сочетаний. Сначала измените или удалите его.",
    "Current Hyprland shortcuts, including your custom bindings. Super is the Windows/Meta key. Click the pencil to change a shortcut.":
        "Текущие сочетания Hyprland, включая ваши. Super — клавиша Windows/Meta. Нажмите карандаш, чтобы изменить сочетание."
};

function localText(text, translate, language) {
    var translated = translate(text);
    if (translated !== text) return translated;
    return String(language || "").startsWith("ru") && RU[text] ? RU[text] : text;
}

// xkb keycode (Qt nativeScanCode on Wayland) → keysym of the first level of the
// "us" layout. Generated from `xkbcli compile-keymap --layout us`.
var KEYSYMS = {"9":"Escape","10":"1","11":"2","12":"3","13":"4","14":"5","15":"6","16":"7","17":"8","18":"9","19":"0","20":"minus","21":"equal","22":"BackSpace","23":"Tab","24":"q","25":"w","26":"e","27":"r","28":"t","29":"y","30":"u","31":"i","32":"o","33":"p","34":"bracketleft","35":"bracketright","36":"Return","37":"Control_L","38":"a","39":"s","40":"d","41":"f","42":"g","43":"h","44":"j","45":"k","46":"l","47":"semicolon","48":"apostrophe","49":"grave","50":"Shift_L","51":"backslash","52":"z","53":"x","54":"c","55":"v","56":"b","57":"n","58":"m","59":"comma","60":"period","61":"slash","62":"Shift_R","63":"KP_Multiply","64":"Alt_L","65":"space","66":"Caps_Lock","67":"F1","68":"F2","69":"F3","70":"F4","71":"F5","72":"F6","73":"F7","74":"F8","75":"F9","76":"F10","77":"Num_Lock","78":"Scroll_Lock","79":"KP_Home","80":"KP_Up","81":"KP_Prior","82":"KP_Subtract","83":"KP_Left","84":"KP_Begin","85":"KP_Right","86":"KP_Add","87":"KP_End","88":"KP_Down","89":"KP_Next","90":"KP_Insert","91":"KP_Delete","92":"ISO_Level3_Shift","93":"F24","94":"less","95":"F11","96":"F12","98":"Katakana","99":"Hiragana","100":"Henkan_Mode","101":"Hiragana_Katakana","102":"Muhenkan","104":"KP_Enter","105":"Control_R","106":"KP_Divide","107":"Print","108":"Alt_R","109":"Linefeed","110":"Home","111":"Up","112":"Prior","113":"Left","114":"Right","115":"End","116":"Down","117":"Next","118":"Insert","119":"Delete","121":"XF86AudioMute","122":"XF86AudioLowerVolume","123":"XF86AudioRaiseVolume","124":"XF86PowerOff","125":"KP_Equal","126":"plusminus","127":"Pause","128":"XF86LaunchA","129":"KP_Decimal","130":"Hangul","131":"Hangul_Hanja","133":"Super_L","134":"Super_R","135":"Menu","136":"Cancel","137":"Redo","138":"SunProps","139":"Undo","140":"SunFront","141":"XF86Copy","142":"XF86Open","143":"XF86Paste","144":"Find","145":"XF86Cut","146":"Help","147":"XF86MenuKB","148":"XF86Calculator","150":"XF86Sleep","151":"XF86WakeUp","152":"XF86Explorer","153":"XF86Send","155":"XF86Xfer","156":"XF86Launch1","157":"XF86Launch2","158":"XF86WWW","159":"XF86DOS","160":"XF86ScreenSaver","161":"XF86RotateWindows","162":"XF86TaskPane","163":"XF86Mail","164":"XF86Favorites","165":"XF86MyComputer","166":"XF86Back","167":"XF86Forward","169":"XF86Eject","170":"XF86Eject","171":"XF86AudioNext","172":"XF86AudioPlay","173":"XF86AudioPrev","174":"XF86AudioStop","175":"XF86AudioRecord","176":"XF86AudioRewind","177":"XF86Phone","179":"XF86Tools","180":"XF86HomePage","181":"XF86Reload","182":"XF86Close","185":"XF86ScrollUp","186":"XF86ScrollDown","187":"parenleft","188":"parenright","189":"XF86New","190":"Redo","191":"XF86Tools","192":"XF86Launch5","193":"XF86Launch6","194":"XF86Launch7","195":"XF86Launch8","196":"XF86Launch9","197":"F19","198":"XF86AudioMicMute","199":"XF86TouchpadToggle","200":"XF86TouchpadOn","201":"F23","202":"F24","203":"ISO_Level5_Shift","204":"NoSymbol","205":"NoSymbol","206":"NoSymbol","207":"NoSymbol","208":"XF86AudioPlay","209":"XF86AudioPause","210":"XF86Launch3","211":"XF86Launch4","212":"XF86LaunchB","213":"XF86Suspend","214":"XF86Close","215":"XF86AudioPlay","216":"XF86AudioForward","217":"XF86AudioBassBoost","218":"Print","220":"XF86WebCam","221":"XF86AudioPreset","223":"XF86Mail","224":"XF86Messenger","225":"XF86Search","226":"XF86Go","227":"XF86Finance","228":"XF86Game","229":"XF86Shop","231":"Cancel","232":"XF86MonBrightnessDown","233":"XF86MonBrightnessUp","234":"XF86AudioMedia","235":"XF86Display","236":"XF86KbdLightOnOff","237":"XF86KbdBrightnessDown","238":"XF86KbdBrightnessUp","239":"XF86Send","240":"XF86Reply","241":"XF86MailForward","242":"XF86Save","243":"XF86Documents","244":"XF86Battery","245":"XF86Bluetooth","246":"XF86WLAN","247":"XF86UWB","249":"XF86Next_VMode","250":"XF86Prev_VMode","251":"XF86MonBrightnessCycle","252":"XF86BrightnessAuto","253":"XF86DisplayOff","254":"XF86WWAN","255":"XF86RFKill","256":"XF86AudioMicMute","360":"XF86OK","361":"XF86Select","362":"XF86GoTo","363":"XF86Clear","365":"XF86Option","366":"XF86Info","367":"XF86Time","368":"XF86VendorLogo","370":"XF86MediaSelectProgramGuide","371":"XF86NextFavorite","372":"XF86Favorites","373":"XF86MediaSelectProgramGuide","374":"XF86MediaSelectHome","376":"XF86MediaLanguageMenu","377":"XF86MediaTitleMenu","378":"XF86Subtitle","379":"XF86CycleAngle","380":"XF86FullScreen","381":"XF86AudioChannelMode","382":"XF86Keyboard","383":"XF86AspectRatio","384":"XF86MediaSelectPC","385":"XF86MediaSelectTV","386":"XF86MediaSelectCable","387":"XF86MediaSelectVCR","388":"XF86MediaSelectVCRPlus","389":"XF86MediaSelectSatellite","391":"XF86CD","392":"XF86MediaSelectTape","393":"XF86MediaSelectRadio","394":"XF86MediaSelectTuner","395":"XF86MediaPlayer","396":"XF86MediaSelectTeletext","397":"XF86DVD","398":"XF86MediaSelectAuxiliary","400":"XF86Audio","401":"XF86Video","404":"XF86Memo","405":"XF86Calendar","406":"XF86Red","407":"XF86Green","408":"XF86Yellow","409":"XF86Blue","410":"XF86ChannelUp","411":"XF86ChannelDown","417":"XF86MediaPlaySlow","418":"XF86AudioRandomPlay","419":"XF86Break","421":"XF86NumberEntryMode","424":"XF86VideoPhone","425":"XF86Game","426":"XF86ZoomIn","427":"XF86ZoomOut","428":"XF86ZoomReset","429":"XF86Word","430":"XF86Editor","431":"XF86Excel","432":"XF86GraphicsEditor","433":"XF86Presentation","434":"XF86Database","435":"XF86News","436":"XF86Voicemail","437":"XF86Addressbook","438":"XF86Messenger","439":"XF86DisplayToggle","440":"XF86SpellCheck","441":"XF86LogOff","442":"dollar","443":"EuroSign","444":"XF86FrameBack","445":"XF86FrameForward","446":"XF86ContextMenu","447":"XF86MediaRepeat","448":"XF8610ChannelsUp","449":"XF8610ChannelsDown","450":"XF86Images","452":"XF86NotificationCenter","453":"XF86PickupPhone","454":"XF86HangupPhone","455":"XF86LinkPhone","472":"XF86Fn","473":"XF86Fn_Esc","474":"XF86Fn_F1","475":"XF86Fn_F2","476":"XF86Fn_F3","477":"XF86Fn_F4","478":"XF86Fn_F5","479":"XF86Fn_F6","480":"XF86Fn_F7","481":"XF86Fn_F8","482":"XF86Fn_F9","483":"XF86Fn_F10","484":"XF86Fn_F11","485":"XF86Fn_F12","486":"XF86Fn_1","487":"XF86Fn_2","488":"XF86Fn_D","489":"XF86Fn_E","490":"XF86Fn_F","491":"XF86Fn_S","492":"XF86Fn_B","493":"XF86FnRightShift","505":"braille_dot_1","506":"braille_dot_2","507":"braille_dot_3","508":"braille_dot_4","509":"braille_dot_5","510":"braille_dot_6","511":"braille_dot_7","512":"braille_dot_8","513":"braille_dot_9","514":"braille_dot_1","520":"XF86Numeric0","521":"XF86Numeric1","522":"XF86Numeric2","523":"XF86Numeric3","524":"XF86Numeric4","525":"XF86Numeric5","526":"XF86Numeric6","527":"XF86Numeric7","528":"XF86Numeric8","529":"XF86Numeric9","530":"XF86NumericStar","531":"XF86NumericPound","532":"XF86NumericA","533":"XF86NumericB","534":"XF86NumericC","535":"XF86NumericD","536":"XF86CameraFocus","537":"XF86WPSButton","538":"XF86TouchpadToggle","539":"XF86TouchpadOn","540":"XF86TouchpadOff","541":"XF86CameraZoomIn","542":"XF86CameraZoomOut","543":"XF86CameraUp","544":"XF86CameraDown","545":"XF86CameraLeft","546":"XF86CameraRight","547":"XF86AttendantOn","548":"XF86AttendantOff","549":"XF86AttendantToggle","550":"XF86LightsToggle","568":"XF86ALSToggle","569":"XF86RotationLockToggle","570":"XF86RefreshRateToggle","584":"XF86Buttonconfig","585":"XF86Taskmanager","586":"XF86Journal","587":"XF86ControlPanel","588":"XF86AppSelect","589":"XF86Screensaver","590":"XF86VoiceCommand","591":"XF86Assistant","592":"ISO_Next_Group","593":"XF86EmojiPicker","594":"XF86Dictate","595":"XF86CameraAccessEnable","596":"XF86CameraAccessDisable","597":"XF86CameraAccessToggle","598":"XF86Accessibility","599":"XF86DoNotDisturb","600":"XF86BrightnessMin","601":"XF86BrightnessMax","602":"XF86ElectronicPrivacyScreenOn","603":"XF86ElectronicPrivacyScreenOff","604":"XF86ActionOnSelection","605":"XF86ContextualInsert","606":"XF86ContextualQuery","616":"XF86KbdInputAssistPrev","617":"XF86KbdInputAssistNext","618":"XF86KbdInputAssistPrevgroup","619":"XF86KbdInputAssistNextgroup","620":"XF86KbdInputAssistAccept","621":"XF86KbdInputAssistCancel","622":"XF86RightUp","623":"XF86RightDown","624":"XF86LeftUp","625":"XF86LeftDown","626":"XF86RootMenu","627":"XF86MediaTopMenu","628":"XF86Numeric11","629":"XF86Numeric12","630":"XF86AudioDesc","631":"XF863DMode","632":"XF86NextFavorite","633":"XF86StopRecord","634":"XF86PauseRecord","635":"XF86VOD","636":"XF86Unmute","637":"XF86FastReverse","638":"XF86SlowReverse","639":"XF86Data","640":"XF86OnScreenKeyboard","641":"XF86PrivacyScreenToggle","642":"XF86SelectiveScreenshot","643":"XF86NextElement","644":"XF86PreviousElement","645":"XF86AutopilotEngageToggle","646":"XF86MarkWaypoint","647":"XF86Sos","648":"XF86NavChart","649":"XF86FishingChart","650":"XF86SingleRangeRadar","651":"XF86DualRangeRadar","652":"XF86RadarOverlay","653":"XF86TraditionalSonar","654":"XF86ClearvuSonar","655":"XF86SidevuSonar","656":"XF86NavInfo","657":"XF86BrightnessAdjust","664":"XF86Macro1","665":"XF86Macro2","666":"XF86Macro3","667":"XF86Macro4","668":"XF86Macro5","669":"XF86Macro6","670":"XF86Macro7","671":"XF86Macro8","672":"XF86Macro9","673":"XF86Macro10","674":"XF86Macro11","675":"XF86Macro12","676":"XF86Macro13","677":"XF86Macro14","678":"XF86Macro15","679":"XF86Macro16","680":"XF86Macro17","681":"XF86Macro18","682":"XF86Macro19","683":"XF86Macro20","684":"XF86Macro21","685":"XF86Macro22","686":"XF86Macro23","687":"XF86Macro24","688":"XF86Macro25","689":"XF86Macro26","690":"XF86Macro27","691":"XF86Macro28","692":"XF86Macro29","693":"XF86Macro30","696":"XF86MacroRecordStart","697":"XF86MacroRecordStop","698":"XF86MacroPresetCycle","699":"XF86MacroPreset1","700":"XF86MacroPreset2","701":"XF86MacroPreset3","704":"XF86KbdLcdMenu1","705":"XF86KbdLcdMenu2","706":"XF86KbdLcdMenu3","707":"XF86KbdLcdMenu4","708":"XF86KbdLcdMenu5","709":"XF86PerformanceMode"};
