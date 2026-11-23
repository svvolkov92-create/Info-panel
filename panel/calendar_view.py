# -*- coding: utf-8 -*-
"""Календарь: сетка месяца, производственный календарь, подсказки дней.
Примесь к классу Panel: методы работают с его состоянием (self)."""
from .core import *  # noqa: F401,F403 — общие константы и функции
from .widgets import ScrollArea  # noqa: F401
from .windows import (MatrixWindow, ReviewDialog, SearchWindow, TaskCard,  # noqa: F401
                      WeeklyReview, WeekView, WeekWindow)


class CalendarMixin:
    # ===================== календарь =====================
    def build_calendar(self):
        head, body = self.section("calendar")
        self.btn_prev = self.button(head, "‹", lambda: self.shift_month(-1), padx=6)
        self.btn_prev.pack(side="left")
        self.lbl_month = tk.Label(head, bg=C["card"], fg=C["fg"], font=self.f_title, cursor="hand2")
        self.lbl_month.pack(side="left", expand=True)
        self.lbl_month.bind("<Button-1>", lambda e: self.go_today())
        self.btn_next = self.button(head, "›", lambda: self.shift_month(1), padx=6)
        self.btn_next.pack(side="right")

        grid = tk.Frame(body, bg=C["card"])
        grid.pack(pady=(6, 0))
        for i, wd in enumerate(WD_SHORT):
            tk.Label(grid, text=wd, width=3, bg=C["card"],
                     fg=C["danger"] if i >= 5 else C["muted"],
                     font=self.f_small).grid(row=0, column=i, padx=1, pady=(0, 2))
        self.day_cells = []
        self.cell_dates = [None] * 42
        for i in range(42):
            lbl = tk.Label(grid, width=3, bg=C["card"], fg=C["fg"], font=self.f_day,
                           pady=2, cursor="hand2")
            lbl.grid(row=1 + i // 7, column=i % 7, padx=1, pady=1)
            lbl.bind("<Button-1>", lambda e, idx=i: self.select_day(idx))
            lbl.bind("<Enter>", lambda e, idx=i: self.day_enter(idx))
            lbl.bind("<Leave>", lambda e: self.hide_tip())
            self.day_cells.append(lbl)

    def shift_month(self, delta):
        m = self.view_m - 1 + delta
        self.view_y += m // 12
        self.view_m = m % 12 + 1
        self.render_calendar()

    def go_today(self):
        self.view_y, self.view_m = self.today.year, self.today.month
        self.selected = self.today
        self.render_calendar()
        self.render_tasks(keep_scroll=False)

    def select_day(self, idx):
        d = self.cell_dates[idx]
        if d is None:
            return
        self.hide_tip()
        if self.pick_task:  # режим «выбрать день для задачи»
            tid, self.pick_task = self.pick_task, None
            self.move_task_date(tid, d)
            return
        self.selected = d
        if (d.year, d.month) != (self.view_y, self.view_m):
            self.view_y, self.view_m = d.year, d.month
        self.render_calendar()
        self.render_tasks(keep_scroll=False)

    def day_info(self, d):
        """('work'|'off'|'short'|'moved', название праздника или '')."""
        name = FIXED_HOLIDAYS.get((d.month, d.day), "")
        cal = self.data["prodcal"].get(str(d.year)) if self.s["prod_cal"] else None
        if cal and len(cal) >= d.timetuple().tm_yday:
            code = cal[d.timetuple().tm_yday - 1]
            if code == "1":
                return "off", name
            if code == "2":
                return "short", ""
            if d.weekday() >= 5:
                return "moved", ""
            return "work", ""
        if d.weekday() >= 5:
            return "off", name
        if self.s["prod_cal"] and name:
            return "off", name
        return "work", ""

    def fetch_prodcal(self, year):
        """Производственный календарь РФ с isdayoff.ru, один раз на год, в фоне."""
        if (not self.s["prod_cal"] or str(year) in self.data["prodcal"]
                or year in self._fetching):
            return
        self._fetching.add(year)

        def work():
            try:
                url = f"https://isdayoff.ru/api/getdata?year={year}&cc=ru&pre=1"
                req = urllib.request.Request(url, headers={"User-Agent": "DesktopPanel"})
                with urllib.request.urlopen(req, timeout=10) as resp:
                    txt = resp.read().decode("ascii", "ignore").strip()
                if re.fullmatch(r"[0-9]{365,366}", txt):
                    self._pending.append(("prodcal", str(year), txt))
            except Exception as exc:  # нет интернета — останутся выходные и основные праздники
                log_error(f"Производственный календарь {year} не загрузился: {exc}")

        threading.Thread(target=work, daemon=True).start()

    def render_calendar(self):
        self.lbl_month.config(text=f"{MONTHS[self.view_m - 1]} {self.view_y}")
        weeks = calendar.Calendar(firstweekday=0).monthdatescalendar(self.view_y, self.view_m)
        days = [d for w in weeks for d in w]
        while len(days) < 42:
            days.append(days[-1] + dt.timedelta(days=1))
        for y in {d.year for d in days}:
            self.fetch_prodcal(y)
        load = {}
        for t in self.data["tasks"]:
            if not t["done"]:
                load[t["date"]] = load.get(t["date"], 0) + 1
        levels = [C["card"], mix(C["card"], C["accent"], 0.16),
                  mix(C["card"], C["accent"], 0.30), mix(C["card"], C["accent"], 0.48)]
        for i, (lbl, d) in enumerate(zip(self.day_cells, days)):
            self.cell_dates[i] = d
            in_month = d.month == self.view_m
            kind, _ = self.day_info(d)
            n = load.get(d.isoformat(), 0)
            lvl = 0 if n == 0 else 1 if n <= 2 else 2 if n <= 4 else 3
            bg = levels[lvl]
            fg = C["danger"] if kind == "off" else C["fg"]
            if not in_month:
                fg = C["faint"]
            if d == self.selected:
                bg = C["selected"]
            if d == self.today:
                bg, fg = C["accent"], C["on_accent"]
            lbl.config(text=str(d.day), bg=bg, fg=fg, font=self.f_day_mark if n else self.f_day)

    def day_enter(self, idx):
        self.hide_tip()
        if self._tdrag:
            return
        self._tip_after = self.root.after(450, lambda: self.show_day_tip(idx))

    def hide_tip(self):
        if self._tip_after:
            self.root.after_cancel(self._tip_after)
            self._tip_after = None
        if self._tip:
            self._tip.destroy()
            self._tip = None

    def show_day_tip(self, idx):
        self._tip_after = None
        d = self.cell_dates[idx]
        cell = self.day_cells[idx]
        tip = tk.Toplevel(self.root)
        tip.overrideredirect(True)
        tip.attributes("-topmost", True)
        tip.configure(bg=C["faint"])
        box = tk.Frame(tip, bg=C["card"], padx=10, pady=8)
        box.pack(padx=1, pady=1)

        def line(text, fg=C["fg"], font=None):
            tk.Label(box, text=text, bg=C["card"], fg=fg, font=font or self.f_small, anchor="w",
                     justify="left", wraplength=int(240 * self.scale())).pack(fill="x")

        line(f"{WEEKDAYS[d.weekday()]}, {d.day} {MONTHS_GEN[d.month - 1]}", font=self.f_title)
        kind, name = self.day_info(d)
        if name:
            line(name, C["danger"])
        elif kind == "short":
            line("Сокращённый рабочий день", C["warn"])
        elif kind == "moved":
            line("Рабочий день (перенос выходного)", C["warn"])
        for ev in self.data["events"]:
            if ev["date"] == d.isoformat():
                line("★ " + ev["title"], C["accent"])
        items = self.tasks_for(d)
        if items:
            for t in items[:8]:
                mark = "✔ " if t["done"] else "☐ "
                txt = mark + (t["time"] + " " if t.get("time") else "") + short(t["text"], 40)
                line(txt, C["muted"] if t["done"] else PRIO_COLOR.get(t.get("priority"), C["fg"]))
            if len(items) > 8:
                line(f"и ещё {len(items) - 8}", C["muted"])
        else:
            line("Задач нет", C["faint"])
        tip.update_idletasks()
        x = cell.winfo_rootx() + cell.winfo_width() + 8
        y = cell.winfo_rooty()
        vl, vt, vr, vb = virtual_screen(self.root)
        if x + tip.winfo_reqwidth() > vr:
            x = self.root.winfo_rootx() - tip.winfo_reqwidth() - 8
        if y + tip.winfo_reqheight() > vb:
            y = vb - tip.winfo_reqheight() - 8
        tip.geometry(f"+{x}+{y}")
        self._tip = tip
