# -*- coding: utf-8 -*-
"""Окно настроек: все параметры панели в одном месте. Изменения применяются сразу."""
from .core import *  # noqa: F401,F403 — общие константы и функции


class SettingsWindow:
    def __init__(self, panel):
        self.p = p = panel
        w = self.win = tk.Toplevel(p.root)
        w.title("Настройки панели")
        w.configure(bg=C["bg"])
        w.attributes("-topmost", True)  # не прятаться за панелью, если та «поверх всех окон»
        w.protocol("WM_DELETE_WINDOW", self.close)
        w.bind("<Escape>", lambda e: self.close())

        out = tk.Frame(w, bg=C["bg"], padx=16, pady=12)
        out.pack(fill="both", expand=True)
        cols = tk.Frame(out, bg=C["bg"])
        cols.pack(fill="both", expand=True)
        left = tk.Frame(cols, bg=C["bg"])
        left.pack(side="left", fill="both", expand=True, anchor="n")
        right = tk.Frame(cols, bg=C["bg"])
        right.pack(side="left", fill="both", expand=True, anchor="n", padx=(24, 0))

        # --- вид ---
        sec = self.section(left, "Вид")
        self.alpha = self.scale(sec, "Непрозрачность, %", 40, 100, round(p.s["alpha"] * 100),
                                p.set_alpha_percent)
        self.check(sec, "Поверх всех окон", p.var_top, p.toggle_topmost)
        self.check(sec, "Сквозные клики (нажимать на панель — с Ctrl)", p.var_ct,
                   lambda: p.set_click_through_mode(p.var_ct.get()))
        self.check(sec, "Под ярлыками рабочего стола", p.var_desk,
                   lambda: p.set_desktop_layer(p.var_desk.get()))

        # --- список задач ---
        sec = self.section(left, "Список задач")
        self.font = self.scale(sec, "Размер шрифта", 7, 16, p.s.get("task_font", 10), p.set_task_font)
        self.gap = self.scale(sec, "Отступ между задачами, пикс.", 0, 12, p.s.get("task_gap", 1),
                              p.set_task_gap)
        self.listh = self.scale(sec, "Предел высоты списка (в авторазмере)", 120, 720,
                                p.s.get("tasks_max", 260), p.set_list_height, step=20)
        self.preview = tk.Label(sec, text="Так выглядит задача в списке", bg=C["card"], fg=C["fg"],
                                font=p.f_task, anchor="w", padx=8, pady=2)
        self.preview.pack(fill="x", pady=(4, 0))

        # --- окно ---
        sec = self.section(left, "Окно")
        self.check(sec, "Запускать вместе с Windows", p.var_auto, lambda: set_autostart(p.var_auto.get()))
        self.check(sec, "Закрепить на текущем месте", p.var_pinned, p.toggle_pinned)
        self.check(sec, "Фиксированная ширина (уголок справа внизу)", p.var_fixed,
                   lambda: p.set_fixed_size(p.var_fixed.get()))
        row = tk.Frame(sec, bg=C["bg"])
        row.pack(fill="x", pady=(4, 0))
        p.button(row, "Блоки и порядок…", p.blocks_dialog, fg=C["accent"], bg=C["bg"], padx=0).pack(side="left")
        p.button(row, "Сбросить высоту блоков", p.reset_all_block_heights, fg=C["accent"],
                 bg=C["bg"]).pack(side="left", padx=(10, 0))
        p.button(sec, "Вернуть панель в угол экрана", p.reset_position, fg=C["accent"], bg=C["bg"],
                 padx=0).pack(anchor="w")

        # --- помодоро ---
        sec = self.section(right, "Помодоро, минуты")
        self.pomo = {}
        for key, label, lo, hi in (("work", "Работа", 1, 180), ("break", "Перерыв", 1, 60),
                                   ("long", "Длинный перерыв", 1, 90), ("cycle", "Длинный после, помидоров", 1, 12)):
            self.pomo[key] = self.spin(sec, label, lo, hi, p.s[key], self.apply_pomo)
        self.check(sec, "Сразу запускать перерыв", p.var_auto_break, p.toggle_auto_break)
        self.check(sec, "Режим фокуса во время работы", p.var_focus, p.toggle_focus_setting)
        p.button(sec, "Звуки и громкость…", p.sounds_dialog, fg=C["accent"], bg=C["bg"], padx=0).pack(anchor="w")

        # --- планирование ---
        sec = self.section(right, "Планирование")
        self.q1 = self.spin(sec, "Лимит «Сделать сейчас» в день", 1, 50, p.s["q1_limit"], self.apply_limits)
        self.hours = self.spin(sec, "Рабочих часов в дне", 1, 24, p.s["day_hours"], self.apply_limits,
                               increment=0.5)
        self.weekend = tk.BooleanVar(value=p.s.get("weekend_hold", True))
        self.check(sec, "В выходные задачи пятницы ждут понедельника", self.weekend,
                   lambda: p.set_weekend_hold(self.weekend.get()))
        self.check(sec, "Утренний разбор хвостов", p.var_review,
                   lambda: (p.s.update(review=p.var_review.get()), p.save()))
        self.check(sec, "Обзор недели по пятницам", p.var_weekly,
                   lambda: (p.s.update(weekly_review=p.var_weekly.get()), p.save()))
        self.check(sec, "Производственный календарь РФ", p.var_prod, p.toggle_prod_cal)

        # --- низ ---
        foot = tk.Frame(out, bg=C["bg"])
        foot.pack(fill="x", pady=(14, 0))
        tk.Label(foot, text=f"Данные: {DATA_DIR}", bg=C["bg"], fg=C["faint"], font=p.f_tiny).pack(side="left")
        if IS_WIN:
            p.button(foot, "Открыть папку", lambda: open_target(DATA_DIR), fg=C["muted"],
                     bg=C["bg"]).pack(side="left", padx=(6, 0))
        p.button(foot, "Готово", self.close, fg=C["accent"], bg=C["bg"]).pack(side="right")

        w.update_idletasks()
        sw, sh = p.root.winfo_screenwidth(), p.root.winfo_screenheight()
        ww, wh = w.winfo_reqwidth(), w.winfo_reqheight()
        x = p.root.winfo_rootx() - ww - 12
        if x < 0:
            x = min(sw - ww, p.root.winfo_rootx() + p.root.winfo_width() + 12)
        w.geometry(f"+{max(0, x)}+{max(0, min(p.root.winfo_rooty(), sh - wh - 40))}")
        w.focus_force()

    # --- элементы ---
    def section(self, parent, title):
        tk.Label(parent, text=title, bg=C["bg"], fg=C["accent"], font=self.p.f_title,
                 anchor="w").pack(fill="x", pady=(10, 4))
        f = tk.Frame(parent, bg=C["bg"])
        f.pack(fill="x")
        return f

    def check(self, parent, text, var, cmd):
        cb = tk.Checkbutton(parent, text=text, variable=var, command=cmd, bg=C["bg"], fg=C["fg"],
                            selectcolor=C["card"], activebackground=C["bg"], activeforeground=C["fg"],
                            font=self.p.f_small, anchor="w", highlightthickness=0, bd=0)
        cb.pack(fill="x", pady=1)
        return cb

    def scale(self, parent, text, lo, hi, value, apply, step=1):
        tk.Label(parent, text=text, bg=C["bg"], fg=C["muted"], font=self.p.f_small, anchor="w").pack(fill="x")
        sc = tk.Scale(parent, from_=lo, to=hi, resolution=step, orient="horizontal", showvalue=True,
                      bg=C["bg"], fg=C["fg"], troughcolor=C["card"], highlightthickness=0, bd=0,
                      activebackground=C["accent"], font=self.p.f_tiny, length=int(240 * self.p.scale()),
                      sliderlength=int(16 * self.p.scale()))
        sc.set(value)
        sc.config(command=lambda v: self.on_scale(apply, v))
        sc.pack(anchor="w")
        return sc

    def on_scale(self, apply, value):
        apply(int(float(value)))
        self.preview.config(font=self.p.f_task) if hasattr(self, "preview") else None

    def spin(self, parent, text, lo, hi, value, apply, increment=1):
        row = tk.Frame(parent, bg=C["bg"])
        row.pack(fill="x", pady=1)
        tk.Label(row, text=text, bg=C["bg"], fg=C["fg"], font=self.p.f_small, anchor="w").pack(side="left")
        var = tk.StringVar(value=f"{value:g}" if isinstance(value, float) else str(value))
        sp = tk.Spinbox(row, from_=lo, to=hi, increment=increment, textvariable=var, width=5,
                        bg=C["card"], fg=C["fg"], insertbackground=C["fg"], buttonbackground=C["card"],
                        relief="flat", font=self.p.f_small, command=apply)
        sp.pack(side="right")
        sp.bind("<Return>", lambda e: apply())
        sp.bind("<FocusOut>", lambda e: apply())
        sp.var = var
        return sp

    # --- применение ---
    def apply_pomo(self):
        try:
            vals = {k: int(sp.var.get()) for k, sp in self.pomo.items()}
        except ValueError:
            return  # недописанное число — дождёмся
        self.p.set_pomo_durations(vals["work"], vals["break"], vals["long"], vals["cycle"])

    def apply_limits(self):
        try:
            q1 = int(self.q1.var.get())
            hours = float(self.hours.var.get().replace(",", "."))
        except ValueError:
            return
        self.p.set_day_limits(q1, hours)

    def close(self):
        self.p.settings_win = None
        try:
            self.win.destroy()
        except tk.TclError:
            pass
