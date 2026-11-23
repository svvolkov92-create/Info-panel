# -*- coding: utf-8 -*-
"""Помодоро, режим фокуса и звуки.
Примесь к классу Panel: методы работают с его состоянием (self)."""
from .core import *  # noqa: F401,F403 — общие константы и функции
from .widgets import ScrollArea  # noqa: F401
from .windows import (MatrixWindow, ReviewDialog, SearchWindow, TaskCard,  # noqa: F401
                      WeeklyReview, WeekView, WeekWindow)


class PomodoroMixin:
    # ===================== режим фокуса =====================
    def build_focus(self):
        bar = self.focus_bar = tk.Frame(self.root, bg=C["card"], padx=14, pady=10)
        self.lbl_focus_mode = tk.Label(bar, bg=C["card"], fg=C["accent"], font=self.f_small, anchor="w")
        self.lbl_focus_mode.pack(fill="x")
        self.lbl_focus_time = tk.Label(bar, bg=C["card"], fg=C["fg"], font=self.f_pomo, anchor="w")
        self.lbl_focus_time.pack(fill="x")
        self.lbl_focus_task = tk.Label(bar, bg=C["card"], fg=C["fg"], font=self.f_norm, anchor="w",
                                       justify="left", wraplength=int((WIDTH - 60) * self.scale()))
        self.lbl_focus_task.pack(fill="x", pady=(2, 6))
        btns = tk.Frame(bar, bg=C["card"])
        btns.pack(fill="x")
        self.btn_focus_pause = self.button(btns, "Пауза", self.pomo_toggle, fg=C["accent"], font=self.f_small)
        self.btn_focus_pause.pack(side="left")
        self.button(btns, "Стоп", self.pomo_reset, fg=C["muted"], font=self.f_small).pack(side="left")
        self.button(btns, "Показать панель", lambda: self.exit_focus(manual=True), fg=C["muted"],
                    font=self.f_small).pack(side="right")

    def enter_focus(self):
        if self.focus_active:
            return
        self.focus_active = True
        self.hide_tip()
        for sec in self.sections.values():
            sec["card"].pack_forget()
        self.focus_bar.pack(fill="x", padx=12, pady=(0, 10))
        self.render_focus()
        self.apply_position()

    def exit_focus(self, manual=False):
        if manual:
            self.focus_suppressed = True
        if not self.focus_active:
            return
        self.focus_active = False
        self.focus_bar.pack_forget()
        self.apply_order()
        self.apply_position()

    def render_focus(self):
        if not self.focus_active:
            return
        mode = {"work": "Фокус", "break": "Перерыв", "long": "Длинный перерыв"}[self.pomo_mode]
        self.lbl_focus_mode.config(text=mode + ("" if self.pomo_running else " · пауза"))
        self.lbl_focus_time.config(text=self.pomo_clock())
        t = self.find_task(self.s.get("pomo_task"))
        self.lbl_focus_task.config(text=t["text"] if t else "Без привязки к задаче",
                                   fg=C["fg"] if t else C["faint"])
        self.btn_focus_pause.config(text="Пауза" if self.pomo_running else "Продолжить")

    def toggle_focus_setting(self):
        self.s["focus_mode"] = self.var_focus.get()
        self.save()
        if not self.s["focus_mode"]:
            self.exit_focus()

    # ===================== звуки =====================
    def sounds_dialog(self):
        dlg = tk.Toplevel(self.root)
        dlg.title("Звуки помодоро")
        dlg.configure(bg=C["bg"], padx=16, pady=12)
        dlg.attributes("-topmost", True)
        dlg.resizable(False, False)
        files = Sound.system_files()
        by_name = {os.path.splitext(os.path.basename(f))[0]: f for f in files}
        base = ["Системный звук", "Без звука"]
        tk.Label(dlg, text="Звук и громкость отдельно для конца работы и конца перерыва.",
                 bg=C["bg"], fg=C["muted"], font=self.f_small).grid(row=0, column=0, columnspan=4,
                                                                   sticky="w", pady=(0, 8))
        for i, (kind, title) in enumerate(SOUND_KINDS.items(), start=1):
            cfg = self.s["sounds"].setdefault(kind, {"file": "default", "vol": 80})
            cur = cfg.get("file", "default")
            names = base + list(by_name) + ["Свой файл…"]
            if cur == "default":
                shown = "Системный звук"
            elif cur == "none":
                shown = "Без звука"
            else:
                shown = os.path.splitext(os.path.basename(cur))[0]
                if shown not in by_name:
                    names.insert(2, shown)
                    by_name[shown] = cur
            tk.Label(dlg, text=title, bg=C["bg"], fg=C["fg"], font=self.f_norm).grid(
                row=i, column=0, sticky="w", padx=(0, 10), pady=4)
            box = ttk.Combobox(dlg, values=names, state="readonly", width=26)
            box.set(shown)
            box.grid(row=i, column=1, pady=4)
            vol = tk.Scale(dlg, from_=0, to=100, orient="horizontal", length=int(140 * self.scale()),
                           bg=C["bg"], fg=C["muted"], troughcolor=C["card"], highlightthickness=0,
                           showvalue=True, font=self.f_tiny, label="")
            vol.set(cfg.get("vol", 80))
            vol.grid(row=i, column=2, padx=8)

            def on_pick(e, k=kind, b=box):
                name = b.get()
                c = self.s["sounds"][k]
                if name == "Системный звук":
                    c["file"] = "default"
                elif name == "Без звука":
                    c["file"] = "none"
                elif name == "Свой файл…":
                    path = filedialog.askopenfilename(parent=dlg, title="Звук",
                                                      filetypes=[("Звук", "*.wav *.mp3"), ("Все", "*.*")])
                    if not path:
                        return
                    c["file"] = path
                    label = os.path.splitext(os.path.basename(path))[0]
                    b.config(values=list(b.cget("values")) + [label])
                    b.set(label)
                else:
                    c["file"] = by_name.get(name, "default")
                self.save()

            box.bind("<<ComboboxSelected>>", on_pick)
            vol.config(command=lambda v, k=kind: (self.s["sounds"][k].update(vol=int(float(v))),
                                                  self.save()))
            self.button(dlg, "▶", lambda k=kind: Sound.play(self.s["sounds"][k]), fg=C["accent"],
                        bg=C["bg"]).grid(row=i, column=3)
        if not IS_WIN:
            tk.Label(dlg, text="Звук работает только в Windows.", bg=C["bg"], fg=C["warn"],
                     font=self.f_tiny).grid(row=3, column=0, columnspan=4, sticky="w")
        self.button(dlg, "Готово", dlg.destroy, fg=C["accent"], bg=C["bg"]).grid(
            row=4, column=3, sticky="e", pady=(8, 0))
        dlg.bind("<Escape>", lambda e: dlg.destroy())
        dlg.geometry(f"+{max(0, self.root.winfo_x() - 300)}+{max(0, self.root.winfo_y() + 60)}")
        return dlg

    # ===================== помодоро =====================
    def build_pomo(self):
        head, body = self.section("pomo")
        self.lbl_pomo_mode = tk.Label(head, bg=C["card"], font=self.f_title, anchor="w")
        self.lbl_pomo_mode.pack(side="left")
        self.make_toggle(self.lbl_pomo_mode, "pomo")
        self.lbl_pomo_count = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_small)
        self.lbl_pomo_count.pack(side="right")

        self.lbl_pomo_task = tk.Label(body, bg=C["card"], fg=C["muted"], font=self.f_small,
                                      anchor="w", cursor="hand2")
        self.lbl_pomo_task.bind("<Button-1>", lambda e: self.link_pomo(None))
        row = tk.Frame(body, bg=C["card"])
        row.pack(fill="x", pady=(4, 0))
        self.lbl_pomo_time = tk.Label(row, bg=C["card"], fg=C["fg"], font=self.f_pomo)
        self.lbl_pomo_time.pack(side="left")
        btns = tk.Frame(row, bg=C["card"])
        btns.pack(side="right")
        self.btn_pomo_start = self.button(btns, "Старт", self.pomo_toggle, fg=C["accent"])
        self.btn_pomo_start.pack(side="left")
        self.button(btns, "⟲", self.pomo_reset, fg=C["muted"], padx=6).pack(side="left")
        self.button(btns, "⏭", self.pomo_skip, fg=C["muted"], padx=6).pack(side="left")
        self.pomo_cycle_lbl = tk.Label(body, bg=C["card"], fg=C["faint"], font=self.f_tiny, anchor="w")
        self.pomo_cycle_lbl.pack(fill="x")

    def pomo_minutes(self, mode):
        return {"work": self.s["work"], "break": self.s["break"], "long": self.s["long"]}[mode]

    def cycle_count(self):
        c = self.data["pomo_cycle"]
        if c.get("date") != self.today.isoformat():
            c.clear()
            c.update(date=self.today.isoformat(), n=0)
        return c

    def pomo_toggle(self):
        if self.pomo_running:
            self.pomo_left = max(0, int(round((self.pomo_end - dt.datetime.now()).total_seconds())))
            self.pomo_running = False
        else:
            self.pomo_end = dt.datetime.now() + dt.timedelta(seconds=self.pomo_left)
            self.pomo_running = True
            if self.pomo_mode == "work" and self.s.get("focus_mode") and not self.focus_suppressed:
                self.enter_focus()
        self.render_pomo()
        self.refresh_cards()

    def pomo_reset(self):
        self.pomo_running = False
        self.pomo_left = self.pomo_minutes(self.pomo_mode) * 60
        self.focus_suppressed = False
        self.exit_focus()
        self.render_pomo()
        self.refresh_cards()

    def pomo_skip(self):
        self.pomo_mode = "break" if self.pomo_mode == "work" else "work"
        self.pomo_reset()

    def pomo_finish(self):
        if self.pomo_mode == "work":
            key = self.today.isoformat()
            self.data["pomodoros"][key] = self.data["pomodoros"].get(key, 0) + 1
            t = self.find_task(self.s.get("pomo_task"))
            minutes = int(self.s["work"])
            if t:
                t["pomos"] = t.get("pomos", 0) + 1
                t["spent"] = t.get("spent", 0) + minutes
            self.data["pomo_log"].append({"date": key, "task": t["id"] if t else None,
                                          "text": t["text"] if t else "", "min": minutes,
                                          "tags": list(t.get("tags") or []) if t else []})
            self.rebase_undo()  # помидор — не действие пользователя, отменять его нечего
            c = self.cycle_count()
            c["n"] += 1
            self.pomo_mode = "long" if c["n"] % max(1, self.s["cycle"]) == 0 else "break"
            self.save()
            self.pomo_reset()
            title = "Длинный перерыв" if self.pomo_mode == "long" else "Перерыв"
            self.toast(f"{title}: {self.pomo_minutes(self.pomo_mode)} мин",
                       "Помидор готов. Отдохните.", C["rest"], timeout=20000, sound="work")
            if self.s["auto_break"]:
                self.pomo_toggle()
            self.render_tasks()
            self.render_stats()
        else:
            self.pomo_mode = "work"
            self.pomo_reset()
            self.toast("Перерыв закончился", "Можно начинать следующий помидор.", C["accent"],
                       timeout=20000, sound="break")
        self.flash_left = 8
        self.flash()

    def flash(self):
        if self.flash_left <= 0:
            self.set_pomo_bg(C["card"])
            return
        color = C["accent"] if self.pomo_mode == "work" else C["rest"]
        self.set_pomo_bg(color if self.flash_left % 2 == 0 else C["card"])
        self.flash_left -= 1
        self.root.after(350, self.flash)

    def set_pomo_bg(self, color):
        def walk(w):
            try:
                w.config(bg=color)
            except tk.TclError:
                pass
            for ch in w.winfo_children():
                walk(ch)
        walk(self.sections["pomo"]["card"])

    def link_pomo(self, tid):
        self.s["pomo_task"] = tid
        self.save()
        if tid and not self.pomo_running:
            self.pomo_mode = "work"
            self.pomo_reset()
            self.pomo_toggle()
        self.render_pomo()
        self.render_tasks()
        self.refresh_cards()

    def pomo_clock(self):
        if self.pomo_running:
            left = max(0, int(round((self.pomo_end - dt.datetime.now()).total_seconds())))
        else:
            left = self.pomo_left
        return f"{left // 60:02d}:{left % 60:02d}"

    def render_pomo(self):
        clock = self.pomo_clock()
        self.render_focus()
        for card in list(self.cards.values()):
            card.update_timer()
        self.lbl_pomo_time.config(text=clock)
        mode = {"work": "Фокус", "break": "Перерыв", "long": "Длинный перерыв"}[self.pomo_mode]
        if self.s["collapsed"].get("pomo"):
            mode += f"  {clock}" + ("" if self.pomo_running else " ⏸")
        color = C["accent"] if self.pomo_mode == "work" else C["rest"]
        self.lbl_pomo_mode.config(text=mode, fg=color)
        self.btn_pomo_start.config(text="Пауза" if self.pomo_running else "Старт")
        n = self.data["pomodoros"].get(self.today.isoformat(), 0)
        self.lbl_pomo_count.config(text=f"сегодня: {n} ●" if n else "")
        t = self.find_task(self.s.get("pomo_task"))
        if t:
            self.lbl_pomo_task.config(text=f"→ {short(t['text'], 38)}   ✕")
            if not self.lbl_pomo_task.winfo_manager():
                self.lbl_pomo_task.pack(fill="x", before=self.lbl_pomo_time.master)
        else:
            if self.s.get("pomo_task"):
                self.s["pomo_task"] = None
            self.lbl_pomo_task.pack_forget()
        every = max(1, self.s["cycle"])
        done_in_cycle = self.cycle_count()["n"] % every
        dots = "●" * done_in_cycle + "○" * (every - done_in_cycle)
        self.pomo_cycle_lbl.config(text=f"{dots}  до длинного перерыва")

    def set_preset(self, w, b, lg):
        self.s.update(work=w, **{"break": b}, long=lg)
        self.save()
        if not self.pomo_running:
            self.pomo_reset()

    def ask_durations(self):
        def ok(vals):
            try:
                w, b, lg, cyc = (int(v) for v in vals)
            except ValueError:
                return "Введите целые числа"
            if not (1 <= w <= 180 and 1 <= b <= 60 and 1 <= lg <= 90 and 1 <= cyc <= 12):
                return "Работа 1–180, перерывы до 60/90 мин, цикл 1–12"
            self.s.update(work=w, **{"break": b}, long=lg, cycle=cyc)
            self.save()
            if not self.pomo_running:
                self.pomo_reset()
            return None

        self.input_dialog("Длительность помодоро", "Время в минутах.",
                          [("Работа", self.s["work"]), ("Перерыв", self.s["break"]),
                           ("Длинный перерыв", self.s["long"]),
                           ("Длинный после N", self.s["cycle"])], ok)
