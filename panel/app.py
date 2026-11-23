# -*- coding: utf-8 -*-
"""
Информационная панель для рабочего стола Windows.
Часы, календарь, задачи, помодоро, заметки, итоги недели, события.

Запуск: двойной клик по файлу (нужен установленный Python 3.9+).

Управление:
  • перетаскивание панели — тянуть за часы; двойной клик по часам сворачивает всё;
  • размер — уголок справа внизу, двойной клик по нему возвращает авторазмер;
  • настройки — правый клик по пустому месту панели;
  • задача: клик по квадратику — выполнена; двойной клик по тексту — правка;
    перетаскивание текста — порядок или перенос на день в календаре;
    правый клик — меню (перенос, важность, время, повтор, подзадачи, помодоро);
  • в начале задачи можно писать «!» (важная) и время «14:00»;
  • Ctrl+V с несколькими строками добавляет несколько задач;
  • быстрый ввод: «завтра 14:00 Созвон ~30м #работа !!1 до пт» — дата, время, оценка, метка,
    квадрант матрицы (!!1…!!4) и дедлайн; под строкой видно, что распознано;
  • клавиши в списке: ↑↓ выбор, пробел — выполнено, Enter — карточка, F2 — правка,
    Delete — удалить, Ctrl+↑/↓ — на день раньше/позже, Esc — снять выбор;
  • Ctrl+Z / Ctrl+Y — отменить / повторить любое изменение задач; Ctrl+F — поиск.

Данные: %APPDATA%\\DesktopPanel\\data.json, ошибки: %APPDATA%\\DesktopPanel\\error.log
"""
from .core import *  # noqa: F401,F403
from .widgets import ScrollArea  # noqa: F401
from .windows import (MatrixWindow, ReviewDialog, SearchWindow, TaskCard,  # noqa: F401
                      WeeklyReview, WeekView, WeekWindow)
from .calendar_view import CalendarMixin
from .tasks import TasksMixin
from .planning import PlanningMixin
from .pomodoro import PomodoroMixin
from .blocks import BlocksMixin
from .window import WindowMixin


class Panel(CalendarMixin, TasksMixin, PlanningMixin, PomodoroMixin, BlocksMixin, WindowMixin):
    def __init__(self):
        self.data = load_data()
        self.s = self.data["settings"]

        self.root = tk.Tk()
        self.root.report_callback_exception = self.on_error
        self.root.title("Панель")
        self.root.overrideredirect(True)
        self.root.configure(bg=C["bg"])
        self.root.attributes("-alpha", self.s["alpha"])
        self.root.attributes("-topmost", self.s["topmost"])

        self.today = dt.date.today()
        self.selected = self.today
        self.view_y, self.view_m = self.today.year, self.today.month

        self.pomo_mode = "work"
        self.pomo_running = False
        self.pomo_left = self.s["work"] * 60
        self.pomo_end = None
        self.flash_left = 0
        self.sections = {}
        self._dragging = False
        self._tdrag = None
        self._editing = None
        self.pick_task = None
        self.hist_undo, self.hist_redo = [], []  # снимки задач для Ctrl+Z / Ctrl+Y
        self._committed = b""
        self._dirty = False
        self._save_after = None
        self._save_warned = False
        self._render_parts = set()
        self._render_after = None
        self._status_after = None
        self.kb_sel = None
        self.review_win = None
        self.desk_active = False
        self.settings_win = None
        self._row_cache = {}     # id задачи → (подпись, строка) для частичной перерисовки списка
        self._empty_label = None
        self._render_sigs = {}
        self.hold_iso = set()  # дни, задачи которых в выходные не переносятся  # блок → данные прошлой отрисовки (чтобы не рисовать то же самое)
        self._undo_after = None
        self._tip = None
        self._tip_after = None
        self._notes_after = None
        self._pending = []
        self._fetching = set()
        self.toasts = []
        self.task_rows = []
        self.cards = {}
        self.scroll_areas = []
        self.future_headers = []
        self._nav_dir = 0
        self._nav_after = None
        self._hl = None
        self.live_views = []
        self.week_win = None
        self.matrix_win = None
        self.search_win = None
        self.focus_active = False
        self.focus_suppressed = False
        self.hidden = False
        self.tray = None

        self.make_fonts()
        self.carry_over_tasks()
        self.rebase_undo()
        self.build()
        self.render_all()
        self.apply_block_heights()
        self.apply_order()
        self.apply_size()
        self.root.bind("<Configure>", self.on_configure)
        self.root.bind_all("<Escape>", self.on_escape, add="+")
        self.root.bind_all("<Control-KeyPress>", self.global_ctrl, add="+")
        self.init_tray()
        self.tick()
        self.root.after(1500, self.maybe_morning_review)
        self.root.after(700, self.report_load_problems)
        self.bind_list_keys()
        if self.s.get("desktop_layer"):
            self.root.after(600, self.enter_desktop_layer)
        self.ct_active = False  # стиль окна сейчас пропускает мышь
        self.ct_peek = False    # Ctrl зажат — временно можно нажимать на панель
        self._ct_after = None
        if self.s.get("click_through"):
            self.root.after(300, self.apply_click_through)

    def on_error(self, exc, val, tb):
        log_error("".join(traceback.format_exception(exc, val, tb)))

    # ===================== шрифты =====================
    def make_fonts(self):
        fam = "Segoe UI"
        self.f_clock = tkfont.Font(family=fam + " Light", size=30)
        self.f_date = tkfont.Font(family=fam, size=10)
        self.f_title = tkfont.Font(family=fam, size=10, weight="bold")
        self.f_norm = tkfont.Font(family=fam, size=10)
        self.f_small = tkfont.Font(family=fam, size=9)
        self.f_tiny = tkfont.Font(family=fam, size=8)
        self.f_italic = tkfont.Font(family=fam, size=9, slant="italic")
        self.f_day = tkfont.Font(family=fam, size=9)
        self.f_day_mark = tkfont.Font(family=fam, size=9, weight="bold", underline=1)
        self.f_pomo = tkfont.Font(family=fam + " Light", size=26)
        # отдельные шрифты списка задач — их размер меняется в настройках, остальная панель не трогается
        self.f_task = tkfont.Font(family=fam)
        self.f_task_bold = tkfont.Font(family=fam, weight="bold")
        self.f_task_small = tkfont.Font(family=fam)
        self.f_task_tiny = tkfont.Font(family=fam)
        self.f_task_italic = tkfont.Font(family=fam, slant="italic")
        self.configure_task_fonts(int(self.s.get("task_font", 10)))

    def configure_task_fonts(self, size):
        self.f_task.configure(size=size)
        self.f_task_bold.configure(size=size)
        self.f_task_small.configure(size=max(6, size - 1))
        self.f_task_tiny.configure(size=max(6, size - 2))
        self.f_task_italic.configure(size=max(6, size - 1))

    def scale(self):
        return self.root.winfo_fpixels("1i") / 96.0

    # ===================== общие элементы =====================
    def section(self, key):
        card = tk.Frame(self.root, bg=C["card"], padx=12, pady=8)
        head = tk.Frame(card, bg=C["card"])
        head.pack(fill="x")
        arrow = tk.Label(head, text="▾", bg=C["card"], fg=C["muted"], font=self.f_norm,
                         cursor="hand2", padx=2)
        arrow.pack(side="left")
        arrow.bind("<Button-1>", lambda e: self.toggle_section(key))
        # полоска внизу блока: тянуть — менять высоту, двойной клик — естественный размер
        grip = tk.Frame(card, height=6, bg=C["card"], cursor="sb_v_double_arrow")
        grip.pack(side="bottom", fill="x", pady=(2, 0))
        grip.bind("<Enter>", lambda e: grip.config(bg=C["faint"]))
        grip.bind("<Leave>", lambda e: grip.config(bg=C["card"]))
        grip.bind("<ButtonPress-1>", lambda e: self.block_resize_start(e, key))
        grip.bind("<B1-Motion>", lambda e: self.block_resize_move(e, key))
        grip.bind("<ButtonRelease-1>", lambda e: self.block_resize_end(key))
        grip.bind("<Double-Button-1>", lambda e: self.reset_block_height(key))
        body = tk.Frame(card, bg=C["card"])
        body.pack(fill="both", expand=True)
        summary = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_small, cursor="hand2")
        summary.bind("<Button-1>", lambda e: self.toggle_section(key))
        self.sections[key] = {"card": card, "body": body, "arrow": arrow, "grip": grip,
                              "summary": summary}
        return head, body

    def make_toggle(self, widget, key):
        widget.bind("<Button-1>", lambda e: self.toggle_section(key))
        widget.config(cursor="hand2")

    def title_label(self, head, key, text):
        lbl = tk.Label(head, text=text, bg=C["card"], fg=C["fg"], font=self.f_title, anchor="w")
        lbl.pack(side="left")
        self.make_toggle(lbl, key)
        return lbl

    def button(self, parent, text, cmd, fg=None, font=None, padx=8, bg=None):
        base = bg or C["card"]
        lbl = tk.Label(parent, text=text, bg=base, fg=fg or C["fg"],
                       font=font or self.f_norm, padx=padx, pady=2, cursor="hand2")
        lbl.bind("<Button-1>", lambda e: cmd())
        lbl.bind("<Enter>", lambda e: lbl.config(bg=C["hover"]))
        lbl.bind("<Leave>", lambda e: lbl.config(bg=base))
        return lbl

    def make_entry(self, parent, placeholder, on_enter, on_paste=None, bg=None, font=None):
        """Поле ввода с подсказкой, Enter, Esc и Ctrl-клавишами в любой раскладке.
        on_paste(lines) вызывается для многострочной вставки."""
        var = tk.StringVar()
        e = tk.Entry(parent, textvariable=var, bg=bg or C["bg"], fg=C["fg"],
                     insertbackground=C["fg"], relief="flat", font=font or self.f_norm,
                     highlightthickness=1, highlightbackground=C["faint"],
                     highlightcolor=C["accent"])
        e.var = var
        ph = tk.Label(e, text=placeholder, bg=bg or C["bg"], fg=C["faint"], font=font or self.f_norm)
        e.placeholder = ph

        def show_ph():
            if not e.get() and self.root.focus_get() is not e:
                ph.place(x=4, rely=0.5, anchor="w")

        def focus(_=None):
            self.root.focus_force()
            e.focus_set()

        ph.place(x=4, rely=0.5, anchor="w")
        # подсказка прячется, как только в поле появился текст, даже без фокуса
        var.trace_add("write", lambda *a: ph.place_forget() if var.get() else show_ph())
        ph.bind("<Button-1>", focus)
        e.bind("<Button-1>", lambda ev: focus(), add="+")
        e.bind("<FocusIn>", lambda ev: ph.place_forget())
        e.bind("<FocusOut>", lambda ev: show_ph())
        e.bind("<Return>", lambda ev: on_enter(e))
        e.bind("<Escape>", lambda ev: (e.delete(0, "end"), "break")[1])
        e.bind("<Control-KeyPress>", lambda ev: self.entry_ctrl(ev, e, on_paste))
        e.bind("<<Paste>>", lambda ev: self.entry_paste(e, on_paste))
        e.show_placeholder = show_ph
        return e

    def entry_ctrl(self, ev, e, on_paste):
        k = ev.keycode
        if k == VK_V:
            return self.entry_paste(e, on_paste)
        if k == VK_C:
            e.event_generate("<<Copy>>")
            return "break"
        if k == VK_X:
            e.event_generate("<<Cut>>")
            return "break"
        if k == VK_A:
            e.select_range(0, "end")
            e.icursor("end")
            return "break"
        return None

    def entry_paste(self, e, on_paste):
        try:
            text = self.root.clipboard_get()
        except tk.TclError:
            return "break"
        lines = [LIST_MARKER.sub("", ln).strip() for ln in text.replace("\r", "\n").split("\n")]
        lines = [ln for ln in lines if ln]
        if len(lines) > 1 and on_paste:
            current = e.get().strip()
            if current:
                lines.insert(0, current)
                e.delete(0, "end")
            on_paste(lines)
            return "break"
        try:
            e.delete("sel.first", "sel.last")
        except tk.TclError:
            pass
        e.insert("insert", " ".join(lines))
        return "break"

    def bind_tree(self, widget, sequence, func, skip_entries=True):
        widget.bind(sequence, func, add="+")
        for ch in widget.winfo_children():
            if skip_entries and isinstance(ch, (tk.Entry, tk.Text)):
                continue
            self.bind_tree(ch, sequence, func, skip_entries)

    def input_dialog(self, title, hint, fields, on_ok, ok_text="Применить"):
        """Небольшое окно с полями. on_ok(values) возвращает текст ошибки или None."""
        dlg = tk.Toplevel(self.root)
        dlg.title(title)
        dlg.configure(bg=C["bg"], padx=16, pady=12)
        dlg.attributes("-topmost", True)
        dlg.resizable(False, False)
        tk.Label(dlg, text=hint, bg=C["bg"], fg=C["muted"], font=self.f_small,
                 justify="left").grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 8))
        entries = []
        for i, (name, val) in enumerate(fields):
            tk.Label(dlg, text=name, bg=C["bg"], fg=C["fg"], font=self.f_norm).grid(
                row=1 + i, column=0, sticky="w", padx=(0, 8), pady=2)
            ent = tk.Entry(dlg, width=12, bg=C["card"], fg=C["fg"], insertbackground=C["fg"],
                           relief="flat", font=self.f_norm)
            ent.insert(0, str(val))
            ent.grid(row=1 + i, column=1, sticky="w", pady=2, ipady=3)
            ent.bind("<Control-KeyPress>", lambda ev, x=ent: self.entry_ctrl(ev, x, None))
            entries.append(ent)
        err = tk.Label(dlg, text="", bg=C["bg"], fg=C["danger"], font=self.f_small)
        err.grid(row=1 + len(fields), column=0, columnspan=2, sticky="w")

        def ok(_=None):
            msg = on_ok([x.get().strip() for x in entries])
            if msg:
                err.config(text=msg)
            else:
                dlg.destroy()

        btns = tk.Frame(dlg, bg=C["bg"])
        btns.grid(row=2 + len(fields), column=0, columnspan=2, sticky="e", pady=(8, 0))
        self.button(btns, ok_text, ok, fg=C["accent"], bg=C["bg"]).pack(side="right")
        self.button(btns, "Отмена", dlg.destroy, fg=C["muted"], bg=C["bg"]).pack(side="right")
        dlg.bind("<Return>", ok)
        dlg.bind("<Escape>", lambda ev: dlg.destroy())
        dlg.update_idletasks()
        dlg.geometry(f"+{max(0, self.root.winfo_x())}+{max(0, self.root.winfo_y() + 60)}")
        dlg.focus_force()
        if entries:
            entries[0].focus_set()
            entries[0].select_range(0, "end")
        return dlg

    # ===================== построение интерфейса =====================
    def build(self):
        r = self.root
        self.spacer = tk.Frame(r, width=WIDTH, height=0, bg=C["bg"])
        self.spacer.pack()

        head = tk.Frame(r, bg=C["bg"], padx=16, pady=10)
        head.pack(fill="x")
        top = tk.Frame(head, bg=C["bg"])
        top.pack(fill="x")
        self.lbl_time = tk.Label(top, bg=C["bg"], fg=C["fg"], font=self.f_clock, anchor="w")
        self.lbl_time.pack(side="left")
        btn_search = tk.Label(top, text="⌕", bg=C["bg"], fg=C["muted"], font=self.f_title,
                              cursor="hand2")
        btn_search.pack(side="right", anchor="ne", pady=(4, 0), padx=(6, 0))
        btn_set = tk.Label(top, text="⚙", bg=C["bg"], fg=C["muted"], font=self.f_title, cursor="hand2")
        btn_set.pack(side="right", anchor="ne", pady=(4, 0), padx=(6, 0))
        btn_set.bind("<Button-1>", lambda e: self.open_settings())
        btn_set.bind("<Enter>", lambda e: btn_set.config(fg=C["accent"]))
        btn_set.bind("<Leave>", lambda e: btn_set.config(fg=C["muted"]))
        btn_search.bind("<Button-1>", lambda e: self.open_search())
        btn_search.bind("<Enter>", lambda e: btn_search.config(fg=C["accent"]))
        btn_search.bind("<Leave>", lambda e: btn_search.config(fg=C["muted"]))
        self.lbl_pin = tk.Label(top, bg=C["bg"], fg=C["faint"], font=self.f_small, anchor="ne")
        self.lbl_pin.pack(side="right", anchor="ne", pady=(6, 0))
        self.lbl_date = tk.Label(head, bg=C["bg"], fg=C["muted"], font=self.f_date, anchor="w")
        self.lbl_date.pack(fill="x")
        self.drag_widgets = (head, top, self.lbl_time, self.lbl_date, self.lbl_pin)
        for w in self.drag_widgets:
            w.bind("<ButtonPress-1>", self.drag_start)
            w.bind("<B1-Motion>", self.drag_move)
            w.bind("<ButtonRelease-1>", self.drag_end)
            w.bind("<Double-Button-1>", lambda e: self.toggle_all())

        self.build_calendar()
        self.build_goals()
        self.build_tasks()
        self.build_future()
        self.build_week()
        self.build_pomo()
        self.build_focus()
        self.build_notes()
        self.build_stats()
        self.build_events()

        g = int(16 * self.scale())
        self.grip = tk.Canvas(r, width=g, height=g, bg=C["bg"], highlightthickness=0)
        try:
            self.grip.config(cursor="size_nw_se")
        except tk.TclError:
            self.grip.config(cursor="bottom_right_corner")
        for k in (1, 2, 3):
            o = g * k // 4
            self.grip.create_line(g - 2, o, o, g - 2, fill=C["faint"], width=2, tags="mark")
        self.grip.bind("<ButtonPress-1>", self.grip_start)
        self.grip.bind("<B1-Motion>", self.grip_move)
        self.grip.bind("<ButtonRelease-1>", self.grip_end)
        self.grip.bind("<Double-Button-1>", lambda e: self.set_fixed_size(False))
        self.grip.bind("<Enter>", lambda e: self.grip.itemconfig("mark", fill=C["accent"]))
        self.grip.bind("<Leave>", lambda e: self.grip.itemconfig("mark", fill=C["faint"]))

        self.make_menu()
        r.bind_all("<Button-3>", self.show_menu)
        self.update_pin_label()

    def render_all(self):
        self.render_calendar()
        self.render_goals()
        self.render_tasks()
        self.render_future()
        self.render_week()
        self.render_pomo()
        self.render_events()
        self.render_stats()
        self.update_summaries()

    # ===================== главный цикл =====================
    def tick(self):
        try:
            self._tick()
            self._tick_error = None
        except Exception:
            err = traceback.format_exc()
            if err != getattr(self, "_tick_error", None):  # одна и та же ошибка — в журнал один раз,
                log_error(err)                              # а не дважды в секунду
                self._tick_error = err
        self.root.after(500, self.tick)

    def _tick(self):
        now = dt.datetime.now()
        self.lbl_time.config(text=now.strftime("%H:%M"))
        self.lbl_date.config(
            text=f"{WEEKDAYS[now.weekday()]}, {now.day} {MONTHS_GEN[now.month - 1]} {now.year}")

        while self._pending:
            kind, *args = self._pending.pop(0)
            if kind == "prodcal":
                self.data["prodcal"][args[0]] = args[1]
                self.save()
                self.render_calendar()

        if now.date() != self.today:
            was_today = self.selected == self.today
            self.today = now.date()
            if was_today:
                self.selected = self.today
                self.view_y, self.view_m = self.today.year, self.today.month
            self.carry_over_tasks()
            self.hist_undo.clear()  # вчерашние шаги отмены к новому дню не относятся
            self.hist_redo.clear()
            self.rebase_undo()
            self.render_all()
            self.refresh_cards()
            self.maybe_morning_review()

        if self.pomo_running and now >= self.pomo_end:
            self.pomo_running = False
            self.pomo_finish()
        # каждый шаг отдельно: сбой в одном (например, в напоминаниях) не должен останавливать таймер
        errors = []
        for step in (self.render_pomo, lambda: self.check_reminders(now), lambda: self.maybe_weekly_review(now)):
            try:
                step()
            except Exception:
                errors.append(traceback.format_exc())
        if errors:
            raise RuntimeError("\n".join(errors))

    def run(self):
        self.root.mainloop()


def already_running():
    """Не даём запустить вторую копию (например, автозапуск + ручной запуск)."""
    if not (IS_WIN and ctypes):
        return False
    try:
        k32 = ctypes.windll.kernel32
        k32.CreateMutexW.restype = wintypes.HANDLE
        Panel._mutex = k32.CreateMutexW(None, False, "Local\\DesktopPanelSingleInstance")
        return k32.GetLastError() == 183  # ERROR_ALREADY_EXISTS
    except Exception:
        return False


def main():
    if already_running():
        if activate_running_copy():  # повторный запуск просто показывает уже работающую панель
            sys.exit(0)
        r = tk.Tk()
        r.withdraw()
        from tkinter import messagebox
        messagebox.showinfo("Панель", "Панель уже запущена.\nЕсли её не видно — щёлкните по значку в трее.")
        r.destroy()
        sys.exit(0)
    try:
        Panel().run()
    except Exception:
        err = traceback.format_exc()
        log_error(err)
        try:
            from tkinter import messagebox
            r = tk.Tk()
            r.withdraw()
            messagebox.showerror("Панель: ошибка запуска", err[-1500:] + f"\n\nПодробности в {LOG_FILE}")
            r.destroy()
        except Exception:
            pass
