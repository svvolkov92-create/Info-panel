# -*- coding: utf-8 -*-
"""Планирование: цели недели, будущие задачи, неделя, матрица, поиск, обзор недели, шаблоны, карточки задач.
Примесь к классу Panel: методы работают с его состоянием (self)."""
from .core import *  # noqa: F401,F403 — общие константы и функции
from .widgets import ScrollArea  # noqa: F401
from .windows import (MatrixWindow, ReviewDialog, SearchWindow, TaskCard,  # noqa: F401
                      WeeklyReview, WeekView, WeekWindow)


class PlanningMixin:
    # ===================== цели недели =====================
    def build_goals(self):
        head, body = self.section("goals")
        self.title_label(head, "goals", "Цели недели")
        self.lbl_goals_count = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_small)
        self.lbl_goals_count.pack(side="right")
        self.goal_entry = self.make_entry(body, f"Цель недели и Enter (до {GOALS_LIMIT})",
                                          on_enter=lambda e: self.add_goal())
        self.goal_entry.pack(fill="x", pady=(6, 4), ipady=3)
        self.goals_frame = tk.Frame(body, bg=C["card"])
        self.goals_frame.pack(fill="x")

    def week_goals(self, d=None, create=False):
        key = week_key(d or self.today)
        if create:
            return self.data["goals"].setdefault(key, [])
        return self.data["goals"].get(key, [])

    def find_goal(self, gid):
        if not gid:
            return None
        for goals in self.data["goals"].values():
            for g in goals:
                if g["id"] == gid:
                    return g
        return None

    def goal_progress(self, gid):
        linked = [t for t in self.data["tasks"] if t.get("goal") == gid]
        return sum(1 for t in linked if t["done"]), len(linked)

    def add_goal(self):
        text = self.goal_entry.get().strip()
        if not text:
            return
        goals = self.week_goals(create=True)
        if len(goals) >= GOALS_LIMIT:
            self.lbl_goals_count.config(text=f"не больше {GOALS_LIMIT}", fg=C["warn"])
            self.root.after(2500, self.render_goals)
            return
        goals.append({"id": uuid.uuid4().hex, "text": text, "done": False})
        self.goal_entry.delete(0, "end")
        self.after_tasks_changed(calendar=False)

    def toggle_goal(self, gid):
        g = self.find_goal(gid)
        if g:
            g["done"] = not g["done"]
            self.after_tasks_changed(calendar=False)

    def delete_goal(self, gid):
        for goals in self.data["goals"].values():
            goals[:] = [g for g in goals if g["id"] != gid]
        for t in self.data["tasks"]:
            if t.get("goal") == gid:
                t.pop("goal")
        self.after_tasks_changed(calendar=False)

    def rename_goal(self, gid):
        g = self.find_goal(gid)
        if not g:
            return

        def ok(vals):
            if not vals[0]:
                return "Название не может быть пустым"
            g["text"] = vals[0]
            self.after_tasks_changed(calendar=False)
            return None

        self.input_dialog("Цель недели", "Новое название цели.", [("Цель", g["text"])], ok)

    def move_goals(self, goals, to_day):
        """Переносит цели (вместе с привязкой задач) на неделю, где лежит to_day."""
        ids = {g["id"] for g in goals}
        moving = [g for lst in self.data["goals"].values() for g in lst if g["id"] in ids]
        for lst in self.data["goals"].values():
            lst[:] = [g for g in lst if g["id"] not in ids]
        self.week_goals(to_day, create=True).extend(moving)
        for k in [k for k, v in self.data["goals"].items() if not v]:
            del self.data["goals"][k]
        self.after_tasks_changed(calendar=False)

    def carry_goals(self):
        prev = [g for g in self.week_goals(self.today - dt.timedelta(days=7)) if not g["done"]]
        if prev:
            self.move_goals(prev, self.today)

    def goal_menu(self, e, gid):
        m = tk.Menu(self.root, tearoff=0)
        m.add_command(label="Показать задачи этой цели", command=lambda: self.set_filter("goal:" + gid))
        m.add_command(label="Переименовать…", command=lambda: self.rename_goal(gid))
        m.add_command(label="Перенести на следующую неделю",
                      command=lambda: self.move_goals([self.find_goal(gid)], self.today + dt.timedelta(days=7)))
        m.add_separator()
        m.add_command(label="Удалить цель", command=lambda: self.delete_goal(gid))
        self.popup(m, e)
        return "break"

    def render_goals(self):
        for w in self.goals_frame.winfo_children():
            w.destroy()
        goals = self.week_goals()
        done = sum(1 for g in goals if g["done"])
        self.lbl_goals_count.config(text=f"{done}/{len(goals)}" if goals else "", fg=C["muted"])
        for g in goals:
            gid = g["id"]
            row = tk.Frame(self.goals_frame, bg=C["card"])
            row.pack(fill="x", pady=1)
            box = tk.Label(row, text="✔" if g["done"] else "○", bg=C["card"],
                           fg=C["ok"] if g["done"] else C["rest"], font=self.f_norm, width=2, cursor="hand2")
            box.pack(side="left", anchor="n")
            box.bind("<Button-1>", lambda e, i=gid: self.toggle_goal(i))
            dn, tot = self.goal_progress(gid)
            if tot:
                bar = tk.Canvas(row, width=int(44 * self.scale()), height=5, bg=C["faint"],
                                highlightthickness=0)
                bar.pack(side="right", padx=(4, 0), pady=(7, 0), anchor="n")
                bar.create_rectangle(0, 0, int(44 * self.scale()) * dn / tot, 5, fill=C["ok"], width=0)
                tk.Label(row, text=f"{dn}/{tot}", bg=C["card"], fg=C["muted"], font=self.f_tiny).pack(
                    side="right", anchor="n")
            txt = tk.Label(row, text=g["text"], bg=C["card"], fg=C["muted"] if g["done"] else C["fg"],
                           font=self.f_small, anchor="w", justify="left", cursor="hand2",
                           wraplength=self.text_wrap() - 30)
            txt.pack(side="left", fill="x", expand=True)
            autowrap(txt)
            txt.bind("<Button-1>", lambda e, i=gid: self.set_filter("goal:" + i))
            self.bind_tree(row, "<Button-3>", lambda e, i=gid: self.goal_menu(e, i))
        if not goals:
            prev = [g for g in self.week_goals(self.today - dt.timedelta(days=7)) if not g["done"]]
            if prev:
                self.button(self.goals_frame, f"Перенести с прошлой недели: {len(prev)}", self.carry_goals,
                            fg=C["accent"], font=self.f_small, padx=0).pack(anchor="w")
            else:
                tk.Label(self.goals_frame, text="3–5 главных результатов недели. Задачи привязываются "
                                                "к целям в карточке.", bg=C["card"], fg=C["faint"],
                         font=self.f_tiny, anchor="w", justify="left",
                         wraplength=self.text_wrap()).pack(fill="x")

    # ===================== время по факту =====================
    def est_ratio(self):
        """Во сколько раз факт (по помидорам) больше оценки — по выполненным задачам, если их ≥ 3."""
        pairs = [(t["spent"], t["est"]) for t in self.data["tasks"]
                 if t["done"] and t.get("est") and t.get("spent")]
        if len(pairs) < 3:
            return None
        return sum(a for a, _ in pairs) / sum(b for _, b in pairs)

    # ===================== обзор недели =====================
    def open_weekly_review(self):
        if self.review_win:
            self.review_win.win.lift()
            return
        self.review_win = WeeklyReview(self)

    def maybe_weekly_review(self, now):
        """По пятницам после 15:00 — один раз за неделю."""
        if not self.s.get("weekly_review", True) or now.weekday() != 4 or now.hour < 15:
            return
        wk = week_key(self.today)
        if self.s.get("review_week") == wk:
            return
        self.s["review_week"] = wk
        self.save()
        self.open_weekly_review()

    # ===================== шаблоны =====================
    @staticmethod
    def template_item(t, base):
        item = {"text": t["text"], "offset": (dt.date.fromisoformat(t["date"]) - base).days}
        for k in ("priority", "eis", "est", "time"):
            if t.get(k):
                item[k] = t[k]
        if t.get("tags"):
            item["tags"] = list(t["tags"])
        if t.get("subs"):
            item["subs"] = [s["text"] for s in t["subs"]]
        return item

    def add_template(self, name, items):
        self.data["templates"].append({"id": uuid.uuid4().hex, "name": name, "items": items})
        self.save()
        self.flash_status(f"шаблон «{short(name, 20)}» сохранён", C["ok"])

    def ask_template_name(self, default, items):
        def ok(vals):
            if not vals[0]:
                return "Введите название"
            self.add_template(vals[0], items)
            return None

        self.input_dialog("Новый шаблон", f"Задач в шаблоне: {len(items)}.\nКак его назвать?",
                          [("Название", default)], ok, "Сохранить")

    def save_task_template(self, tid):
        t = self.find_task(tid)
        if t:
            item = self.template_item(t, dt.date.fromisoformat(t["date"]))
            self.ask_template_name(short(t["text"], 30), [item])

    def save_day_template(self):
        items = [self.template_item(t, self.selected) for t in self.tasks_for(self.selected)]
        if not items:
            self.flash_status("В выбранном дне нет задач", C["muted"])
            return
        self.ask_template_name(f"День {WD_SHORT[self.selected.weekday()].lower()}", items)

    def apply_template(self, tpl_id):
        tpl = next((x for x in self.data["templates"] if x["id"] == tpl_id), None)
        if not tpl:
            return
        for item in tpl["items"]:
            day = max(self.today, self.selected + dt.timedelta(days=item.get("offset", 0)))
            t = {"id": uuid.uuid4().hex, "text": item["text"], "date": day.isoformat(), "done": False,
                 "created": now_str()}
            for k in ("priority", "eis", "est", "time"):
                if item.get(k):
                    t[k] = item[k]
            if item.get("tags"):
                t["tags"] = list(item["tags"])
            if item.get("subs"):
                t["subs"] = [{"id": uuid.uuid4().hex, "text": x, "done": False} for x in item["subs"]]
            self.add_log(t, f"из шаблона «{tpl['name']}»")
            self.data["tasks"].append(t)
        self.after_tasks_changed()
        self.flash_status(f"из шаблона: {len(tpl['items'])}", C["ok"])

    def delete_template(self, tpl_id):
        self.data["templates"] = [x for x in self.data["templates"] if x["id"] != tpl_id]
        self.save()

    def fill_template_menu(self):
        m = self.tpl_menu
        m.delete(0, "end")
        for sub in m.winfo_children():  # подменю прошлого раза
            sub.destroy()
        tpls = self.data["templates"]
        day = f"{self.selected.day} {MONTHS_GEN[self.selected.month - 1]}"
        if tpls:
            for tpl in tpls:
                m.add_command(label=f"Добавить на {day}: {tpl['name']} ({len(tpl['items'])})",
                              command=lambda x=tpl["id"]: self.apply_template(x))
        else:
            m.add_command(label="Шаблонов пока нет", state="disabled")
        m.add_separator()
        m.add_command(label="Сохранить выбранный день как шаблон…", command=self.save_day_template)
        if tpls:
            dm = tk.Menu(m, tearoff=0)
            for tpl in tpls:
                dm.add_command(label=tpl["name"], command=lambda x=tpl["id"]: self.delete_template(x))
            m.add_cascade(label="Удалить шаблон", menu=dm)

    # ===================== неделя, матрица, поиск =====================
    def build_week(self):
        head, body = self.section("week")
        self.title_label(head, "week", "Неделя")
        self.button(head, "⤢", self.open_week_window, fg=C["muted"], font=self.f_small,
                    padx=4).pack(side="right")
        self.week_view = WeekView(self, body, compact=True)
        self.week_view.frame.pack(fill="both", expand=True, pady=(6, 0))

    def render_week(self):
        last = (self.today + dt.timedelta(days=6)).isoformat()
        today = self.today.isoformat()
        sig = (today, self.s["day_hours"],
               tuple((t["id"], t["date"], t["text"], t["done"], t.get("priority"), t.get("time"), t.get("est"))
                     for t in self.data["tasks"] if today <= t["date"] <= last))
        if self.unchanged("week", sig):
            return
        self.week_view.render(self.today)

    def open_week_window(self):
        if self.week_win:
            self.week_win.win.lift()
            return
        self.week_win = WeekWindow(self)

    def open_matrix(self):
        if self.matrix_win:
            self.matrix_win.win.lift()
            return
        self.matrix_win = MatrixWindow(self)

    def open_search(self):
        if self.search_win:
            self.search_win.win.lift()
            self.search_win.win.focus_force()
            self.search_win.entry.focus_set()
            return
        self.search_win = SearchWindow(self)

    # ===================== будущие задачи =====================
    def build_future(self):
        head, body = self.section("future")
        self.title_label(head, "future", "Будущие задачи")
        self.lbl_future_count = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_small)
        self.lbl_future_count.pack(side="right")
        self.fut_entry = self.make_entry(body, "Задача и дата: «Купить билеты 20.11»",
                                         on_enter=lambda e: self.add_future(),
                                         on_paste=self.add_future_lines)
        self.fut_entry.pack(fill="x", pady=(6, 4), ipady=3)
        self.fut_hint = tk.Label(body, bg=C["card"], fg=C["danger"], font=self.f_tiny,
                                 anchor="w", justify="left")
        self.fut_area = ScrollArea(self, body)
        self.fut_area.wrap.pack(fill="both", expand=True)

    def show_future_hint(self, text):
        self.fut_hint.config(text=text)
        self.fut_hint.pack(fill="x", before=self.fut_area.wrap)
        self.root.after(5000, self.fut_hint.pack_forget)

    def split_task_date(self, raw):
        """«Купить билеты 20.11» → ("Купить билеты", date). Дата — последнее слово."""
        m = re.match(r"^(.*\S)\s+(\S+)$", raw.strip())
        if m:
            d = parse_date(m.group(2), self.today)
            if d:
                return m.group(1), d
        return raw.strip(), None

    def add_future(self):
        raw = self.fut_entry.get().strip()
        if not raw:
            return
        text, d = self.split_task_date(raw)
        if not d:
            self.show_future_hint("Добавьте дату в конце: «… 20.11», «… +3», «… пт», «… завтра»")
            return
        if d < self.today:
            self.show_future_hint("Эта дата уже прошла")
            return
        self.data["tasks"].append(self.new_task(text, d))
        self.fut_entry.delete(0, "end")
        self.after_tasks_changed()

    def add_future_lines(self, lines):
        added, skipped = 0, 0
        for ln in lines:
            text, d = self.split_task_date(ln)
            if d and d >= self.today:
                self.data["tasks"].append(self.new_task(text, d))
                added += 1
            else:
                skipped += 1
        if added:
            self.after_tasks_changed()
        if skipped:
            self.show_future_hint(f"Без даты в конце строки пропущено: {skipped}")

    def unchanged(self, name, signature):
        """True, если входные данные блока те же, что при прошлой отрисовке, — перерисовка не нужна."""
        if self._render_sigs.get(name) == signature:
            return True
        self._render_sigs[name] = signature
        return False

    def render_future(self):
        today = self.today.isoformat()
        sig = (today, tuple((t["id"], t["date"], t["text"], t.get("time"), t.get("priority"), t.get("eis"))
                            for t in self.data["tasks"] if t["date"] > today and not t["done"]))
        if self.unchanged("future", sig):
            return
        frame = self.fut_area.frame
        for w in frame.winfo_children():
            w.destroy()
        self.future_headers = []
        today = self.today.isoformat()
        by_date = {}  # один проход по задачам вместо отдельного поиска для каждой даты
        for t in self.data["tasks"]:
            if t["date"] > today and not t["done"]:
                by_date.setdefault(t["date"], []).append(t)
        dates = sorted(by_date)
        total = sum(len(v) for v in by_date.values())
        shown = 0
        for iso in dates:
            d = dt.date.fromisoformat(iso)
            timed = sorted((t for t in by_date[iso] if t.get("time")), key=lambda t: t["time"])
            for t in timed + [t for t in by_date[iso] if not t.get("time")]:
                if shown >= FUTURE_MAX_ROWS:
                    break
                row = self.build_future_row(frame, t, d)
                row.drop_date = d  # бросить задачу на строку — перенести на её дату
                self.future_headers.append(row)
                shown += 1
        if shown < total:
            more = tk.Label(frame, text=f"и ещё {plural(total - shown, 'задача', 'задачи', 'задач')} позже — "
                                        "открыть неделю ⤢ или поиск", bg=C["card"], fg=C["muted"],
                            font=self.f_tiny, anchor="w", cursor="hand2")
            more.pack(fill="x", pady=(4, 0))
            more.bind("<Button-1>", lambda e: self.open_week_window())
        self.lbl_future_count.config(text=str(total) if total else "")
        if not dates:
            tk.Label(frame, text="Нет запланированных задач", bg=C["card"], fg=C["faint"],
                     font=self.f_small, anchor="w").pack(fill="x")
        self.fut_area.layout(fill=bool(self.s["block_h"].get("future")),
                             max_h=int(220 * self.scale()))

    def future_date_text(self, d):
        n = (d - self.today).days
        if n == 1:
            return "завтра"
        if n == 2:
            return "послезавтра"
        return f"{WD_SHORT[d.weekday()].lower()} {short_date(d, self.today)}"

    def build_future_row(self, parent, t, d):
        tid = t["id"]
        row = tk.Frame(parent, bg=C["card"])
        row.pack(fill="x", pady=0)
        tk.Frame(row, width=3, bg=PRIO_COLOR.get(t.get("priority"), C["card"])).pack(
            side="left", fill="y", padx=(0, 3))
        when = tk.Label(row, text=self.future_date_text(d), bg=C["card"], fg=C["muted"],
                        font=self.f_tiny, cursor="hand2")
        when.pack(side="right", anchor="n", padx=(6, 0), pady=(1, 0))
        when.bind("<Button-1>", lambda e: self.show_day(d))
        box = tk.Label(row, text="☐", bg=C["card"], fg=C["muted"], font=self.f_small, width=2,
                       cursor="hand2")
        box.pack(side="left", anchor="n")
        box.bind("<Button-1>", lambda e: self.toggle_task(tid))
        if t.get("eis") in EIS:
            tk.Label(row, text="■", bg=C["card"], fg=EIS[t["eis"]][2], font=self.f_tiny).pack(
                side="right", anchor="n")
        text = (t["time"] + "  " if t.get("time") else "") + t["text"]
        txt = tk.Label(row, text=text, bg=C["card"], fg=C["fg"], font=self.f_small, anchor="w",
                       justify="left", wraplength=self.text_wrap() - 90, cursor="hand2")
        txt.pack(side="left", fill="x", expand=True)
        autowrap(txt)
        txt.bind("<ButtonPress-1>", lambda e: self.tdrag_press(e, tid, lambda: self.open_card(tid)))
        txt.bind("<B1-Motion>", self.tdrag_motion)
        txt.bind("<ButtonRelease-1>", self.tdrag_release)
        self.bind_tree(row, "<Button-3>", lambda e: self.task_menu(e, tid))
        return row

    def show_day(self, d):
        self.selected = d
        self.view_y, self.view_m = d.year, d.month
        self.render_calendar()
        self.render_tasks(keep_scroll=False)

    # ===================== карточка задачи =====================
    def open_card(self, tid):
        if not self.find_task(tid):
            return
        card = self.cards.get(tid)
        if card:
            card.win.deiconify()
            card.win.lift()
            card.win.focus_force()
            return
        self.cards[tid] = TaskCard(self, tid)

    def refresh_cards(self):
        for card in list(self.cards.values()):
            card.refresh()
        for view in list(self.live_views):
            try:
                view.refresh()
            except tk.TclError:  # окно уже закрыто
                if view in self.live_views:
                    self.live_views.remove(view)
