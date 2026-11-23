# -*- coding: utf-8 -*-
"""Отдельные окна: карточка задачи, неделя, матрица, разбор задач, поиск, обзор недели."""
from .core import *  # noqa: F401,F403 — общие константы и функции
from .widgets import ScrollArea


class TaskCard:
    """Отдельное окно задачи: дата, приоритет, матрица Эйзенхауэра, помодоро, подзадачи, заметка."""

    def __init__(self, panel, tid):
        self.p, self.tid = panel, tid
        p = panel
        self._note_after = None
        self._sub_focus = False
        self._tag_focus = False
        self.pomo_lbl = None
        w = self.win = tk.Toplevel(p.root)
        w.title("Задача")
        w.configure(bg=C["bg"])
        w.protocol("WM_DELETE_WINDOW", self.close)
        if p.s["topmost"]:
            w.attributes("-topmost", True)
        w.bind("<Escape>", lambda e: self.close())

        out = tk.Frame(w, bg=C["bg"], padx=16, pady=12)
        out.pack(fill="both", expand=True)
        self.title_e = tk.Entry(out, bg=C["card"], fg=C["fg"], insertbackground=C["fg"],
                                relief="flat", font=p.f_title, highlightthickness=1,
                                highlightbackground=C["faint"], highlightcolor=C["accent"])
        self.title_e.pack(fill="x", ipady=5)
        self.title_e.bind("<Return>", lambda e: self.save_title())
        self.title_e.bind("<FocusOut>", lambda e: self.save_title())
        self.title_e.bind("<Control-KeyPress>", lambda e: p.entry_ctrl(e, self.title_e, None))
        self.status = tk.Frame(out, bg=C["bg"])
        self.status.pack(fill="x", pady=(6, 0))

        # футер закреплён внизу, середина прокручивается
        foot = tk.Frame(out, bg=C["bg"])
        foot.pack(side="bottom", fill="x", pady=(10, 0))
        self.area = ScrollArea(p, out)
        for wdg in (self.area.wrap, self.area.sb, self.area.canvas, self.area.frame):
            wdg.config(bg=C["bg"])
        self.area.wrap.pack(fill="both", expand=True)
        self.area.frame.bind("<Configure>", lambda e: self._relayout())
        self._relayout_after = None
        body = self.area.frame

        self.sec_when = self.section(body, "when", "Когда")
        self.sec_prio = self.section(body, "prio", "Приоритет по важности")
        self.sec_eis = self.section(body, "eis", "Матрица Эйзенхауэра")
        self.sec_tags = self.section(body, "tags", "Метки")
        self.sec_goal = self.section(body, "goal", "Цель недели")
        self.sec_pomo = self.section(body, "pomo", "Помодоро")
        self.sec_subs = self.section(body, "subs", "Подзадачи")
        self.sec_hist = self.section(body, "hist", "История")
        note_box = self.section(body, "note",
                                "Заметка (ссылки и пути к файлам открываются по клику)")
        self.note = tk.Text(note_box, height=6, wrap="word", bg=C["card"], fg=C["fg"],
                            insertbackground=C["fg"], relief="flat", font=p.f_small,
                            highlightthickness=1, highlightbackground=C["faint"],
                            highlightcolor=C["accent"], padx=6, pady=4, undo=True)
        self.note.pack(fill="x")
        self.note.insert("1.0", (p.find_task(tid) or {}).get("note", ""))
        p.setup_links(self.note)
        self.note.edit_reset()
        self.note.edit_modified(False)
        self.note.bind("<<Modified>>", self.note_modified)
        self.note.bind("<Control-KeyPress>", lambda e: p.text_ctrl(e, self.note))

        p.button(foot, "Удалить задачу", self.delete, fg=C["danger"], bg=C["bg"]).pack(side="left")
        p.button(foot, "В шаблон…", lambda: p.save_task_template(self.tid), fg=C["muted"],
                 bg=C["bg"]).pack(side="left", padx=(8, 0))
        p.button(foot, "Закрыть", self.close, fg=C["accent"], bg=C["bg"]).pack(side="right")

        self.refresh()
        w.update_idletasks()
        cw = max(w.winfo_reqwidth(), int(360 * p.scale()))
        x = p.root.winfo_rootx() - cw - 12
        if x < virtual_screen(p.root)[0]:
            x = p.root.winfo_rootx() + p.root.winfo_width() + 12
        # высота по содержимому, но не выше экрана — дальше прокрутка
        y = max(0, p.root.winfo_rooty())
        scr_h = w.winfo_screenheight()
        need = w.winfo_reqheight() + self.area.frame.winfo_reqheight()
        h = max(int(300 * p.scale()), min(need, scr_h - y - 60))
        w.geometry(f"{cw}x{h}+{max(0, x)}+{y}")
        w.minsize(cw, int(240 * p.scale()))
        w.focus_force()

    # --- элементы ---
    def section(self, parent, key, title):
        """Секция со сворачиваемым заголовком; состояние запоминается в настройках."""
        collapsed = self.p.s.setdefault("card_collapsed", [])
        box = tk.Frame(parent, bg=C["bg"])
        box.pack(fill="x")
        head = tk.Label(box, bg=C["bg"], fg=C["muted"], font=self.p.f_tiny, anchor="w",
                        cursor="hand2")
        head.pack(fill="x", pady=(10, 3))
        f = tk.Frame(box, bg=C["bg"])

        def show():
            shut = key in collapsed
            head.config(text=("▸ " if shut else "▾ ") + title)
            if shut:
                f.pack_forget()
            else:
                f.pack(fill="x")

        def toggle(e=None):
            if key in collapsed:
                collapsed.remove(key)
            else:
                collapsed.append(key)
            self.p.save()
            show()

        head.bind("<Button-1>", toggle)
        head.bind("<Enter>", lambda e: head.config(fg=C["fg"]))
        head.bind("<Leave>", lambda e: head.config(fg=C["muted"]))
        show()
        return f

    def _relayout(self):
        if self._relayout_after is None:
            self._relayout_after = self.win.after_idle(self._do_relayout)

    def _do_relayout(self):
        self._relayout_after = None
        try:
            self.area.layout(True, 0)
        except tk.TclError:
            pass

    def chip(self, parent, text, selected, color, cmd, side="left"):
        bg = mix(C["card"], color, 0.45) if selected else C["card"]
        lbl = tk.Label(parent, text=text, bg=bg, fg=C["fg"] if selected else C["muted"],
                       font=self.p.f_small, padx=8, pady=3, cursor="hand2")
        lbl.pack(side=side, padx=(0, 4), pady=1)
        lbl.bind("<Button-1>", lambda e: cmd())
        if not selected:
            lbl.bind("<Enter>", lambda e: lbl.config(bg=C["hover"]))
            lbl.bind("<Leave>", lambda e: lbl.config(bg=bg))
        return lbl

    @staticmethod
    def clear(frame):
        for ch in frame.winfo_children():
            ch.destroy()

    def task(self):
        return self.p.find_task(self.tid)

    # --- отрисовка ---
    def refresh(self):
        t = self.task()
        if not t:
            self.close(save=False)
            return
        p = self.p
        self.win.title(f"Задача: {short(t['text'], 40)}")
        if self.win.focus_get() is not self.title_e and self.title_e.get() != t["text"]:
            self.title_e.delete(0, "end")
            self.title_e.insert(0, t["text"])

        self.clear(self.status)
        self.chip(self.status, "✔ Выполнена" if t["done"] else "☐ Не выполнена", t["done"],
                  C["ok"], lambda: p.toggle_task(self.tid))
        note = p.carried_note(t)
        if note and not t["done"]:
            tk.Label(self.status, text=note, bg=C["bg"], fg=C["warn"], font=p.f_italic).pack(
                side="left", padx=(6, 0))

        # когда
        self.clear(self.sec_when)
        d = dt.date.fromisoformat(t["date"])
        tk.Label(self.sec_when, text=date_title(d, p.today), bg=C["bg"], fg=C["fg"],
                 font=p.f_norm, anchor="w").pack(fill="x")
        row = tk.Frame(self.sec_when, bg=C["bg"])
        row.pack(fill="x", pady=(3, 0))
        monday = p.today + dt.timedelta(days=7 - p.today.weekday())
        for label, day in (("Сегодня", p.today), ("Завтра", p.today + dt.timedelta(days=1)),
                           ("Пн", monday), ("+неделя", d + dt.timedelta(days=7))):
            self.chip(row, label, day == d, C["accent"], lambda x=day: p.move_task_date(self.tid, x))
        self.chip(row, "Дата…", False, C["accent"], lambda: p.ask_date(self.tid))
        row2 = tk.Frame(self.sec_when, bg=C["bg"])
        row2.pack(fill="x", pady=(3, 0))
        self.chip(row2, f"Время: {t['time']}" if t.get("time") else "Время…", bool(t.get("time")),
                  C["accent"], lambda: p.ask_time(self.tid))
        r = p.find_rec(t.get("rec"))
        rule = r["rule"] if r else None
        wd = d.weekday()
        for label, value in (("Без повтора", None), ("Каждый день", "daily"),
                             ("По будням", "weekdays"), (f"Каждую неделю", f"w{wd}")):
            self.chip(row2, label, rule == value, C["rest"],
                      lambda v=value: p.set_repeat(self.tid, v))
        if rule and rule not in BASIC_RULES and rule != f"w{wd}":
            row2b = tk.Frame(self.sec_when, bg=C["bg"])
            row2b.pack(fill="x", pady=(3, 0))
            self.chip(row2b, "↻ " + rule_text(rule), True, C["rest"], lambda: p.ask_repeat(self.tid))
        else:
            self.chip(row2, "Другое…", False, C["rest"], lambda: p.ask_repeat(self.tid))
        row3 = tk.Frame(self.sec_when, bg=C["bg"])
        row3.pack(fill="x", pady=(3, 0))
        if t.get("deadline"):
            dl = dt.date.fromisoformat(t["deadline"])
            text, color = deadline_badge(t, p.today)
            self.chip(row3, f"⚑ Дедлайн: {WD_SHORT[dl.weekday()].lower()}, {dl.day} "
                            f"{MONTHS_GEN[dl.month - 1]}", True, color, lambda: p.ask_deadline(self.tid))
            tk.Label(row3, text=text.replace("⚑ ", ""), bg=C["bg"], fg=color,
                     font=p.f_tiny).pack(side="left", padx=(2, 6))
            self.chip(row3, "Убрать", False, C["danger"], lambda: p.set_deadline(self.tid, None))
        else:
            self.chip(row3, "⚑ Дедлайн…", False, C["danger"], lambda: p.ask_deadline(self.tid))
        row4 = tk.Frame(self.sec_when, bg=C["bg"])
        row4.pack(fill="x", pady=(3, 0))
        tk.Label(row4, text="Оценка:", bg=C["bg"], fg=C["muted"], font=p.f_small).pack(
            side="left", padx=(0, 4))
        est = t.get("est")
        presets = ((None, "—"), (15, "15 мин"), (30, "30 мин"), (60, "1 ч"), (120, "2 ч"), (240, "4 ч"))
        for mins, label in presets:
            self.chip(row4, label, est == mins, C["accent"], lambda m=mins: p.set_est(self.tid, m))
        if est and est not in dict(presets):
            self.chip(row4, fmt_est(est), True, C["accent"], lambda: p.ask_est(self.tid))
        self.chip(row4, "Другое…", False, C["accent"], lambda: p.ask_est(self.tid))

        # приоритет
        self.clear(self.sec_prio)
        for value, name, color in PRIORITIES:
            self.chip(self.sec_prio, name, t.get("priority") == value, color,
                      lambda v=value: p.set_field(self.tid, "priority", v))

        # матрица Эйзенхауэра 2×2
        self.clear(self.sec_eis)
        grid = tk.Frame(self.sec_eis, bg=C["bg"])
        grid.pack(anchor="w")
        for col, text in ((1, "Срочно"), (2, "Не срочно")):
            tk.Label(grid, text=text, bg=C["bg"], fg=C["muted"], font=p.f_tiny).grid(
                row=0, column=col, pady=(0, 2))
        for rw, text in ((1, "Важно"), (2, "Не\nважно")):
            tk.Label(grid, text=text, bg=C["bg"], fg=C["muted"], font=p.f_tiny,
                     justify="right").grid(row=rw, column=0, padx=(0, 6), sticky="e")
        for q, rw, col in (("q1", 1, 1), ("q2", 1, 2), ("q3", 2, 1), ("q4", 2, 2)):
            name, desc, color = EIS[q]
            sel = t.get("eis") == q
            cell = tk.Label(grid, text=f"{name}\n{desc}", bg=mix(C["card"], color, 0.55 if sel else 0.12),
                            fg=C["fg"] if sel else C["muted"], font=p.f_small, width=20, height=3,
                            cursor="hand2", relief="flat")
            cell.grid(row=rw, column=col, padx=2, pady=2, sticky="nsew")
            cell.bind("<Button-1>", lambda e, q=q, s=sel: p.set_field(self.tid, "eis", None if s else q))
        hint = "Щёлкните квадрант. Повторный щелчок снимает отметку." if not t.get("eis") else \
            f"Сейчас: {EIS[t['eis']][0].lower()} ({EIS[t['eis']][1]})"
        tk.Label(self.sec_eis, text=hint, bg=C["bg"], fg=C["faint"], font=p.f_tiny,
                 anchor="w").pack(fill="x", pady=(2, 0))

        # метки
        self.clear(self.sec_tags)
        if t.get("tags"):
            trow = tk.Frame(self.sec_tags, bg=C["bg"])
            trow.pack(fill="x")
            for tg in t["tags"]:
                self.chip(trow, f"#{tg}  ✕", True, tag_color(tg), lambda g=tg: p.remove_tag(self.tid, g))
        te = p.make_entry(self.sec_tags, "#метка и Enter (можно несколько)", font=p.f_small,
                          bg=C["card"], on_enter=lambda e: self.add_tag(e))
        te.pack(fill="x", pady=(3, 0), ipady=2)
        if self._tag_focus:
            self._tag_focus = False
            te.focus_set()

        # цель недели
        self.clear(self.sec_goal)
        goals = p.week_goals(dt.date.fromisoformat(t["date"]))
        if goals:
            grow = tk.Frame(self.sec_goal, bg=C["bg"])
            grow.pack(fill="x")
            self.chip(grow, "Нет", not t.get("goal"), C["rest"], lambda: p.set_field(self.tid, "goal", None))
            for g in goals:
                self.chip(grow, "○ " + short(g["text"], 18), t.get("goal") == g["id"], C["rest"],
                          lambda x=g["id"]: p.set_field(self.tid, "goal", x))
        else:
            tk.Label(self.sec_goal, text="На эту неделю целей нет — их задают в блоке «Цели недели»",
                     bg=C["bg"], fg=C["faint"], font=p.f_tiny, anchor="w").pack(fill="x")

        # история
        self.clear(self.sec_hist)
        created = t.get("created")
        self.hist_line(f"Создана: {created[8:10]}.{created[5:7]}.{created[:4]} {created[11:16]}"
                       if created else "Создана: до появления истории", C["muted"])
        moves, carries = t.get("moves", 0), t.get("carries", 0)
        total = moves + carries
        if total:
            text = (f"Переносилась {plural(total, 'раз', 'раза', 'раз')}: вручную {moves}, "
                    f"автоматически {carries}")
            if total >= 3:
                text += ". Может, разбить задачу или отказаться от неё?"
            self.hist_line(text, C["warn"] if total >= 3 else C["muted"])
        if t["done"] and t.get("done_at"):
            da = t["done_at"]
            self.hist_line(f"Выполнена: {da[8:10]}.{da[5:7]}.{da[:4]}", C["ok"])
        for at, what in list(reversed(t.get("log") or []))[:5]:
            self.hist_line(f"{at[8:10]}.{at[5:7]} {at[11:16]}  {what}", C["faint"])

        # помодоро
        self.clear(self.sec_pomo)
        self.pomo_lbl = None
        prow = tk.Frame(self.sec_pomo, bg=C["bg"])
        prow.pack(fill="x")
        if p.s.get("pomo_task") == self.tid:
            mode = {"work": "Фокус", "break": "Перерыв", "long": "Длинный перерыв"}[p.pomo_mode]
            self.pomo_lbl = tk.Label(prow, text="", bg=C["bg"],
                                     fg=C["accent"] if p.pomo_mode == "work" else C["rest"],
                                     font=p.f_title)
            self.pomo_lbl.pack(side="left", padx=(0, 8))
            self.pomo_mode_name = mode
            self.update_timer()
            self.chip(prow, "Пауза" if p.pomo_running else "▶ Продолжить", False, C["accent"],
                      p.pomo_toggle)
            self.chip(prow, "Сброс", False, C["accent"], p.pomo_reset)
            self.chip(prow, "Отвязать", False, C["accent"], lambda: p.link_pomo(None))
        else:
            self.chip(prow, "▶ Запустить помодоро", False, C["accent"],
                      lambda: p.link_pomo(self.tid))
            other = p.find_task(p.s.get("pomo_task"))
            if other:
                tk.Label(prow, text=f"сейчас идёт: {short(other['text'], 22)}", bg=C["bg"],
                         fg=C["faint"], font=p.f_tiny).pack(side="left")
        if t.get("pomos"):
            tk.Label(self.sec_pomo, text=f"Помидоров по задаче: {t['pomos']}", bg=C["bg"],
                     fg=C["muted"], font=p.f_tiny, anchor="w").pack(fill="x", pady=(2, 0))
        spent, est = t.get("spent"), t.get("est")
        if spent:
            text = f"По факту: {fmt_est(spent)}" + (f" из оценки {fmt_est(est)}" if est else "")
            tk.Label(self.sec_pomo, text=text, bg=C["bg"],
                     fg=C["warn"] if est and spent > est else C["muted"], font=p.f_tiny,
                     anchor="w").pack(fill="x")
        ratio = p.est_ratio()
        if est and ratio and abs(ratio - 1) > 0.15:
            k = f"{ratio:.1f}".replace(".", ",")
            tk.Label(self.sec_pomo, text=f"С поправкой на ваш опыт (×{k}) ≈ {fmt_est(round(est * ratio))}",
                     bg=C["bg"], fg=C["faint"], font=p.f_tiny, anchor="w").pack(fill="x")

        # подзадачи
        self.clear(self.sec_subs)
        for sub in t.get("subs") or []:
            sr = tk.Frame(self.sec_subs, bg=C["bg"])
            sr.pack(fill="x")
            box = tk.Label(sr, text="✔" if sub["done"] else "☐", bg=C["bg"],
                           fg=C["ok"] if sub["done"] else C["muted"], font=p.f_small, width=2,
                           cursor="hand2")
            box.pack(side="left")
            txt = tk.Label(sr, text=sub["text"], bg=C["bg"], fg=C["muted"] if sub["done"] else C["fg"],
                           font=p.f_small, anchor="w", justify="left", cursor="hand2",
                           wraplength=int(260 * p.scale()))
            txt.pack(side="left", fill="x", expand=True)
            autowrap(txt)
            dl = tk.Label(sr, text="✕", bg=C["bg"], fg=C["faint"], font=p.f_tiny, cursor="hand2")
            dl.pack(side="right")
            for wdg in (box, txt):
                wdg.bind("<Button-1>", lambda e, sid=sub["id"]: p.toggle_sub(self.tid, sid))
            dl.bind("<Button-1>", lambda e, sid=sub["id"]: p.delete_sub(self.tid, sid))
        se = p.make_entry(self.sec_subs, "Подзадача и Enter", font=p.f_small, bg=C["card"],
                          on_enter=lambda e: self.add_sub(e),
                          on_paste=lambda lines: self.add_subs(lines))
        se.pack(fill="x", pady=(3, 0), ipady=2)
        if self._sub_focus:
            self._sub_focus = False
            se.focus_set()

    def hist_line(self, text, color):
        tk.Label(self.sec_hist, text=text, bg=C["bg"], fg=color, font=self.p.f_tiny, anchor="w",
                 justify="left", wraplength=int(330 * self.p.scale())).pack(fill="x")

    def add_tag(self, e):
        raw = e.get().replace(",", " ").split()
        tags = [x.lstrip("#").lower() for x in raw if x.lstrip("#")]
        if tags:
            self._tag_focus = True
            self.p.add_tags(self.tid, tags)
        return "break"

    def update_timer(self):
        if self.pomo_lbl is not None and self.pomo_lbl.winfo_exists():
            self.pomo_lbl.config(text=f"{self.pomo_mode_name}  {self.p.pomo_clock()}")

    # --- действия ---
    def save_title(self):
        t = self.task()
        text = self.title_e.get().strip()
        if not t or not text or text == t["text"]:
            return
        text, ex = parse_extras(text, self.p.today)
        self.p.apply_extras(t, ex, replace=False)
        t["text"] = text or t["text"]
        r = self.p.find_rec(t.get("rec"))
        if r:
            r["text"] = t["text"]
        self.title_e.delete(0, "end")
        self.title_e.insert(0, t["text"])
        self.p.after_tasks_changed()

    def add_sub(self, e):
        text = e.get().strip()
        if text:
            self.add_subs([text])
        return "break"

    def add_subs(self, lines):
        self._sub_focus = True
        self.p.add_subtask(self.tid, lines, open_in_list=False)

    def note_modified(self, e):
        if not self.note.edit_modified():
            return
        self.note.edit_modified(False)
        self.p.linkify(self.note)
        if self._note_after:
            self.p.root.after_cancel(self._note_after)
        self._note_after = self.p.root.after(700, self.save_note)

    def save_note(self):
        if self._note_after:  # вызвали напрямую — отложенное сохранение больше не нужно
            self.p.root.after_cancel(self._note_after)
        self._note_after = None
        t = self.task()
        if not t:
            return
        text = self.note.get("1.0", "end-1c")
        if text.strip():
            t["note"] = text
        else:
            t.pop("note", None)
        self.p.commit_undo()  # правка заметки — отдельный шаг отмены
        self.p.save()
        self.p.render_tasks()

    def delete(self):
        self.close()
        self.p.delete_task(self.tid)

    def close(self, save=True):
        pending = self._note_after
        if pending:  # отложенное сохранение не должно сработать после закрытия окна
            self.p.root.after_cancel(pending)
            self._note_after = None
        if save:
            if pending:
                self.save_note()
            self.save_title()
        self.p.cards.pop(self.tid, None)
        self.area.unregister()
        try:
            self.win.destroy()
        except tk.TclError:
            pass


class WeekView:
    """Семь колонок дней. compact — узкие колонки для панели, иначе для отдельного окна."""

    def __init__(self, panel, parent, compact):
        self.p, self.compact = panel, compact
        self.frame = tk.Frame(parent, bg=C["card"])

    def render(self, start):
        p = self.p
        for w in self.frame.winfo_children():
            w.destroy()
        nchars = 6 if self.compact else 60
        limit = 6 if self.compact else 60
        for i in range(7):
            self.frame.columnconfigure(i, weight=1, uniform="day")
            d = start + dt.timedelta(days=i)
            is_today = d == p.today
            col_bg = mix(C["card"], C["accent"], 0.10) if is_today else C["card"]
            col = tk.Frame(self.frame, bg=col_bg, padx=2, pady=2)
            col.grid(row=0, column=i, sticky="nsew", padx=1)
            col.drop_date = d
            kind, _ = p.day_info(d)
            hdr = tk.Label(col, text=f"{WD_SHORT[d.weekday()]}\n{d.day}", bg=col_bg,
                           fg=C["accent"] if is_today else (C["danger"] if kind == "off" else C["muted"]),
                           font=p.f_title if is_today else p.f_tiny, cursor="hand2")
            hdr.pack(fill="x")
            hdr.bind("<Button-1>", lambda e, day=d: p.show_day(day))
            items = p.tasks_for(d)
            items = [t for t in items if not t["done"]] + [t for t in items if t["done"]]
            est = sum(t.get("est") or 0 for t in items if not t["done"])
            if est and not self.compact:
                tk.Label(col, text=f"⏱ {fmt_est(est)}", bg=col_bg,
                         fg=C["danger"] if est > p.s["day_hours"] * 60 else C["faint"],
                         font=p.f_tiny).pack(fill="x")
            for t in items[:limit]:
                self.item(col, t, nchars)
            if len(items) > limit:
                tk.Label(col, text=f"+{len(items) - limit}", bg=col_bg, fg=C["muted"],
                         font=p.f_tiny).pack(fill="x")
            if not items:
                tk.Frame(col, height=int(18 * p.scale()), bg=col_bg).pack(fill="x")

    def item(self, col, t, nchars):
        p = self.p
        tid = t["id"]
        color = PRIO_COLOR.get(t.get("priority"))
        bg = C["bg"] if t["done"] else (mix(C["card"], color, 0.35) if color else C["selected"])
        text = ("✔ " if t["done"] else "") + (t["time"] + " " if t.get("time") and not self.compact else "")
        text += short(t["text"], nchars)
        lbl = tk.Label(col, text=text, bg=bg, fg=C["faint"] if t["done"] else C["fg"],
                       font=p.f_tiny if self.compact else p.f_small, anchor="w", justify="left",
                       wraplength=0 if self.compact else int(150 * p.scale()), padx=3, pady=1,
                       cursor="hand2")
        lbl.pack(fill="x", pady=1)
        if not self.compact:
            autowrap(lbl)
        lbl.bind("<ButtonPress-1>", lambda e: p.tdrag_press(e, tid, lambda: p.open_card(tid)))
        lbl.bind("<B1-Motion>", p.tdrag_motion)
        lbl.bind("<ButtonRelease-1>", p.tdrag_release)
        lbl.bind("<Button-3>", lambda e: p.task_menu(e, tid))
        if self.compact:
            lines = [(t["text"], C["fg"])]
            badge = deadline_badge(t, p.today)
            if badge:
                lines.append(badge)
            lbl.bind("<Enter>", lambda e: p.text_tip(lbl, lines))
            lbl.bind("<Leave>", lambda e: p.hide_tip())


class WeekWindow:
    def __init__(self, panel):
        self.p = panel
        p = panel
        self.start = p.today - dt.timedelta(days=p.today.weekday())
        w = self.win = tk.Toplevel(p.root)
        w.title("Неделя")
        w.configure(bg=C["bg"])
        w.protocol("WM_DELETE_WINDOW", self.close)
        w.bind("<Escape>", lambda e: self.close())
        if p.s["topmost"]:
            w.attributes("-topmost", True)
        top = tk.Frame(w, bg=C["bg"], padx=12, pady=8)
        top.pack(fill="x")
        p.button(top, "‹", lambda: self.shift(-7), bg=C["bg"], padx=8).pack(side="left")
        self.title = tk.Label(top, bg=C["bg"], fg=C["fg"], font=p.f_title)
        self.title.pack(side="left", padx=8)
        p.button(top, "›", lambda: self.shift(7), bg=C["bg"], padx=8).pack(side="left")
        p.button(top, "Эта неделя", lambda: self.shift(None), fg=C["accent"], bg=C["bg"]).pack(side="left")
        tk.Label(top, text="Перетаскивайте задачи между днями · клик — карточка задачи", bg=C["bg"],
                 fg=C["faint"], font=p.f_tiny).pack(side="right")
        body = tk.Frame(w, bg=C["card"], padx=6, pady=6)
        body.pack(fill="both", expand=True, padx=12, pady=(0, 12))
        self.view = WeekView(p, body, compact=False)
        self.view.frame.pack(fill="both", expand=True)
        p.live_views.append(self)
        self.refresh()
        sw = p.root.winfo_screenwidth()
        w.geometry(f"{min(int(1150 * p.scale()), sw - 80)}x{int(520 * p.scale())}+40+60")

    def shift(self, days):
        if days is None:
            self.start = self.p.today - dt.timedelta(days=self.p.today.weekday())
        else:
            self.start += dt.timedelta(days=days)
        self.refresh()

    def refresh(self):
        end = self.start + dt.timedelta(days=6)
        if self.start.month == end.month:
            text = f"{self.start.day} – {end.day} {MONTHS_GEN[end.month - 1]} {end.year}"
        else:
            text = (f"{self.start.day} {MONTHS_GEN[self.start.month - 1]} – "
                    f"{end.day} {MONTHS_GEN[end.month - 1]} {end.year}")
        self.title.config(text=text)
        self.view.render(self.start)

    def close(self):
        if self in self.p.live_views:
            self.p.live_views.remove(self)
        self.p.week_win = None
        self.win.destroy()


class MatrixWindow:
    SCOPES = {"today": "Сегодня", "week": "Неделя", "all": "Все незакрытые"}

    def __init__(self, panel):
        self.p = panel
        p = panel
        self.scope = "week"
        self.areas = {}
        w = self.win = tk.Toplevel(p.root)
        w.title("Матрица Эйзенхауэра")
        w.configure(bg=C["bg"])
        w.protocol("WM_DELETE_WINDOW", self.close)
        w.bind("<Escape>", lambda e: self.close())
        if p.s["topmost"]:
            w.attributes("-topmost", True)
        top = tk.Frame(w, bg=C["bg"], padx=12, pady=8)
        top.pack(fill="x")
        self.scope_row = tk.Frame(top, bg=C["bg"])
        self.scope_row.pack(side="left")
        tk.Label(top, text="Перетащите задачу в другой квадрант · клик — карточка", bg=C["bg"],
                 fg=C["faint"], font=p.f_tiny).pack(side="right")

        grid = tk.Frame(w, bg=C["bg"], padx=12)
        grid.pack(fill="both", expand=True)
        grid.columnconfigure(1, weight=1, uniform="q")
        grid.columnconfigure(2, weight=1, uniform="q")
        grid.rowconfigure(1, weight=1, uniform="q")
        grid.rowconfigure(2, weight=1, uniform="q")
        for col, text in ((1, "Срочно"), (2, "Не срочно")):
            tk.Label(grid, text=text, bg=C["bg"], fg=C["muted"], font=p.f_small).grid(row=0, column=col)
        for row, text in ((1, "Важно"), (2, "Не\nважно")):
            tk.Label(grid, text=text, bg=C["bg"], fg=C["muted"], font=p.f_small).grid(
                row=row, column=0, padx=(0, 6))
        for q, row, col in (("q1", 1, 1), ("q2", 1, 2), ("q3", 2, 1), ("q4", 2, 2)):
            outer = self.quadrant(grid, q, *EIS[q])
            outer.grid(row=row, column=col, sticky="nsew", padx=3, pady=3)
            self.areas[q] = self._last
        bottom = tk.Frame(w, bg=C["bg"], padx=12, pady=8)
        bottom.pack(fill="x")
        self.quadrant(bottom, "none", "Без отметки", "перетащите в нужный квадрант", C["faint"],
                      height=110).pack(fill="x")
        self.areas["none"] = self._last
        p.live_views.append(self)
        self.refresh()
        sw, sh = p.root.winfo_screenwidth(), p.root.winfo_screenheight()
        ww, wh = min(int(1000 * p.scale()), sw - 80), min(int(720 * p.scale()), sh - 100)
        w.geometry(f"{ww}x{wh}+{(sw - ww) // 2}+{(sh - wh) // 2}")

    def quadrant(self, parent, q, name, desc, color, height=None):
        p = self.p
        outer = tk.Frame(parent, bg=mix(C["card"], color, 0.6), padx=2, pady=2)
        outer.drop_eis = q
        inner = tk.Frame(outer, bg=C["card"], padx=8, pady=6)
        inner.pack(fill="both", expand=True)
        head = tk.Frame(inner, bg=C["card"])
        head.pack(fill="x")
        tk.Label(head, text=name, bg=C["card"], fg=color, font=p.f_title).pack(side="left")
        tk.Label(head, text=desc, bg=C["card"], fg=C["faint"], font=p.f_tiny).pack(side="left", padx=6)
        count = tk.Label(head, bg=C["card"], fg=C["muted"], font=p.f_small)
        count.pack(side="right")
        area = ScrollArea(p, inner)
        area.wrap.pack(fill="both", expand=True, pady=(4, 0))
        if height:
            area.canvas.config(height=height)
        area.count = count
        area.color = color
        self._last = area
        self._last_frame = outer
        return outer

    def tasks_in_scope(self):
        today = self.p.today
        out = []
        for t in self.p.data["tasks"]:
            if t["done"]:
                continue
            d = dt.date.fromisoformat(t["date"])
            if self.scope == "today" and d != today:
                continue
            if self.scope == "week" and not today <= d <= today + dt.timedelta(days=6):
                continue
            out.append(t)
        return sorted(out, key=lambda t: (t["date"], PRIO_RANK.get(t.get("priority"), 3)))

    def refresh(self):
        p = self.p
        for w in self.scope_row.winfo_children():
            w.destroy()
        for key, label in self.SCOPES.items():
            sel = key == self.scope
            lbl = tk.Label(self.scope_row, text=label, bg=mix(C["card"], C["accent"], 0.45) if sel else C["card"],
                           fg=C["fg"] if sel else C["muted"], font=p.f_small, padx=10, pady=3,
                           cursor="hand2")
            lbl.pack(side="left", padx=(0, 4))
            lbl.bind("<Button-1>", lambda e, k=key: self.set_scope(k))
        groups = {k: [] for k in self.areas}
        for t in self.tasks_in_scope():
            groups[t.get("eis") if t.get("eis") in EIS else "none"].append(t)
        for q, area in self.areas.items():
            for w in area.frame.winfo_children():
                w.destroy()
            area.count.config(text=str(len(groups[q])) if groups[q] else "")
            for t in groups[q][:MATRIX_MAX_ROWS]:
                self.item(area.frame, t)
            if len(groups[q]) > MATRIX_MAX_ROWS:
                tk.Label(area.frame, text=f"и ещё {len(groups[q]) - MATRIX_MAX_ROWS} — сузьте период",
                         bg=C["card"], fg=C["muted"], font=p.f_tiny, anchor="w").pack(fill="x")
            if not groups[q]:
                tk.Label(area.frame, text="пусто", bg=C["card"], fg=C["faint"], font=p.f_small,
                         anchor="w").pack(fill="x")
            area.layout(fill=q != "none", max_h=int(110 * p.scale()))

    def item(self, parent, t):
        p = self.p
        tid = t["id"]
        row = tk.Frame(parent, bg=C["card"])
        row.pack(fill="x", pady=1)
        tk.Frame(row, width=3, bg=PRIO_COLOR.get(t.get("priority"), C["card"])).pack(
            side="left", fill="y", padx=(0, 4))
        d = dt.date.fromisoformat(t["date"])
        when = "сегодня" if d == p.today else f"{WD_SHORT[d.weekday()].lower()} {short_date(d, p.today)}"
        tk.Label(row, text=when, bg=C["card"], fg=C["faint"], font=p.f_tiny, width=9,
                 anchor="w").pack(side="left")
        txt = tk.Label(row, text=(t["time"] + "  " if t.get("time") else "") + t["text"], bg=C["card"],
                       fg=C["fg"], font=p.f_small, anchor="w", justify="left", cursor="hand2",
                       wraplength=int(330 * p.scale()))
        txt.pack(side="left", fill="x", expand=True)
        autowrap(txt)
        badge = deadline_badge(t, p.today)
        if badge:
            tk.Label(row, text=badge[0], bg=C["card"], fg=badge[1], font=p.f_tiny).pack(side="right")
        txt.bind("<ButtonPress-1>", lambda e: p.tdrag_press(e, tid, lambda: p.open_card(tid)))
        txt.bind("<B1-Motion>", p.tdrag_motion)
        txt.bind("<ButtonRelease-1>", p.tdrag_release)
        p.bind_tree(row, "<Button-3>", lambda e: p.task_menu(e, tid))

    def set_scope(self, key):
        self.scope = key
        self.refresh()

    def close(self):
        for area in self.areas.values():
            area.unregister()
        if self in self.p.live_views:
            self.p.live_views.remove(self)
        self.p.matrix_win = None
        self.win.destroy()


class ReviewDialog:
    """Список задач с кнопками «сегодня / завтра / дата / удалить».
    keep(t) решает, осталась ли задача в списке после очередного действия."""

    def __init__(self, panel, title, hint, keep, order_key=None, keep_label=None):
        self.p, self.keep_fn, self.order_key, self.keep_label = panel, keep, order_key, keep_label
        self.kept = set()
        p = panel
        w = self.win = tk.Toplevel(p.root)
        w.title(title)
        w.configure(bg=C["bg"])
        w.attributes("-topmost", True)
        w.protocol("WM_DELETE_WINDOW", self.close)
        w.bind("<Escape>", lambda e: self.close())
        box = tk.Frame(w, bg=C["bg"], padx=16, pady=12)
        box.pack(fill="both", expand=True)
        tk.Label(box, text=title, bg=C["bg"], fg=C["fg"], font=p.f_title, anchor="w").pack(fill="x")
        self.hint = tk.Label(box, text=hint, bg=C["bg"], fg=C["muted"], font=p.f_small, anchor="w",
                             justify="left", wraplength=int(460 * p.scale()))
        self.hint.pack(fill="x", pady=(2, 8))
        self.area = ScrollArea(p, box)
        self.area.wrap.pack(fill="both", expand=True)
        foot = tk.Frame(box, bg=C["bg"])
        foot.pack(fill="x", pady=(10, 0))
        p.button(foot, "Готово", self.close, fg=C["accent"], bg=C["bg"]).pack(side="right")
        p.live_views.append(self)
        self.refresh()
        w.update_idletasks()
        ww = max(int(520 * p.scale()), w.winfo_reqwidth())
        sw, sh = p.root.winfo_screenwidth(), p.root.winfo_screenheight()
        w.geometry(f"{ww}x{min(int(520 * p.scale()), sh - 120)}+{(sw - ww) // 2}+{sh // 6}")

    def tasks(self):
        items = [t for t in self.p.data["tasks"] if self.keep_fn(t) and t["id"] not in self.kept]
        return sorted(items, key=self.order_key) if self.order_key else items

    def refresh(self):
        p = self.p
        for w in self.area.frame.winfo_children():
            w.destroy()
        items = self.tasks()
        if not items:
            tk.Label(self.area.frame, text="Всё разобрано ✔", bg=C["card"], fg=C["ok"],
                     font=p.f_norm).pack(pady=12)
            self.area.layout(fill=True, max_h=0)
            p.root.after(1200, self.close)
            return
        tomorrow = p.today + dt.timedelta(days=1)
        for t in items:
            tid = t["id"]
            row = tk.Frame(self.area.frame, bg=C["card"], padx=6, pady=4)
            row.pack(fill="x", pady=1)
            tk.Frame(row, width=3, bg=PRIO_COLOR.get(t.get("priority"), C["card"])).pack(
                side="left", fill="y", padx=(0, 6))
            col = tk.Frame(row, bg=C["card"])
            col.pack(side="left", fill="x", expand=True)
            tk.Label(col, text=t["text"], bg=C["card"], fg=C["fg"], font=p.f_norm, anchor="w",
                     justify="left", wraplength=int(250 * p.scale())).pack(fill="x")
            meta = []
            note = p.carried_note(t)
            if note:
                meta.append(note)
            if t.get("eis") in EIS:
                meta.append(EIS[t["eis"]][0])
            if t.get("est"):
                meta.append(fmt_est(t["est"]))
            badge = deadline_badge(t, p.today)
            if badge:
                meta.append(badge[0])
            if meta:
                tk.Label(col, text=" · ".join(meta), bg=C["card"], fg=C["muted"], font=p.f_tiny,
                         anchor="w", justify="left", wraplength=int(250 * p.scale())).pack(fill="x")
            btns = tk.Frame(row, bg=C["card"])
            btns.pack(side="right")
            if self.keep_label:
                p.button(btns, self.keep_label, lambda i=tid: self.keep(i), fg=C["ok"],
                         font=p.f_small, padx=5).pack(side="left")
            p.button(btns, "Завтра", lambda i=tid: p.move_task_date(i, tomorrow), fg=C["accent"],
                     font=p.f_small, padx=5).pack(side="left")
            p.button(btns, "Дата…", lambda i=tid: p.ask_date(i), fg=C["accent"],
                     font=p.f_small, padx=5).pack(side="left")
            p.button(btns, "Удалить", lambda i=tid: p.delete_task(i), fg=C["danger"],
                     font=p.f_small, padx=5).pack(side="left")
        self.area.layout(fill=True, max_h=0)

    def keep(self, tid):
        self.kept.add(tid)
        self.refresh()

    def close(self):
        if self in self.p.live_views:
            self.p.live_views.remove(self)
        self.area.unregister()
        try:
            self.win.destroy()
        except tk.TclError:
            pass


class SearchWindow:
    def __init__(self, panel):
        self.p = panel
        p = panel
        w = self.win = tk.Toplevel(p.root)
        w.title("Поиск задач")
        w.configure(bg=C["bg"])
        w.protocol("WM_DELETE_WINDOW", self.close)
        w.bind("<Escape>", lambda e: self.close())
        if p.s["topmost"]:
            w.attributes("-topmost", True)
        box = tk.Frame(w, bg=C["bg"], padx=14, pady=12)
        box.pack(fill="both", expand=True)
        self.entry = p.make_entry(box, "Что ищем? Текст, заметка, подзадача или #метка",
                                  on_enter=lambda e: self.open_first(), bg=C["card"])
        self.entry.pack(fill="x", ipady=5)
        self.entry.var.trace_add("write", lambda *a: self.refresh())
        self.status = tk.Label(box, bg=C["bg"], fg=C["muted"], font=p.f_tiny, anchor="w")
        self.status.pack(fill="x", pady=(4, 4))
        self.area = ScrollArea(p, box)
        self.area.wrap.pack(fill="both", expand=True)
        self.results = []
        p.live_views.append(self)
        self.refresh()
        x = max(0, p.root.winfo_rootx() - int(540 * p.scale()))
        w.geometry(f"{int(520 * p.scale())}x{int(560 * p.scale())}+{x}+{max(0, p.root.winfo_rooty())}")
        w.focus_force()
        self.entry.focus_set()

    @staticmethod
    def haystack(t):
        parts = [t["text"], t.get("note") or ""] + [s["text"] for s in t.get("subs") or []]
        parts += ["#" + g for g in t.get("tags") or []]
        return "\n".join(parts).lower()

    def refresh(self):
        p = self.p
        for w in self.area.frame.winfo_children():
            w.destroy()
        words = self.entry.get().lower().split()
        if not words:
            self.results = []
            self.status.config(text="Ищу по всем задачам: сегодняшним, будущим и выполненным за 30 дней")
            self.area.layout(fill=True, max_h=0)
            return
        found = [t for t in p.data["tasks"] if all(wd in self.haystack(t) for wd in words)]
        found.sort(key=lambda t: (t["done"], t["date"]))
        self.results = found
        self.status.config(text=f"Найдено: {len(found)}" + (" (показаны первые 100)" if len(found) > 100 else ""))
        for t in found[:100]:
            self.item(t, words)
        self.area.layout(fill=True, max_h=0)

    def item(self, t, words):
        p = self.p
        tid = t["id"]
        d = dt.date.fromisoformat(t["date"])
        row = tk.Frame(self.area.frame, bg=C["card"], padx=6, pady=3, cursor="hand2")
        row.pack(fill="x", pady=1)
        top = tk.Frame(row, bg=C["card"])
        top.pack(fill="x")
        tk.Label(top, text="✔" if t["done"] else "☐", bg=C["card"],
                 fg=C["ok"] if t["done"] else C["muted"], font=p.f_small).pack(side="left")
        when = "сегодня" if d == p.today else f"{WD_SHORT[d.weekday()].lower()} {short_date(d, p.today)}"
        tk.Label(top, text=when, bg=C["card"], fg=C["accent"] if d >= p.today else C["faint"],
                 font=p.f_tiny, width=10, anchor="w").pack(side="left", padx=(4, 0))
        found = tk.Label(top, text=t["text"], bg=C["card"], fg=C["muted"] if t["done"] else C["fg"],
                         font=p.f_small, anchor="w", justify="left", wraplength=int(360 * p.scale()))
        found.pack(side="left", fill="x", expand=True)
        autowrap(found)
        note = t.get("note") or ""
        low = note.lower()
        pos = min((low.find(wd) for wd in words if wd in low), default=-1)
        if pos >= 0:
            start = max(0, pos - 25)
            snippet = ("…" if start else "") + note[start:start + 80].replace("\n", " ") + "…"
            tk.Label(row, text="✎ " + snippet, bg=C["card"], fg=C["faint"], font=p.f_tiny,
                     anchor="w", justify="left", wraplength=int(440 * p.scale())).pack(fill="x")
        p.bind_tree(row, "<Button-1>", lambda e: self.go(tid))

    def go(self, tid):
        t = self.p.find_task(tid)
        if t:
            self.p.show_day(dt.date.fromisoformat(t["date"]))
            self.p.open_card(tid)

    def open_first(self):
        if self.results:
            self.go(self.results[0]["id"])

    def close(self):
        if self in self.p.live_views:
            self.p.live_views.remove(self)
        self.area.unregister()
        self.p.search_win = None
        self.win.destroy()


class WeeklyReview:
    def __init__(self, panel):
        self.p = p = panel
        self.start = p.today - dt.timedelta(days=p.today.weekday())
        end = self.start + dt.timedelta(days=6)
        s_iso, e_iso, today_iso = self.start.isoformat(), end.isoformat(), p.today.isoformat()
        w = self.win = tk.Toplevel(p.root)
        w.title("Обзор недели")
        w.configure(bg=C["bg"])
        w.protocol("WM_DELETE_WINDOW", self.close)
        w.bind("<Escape>", lambda e: self.close())
        if p.s["topmost"]:
            w.attributes("-topmost", True)
        box = self.box = tk.Frame(w, bg=C["bg"], padx=18, pady=14)
        box.pack(fill="both", expand=True)
        span = (f"{self.start.day} – {end.day} {MONTHS_GEN[end.month - 1]}" if self.start.month == end.month
                else f"{self.start.day} {MONTHS_GEN[self.start.month - 1]} – {end.day} {MONTHS_GEN[end.month - 1]}")
        tk.Label(box, text=f"Обзор недели · {span}", bg=C["bg"], fg=C["fg"], font=p.f_title,
                 anchor="w").pack(fill="x")

        tasks = p.data["tasks"]
        done = [t for t in tasks if t["done"] and s_iso <= (t.get("done_at") or "") <= e_iso]
        by_day = [sum(1 for t in done if t["done_at"] == (self.start + dt.timedelta(days=i)).isoformat())
                  for i in range(7)]
        self.header("Сделано")
        self.line(f"Выполнено задач: {len(done)}", C["ok"] if done else C["muted"], p.f_norm)
        self.line("  ".join(f"{WD_SHORT[i].lower()} {n}" for i, n in enumerate(by_day)), C["faint"])
        still_open = [t for t in tasks if not t["done"] and s_iso <= t["date"] <= today_iso]
        if still_open:
            self.line(f"Не закрыто из запланированного: {len(still_open)}", C["warn"])

        moves = sum(1 for t in tasks for at, what in t.get("log") or []
                    if s_iso <= at[:10] <= e_iso and "перенесена" in what)
        chronic = sorted((t for t in tasks if not t["done"] and t.get("moves", 0) + t.get("carries", 0) >= 3),
                         key=lambda t: -(t.get("moves", 0) + t.get("carries", 0)))[:5]
        self.header("Переносы")
        self.line(f"Переносов за неделю: {moves}", C["muted"])
        if chronic:
            self.line("Часто переносятся — разбить, делегировать или отказаться?", C["warn"])
            for t in chronic:
                n = t.get("moves", 0) + t.get("carries", 0)
                self.line(f"  ↷ {n}  {short(t['text'], 50)}", C["fg"], click=lambda i=t["id"]: p.open_card(i))

        days = [(self.start + dt.timedelta(days=i)).isoformat() for i in range(7)]
        pomos = sum(p.data["pomodoros"].get(d, 0) for d in days)
        logs = [x for x in p.data["pomo_log"] if s_iso <= x["date"] <= e_iso]
        minutes = sum(x.get("min", p.s["work"]) for x in logs)
        self.header("Фокус")
        self.line(f"Помидоров: {pomos}" + (f" · {fmt_est(minutes)} работы" if minutes else ""), C["accent"])
        by_tag = {}
        for x in logs:
            for g in x.get("tags") or ["без метки"]:
                by_tag[g] = by_tag.get(g, 0) + x.get("min", p.s["work"])
        for g, m in sorted(by_tag.items(), key=lambda kv: -kv[1])[:5]:
            name = g if g == "без метки" else "#" + g
            self.line(f"  {name}: {fmt_est(m)}", tag_color(g) if g != "без метки" else C["muted"])

        self.goals = p.week_goals()
        self.header("Цели недели")
        if self.goals:
            for g in self.goals:
                dn, tot = p.goal_progress(g["id"])
                mark = "✔" if g["done"] else "○"
                self.line(f"{mark} {short(g['text'], 40)}" + (f"  · задач {dn}/{tot}" if tot else ""),
                          C["ok"] if g["done"] else C["fg"])
        else:
            self.line("Целей на неделю не было", C["faint"])

        ratio = p.est_ratio()
        self.header("Оценки времени")
        if ratio is None:
            self.line("Мало данных: нужны хотя бы 3 выполненные задачи с оценкой и помидорами", C["faint"])
        elif abs(ratio - 1) <= 0.15:
            self.line("Оценки точные — фактическое время в пределах ±15%", C["ok"])
        else:
            k = f"{ratio:.1f}".replace(".", ",")
            more = "больше" if ratio > 1 else "меньше"
            self.line(f"Задачи занимают в среднем в {k} раза {more} оценки", C["warn"])

        btns = tk.Frame(box, bg=C["bg"])
        btns.pack(fill="x", pady=(14, 0))
        p.button(btns, "Спланировать следующую неделю", self.plan_next, fg=C["accent"],
                 bg=C["bg"]).pack(side="left")
        undone = [g for g in self.goals if not g["done"]]
        if undone:
            p.button(btns, f"Перенести незавершённые цели ({len(undone)})", self.carry_goals,
                     fg=C["muted"], bg=C["bg"]).pack(side="left", padx=(8, 0))
        p.button(btns, "Закрыть", self.close, fg=C["muted"], bg=C["bg"]).pack(side="right")
        w.update_idletasks()
        sw, sh = p.root.winfo_screenwidth(), p.root.winfo_screenheight()
        ww = max(w.winfo_reqwidth(), int(480 * p.scale()))
        w.geometry(f"{ww}x{min(w.winfo_reqheight(), sh - 100)}+{(sw - ww) // 2}+{max(20, sh // 8)}")

    def header(self, text):
        tk.Label(self.box, text=text, bg=C["bg"], fg=C["muted"], font=self.p.f_tiny,
                 anchor="w").pack(fill="x", pady=(10, 2))

    def line(self, text, color, font=None, click=None):
        lbl = tk.Label(self.box, text=text, bg=C["bg"], fg=color, font=font or self.p.f_small,
                       anchor="w", justify="left", wraplength=int(520 * self.p.scale()))
        lbl.pack(fill="x")
        if click:
            lbl.config(cursor="hand2")
            lbl.bind("<Button-1>", lambda e: click())

    def plan_next(self):
        self.close()
        self.p.open_week_window()
        self.p.week_win.start = self.start + dt.timedelta(days=7)
        self.p.week_win.refresh()

    def carry_goals(self):
        self.p.move_goals(self.goals, self.start + dt.timedelta(days=7))
        self.close()

    def close(self):
        self.p.review_win = None
        try:
            self.win.destroy()
        except tk.TclError:
            pass
