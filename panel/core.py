# -*- coding: utf-8 -*-
"""Общая часть панели: константы, разбор ввода, даты и повторы, хранение данных, звук, вызовы Windows."""
import calendar
import datetime as dt
import json
import os
import re
import sys
import threading
import traceback
import glob
import urllib.request
import uuid
import webbrowser
import zlib
import tkinter as tk
from tkinter import filedialog
from tkinter import font as tkfont
from tkinter import ttk

IS_WIN = sys.platform == "win32"

try:
    import ctypes
    from ctypes import wintypes
    if IS_WIN:
        try:  # чёткий текст на экранах с масштабированием
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
except Exception:
    ctypes = None

try:
    import winsound
except ImportError:
    winsound = None

try:
    import winreg
except ImportError:
    winreg = None

APP_NAME = "DesktopPanel"
DATA_DIR = os.path.join(os.environ.get("APPDATA", os.path.expanduser("~")), APP_NAME)
DATA_FILE = os.path.join(DATA_DIR, "data.json")
LOG_FILE = os.path.join(DATA_DIR, "error.log")
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"

C = {
    "bg": "#1e1f24",
    "card": "#272830",
    "hover": "#34363f",
    "fg": "#e8e8ec",
    "muted": "#8b8d98",
    "faint": "#55576a",
    "accent": "#7aa2f7",
    "ok": "#9ece6a",
    "rest": "#73daca",
    "warn": "#e0af68",
    "danger": "#f7768e",
    "on_accent": "#1e1f24",
    "selected": "#3b3e52",
}

MONTHS = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль",
          "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]
MONTHS_GEN = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля",
              "августа", "сентября", "октября", "ноября", "декабря"]
WEEKDAYS = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
WD_SHORT = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
WD_ACC = ["понедельник", "вторник", "среду", "четверг", "пятницу", "субботу", "воскресенье"]
WD_DAT_PL = ["по понедельникам", "по вторникам", "по средам", "по четвергам",
             "по пятницам", "по субботам", "по воскресеньям"]

BLOCKS = {
    "calendar": "Календарь",
    "goals": "Цели недели",
    "tasks": "Задачи",
    "future": "Будущие задачи",
    "week": "Неделя",
    "pomo": "Помодоро",
    "notes": "Заметки",
    "stats": "Итоги недели",
    "events": "События",
}

FIXED_HOLIDAYS = {
    (1, 1): "Новогодние каникулы", (1, 2): "Новогодние каникулы", (1, 3): "Новогодние каникулы",
    (1, 4): "Новогодние каникулы", (1, 5): "Новогодние каникулы", (1, 6): "Новогодние каникулы",
    (1, 7): "Рождество Христово", (1, 8): "Новогодние каникулы",
    (2, 23): "День защитника Отечества", (3, 8): "Международный женский день",
    (5, 1): "Праздник Весны и Труда", (5, 9): "День Победы",
    (6, 12): "День России", (11, 4): "День народного единства",
}

POMO_PRESETS = [(25, 5, 15), (50, 10, 20), (15, 3, 10)]

# приоритет по важности: (значение, название, цвет)
PRIORITIES = [(None, "Нет", C["faint"]), ("low", "Низкий", C["accent"]),
              ("medium", "Средний", C["warn"]), ("high", "Высокий", C["danger"])]
PRIO_COLOR = {"low": C["accent"], "medium": C["warn"], "high": C["danger"]}
PRIO_NAME = {v: n for v, n, _ in PRIORITIES}

# матрица Эйзенхауэра: квадрант -> (действие, описание, цвет)
EIS = {
    "q1": ("Сделать сейчас", "важно и срочно", C["danger"]),
    "q2": ("Запланировать", "важно, не срочно", C["accent"]),
    "q3": ("Делегировать", "срочно, не важно", C["warn"]),
    "q4": ("Отложить", "не важно, не срочно", C["muted"]),
}

WD_TOKENS = {
    "пн": 0, "пон": 0, "понедельник": 0, "вт": 1, "вторник": 1, "ср": 2, "среда": 2, "среду": 2,
    "чт": 3, "четверг": 3, "пт": 4, "пятница": 4, "пятницу": 4, "сб": 5, "суббота": 5,
    "субботу": 5, "вс": 6, "воскресенье": 6,
}
WIDTH = 330
MIN_W = 260
MARGIN = 20
REMIND_BEFORE = 10  # минут до задачи со временем

ANCHORS = {
    "nw": "Левый верхний угол",
    "ne": "Правый верхний угол",
    "sw": "Левый нижний угол",
    "se": "Правый нижний угол",
    "c": "Центр экрана",
}

LIST_MARKER = re.compile(r"^\s*(?:[-*•·–—▪►]+|\d+[.)]|\[[ xXхХ]?\])\s*(?:\[[ xXхХ]?\]\s*)?")
TIME_PREFIX = re.compile(r"^\s*([01]?\d|2[0-3])[:.]([0-5]\d)\s+(.+)$")
PRIO_PREFIX = re.compile(r"^\s*!+\s*(.+)$")
EVENT_RE = re.compile(r"^(.+?)\s+(\d{1,2})\.(\d{1,2})(?:\.(\d{2}|\d{4}))?\s*$")

VK_A, VK_C, VK_V, VK_X, VK_Y, VK_Z = 65, 67, 86, 88, 89, 90


# ---------- служебное ----------

LOG_LIMIT = 1024 * 1024  # больше мегабайта — старый журнал уходит в error.old.log


def log_error(text):
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > LOG_LIMIT:
            os.replace(LOG_FILE, os.path.join(DATA_DIR, "error.old.log"))
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(f"\n[{dt.datetime.now():%Y-%m-%d %H:%M:%S}]\n{text}\n")
    except Exception:
        pass


def plural(n, one, few, many):
    if n % 10 == 1 and n % 100 != 11:
        return f"{n} {one}"
    if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
        return f"{n} {few}"
    return f"{n} {many}"


def plural_days(n):
    return plural(n, "день", "дня", "дней")


def mix(c1, c2, k):
    """Смешивает два цвета #rrggbb: k=0 — первый, k=1 — второй."""
    a = [int(c1[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(c2[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * k):02x}" for x, y in zip(a, b))


def short(text, n):
    return text if len(text) <= n else text[:n - 1] + "…"


def parse_task_text(raw):
    """«! 14:00 Созвон» → ("Созвон", prio=True, time="14:00")."""
    text, prio, time = raw.strip(), False, None
    for _ in range(2):
        m = PRIO_PREFIX.match(text)
        if m:
            prio, text = True, m.group(1).strip()
        m = TIME_PREFIX.match(text)
        if m:
            time, text = f"{int(m.group(1)):02d}:{m.group(2)}", m.group(3).strip()
    return text, prio, time


def parse_date(text, today):
    """«15.11», «15.11.2026», «2026-11-15», «+3», «завтра», «пт» → date или None.
    Дата без года, которая в этом году уже прошла, считается следующим годом."""
    s = text.strip().lower().rstrip(".")
    if not s:
        return None
    rel = {"сегодня": 0, "завтра": 1, "послезавтра": 2}
    if s in rel:
        return today + dt.timedelta(days=rel[s])
    m = re.fullmatch(r"\+(\d{1,3})", s)
    if m:
        return today + dt.timedelta(days=int(m.group(1)))
    if s in WD_TOKENS:
        delta = (WD_TOKENS[s] - today.weekday()) % 7 or 7
        return today + dt.timedelta(days=delta)
    try:
        m = re.fullmatch(r"(\d{1,2})[./](\d{1,2})(?:[./](\d{2}|\d{4}))?", s)
        if m:
            day, mon, year = int(m.group(1)), int(m.group(2)), m.group(3)
            if year:
                return dt.date(int(year) + (2000 if len(year) == 2 else 0), mon, day)
            d = dt.date(today.year, mon, day)
            return d if d >= today else dt.date(today.year + 1, mon, day)
        m = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})", s)
        if m:
            return dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None
    return None


def date_title(d, today):
    """«Завтра · вт, 13 октября» / «Сегодня · пн, 12 октября» / «Через 5 дней · …»."""
    n = (d - today).days
    rel = {0: "Сегодня", 1: "Завтра", 2: "Послезавтра", -1: "Вчера"}.get(n)
    if rel is None:
        rel = f"Через {plural_days(n)}" if n > 0 else f"{plural_days(-n)} назад"
    tail = f"{WD_SHORT[d.weekday()].lower()}, {d.day} {MONTHS_GEN[d.month - 1]}"
    if d.year != today.year:
        tail += f" {d.year}"
    return f"{rel} · {tail}"


TAG_RE = re.compile(r"(?<!\S)#([\w-]+)")
EST_RE = re.compile(r"(?<!\S)~\s*(\d+(?:[.,]\d+)?)\s*(ч|час|часа|часов|h|м|мин|m)?(?!\S)",
                    re.IGNORECASE)
DEADLINE_RE = re.compile(r"(?<!\S)до\s+(\S+)\s*$", re.IGNORECASE)
LINK_RE = re.compile(r'"[A-Za-z]:\\[^"\n]+"|https?://[^\s<>"]+|www\.[^\s<>"]+'
                     r'|[A-Za-z]:\\[^\s<>"|?*]+|\\\\[^\s<>"|?*]+')
TAG_COLORS = ["#7aa2f7", "#9ece6a", "#e0af68", "#bb9af7", "#73daca", "#ff9e64", "#f7768e", "#2ac3de"]
EIS_ORDER = {"q1": 0, "q2": 1, "q3": 2, "q4": 3}
PRIO_RANK = {"high": 0, "medium": 1, "low": 2}
SORTS = {"manual": "Мой порядок", "priority": "По приоритету", "eis": "По матрице",
         "deadline": "По дедлайну"}
FILTERS = {"all": "Все задачи", "q1": "Только «Сделать сейчас»", "q2": "Только «Запланировать»",
           "q3": "Только «Делегировать»", "q4": "Только «Отложить»", "none": "Без квадранта"}
SOUND_KINDS = {"work": "Конец работы", "break": "Конец перерыва"}
MEDIA_DIR = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Media")


def now_str():
    return dt.datetime.now().strftime("%Y-%m-%d %H:%M")


def tag_color(tag):
    # crc32, а не hash(): цвет метки должен быть одинаковым между запусками
    return TAG_COLORS[zlib.crc32(tag.encode("utf-8")) % len(TAG_COLORS)]


def parse_extras(text, today):
    """Метки «#дом», оценка «~30м» / «~2ч» и дедлайн «до пт» в конце текста.
    Оценка без единицы: до 8 включительно — часы, больше — минуты."""
    tags = []
    for m in TAG_RE.finditer(text):
        tg = m.group(1).lower()
        if tg not in tags:
            tags.append(tg)
    text = TAG_RE.sub("", text)
    est = None
    m = EST_RE.search(text)
    if m:
        v = float(m.group(1).replace(",", "."))
        unit = (m.group(2) or "").lower()
        est = round(v * 60) if unit.startswith(("ч", "h")) or (not unit and v <= 8) else round(v)
        text = text[:m.start()] + text[m.end():]
    deadline = None
    stripped = text.rstrip()
    m = DEADLINE_RE.search(stripped)
    if m:
        d = parse_date(m.group(1), today)
        if d:
            deadline, text = d, stripped[:m.start()]
    return re.sub(r"\s{2,}", " ", text).strip(), {"tags": tags, "est": est or None,
                                                  "deadline": deadline}


def fmt_est(minutes):
    if minutes < 60:
        return f"{minutes} мин"
    return f"{minutes / 60:.1f}".rstrip("0").rstrip(".").replace(".", ",") + " ч"


def est_token(minutes):
    return f"~{minutes // 60}ч" if minutes % 60 == 0 else f"~{minutes}м"


def short_date(d, today):
    s = f"{d.day:02d}.{d.month:02d}"
    return s if d.year == today.year else f"{s}.{d.year}"


def deadline_badge(t, today):
    """(текст, цвет) значка дедлайна или None."""
    if not t.get("deadline"):
        return None
    d = dt.date.fromisoformat(t["deadline"])
    n = (d - today).days
    if n < 0:
        return f"⚑ просрочен на {plural_days(-n)}", C["danger"]
    if n == 0:
        return "⚑ дедлайн сегодня", C["danger"]
    if n == 1:
        return "⚑ дедлайн завтра", C["danger"]
    if n <= 3:
        return f"⚑ до {WD_SHORT[d.weekday()].lower()} {short_date(d, today)}", C["warn"]
    return f"⚑ до {short_date(d, today)}", C["muted"]


def open_target(target):
    """Открывает ссылку или путь к файлу/папке программой по умолчанию."""
    t = target.strip().strip('"').rstrip(".,;:)")
    if t.lower().startswith("www."):
        t = "https://" + t
    if IS_WIN:
        os.startfile(t)  # noqa: S606 — пользователь сам щёлкнул по своей ссылке
    else:
        webbrowser.open(t)


class Sound:
    """Звук по настройке {"file": "default" | "none" | путь, "vol": 0..100}.
    Громкость задаётся через MCI Windows; если не вышло — играем без регулировки."""
    ALIAS = "desktop_panel_snd"

    @staticmethod
    def system_files():
        return sorted(glob.glob(os.path.join(MEDIA_DIR, "*.wav")), key=str.lower)

    @classmethod
    def play(cls, cfg):
        f = (cfg or {}).get("file", "default")
        if f == "none":
            return
        if f == "default" or not os.path.isfile(f):
            if winsound:
                try:
                    winsound.PlaySound("SystemExclamation", winsound.SND_ALIAS | winsound.SND_ASYNC)
                except Exception:
                    log_error("Системный звук не сыграл:\n" + traceback.format_exc())
            return
        vol = max(0, min(100, int((cfg or {}).get("vol", 80))))
        try:
            send = ctypes.windll.winmm.mciSendStringW
            send.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.UINT, wintypes.HANDLE]
            send.restype = wintypes.UINT
            send(f"close {cls.ALIAS}", None, 0, None)
            err = send(f'open "{f}" type mpegvideo alias {cls.ALIAS}', None, 0, None)
            if err:
                raise OSError(f"MCI open error {err}")
            send(f"setaudio {cls.ALIAS} volume to {vol * 10}", None, 0, None)
            if send(f"play {cls.ALIAS}", None, 0, None):
                raise OSError("MCI play error")
        except Exception:
            log_error("Звук через MCI не сыграл:\n" + traceback.format_exc())
            if winsound:
                try:
                    winsound.PlaySound(f, winsound.SND_FILENAME | winsound.SND_ASYNC)
                except Exception:
                    log_error(f"Звук {f} не сыграл:\n" + traceback.format_exc())


WS_EX_LAYERED, WS_EX_TRANSPARENT, GWL_EXSTYLE, LWA_ALPHA = 0x80000, 0x20, -20, 0x2
VK_CONTROL = 0x11


def set_click_through(root, on, alpha):
    """Включает/выключает «прозрачность для мыши» у окна панели (Windows).
    WS_EX_TRANSPARENT работает только вместе с WS_EX_LAYERED, а слоистому окну обязательно
    нужна прозрачность через SetLayeredWindowAttributes — иначе оно станет невидимым.
    Возвращает True, если стиль удалось применить."""
    if not (IS_WIN and ctypes):
        return False
    try:
        u = ctypes.windll.user32
        u.GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
        u.GetWindowLongW.restype = ctypes.c_long
        u.SetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_long]
        u.SetWindowLongW.restype = ctypes.c_long
        # wintypes.BYTE знаковый, а прозрачность — 0..255, поэтому c_ubyte
        u.SetLayeredWindowAttributes.argtypes = [wintypes.HWND, wintypes.DWORD, ctypes.c_ubyte,
                                                 wintypes.DWORD]
        hwnd = int(root.wm_frame(), 16)
        style = u.GetWindowLongW(hwnd, GWL_EXSTYLE)
        if on:
            style |= WS_EX_LAYERED | WS_EX_TRANSPARENT
        else:
            style &= ~WS_EX_TRANSPARENT
        u.SetWindowLongW(hwnd, GWL_EXSTYLE, style)
        if style & WS_EX_LAYERED:
            u.SetLayeredWindowAttributes(hwnd, 0, max(1, min(255, int(alpha * 255))), LWA_ALPHA)
        return True
    except Exception:
        log_error("Сквозные клики не применились:\n" + traceback.format_exc())
        return False


WM_SHOW_PANEL = 0x0400 + 21  # «покажись» — от второго запуска программы
TRAY_CLASS = "DesktopPanelTrayWnd"


def _user32():
    u = ctypes.windll.user32
    u.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    u.SetParent.argtypes = [wintypes.HWND, wintypes.HWND]
    u.SetParent.restype = wintypes.HWND
    u.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
    u.FindWindowW.restype = wintypes.HWND
    u.FindWindowExW.argtypes = [wintypes.HWND, wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR]
    u.FindWindowExW.restype = wintypes.HWND
    u.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    u.SendMessageTimeoutW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM,
                                      wintypes.UINT, wintypes.UINT, ctypes.POINTER(ctypes.c_size_t)]
    return u


def native_show(root, visible):
    """Скрыть/показать окно средствами Windows. У окна без рамки пара withdraw()/deiconify()
    в Tk ненадёжна — после неё панель могла не вернуться из трея."""
    hwnd = int(root.wm_frame(), 16)
    _user32().ShowWindow(hwnd, 5 if visible else 0)  # SW_SHOW / SW_HIDE


def activate_running_copy():
    """Просит уже запущенную панель показаться. True — нашли и попросили."""
    if not (IS_WIN and ctypes):
        return False
    try:
        u = _user32()
        hwnd = u.FindWindowW(TRAY_CLASS, None)
        return bool(hwnd) and bool(u.PostMessageW(hwnd, WM_SHOW_PANEL, 0, 0))
    except Exception:
        log_error("Не удалось обратиться к запущенной панели:\n" + traceback.format_exc())
        return False


def desktop_layer_window():
    """Окно рабочего стола позади значков — туда же встраиваются «живые обои».
    Progman по сообщению 0x052C создаёт слой WorkerW. Ищем его двумя способами: как в Windows 10
    и ранних 11 (отдельное окно сразу после окна со значками) и как в Windows 11 24H2 (внутри Progman)."""
    if not (IS_WIN and ctypes):
        return None
    u = _user32()
    progman = u.FindWindowW("Progman", None)
    if not progman:
        return None
    res = ctypes.c_size_t()
    u.SendMessageTimeoutW(progman, 0x052C, 0xD, 0x1, 0, 1000, ctypes.byref(res))
    u.SendMessageTimeoutW(progman, 0x052C, 0, 0, 0, 1000, ctypes.byref(res))
    found = []
    proc_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def check(hwnd, _):
        if u.FindWindowExW(hwnd, None, "SHELLDLL_DefView", None):
            worker = u.FindWindowExW(None, hwnd, "WorkerW", None)
            if worker:
                found.append(worker)
        return True

    u.EnumWindows(proc_type(check), 0)
    worker = found[0] if found else (u.FindWindowExW(progman, None, "WorkerW", None) or None)
    try:  # сведения для error.log: без них на другой машине не разобраться
        import platform
        info = f"Windows {platform.version()}; Progman={progman:#x}; WorkerW={worker or 0:#x}"
        if worker:
            info += f"; видим={bool(u.IsWindowVisible(worker))}; прямоугольник={window_rect(worker)}"
        info += "; способ=" + ("отдельное окно" if found else "внутри Progman" if worker else "не найден")
        log_error("Слой рабочего стола: " + info)
    except Exception:
        log_error("Не удалось описать слой рабочего стола:\n" + traceback.format_exc())
    return worker


WS_CHILD, WS_POPUP, GWL_STYLE = 0x40000000, 0x80000000, -16
SWP_NOACTIVATE, SWP_SHOWWINDOW, SWP_FRAMECHANGED, SWP_NOZORDER = 0x10, 0x40, 0x20, 0x4


def window_rect(hwnd):
    class RECT(ctypes.Structure):
        _fields_ = [("l", ctypes.c_long), ("t", ctypes.c_long), ("r", ctypes.c_long), ("b", ctypes.c_long)]
    r = RECT()
    ctypes.windll.user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(r))
    return r.l, r.t, r.r, r.b


def _styles(hwnd):
    u = ctypes.windll.user32
    u.GetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int]
    u.GetWindowLongW.restype = ctypes.c_long
    u.SetWindowLongW.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_long]
    return u


def embed_in_desktop(root, parent, x, y):
    """Встраивает окно в слой рабочего стола. Дочернее окно не может быть «слоистым»
    (полупрозрачным) — Windows его просто не рисует, поэтому этот стиль снимаем.
    x, y — экранные координаты; пересчитываются от угла родителя."""
    hwnd = int(root.wm_frame(), 16)
    u = _styles(hwnd)
    ex = u.GetWindowLongW(hwnd, GWL_EXSTYLE) & ~(WS_EX_LAYERED | WS_EX_TRANSPARENT)
    u.SetWindowLongW(hwnd, GWL_EXSTYLE, ex)
    style = (u.GetWindowLongW(hwnd, GWL_STYLE) & ~WS_POPUP) | WS_CHILD
    u.SetWindowLongW(hwnd, GWL_STYLE, ctypes.c_long(style & 0xFFFFFFFF).value)
    _user32().SetParent(hwnd, parent)
    pl, pt, _, _ = window_rect(parent)
    w, h = root.winfo_width(), root.winfo_height()
    u.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                               ctypes.c_int, wintypes.UINT]
    u.SetWindowPos(hwnd, None, x - pl, y - pt, w, h,
                   SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW | SWP_FRAMECHANGED)
    return pl, pt


def release_from_desktop(root, x, y):
    """Возвращает окно обычным окном верхнего уровня в экранных координатах x, y."""
    hwnd = int(root.wm_frame(), 16)
    u = _styles(hwnd)
    _user32().SetParent(hwnd, None)
    style = (u.GetWindowLongW(hwnd, GWL_STYLE) & ~WS_CHILD) | WS_POPUP
    u.SetWindowLongW(hwnd, GWL_STYLE, ctypes.c_long(style & 0xFFFFFFFF).value)
    u.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                               ctypes.c_int, wintypes.UINT]
    u.SetWindowPos(hwnd, None, x, y, root.winfo_width(), root.winfo_height(),
                   SWP_NOZORDER | SWP_SHOWWINDOW | SWP_FRAMECHANGED)


def autowrap(label, min_width=40):
    """Перенос текста по фактической ширине метки. Заранее заданная ширина переноса не учитывает
    масштаб Windows и ширину значков рядом: текст обрезался справа вместо переноса.
    Метка должна быть упакована с fill="x", чтобы её ширину задавал родитель, а не текст."""
    def on_configure(e):
        pad = 2 * (int(label.cget("bd")) + int(label.cget("padx")) + int(label.cget("highlightthickness")))
        width = max(min_width, e.width - pad - 1)  # не шире выделенного места — окно не раздуется
        if label.cget("wraplength") != width and str(label.cget("wraplength")) != str(width):
            label.config(wraplength=width)
    label.bind("<Configure>", on_configure, add="+")


def ctrl_pressed():
    try:
        return bool(ctypes.windll.user32.GetAsyncKeyState(VK_CONTROL) & 0x8000)
    except Exception:
        return False


GOALS_LIMIT = 5
RESIZE_FRAME_MS = 16
FUTURE_MAX_ROWS = 60   # строк в блоке «Будущие задачи»: окно выше 32767 пикселей Windows не рисует
MATRIX_MAX_ROWS = 80   # задач в одном квадранте окна матрицы
UNDO_COMPRESS = 1      # уровень zlib для снимков отмены: быстро и в ~8 раз меньше памяти  # изменение размеров применяется не чаще раза за кадр
UNDO_KEYS = ("tasks", "recurring", "goals")
UNDO_DEPTH = 50
QUAD_RE = re.compile(r"(?<!\S)!!([1-4])(?!\S)")
DATE_WORDS = {"сегодня": 0, "завтра": 1, "послезавтра": 2}
WD_PREFIX = {}
for _i, (_short, _acc) in enumerate(zip(["пн", "вт", "ср", "чт", "пт", "сб", "вс"],
                                         ["понедельник", "вторник", "среду", "четверг",
                                          "пятницу", "субботу", "воскресенье"])):
    _prep = "во" if _i == 1 else "в"
    WD_PREFIX.update({_short: _i, f"в {_short}": _i, f"во {_short}": _i, f"{_prep} {_acc}": _i})
WD_GENDER = [0, 0, 1, 0, 1, 1, 2]  # м, м, ж, м, ж, ж, ср — для «первый/первую/первое»
ORDINALS = {1: ("первый", "первую", "первое"), 2: ("второй", "вторую", "второе"),
            3: ("третий", "третью", "третье"), 4: ("четвёртый", "четвёртую", "четвёртое")}
LAST_FORMS = ("последний", "последнюю", "последнее")
ORD_LABELS = ["1-й", "2-й", "3-й", "4-й", "последний"]


WD_FROM = ["с понедельника", "со вторника", "со среды", "с четверга", "с пятницы", "с субботы",
           "с воскресенья"]


def hold_dates(today, is_off, max_back=14):
    """Дни, задачи которых в выходной не переносятся: последний рабочий день и выходные после него
    до вчерашнего. В рабочий день — пусто. is_off(date) — выходной ли день (с учётом праздников)."""
    if not is_off(today):
        return []
    dates, d = [], today - dt.timedelta(days=1)
    while is_off(d):
        dates.append(d)
        d -= dt.timedelta(days=1)
        if len(dates) > max_back:  # столько выходных подряд не бывает — что-то не так с календарём
            return []
    dates.append(d)  # последний рабочий день
    return sorted(dates)


def week_key(d):
    return (d - dt.timedelta(days=d.weekday())).isoformat()


def parse_date_prefix(text, today):
    """«завтра Купить хлеб» → (date, "Купить хлеб"); дата только в начале строки.
    «15.10» здесь — дата; время с точкой распознаётся, только если это не дата («9.30», «14.00»)."""
    low = text.lower()
    for phrase in sorted(WD_PREFIX, key=len, reverse=True):
        if low.startswith(phrase + " ") and text[len(phrase):].strip():
            delta = (WD_PREFIX[phrase] - today.weekday()) % 7 or 7
            return today + dt.timedelta(days=delta), text[len(phrase):].strip()
    m = re.match(r"^(\S+)\s+(.+)$", text)
    if not m:
        return None, text
    tok, rest = m.group(1).lower().rstrip(","), m.group(2).strip()
    if tok in DATE_WORDS:
        return today + dt.timedelta(days=DATE_WORDS[tok]), rest
    if re.fullmatch(r"\+\d{1,3}", tok) or re.fullmatch(r"\d{1,2}[./]\d{1,2}(?:[./](?:\d{2}|\d{4}))?", tok):
        d = parse_date(tok, today)
        if d:
            return d, rest
    return None, text


def parse_quick(raw, today, allow_date=True):
    """Быстрый ввод одной строкой: дата, «!», время, «!!1…4», #метки, ~оценка, «до …»."""
    text = raw.strip()
    res = {"date": None, "prio": False, "time": None, "eis": None}
    m = QUAD_RE.search(text)
    if m:
        res["eis"] = "q" + m.group(1)
        text = (text[:m.start()] + text[m.end():]).strip()
    for _ in range(4):  # префиксы могут идти в любом порядке
        changed = False
        m = PRIO_PREFIX.match(text)
        if m and not res["prio"]:
            res["prio"], text, changed = True, m.group(1).strip(), True
        if allow_date and not res["date"]:
            d, rest = parse_date_prefix(text, today)
            if d:
                res["date"], text, changed = d, rest, True
        m = TIME_PREFIX.match(text)
        if m and not res["time"]:
            res["time"] = f"{int(m.group(1)):02d}:{m.group(2)}"
            text, changed = m.group(3).strip(), True
        if not changed:
            break
    text, ex = parse_extras(text, today)
    res.update(ex)
    res["text"] = text
    return res


def rule_matches(rule, d, start=None):
    """Правила повтора: daily, weekdays, w{день}, d{N} — каждые N дней, W{N}:{день} — каждые
    N недель, m{число} — число месяца, m{k}:{день} — k-й день недели месяца, mL{день} — последний."""
    if not rule:
        return False
    if rule == "daily":
        return True
    if rule == "weekdays":
        return d.weekday() < 5
    start = start or d
    if rule.startswith("d"):
        n = max(1, int(rule[1:]))
        return d >= start and (d - start).days % n == 0
    if rule.startswith("W"):
        n, wd = (int(x) for x in rule[1:].split(":"))
        if d.weekday() != wd or d < start:
            return False
        weeks = ((d - dt.timedelta(days=d.weekday())) - (start - dt.timedelta(days=start.weekday()))).days // 7
        return weeks % max(1, n) == 0
    if rule.startswith("w"):
        return d.weekday() == int(rule[1:])
    if rule.startswith("mL"):
        return d.weekday() == int(rule[2:]) and (d + dt.timedelta(days=7)).month != d.month
    if rule.startswith("m") and ":" in rule:
        k, wd = (int(x) for x in rule[1:].split(":"))
        return d.weekday() == wd and (d.day - 1) // 7 + 1 == k
    if rule.startswith("m"):
        day = int(rule[1:])
        return d.day == min(day, calendar.monthrange(d.year, d.month)[1])
    return False


def rule_text(rule):
    if not rule:
        return ""
    if rule == "daily":
        return "каждый день"
    if rule == "weekdays":
        return "по будням"
    if rule.startswith("d"):
        n = int(rule[1:])
        return "каждый день" if n == 1 else f"каждые {plural_days(n)}"
    if rule.startswith("W"):
        n, wd = (int(x) for x in rule[1:].split(":"))
        if n == 1:
            return WD_DAT_PL[wd]
        return f"каждые {plural(n, 'неделю', 'недели', 'недель')} {'во' if wd == 1 else 'в'} {WD_ACC[wd]}"
    if rule.startswith("w"):
        return WD_DAT_PL[int(rule[1:])]
    if rule.startswith("mL"):
        wd = int(rule[2:])
        return f"в {LAST_FORMS[WD_GENDER[wd]]} {WD_ACC[wd]} месяца"
    if rule.startswith("m") and ":" in rule:
        k, wd = (int(x) for x in rule[1:].split(":"))
        return f"{'во' if k == 2 else 'в'} {ORDINALS[k][WD_GENDER[wd]]} {WD_ACC[wd]} месяца"
    if rule.startswith("m"):
        return f"{int(rule[1:])}-го числа каждого месяца"
    return ""


BASIC_RULES = ("daily", "weekdays")


# ---------- хранение данных ----------

def default_settings():
    return {
        "x": None, "y": 80, "alpha": 0.94, "topmost": False,
        "work": 25, "break": 5, "long": 15, "cycle": 4, "auto_break": False,
        "pinned": False, "anchor": "free", "tasks_max": 260,
        "size_fixed": False, "w": None, "h": None,
        "order": list(BLOCKS), "hidden_blocks": [],
        "collapsed": {k: False for k in BLOCKS},
        "prod_cal": True, "pomo_task": None,
        "block_h": {},  # высота тела блока, заданная вручную (в пикселях)
        "sort": "manual", "filter": "all", "q1_limit": 5, "day_hours": 8,
        "review": True, "review_date": "", "focus_mode": True, "stats_by": "task",
        "weekly_review": True, "review_week": "",
        "click_through": False, "ct_hint_shown": False,
        "task_font": 10, "task_gap": 1, "weekend_hold": True, "card_collapsed": [],
        "desktop_layer": False, "desk_hint_shown": False, "desk_confirmed": False,
        "sounds": {"work": {"file": "default", "vol": 80}, "break": {"file": "default", "vol": 80}},
    }


BACKUP_FILE = os.path.join(DATA_DIR, "data.bak.json")
LOAD_INFO = {"restored": None, "corrupt": None, "blocked": False}


def _read_json(path):
    with open(path, encoding="utf-8") as f:
        loaded = json.load(f)
    if not isinstance(loaded, dict) or not isinstance(loaded.get("tasks", []), list):
        raise ValueError("неожиданная структура файла")
    return loaded


def read_saved():
    """Данные из data.json, а если он испорчен или пропал — из копии прошлого сохранения.
    Испорченный файл переименовывается, чтобы его не затёрло следующее сохранение."""
    try:
        return _read_json(DATA_FILE)
    except FileNotFoundError:
        pass  # первый запуск или сбой между переименованиями — дальше пробуем копию
    except Exception:
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        bad = os.path.join(DATA_DIR, f"data.corrupt-{stamp}.json")
        try:
            os.replace(DATA_FILE, bad)
            LOAD_INFO["corrupt"] = bad
        except OSError:
            LOAD_INFO["corrupt"] = DATA_FILE
            LOAD_INFO["blocked"] = True  # не смогли убрать в сторону — не пишем поверх
        log_error(f"data.json не читается (сохранён как {LOAD_INFO['corrupt']}):\n"
                  + traceback.format_exc())
    try:
        loaded = _read_json(BACKUP_FILE)
    except FileNotFoundError:
        return None
    except Exception:
        log_error("Копия данных тоже не читается:\n" + traceback.format_exc())
        return None
    if LOAD_INFO["corrupt"]:
        LOAD_INFO["restored"] = BACKUP_FILE
    return loaded


def load_data():
    d = {"tasks": [], "recurring": [], "events": [], "notes": "",
         "pomodoros": {}, "pomo_cycle": {}, "prodcal": {}, "pomo_log": [],
         "goals": {}, "templates": [], "settings": default_settings()}
    loaded = read_saved()
    if loaded is None:
        return d
    try:
        for k in ("tasks", "recurring", "events", "notes", "pomodoros", "pomo_cycle", "prodcal",
                  "pomo_log", "goals", "templates"):
            if k in loaded:
                d[k] = loaded[k]
        s = d["settings"]
        collapsed = s["collapsed"]
        s.update(loaded.get("settings", {}))
        collapsed.update(s.get("collapsed") or {})
        s["collapsed"] = collapsed
        order = [k for k in s.get("order") or [] if k in BLOCKS]
        keys = list(BLOCKS)
        for i, k in enumerate(keys):  # новые блоки встают после своего соседа
            if k not in order:
                prev = keys[i - 1] if i else None
                order.insert(order.index(prev) + 1 if prev in order else len(order), k)
        s["order"] = order
        for t in d["tasks"] + d["recurring"]:  # «важная» из прошлых версий → высокий приоритет
            if t.pop("prio", False):
                t.setdefault("priority", "high")
        d["tasks"] = sanitize_tasks(d["tasks"])
    except Exception:
        # данные прочитались, но устроены неожиданно — не перезаписываем их, пока не разберёмся
        LOAD_INFO["blocked"] = True
        log_error("Не удалось разобрать данные, сохранение отключено:\n" + traceback.format_exc())
    return d


def _valid_date(value):
    try:
        dt.date.fromisoformat(value)
        return True
    except (TypeError, ValueError):
        return False


def sanitize_tasks(tasks):
    """Чинит задачи после ручной правки файла: без id, текста или с испорченной датой.
    Испорченная дата иначе роняла бы перерисовку и таймер при каждом тике."""
    today = dt.date.today().isoformat()
    fixed, seen = [], set()
    for t in tasks:
        if not isinstance(t, dict):
            log_error(f"Пропущена непонятная запись в задачах: {str(t)[:200]}")
            continue
        if not t.get("id") or t["id"] in seen:
            t["id"] = uuid.uuid4().hex
        seen.add(t["id"])
        t["text"] = str(t.get("text") or "(без названия)")
        t["done"] = bool(t.get("done"))
        if not _valid_date(t.get("date")):
            log_error(f"У задачи «{t['text'][:60]}» испорчена дата {t.get('date')!r} — поставил сегодня")
            t["date"] = today
        for key in ("deadline", "from", "done_at"):
            if key in t and not _valid_date(t[key]):
                log_error(f"У задачи «{t['text'][:60]}» испорчено поле {key}={t[key]!r} — убрал")
                t.pop(key)
        if "snooze" in t:
            try:
                dt.datetime.fromisoformat(t["snooze"])
            except (TypeError, ValueError):
                t.pop("snooze")
        if t.get("time") and not re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", str(t["time"])):
            t.pop("time")
        fixed.append(t)
    return fixed


def save_data(d):
    """Атомарная запись с fsync; прежняя версия файла остаётся копией (data.bak.json).
    Возвращает True, если записали."""
    if LOAD_INFO["blocked"]:
        return False
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        tmp = DATA_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(d, f, ensure_ascii=False, indent=1)
            f.flush()
            os.fsync(f.fileno())
        if os.path.exists(DATA_FILE):
            os.replace(DATA_FILE, BACKUP_FILE)
        os.replace(tmp, DATA_FILE)
        return True
    except Exception:
        log_error("Не удалось сохранить данные:\n" + traceback.format_exc())
        return False


# ---------- экран ----------

def work_area(root):
    if not (IS_WIN and ctypes):
        return 0, 0, root.winfo_screenwidth(), root.winfo_screenheight()
    try:
        class RECT(ctypes.Structure):
            _fields_ = [("l", ctypes.c_long), ("t", ctypes.c_long),
                        ("r", ctypes.c_long), ("b", ctypes.c_long)]
        r = RECT()
        if ctypes.windll.user32.SystemParametersInfoW(0x30, 0, ctypes.byref(r), 0):
            return r.l, r.t, r.r, r.b
    except Exception:
        log_error("Не удалось узнать рабочую область экрана:\n" + traceback.format_exc())
    return 0, 0, root.winfo_screenwidth(), root.winfo_screenheight()


def virtual_screen(root):
    if not (IS_WIN and ctypes):
        return 0, 0, root.winfo_screenwidth(), root.winfo_screenheight()
    try:
        gm = ctypes.windll.user32.GetSystemMetrics
        x, y, w, h = gm(76), gm(77), gm(78), gm(79)
        if w and h:
            return x, y, x + w, y + h
    except Exception:
        log_error("Не удалось узнать размеры мониторов:\n" + traceback.format_exc())
    return 0, 0, root.winfo_screenwidth(), root.winfo_screenheight()


# ---------- автозапуск ----------

def autostart_command():
    if getattr(sys, "frozen", False):
        return f'"{sys.executable}"'
    exe = sys.executable
    if exe.lower().endswith("python.exe"):
        w = exe[:-len("python.exe")] + "pythonw.exe"
        if os.path.exists(w):
            exe = w
    return f'"{exe}" "{os.path.abspath(sys.argv[0])}"'


def autostart_enabled():
    if not winreg:
        return False
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, APP_NAME)
            return True
    except OSError:
        return False


def set_autostart(on):
    if not winreg:
        return
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
            if on:
                winreg.SetValueEx(k, APP_NAME, 0, winreg.REG_SZ, autostart_command())
            else:
                try:
                    winreg.DeleteValue(k, APP_NAME)
                except OSError:
                    pass
    except OSError:
        pass
