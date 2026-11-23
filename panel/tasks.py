# -*- coding: utf-8 -*-
"""Список задач: данные, отрисовка, правка, перетаскивание, меню, клавиши, отмена, напоминания, сортировка и фильтр.
Примесь к классу Panel: методы работают с его состоянием (self)."""
from .core import *  # noqa: F401,F403 — общие константы и функции
from .widgets import ScrollArea  # noqa: F401
from .windows import (MatrixWindow, ReviewDialog, SearchWindow, TaskCard,  # noqa: F401
                      WeeklyReview, WeekView, WeekWindow)


class TasksMixin:
    # ===================== задачи =====================
    def build_tasks(self):
        head, body = self.section("tasks")
        self.lbl_tasks_title = self.title_label(head, "tasks", "")
        self.lbl_tasks_date = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_small, anchor="w")
        self.lbl_tasks_date.pack(side="left", padx=(6, 0))
        self.make_toggle(self.lbl_tasks_date, "tasks")
        self.lbl_tasks_count = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_small)
        self.lbl_tasks_count.pack(side="right")
        self.lbl_day_load = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_small)
        self.lbl_day_load.pack(side="right", padx=(0, 8))
        # тонкая полоса загрузки дня: доля оценок от рабочих часов
        self.load_bar = tk.Canvas(body, height=3, bg=C["faint"], highlightthickness=0)
        self.load_bar_fill = self.load_bar.create_rectangle(0, 0, 0, 3, width=0, fill=C["accent"])
        self.load_frac = 0.0
        self.load_bar.bind("<Configure>", lambda e: self.draw_load_bar())

        self.entry = self.make_entry(body, "Новая задача и Enter, или Ctrl+V списком",
                                     on_enter=lambda e: self.add_task(), on_paste=self.add_tasks)
        self.entry.pack(fill="x", pady=(8, 4), ipady=4)
        self.lbl_preview = tk.Frame(body, bg=C["card"])  # распознанные части быстрого ввода
        self.entry.var.trace_add("write", lambda *a: self.update_preview())

        ctrl = tk.Frame(body, bg=C["card"])
        ctrl.pack(fill="x", pady=(0, 4))
        self.lbl_sort = tk.Label(ctrl, bg=C["card"], fg=C["muted"], font=self.f_tiny, cursor="hand2")
        self.lbl_sort.pack(side="left")
        self.lbl_sort.bind("<Button-1>", self.sort_menu)
        self.lbl_filter = tk.Label(ctrl, bg=C["card"], fg=C["muted"], font=self.f_tiny, cursor="hand2")
        self.lbl_filter.pack(side="left", padx=(10, 0))
        self.lbl_filter.bind("<Button-1>", self.filter_menu)
        self.lbl_load = tk.Label(ctrl, bg=C["card"], fg=C["muted"], font=self.f_tiny)
        self.lbl_load.pack(side="right")
        self.over_bar = tk.Frame(body, bg=mix(C["card"], C["warn"], 0.18), padx=6, pady=3)
        self.over_lbl = tk.Label(self.over_bar, bg=self.over_bar["bg"], fg=C["warn"], font=self.f_tiny,
                                 anchor="w", justify="left", wraplength=int((WIDTH - 130) * self.scale()))
        self.over_lbl.pack(side="left", fill="x", expand=True)
        self.button(self.over_bar, "Разгрузить…", self.unload_day, fg=C["warn"], font=self.f_tiny,
                    padx=4, bg=self.over_bar["bg"]).pack(side="right")

        wrap = tk.Frame(body, bg=C["card"])
        wrap.pack(fill="both", expand=True)
        self.tasks_wrap_ref = wrap
        self.tasks_sb = tk.Canvas(wrap, width=6, height=1, bg=C["card"], highlightthickness=0,
                                  cursor="hand2")
        self.tasks_canvas = tk.Canvas(wrap, width=1, height=1, bg=C["card"],
                                      highlightthickness=0, yscrollincrement=1)
        self.tasks_canvas.pack(side="left", fill="both", expand=True)
        self.tasks_frame = tk.Frame(self.tasks_canvas, bg=C["card"])
        self.tasks_win = self.tasks_canvas.create_window((0, 0), window=self.tasks_frame, anchor="nw")
        self.tasks_canvas.bind("<Configure>", self.on_tasks_canvas_configure)
        self.tasks_canvas.config(yscrollcommand=self.update_scrollbar)
        self.sb_thumb = self.tasks_sb.create_rectangle(0, 0, 6, 0, fill=C["faint"], width=0)
        self.tasks_sb.bind("<ButtonPress-1>", self.sb_press)
        self.tasks_sb.bind("<B1-Motion>", self.sb_drag)
        self.tasks_sb.bind("<Configure>", lambda e: self.update_scrollbar(*self.tasks_canvas.yview()))
        self.tasks_sb.bind("<Enter>", lambda e: self.tasks_sb.itemconfig(self.sb_thumb, fill=C["accent"]))
        self.tasks_sb.bind("<Leave>", lambda e: self.tasks_sb.itemconfig(self.sb_thumb, fill=C["faint"]))
        self.tasks_wrap = wrap
        self.root.bind_all("<MouseWheel>", self.on_wheel)
        self.root.bind_all("<Button-4>", lambda e: self.scroll_tasks(-60, e))
        self.root.bind_all("<Button-5>", lambda e: self.scroll_tasks(60, e))

        self.undo_bar = tk.Frame(body, bg=C["hover"], padx=8, pady=4)
        self.undo_lbl = tk.Label(self.undo_bar, bg=C["hover"], fg=C["fg"], font=self.f_small, anchor="w")
        self.undo_lbl.pack(side="left", fill="x", expand=True)
        self.button(self.undo_bar, "Отменить", self.undo_delete, fg=C["accent"], bg=C["hover"],
                    font=self.f_small, padx=6).pack(side="right")

        self.drop_line = tk.Frame(self.tasks_frame, height=2, bg=C["accent"])

    # ===================== данные задач =====================
    def update_hold(self):
        """В выходные задачи последнего рабочего дня остаются на месте и видны в «сегодня»."""
        if self.s.get("weekend_hold", True):
            days = hold_dates(self.today, lambda d: self.day_info(d)[0] == "off")
        else:
            days = []
        self.hold_iso = {d.isoformat() for d in days}
        return min(self.hold_iso) if self.hold_iso else None

    def carry_over_tasks(self):
        today = self.today.isoformat()
        cutoff = (self.today - dt.timedelta(days=30)).isoformat()
        hold_start = self.update_hold()
        target = hold_start or today  # в выходной хвосты собираются в последний рабочий день
        kept = []
        for t in self.data["tasks"]:
            if not t["done"] and t["date"] < target:
                t.setdefault("from", t["date"])
                t["date"] = target
                t.pop("reminded", None)  # напомнить о времени заново
                t["carries"] = t.get("carries", 0) + 1
                self.add_log(t, "не закрыта — перенесена" + ("" if target == today else " (ждёт конца выходных)"))
            if t["done"] and t["date"] < cutoff:
                continue
            kept.append(t)
        self.data["tasks"] = kept
        self.generate_recurring()
        self.apply_auto_urgency()
        self.data["events"] = [e for e in self.data["events"] if e["date"] >= today]
        keep_from = (self.today - dt.timedelta(days=60)).isoformat()
        self.data["pomo_log"] = [x for x in self.data["pomo_log"] if x["date"] >= keep_from]
        self.save()

    def generate_recurring(self):
        today = self.today.isoformat()
        for r in self.data["recurring"]:
            start = dt.date.fromisoformat(r["start"]) if r.get("start") else None
            if not rule_matches(r["rule"], self.today, start) or r.get("last", "") >= today:
                continue
            if any(t.get("rec") == r["id"] and not t["done"] for t in self.data["tasks"]):
                continue  # прошлый раз ещё не закрыт — он и так перенесён на сегодня
            self.data["tasks"].append({"id": uuid.uuid4().hex, "text": r["text"], "date": today,
                                       "done": False, "priority": r.get("priority"),
                                       "eis": r.get("eis"), "time": r.get("time"), "rec": r["id"],
                                       "created": now_str(), "log": [[now_str(), "создана повтором"]]})
            r["last"] = today

    def find_task(self, tid):
        for t in self.data["tasks"]:
            if t["id"] == tid:
                return t
        return None

    def find_rec(self, rid):
        for r in self.data["recurring"]:
            if r["id"] == rid:
                return r
        return None

    def held(self, t):
        """Задача последнего рабочего дня, которая в выходные висит в «сегодня»."""
        return t["date"] in self.hold_iso and t["date"] < self.today.isoformat()

    def tasks_for(self, d):
        key = d.isoformat()
        if d == self.today and self.hold_iso:
            today = key
            items = [t for t in self.data["tasks"] if t["date"] == key or (
                t["date"] in self.hold_iso and (not t["done"] or t.get("done_at") == today))]
        else:
            items = [t for t in self.data["tasks"] if t["date"] == key]
        timed = sorted((t for t in items if t.get("time")), key=lambda t: t["time"])
        return timed + [t for t in items if not t.get("time")]

    def new_task(self, raw, date=None):
        """date задан — дата из текста не берётся (блок «Будущие задачи» разбирает её сам)."""
        q = parse_quick(raw, self.today, allow_date=date is None)
        day = date or q["date"] or self.selected
        t = {"id": uuid.uuid4().hex, "text": q["text"] or raw.strip(),
             "date": day.isoformat(), "done": False, "created": now_str()}
        if q["prio"]:
            t["priority"] = "high"
        if q["time"]:
            t["time"] = q["time"]
        if q["eis"]:
            t["eis"] = q["eis"]
        self.apply_extras(t, q, replace=False)
        self.add_log(t, "создана")
        return t

    def update_preview(self):
        """Под строкой ввода показываем, что распознано, — чтобы «15.10» не стало неожиданностью."""
        raw = self.entry.get().strip()
        parts = []
        q = parse_quick(raw, self.today) if raw else None
        if q:
            if q["date"]:
                parts.append((date_title(q["date"], self.today), C["accent"]))
            if q["time"]:
                parts.append((q["time"], C["accent"]))
            if q["prio"]:
                parts.append(("высокий приоритет", C["danger"]))
            if q["eis"]:
                parts.append((EIS[q["eis"]][0], EIS[q["eis"]][2]))
            if q["est"]:
                parts.append((fmt_est(q["est"]), C["muted"]))
            for g in q["tags"]:
                parts.append(("#" + g, tag_color(g)))
            if q["deadline"]:
                parts.append((f"⚑ до {short_date(q['deadline'], self.today)}", C["warn"]))
        box = self.lbl_preview
        for w in box.winfo_children():
            w.destroy()
        if not parts:
            box.pack_forget()
            return
        line, line_w, limit = None, 0, self.text_wrap()
        for text, color in parts:
            w = self.f_tiny.measure(text) + 18
            if line is None or (line_w and line_w + w > limit):
                line = tk.Frame(box, bg=C["card"])
                line.pack(fill="x", pady=(0, 2))
                line_w = 0
            tk.Label(line, text=text, bg=mix(C["card"], color, 0.2), fg=color, font=self.f_tiny,
                     padx=6, pady=1).pack(side="left", padx=(0, 4))
            line_w += w
        if q["text"] and q["text"] != raw:
            tk.Label(box, text=f"Название: {q['text']}", bg=C["card"], fg=C["muted"], font=self.f_tiny,
                     anchor="w", justify="left", wraplength=limit).pack(fill="x")
        if not box.winfo_manager():
            box.pack(fill="x", after=self.entry, pady=(0, 4))

    @staticmethod
    def add_log(t, what):
        log = t.setdefault("log", [])
        log.append([now_str(), what])
        del log[:-30]  # история не разрастается

    @staticmethod
    def apply_extras(t, ex, replace):
        """replace=True — поле целиком из текста (правка строки), иначе только дополняем."""
        if replace or ex["tags"]:
            tags = ex["tags"] if replace else list(dict.fromkeys((t.get("tags") or []) + ex["tags"]))
            if tags:
                t["tags"] = tags
            else:
                t.pop("tags", None)
        if replace or ex["est"]:
            if ex["est"]:
                t["est"] = ex["est"]
            else:
                t.pop("est", None)
        if replace or ex["deadline"]:
            if ex["deadline"]:
                t["deadline"] = ex["deadline"].isoformat()
            else:
                t.pop("deadline", None)

    def apply_auto_urgency(self):
        """До дедлайна 2 дня или меньше — задача становится срочной (квадрант сдвигается)."""
        for t in self.data["tasks"]:
            if t["done"] or not t.get("deadline") or t.get("eis") not in ("q2", "q4"):
                continue
            if (dt.date.fromisoformat(t["deadline"]) - self.today).days <= 2:
                t["eis"] = "q1" if t["eis"] == "q2" else "q3"
                self.add_log(t, "стала срочной: близко дедлайн")

    def set_deadline(self, tid, d):
        t = self.find_task(tid)
        if not t:
            return
        if d:
            t["deadline"] = d.isoformat()
            self.add_log(t, f"дедлайн {short_date(d, self.today)}")
        else:
            t.pop("deadline", None)
            self.add_log(t, "дедлайн снят")
        self.after_tasks_changed()

    def ask_deadline(self, tid):
        t = self.find_task(tid)
        if not t:
            return
        cur = dt.date.fromisoformat(t["deadline"]) if t.get("deadline") else None

        def ok(vals):
            if not vals[0]:
                self.set_deadline(tid, None)
                return None
            d = parse_date(vals[0], self.today)
            if not d:
                return "Не понял дату. Примеры: 20.11, +3, пт, завтра"
            self.set_deadline(tid, d)
            return None

        self.input_dialog("Дедлайн", f"«{short(t['text'], 40)}»\nДо какого числа нужно сделать?\n"
                                     "Пусто — убрать дедлайн. За 2 дня задача станет срочной.",
                          [("Дедлайн", short_date(cur, self.today) if cur else "")], ok)

    def set_est(self, tid, minutes):
        t = self.find_task(tid)
        if not t:
            return
        if minutes:
            t["est"] = int(minutes)
        else:
            t.pop("est", None)
        self.after_tasks_changed(calendar=False)

    def ask_est(self, tid):
        t = self.find_task(tid)
        if not t:
            return

        def ok(vals):
            if not vals[0]:
                self.set_est(tid, None)
                return None
            _, ex = parse_extras("x ~" + vals[0].lstrip("~"), self.today)
            if not ex["est"]:
                return "Примеры: 45м, 1,5ч, 2ч"
            self.set_est(tid, ex["est"])
            return None

        cur = est_token(t["est"]).lstrip("~") if t.get("est") else ""
        self.input_dialog("Оценка времени", "Сколько займёт задача? Например: 45м, 1,5ч, 2ч.",
                          [("Время", cur)], ok)

    def add_tags(self, tid, tags):
        t = self.find_task(tid)
        if t:
            t["tags"] = list(dict.fromkeys((t.get("tags") or []) + tags))
            self.after_tasks_changed(calendar=False)

    def remove_tag(self, tid, tag):
        t = self.find_task(tid)
        if t:
            t["tags"] = [g for g in t.get("tags") or [] if g != tag]
            if not t["tags"]:
                t.pop("tags")
            self.after_tasks_changed(calendar=False)

    def add_task(self):
        text = self.entry.get().strip()
        if not text:
            return
        t = self.new_task(text)
        self.data["tasks"].append(t)
        self.entry.delete(0, "end")
        self.after_tasks_changed()
        if t["date"] != self.selected.isoformat():
            d = dt.date.fromisoformat(t["date"])
            self.flash_status(f"→ на {WD_SHORT[d.weekday()].lower()}, {d.day} {MONTHS_GEN[d.month - 1]}")

    def add_tasks(self, lines):
        self.data["tasks"].extend(self.new_task(ln) for ln in lines)
        self.after_tasks_changed()
        self.flash_status(f"добавлено: {len(lines)}", C["ok"])

    def flash_status(self, text, color=None):
        """Короткое сообщение на месте счётчика задач."""
        self.lbl_tasks_count.config(text=text, fg=color or C["accent"])
        if self._status_after:
            self.root.after_cancel(self._status_after)
        self._status_after = self.root.after(2500, self._clear_status)

    def _clear_status(self):
        self._status_after = None
        self.render_tasks()

    def toggle_task(self, tid):
        t = self.find_task(tid)
        if not t:
            return
        t["done"] = not t["done"]
        if t["done"]:
            t["done_at"] = self.today.isoformat()
            self.add_log(t, "выполнена")
        else:
            t.pop("done_at", None)
            self.add_log(t, "снова открыта")
        self.after_tasks_changed()
        if t["done"]:
            self.show_undo(f"Выполнена «{short(t['text'], 22)}»")

    def delete_task(self, tid):
        for i, t in enumerate(self.data["tasks"]):
            if t["id"] == tid:
                del self.data["tasks"][i]
                break
        else:
            return
        if self.s.get("pomo_task") == tid:
            self.s["pomo_task"] = None
            self.render_pomo()
        self.after_tasks_changed()
        self.show_undo(f"Удалена «{short(t['text'], 22)}»")

    def show_undo(self, text):
        self.undo_lbl.config(text=text)
        if not self.undo_bar.winfo_manager():
            self.undo_bar.pack(fill="x", pady=(4, 0))
        if self._undo_after:
            self.root.after_cancel(self._undo_after)
        self._undo_after = self.root.after(6000, self.hide_undo)

    def hide_undo(self):
        if self._undo_after:
            self.root.after_cancel(self._undo_after)
        self._undo_after = None
        self.undo_bar.pack_forget()

    def undo_delete(self):
        self.undo()

    # ===================== отмена и повтор любых изменений задач =====================
    def undo_state(self):
        """Снимок задач, целей и повторов. Хранится сжатым: 50 снимков по 1 МБ иначе заняли бы 50 МБ."""
        raw = json.dumps({k: self.data.get(k) for k in UNDO_KEYS}, ensure_ascii=False, sort_keys=True)
        return zlib.compress(raw.encode("utf-8"), UNDO_COMPRESS)

    def commit_undo(self):
        """Если задачи изменились с прошлого снимка — прежнее состояние уходит в историю."""
        state = self.undo_state()
        if state != self._committed:
            self.hist_undo.append(self._committed)
            del self.hist_undo[:-UNDO_DEPTH]
            self.hist_redo.clear()
            self._committed = state

    def rebase_undo(self):
        """Служебные изменения (напоминания, помидоры, перенос дня) не становятся шагом отмены."""
        self._committed = self.undo_state()

    def undo(self):
        self._step_history(self.hist_undo, self.hist_redo, "Отменено", "Нечего отменять")

    def redo(self):
        self._step_history(self.hist_redo, self.hist_undo, "Повторено", "Нечего повторять")

    def _step_history(self, src, dst, done_text, empty_text):
        self.commit_undo()  # то, что ещё не в истории (например, заметка), тоже отменяется
        if not src:
            self.flash_status(empty_text, C["muted"])
            return
        dst.append(self._committed)
        self._committed = src.pop()
        restored = json.loads(zlib.decompress(self._committed).decode("utf-8"))
        self.data["tasks"] = restored.get("tasks") or []
        self.data["recurring"] = restored.get("recurring") or []
        self.data["goals"] = restored.get("goals") or {}
        if self.s.get("pomo_task") and not self.find_task(self.s["pomo_task"]):
            self.s["pomo_task"] = None
        self.save()
        self.hide_undo()
        self.render_all()
        self.refresh_cards()
        self.flash_status(done_text)

    def clear_done(self):
        key = self.selected.isoformat()
        self.data["tasks"] = [t for t in self.data["tasks"]
                              if not (t["date"] == key and t["done"])]
        self.after_tasks_changed()

    def move_task_date(self, tid, d):
        t = self.find_task(tid)
        if not t:
            return
        if t["date"] == d.isoformat():
            self.render_all()
            return
        t["date"] = d.isoformat()
        t.pop("from", None)
        t.pop("reminded", None)
        t.pop("snooze", None)
        t["moves"] = t.get("moves", 0) + 1
        self.add_log(t, f"перенесена на {short_date(d, self.today)}")
        self.after_tasks_changed()
        self.show_undo("Перенесена на " + (self.future_date_text(d) if d > self.today
                                            else "сегодня" if d == self.today else short_date(d, self.today)))

    def set_field(self, tid, key, value):
        """Приоритет (priority) или квадрант Эйзенхауэра (eis); у повторяющейся задачи — и в правиле."""
        t = self.find_task(tid)
        if not t:
            return
        if value:
            t[key] = value
        else:
            t.pop(key, None)
        r = self.find_rec(t.get("rec"))
        if r:
            r[key] = value
        self.after_tasks_changed()

    def ask_date(self, tid):
        t = self.find_task(tid)
        if not t:
            return
        d = dt.date.fromisoformat(t["date"])

        def ok(vals):
            nd = parse_date(vals[0], self.today)
            if not nd:
                return "Не понял дату. Примеры: 20.11, 20.11.2026, +3, пт, завтра"
            if nd < self.today:
                return "Эта дата уже прошла"
            self.move_task_date(tid, nd)
            return None

        self.input_dialog("Перенести задачу",
                          f"«{short(t['text'], 40)}»\nНа какую дату? Например: 20.11, +3, пт, завтра.",
                          [("Дата", f"{d.day:02d}.{d.month:02d}.{d.year}")], ok, "Перенести")

    def set_time(self, tid, value):
        t = self.find_task(tid)
        if not t:
            return
        if value:
            t["time"] = value
        else:
            t.pop("time", None)
        t.pop("reminded", None)
        r = self.find_rec(t.get("rec"))
        if r:
            r["time"] = t.get("time")
        self.after_tasks_changed()

    def ask_time(self, tid):
        t = self.find_task(tid)

        def ok(vals):
            v = vals[0].replace(".", ":")
            if not v:
                self.set_time(tid, None)
                return None
            m = re.fullmatch(r"([01]?\d|2[0-3]):([0-5]\d)", v)
            if not m:
                return "Формат: 14:30"
            self.set_time(tid, f"{int(m.group(1)):02d}:{m.group(2)}")
            return None

        self.input_dialog("Время задачи",
                          f"Во сколько? За {REMIND_BEFORE} минут придёт напоминание.\n"
                          "Оставьте пустым, чтобы убрать время.",
                          [("Время", t.get("time") or "")], ok)

    def set_repeat(self, tid, rule):
        t = self.find_task(tid)
        if not t:
            return
        r = self.find_rec(t.get("rec"))
        if rule is None:
            if r:
                self.data["recurring"].remove(r)
            for x in self.data["tasks"]:
                if r and x.get("rec") == r["id"]:
                    x.pop("rec", None)
        elif r:
            r["rule"] = rule
        else:
            rid = uuid.uuid4().hex
            self.data["recurring"].append({"id": rid, "text": t["text"], "rule": rule,
                                           "priority": t.get("priority"), "eis": t.get("eis"),
                                           "time": t.get("time"), "last": t["date"],
                                           "start": t["date"]})
            t["rec"] = rid
        if r and rule:
            r["start"] = t["date"]  # отсчёт «каждые N» — от даты этой задачи
        self.after_tasks_changed()

    def ask_repeat(self, tid):
        """Окно гибкого правила повтора."""
        t = self.find_task(tid)
        if not t:
            return
        d = dt.date.fromisoformat(t["date"])
        r = self.find_rec(t.get("rec"))
        cur = r["rule"] if r else ""
        dlg = tk.Toplevel(self.root)
        dlg.title("Повтор задачи")
        dlg.configure(bg=C["bg"], padx=16, pady=12)
        dlg.attributes("-topmost", True)
        dlg.resizable(False, False)
        mode = tk.StringVar(value="days")
        n_days, n_weeks, mday = tk.StringVar(value="2"), tk.StringVar(value="2"), tk.StringVar(value=str(d.day))
        wd_w, wd_m = tk.StringVar(value=WEEKDAYS[d.weekday()]), tk.StringVar(value=WEEKDAYS[d.weekday()])
        ordv = tk.StringVar(value=ORD_LABELS[min(3, (d.day - 1) // 7)])
        if cur.startswith("d"):
            mode.set("days"); n_days.set(cur[1:])
        elif cur.startswith("W"):
            n, wd = cur[1:].split(":"); mode.set("weeks"); n_weeks.set(n); wd_w.set(WEEKDAYS[int(wd)])
        elif cur.startswith("mL"):
            mode.set("monthwd"); ordv.set(ORD_LABELS[4]); wd_m.set(WEEKDAYS[int(cur[2:])])
        elif cur.startswith("m") and ":" in cur:
            k, wd = cur[1:].split(":"); mode.set("monthwd"); ordv.set(ORD_LABELS[int(k) - 1])
            wd_m.set(WEEKDAYS[int(wd)])
        elif cur.startswith("m"):
            mode.set("monthday"); mday.set(cur[1:])
        tk.Label(dlg, text=f"«{short(t['text'], 40)}»", bg=C["bg"], fg=C["fg"], font=self.f_title,
                 anchor="w").grid(row=0, column=0, columnspan=5, sticky="w", pady=(0, 8))

        def radio(row, value, text):
            tk.Radiobutton(dlg, text=text, variable=mode, value=value, bg=C["bg"], fg=C["fg"],
                           selectcolor=C["card"], activebackground=C["bg"], activeforeground=C["fg"],
                           font=self.f_small, anchor="w").grid(row=row, column=0, sticky="w", pady=3)

        def spin(row, col, var, lo, hi):
            sp = tk.Spinbox(dlg, from_=lo, to=hi, textvariable=var, width=4, bg=C["card"], fg=C["fg"],
                            insertbackground=C["fg"], buttonbackground=C["card"], relief="flat",
                            font=self.f_small)
            sp.grid(row=row, column=col, sticky="w", padx=(0, 4))

        def label(row, col, text):
            tk.Label(dlg, text=text, bg=C["bg"], fg=C["muted"], font=self.f_small).grid(
                row=row, column=col, sticky="w", padx=(0, 4))

        def combo(row, col, var, values, width):
            ttk.Combobox(dlg, textvariable=var, values=values, state="readonly", width=width).grid(
                row=row, column=col, sticky="w", padx=(0, 4))

        radio(1, "days", "Каждые"); spin(1, 1, n_days, 1, 365); label(1, 2, "дн.")
        radio(2, "weeks", "Каждые"); spin(2, 1, n_weeks, 1, 52); label(2, 2, "нед., в")
        combo(2, 3, wd_w, WEEKDAYS, 12)
        radio(3, "monthday", "Каждый месяц,"); spin(3, 1, mday, 1, 31); label(3, 2, "-го числа")
        radio(4, "monthwd", "Каждый месяц, в"); combo(4, 1, ordv, ORD_LABELS, 9)
        combo(4, 3, wd_m, WEEKDAYS, 12)
        preview = tk.Label(dlg, bg=C["bg"], fg=C["rest"], font=self.f_small, anchor="w")
        preview.grid(row=5, column=0, columnspan=5, sticky="w", pady=(8, 0))
        err = tk.Label(dlg, bg=C["bg"], fg=C["danger"], font=self.f_small, anchor="w")
        err.grid(row=6, column=0, columnspan=5, sticky="w")

        def build_rule():
            m = mode.get()
            if m == "days":
                n = int(n_days.get())
                if not 1 <= n <= 365:
                    raise ValueError
                return "daily" if n == 1 else f"d{n}"
            if m == "weeks":
                n = int(n_weeks.get())
                if not 1 <= n <= 52:
                    raise ValueError
                wd = WEEKDAYS.index(wd_w.get())
                return f"w{wd}" if n == 1 else f"W{n}:{wd}"
            if m == "monthday":
                n = int(mday.get())
                if not 1 <= n <= 31:
                    raise ValueError
                return f"m{n}"
            wd = WEEKDAYS.index(wd_m.get())
            k = ORD_LABELS.index(ordv.get())
            return f"mL{wd}" if k == 4 else f"m{k + 1}:{wd}"

        def update(*_):
            try:
                preview.config(text="↻ " + rule_text(build_rule()))
                err.config(text="")
            except ValueError:
                preview.config(text="")

        for var in (mode, n_days, n_weeks, mday, wd_w, wd_m, ordv):
            var.trace_add("write", update)
        update()

        def ok(_=None):
            try:
                rule = build_rule()
            except ValueError:
                err.config(text="Проверьте число")
                return
            dlg.destroy()
            self.set_repeat(tid, rule)

        btns = tk.Frame(dlg, bg=C["bg"])
        btns.grid(row=7, column=0, columnspan=5, sticky="e", pady=(10, 0))
        self.button(btns, "Сохранить", ok, fg=C["accent"], bg=C["bg"]).pack(side="right")
        self.button(btns, "Отмена", dlg.destroy, fg=C["muted"], bg=C["bg"]).pack(side="right")
        dlg.bind("<Return>", ok)
        dlg.bind("<Escape>", lambda e: dlg.destroy())
        dlg.geometry(f"+{max(0, self.root.winfo_x() - 380)}+{max(0, self.root.winfo_y() + 80)}")
        dlg.focus_force()
        return dlg

    def toggle_open(self, tid):
        t = self.find_task(tid)
        if t:
            t["open"] = not t.get("open")
            self.after_tasks_changed(calendar=False)

    def add_subtask(self, tid, lines, open_in_list=True):
        t = self.find_task(tid)
        if not t:
            return
        subs = t.setdefault("subs", [])
        for ln in lines:
            if ln.strip():
                subs.append({"id": uuid.uuid4().hex, "text": ln.strip(), "done": False})
        if open_in_list:
            t["open"] = True
            self._focus_sub = tid
        self.after_tasks_changed(calendar=False)

    def toggle_sub(self, tid, sid):
        t = self.find_task(tid)
        for s in (t or {}).get("subs", []):
            if s["id"] == sid:
                s["done"] = not s["done"]
        self.after_tasks_changed(calendar=False)

    def delete_sub(self, tid, sid):
        t = self.find_task(tid)
        if t:
            t["subs"] = [s for s in t.get("subs", []) if s["id"] != sid]
            self.after_tasks_changed(calendar=False)

    def after_tasks_changed(self, calendar=True):
        """Список дня перерисовывается сразу, остальное — одним заходом, когда Tk освободится:
        несколько изменений подряд дают одну перерисовку."""
        self.hide_undo()
        self.apply_auto_urgency()
        self.commit_undo()
        self.save()
        self.render_tasks()
        self.request_render("goals", "future", "week", "stats", "views",
                            *(("calendar",) if calendar else ()))

    def request_render(self, *parts):
        self._render_parts.update(parts)
        if self._render_after is None:
            # таймер, а не after_idle: раскладка списка вызывает update_idletasks(), и idle-задача
            # выполнилась бы сразу, без объединения нескольких изменений в одну перерисовку
            self._render_after = self.root.after(1, self._do_render)

    def _do_render(self):
        self._render_after = None
        parts, self._render_parts = self._render_parts, set()
        if "tasks_layout" in parts:  # шрифт или отступы поменялись — пересчитать высоту списка
            self.layout_tasks(self.tasks_canvas.yview()[0])
            self.apply_position()
        for name in ("calendar", "goals", "future", "week", "stats"):
            if name in parts:
                getattr(self, "render_" + name)()
        if "views" in parts:
            self.refresh_cards()
        if "future" in parts:
            self.update_summaries()

    def save(self):
        """Помечает данные изменёнными; на диск они уходят пачкой через секунду."""
        self._dirty = True
        if self._save_after is None:
            self._save_after = self.root.after(1000, self.flush_save)

    def flush_save(self):
        if self._save_after is not None:
            self.root.after_cancel(self._save_after)
            self._save_after = None
        if not self._dirty:
            return True
        data = self.data
        ok = save_data(data)
        self._dirty = not ok
        if ok:
            self._save_warned = False
        elif not self._save_warned:
            self._save_warned = True
            why = ("Файл данных не удалось разобрать при запуске — чтобы не потерять его, запись "
                   "отключена." if LOAD_INFO["blocked"] else "Изменения пока только в памяти.")
            self.toast("Не удалось сохранить", f"{why} Подробности в error.log", C["danger"], timeout=20000)
        return ok

    def report_load_problems(self):
        if LOAD_INFO["restored"]:
            self.toast("Данные восстановлены из копии",
                       "Основной файл был повреждён. Восстановлено последнее удачное сохранение; "
                       f"повреждённый файл сохранён как {os.path.basename(LOAD_INFO['corrupt'])}.",
                       C["warn"], timeout=30000)
        elif LOAD_INFO["corrupt"] and not LOAD_INFO["blocked"]:
            self.toast("Файл данных повреждён",
                       "Копии не нашлось, поэтому список начат заново. Повреждённый файл сохранён "
                       f"как {os.path.basename(LOAD_INFO['corrupt'])} в папке {DATA_DIR}.",
                       C["danger"], timeout=60000)
        elif LOAD_INFO["blocked"]:
            self.toast("Сохранение отключено",
                       f"Файл данных в {DATA_DIR} не удалось прочитать или убрать в сторону. Чтобы его "
                       "не затереть, изменения не сохраняются. Подробности в error.log.",
                       C["danger"], timeout=60000)

    def carried_note(self, t):
        src = t.get("from")
        if not src or src >= t["date"]:
            return None
        d = dt.date.fromisoformat(src)
        days = (dt.date.fromisoformat(t["date"]) - d).days
        when = f"{d.day} {MONTHS_GEN[d.month - 1]}"
        if d.year != self.today.year:
            when += f" {d.year}"
        note = f"не закрыта с {when}"
        if days > 1:
            note += f" · {plural_days(days)}"
        return note

    # ===================== прокрутка списка задач =====================
    def max_list_height(self):
        return int(self.s.get("tasks_max", 260) * self.scale())

    def render_tasks(self, keep_scroll=True):
        if self._editing or self._tdrag:
            return
        pos = self.tasks_canvas.yview()[0] if keep_scroll else 0.0
        self._fill_tasks()
        self.layout_tasks(pos)

    def layout_tasks(self, pos=0.0):
        self.tasks_frame.update_idletasks()
        h = self.tasks_frame.winfo_reqheight()
        if self.tasks_fill_space():
            self.tasks_canvas.config(height=40, scrollregion=(0, 0, 0, h))
            self.root.update_idletasks()
            limit = max(self.tasks_canvas.winfo_height(), 1)
        else:
            limit = self.max_list_height()
            self.tasks_canvas.config(height=min(h, limit), scrollregion=(0, 0, 0, h))
        if h > limit + 1:
            if not self.tasks_sb.winfo_manager():
                self.tasks_sb.pack(side="right", fill="y", padx=(4, 0))
            self.tasks_canvas.yview_moveto(pos)
        else:
            self.tasks_sb.pack_forget()
            self.tasks_canvas.yview_moveto(0)

    def on_tasks_canvas_configure(self, e):
        self.tasks_canvas.itemconfigure(self.tasks_win, width=e.width)
        if self.tasks_fill_space():
            h = self.tasks_frame.winfo_reqheight()
            if (h > e.height + 1) != bool(self.tasks_sb.winfo_manager()):
                self.root.after_idle(lambda: self.layout_tasks(self.tasks_canvas.yview()[0]))

    def tasks_fill_space(self):
        """Список занимает всё место блока, а не подстраивается под число задач."""
        return bool(self.s["block_h"].get("tasks"))

    def text_wrap(self):
        w = self.s["w"] if self.s["size_fixed"] and self.s["w"] else WIDTH
        return max(120, w - 120)

    def update_scrollbar(self, first, last):
        first, last = float(first), float(last)
        self._sb_view = (first, last)
        h = max(self.tasks_sb.winfo_height(), 1)
        y1, y2 = first * h, max(last * h, first * h + 16)
        self.tasks_sb.coords(self.sb_thumb, 0, y1, 6, min(y2, h))

    def sb_press(self, e):
        first, last = getattr(self, "_sb_view", (0.0, 1.0))
        h = max(self.tasks_sb.winfo_height(), 1)
        frac = e.y / h
        if not first <= frac <= last:
            self.tasks_canvas.yview_moveto(frac - (last - first) / 2)
            first, last = self.tasks_canvas.yview()
        self._sb_start = (e.y, first)

    def sb_drag(self, e):
        y0, first0 = self._sb_start
        h = max(self.tasks_sb.winfo_height(), 1)
        self.tasks_canvas.yview_moveto(first0 + (e.y - y0) / h)

    def pointer_inside(self, e, container):
        w = self.root.winfo_containing(e.x_root, e.y_root)
        while w is not None:
            if w is container:
                return True
            w = w.master
        return False

    def on_wheel(self, e):
        self.scroll_tasks(-e.delta // 2, e)

    def scroll_tasks(self, pixels, e):
        if self.tasks_sb.winfo_manager() and self.pointer_inside(e, self.tasks_wrap):
            self.tasks_canvas.yview_scroll(int(pixels), "units")
        for area in self.scroll_areas:
            if self.pointer_inside(e, area.wrap):
                area.scroll(pixels)

    def set_list_height(self, v):
        self.s["tasks_max"] = v
        self.save()
        self.render_tasks()

    # ===================== отрисовка задач =====================
    def _fill_tasks(self):
        d = self.selected
        if self.pick_task:
            title, tcolor = "Выберите день в календаре (Esc — отмена)", C["warn"]
        elif d == self.today:
            title, tcolor = "Задачи на сегодня", C["fg"]
        elif d == self.today + dt.timedelta(days=1):
            title, tcolor = "Задачи на завтра", C["fg"]
        else:
            title, tcolor = f"Задачи на {d.day} {MONTHS_GEN[d.month - 1]}", C["fg"]
        self.lbl_tasks_title.config(text=title, fg=tcolor)
        if self.pick_task:
            date_text = ""
        elif d in (self.today, self.today + dt.timedelta(days=1)):
            date_text = f"{d.day} {MONTHS_GEN[d.month - 1]}, {WD_SHORT[d.weekday()].lower()}"
        else:  # число уже в заголовке — добавляем день недели
            date_text = WD_SHORT[d.weekday()].lower() + (f", {d.year}" if d.year != self.today.year else "")
        self.lbl_tasks_date.config(text=date_text)

        self.drop_line.place_forget()
        if self._empty_label is not None:
            self._empty_label.destroy()
            self._empty_label = None
        self.task_rows = []
        all_items = self.tasks_for(d)
        done = sum(t["done"] for t in all_items)
        if all_items and done == len(all_items):
            self.lbl_tasks_count.config(text=f"всё сделано ✔ {done}", fg=C["ok"])
        else:
            self.lbl_tasks_count.config(text=f"{done} из {len(all_items)}" if all_items else "",
                                        fg=C["muted"])
        self.render_task_controls(all_items)
        items = self.view_tasks(d)

        self.sync_task_rows(items)
        if not items:
            self._empty_label = self.build_empty_state(d, bool(all_items))
            return
        focus_tid = getattr(self, "_focus_sub", None)
        if focus_tid:
            self._focus_sub = None
            for tid, row in self.task_rows:
                if tid == focus_tid and getattr(row, "sub_entry", None):
                    row.sub_entry.focus_set()
        if self.kb_sel not in dict(self.task_rows):
            self.kb_sel = None
        self.highlight_rows()  # и снять выделение со строк, взятых из кэша

    def build_empty_state(self, d, filtered):
        """Пустой список подсказывает следующий шаг, а не просто молчит."""
        box = tk.Frame(self.tasks_frame, bg=C["card"])
        box.pack(fill="x", pady=(2, 0))
        if filtered:
            tk.Label(box, text="Нет задач по этому фильтру", bg=C["card"], fg=C["faint"],
                     font=self.f_small, anchor="w").pack(side="left")
            self.button(box, "Показать все", lambda: self.set_filter("all"), fg=C["accent"],
                        font=self.f_small, padx=6).pack(side="left", padx=(6, 0))
            return box
        nxt = d + dt.timedelta(days=1)
        later = [t for t in self.tasks_for(nxt) if not t["done"]] if d >= self.today else []
        if not later:
            tk.Label(box, text="Пока пусто — впишите задачу выше", bg=C["card"], fg=C["faint"],
                     font=self.f_small, anchor="w").pack(fill="x")
            return box
        when = "сегодня" if d == self.today else "этот день"
        tk.Label(box, text=f"На {when} пусто. На следующий день "
                           f"{plural(len(later), 'задача', 'задачи', 'задач')}.",
                 bg=C["card"], fg=C["fg"], font=self.f_small, anchor="w", justify="left",
                 wraplength=self.text_wrap()).pack(fill="x")
        btns = tk.Frame(box, bg=C["card"])
        btns.pack(fill="x", pady=(4, 0))
        self.button(btns, f"Взять на {when}", lambda: self.pull_tasks(nxt, d), fg=C["accent"],
                    font=self.f_small, padx=6).pack(side="left")
        self.button(btns, "Матрица", self.open_matrix, fg=C["muted"],
                    font=self.f_small, padx=6).pack(side="left", padx=(6, 0))
        return box

    def pull_tasks(self, src, dst):
        """Незакрытые задачи дня src переносятся на dst одним шагом отмены."""
        moved = [t for t in self.tasks_for(src) if not t["done"]]
        for t in moved:
            t["date"] = dst.isoformat()
            t.pop("from", None)
            t.pop("reminded", None)
            t["moves"] = t.get("moves", 0) + 1
            self.add_log(t, f"перенесена на {short_date(dst, self.today)}")
        if moved:
            self.after_tasks_changed()
            self.show_undo(f"Взято {plural(len(moved), 'задача', 'задачи', 'задач')}")

    def row_signature(self, t):
        """Всё, от чего зависит вид строки. Совпало — строку можно не пересоздавать."""
        goal = self.find_goal(t.get("goal"))
        rec = self.find_rec(t.get("rec"))
        return (json.dumps(t, ensure_ascii=False, sort_keys=True), self.today,
                self.s.get("pomo_task") == t["id"], goal["text"] if goal else None,
                rec["rule"] if rec else None, int(self.s.get("task_gap", 1)))

    def sync_task_rows(self, items):
        """Пересоздаём только новые и изменившиеся строки; остальные просто переупаковываем
        в нужном порядке. Отметка одной задачи из 60 — одна строка вместо шестидесяти."""
        cache = self._row_cache
        wanted = {t["id"] for t in items}
        for tid in [k for k in cache if k not in wanted]:
            cache.pop(tid)[1].destroy()
        for tid, (sig, row) in list(cache.items()):
            row.pack_forget()
        for t in items:
            sig = self.row_signature(t)
            cached = cache.get(t["id"])
            if cached and cached[0] == sig and cached[1].winfo_exists():
                row = cached[1]
                row.pack(fill="x", pady=int(self.s.get("task_gap", 1)))
                self.task_rows.append((t["id"], row))
            else:
                if cached:
                    cached[1].destroy()
                self.build_task_row(t)
                cache[t["id"]] = (sig, self.task_rows[-1][1])

    def drop_row_cache(self):
        for _, row in self._row_cache.values():
            row.destroy()
        self._row_cache.clear()

    def build_task_row(self, t):
        tid = t["id"]
        done = t["done"]
        note = self.carried_note(t)
        row = tk.Frame(self.tasks_frame, bg=C["card"])
        row.pack(fill="x", pady=int(self.s.get("task_gap", 1)))
        self.task_rows.append((tid, row))

        carried = bool(note) and not done
        arrow = tk.Label(row, text="➜", bg=C["card"], fg=C["warn"] if carried else C["card"],
                         font=self.f_task, cursor="hand2")
        arrow.pack(side="left", anchor="n")
        box = tk.Label(row, text="✔" if done else "☐", bg=C["card"],
                       fg=C["ok"] if done else C["muted"],
                       font=self.f_task_bold if done else self.f_task, width=2, cursor="hand2")
        box.pack(side="left", anchor="n")
        dele = tk.Label(row, text="✕", bg=C["card"], fg=C["card"], font=self.f_task_small, cursor="hand2")
        dele.pack(side="right", anchor="n")
        more = tk.Label(row, text="⋯", bg=C["card"], fg=C["card"], font=self.f_task_bold, cursor="hand2")
        more.pack(side="right", anchor="n", padx=(0, 2))
        # частые действия видны при наведении: помидор и перенос на следующий день
        later = tk.Label(row, text="↷", bg=C["card"], fg=C["card"], font=self.f_task, cursor="hand2")
        play = tk.Label(row, text="▶", bg=C["card"], fg=C["card"], font=self.f_task_small, cursor="hand2")
        hover_icons = [(dele, C["danger"]), (more, C["muted"])]
        if not done:
            later.pack(side="right", anchor="n", padx=(0, 2))
            play.pack(side="right", anchor="n", padx=(0, 2))
            hover_icons += [(later, C["accent"]), (play, C["ok"])]
        prio = PRIO_COLOR.get(t.get("priority"))
        if prio and not done:
            tk.Label(row, text="●", bg=C["card"], fg=prio, font=self.f_task_tiny).pack(
                side="right", anchor="n", padx=(0, 4), pady=(3, 0))

        col = tk.Frame(row, bg=C["card"])
        col.pack(side="left", fill="x", expand=True, padx=(4, 0))
        line = tk.Frame(col, bg=C["card"])
        line.pack(fill="x")
        wrap = self.text_wrap()
        drag_parts = [line]
        if t.get("time"):
            tl = tk.Label(line, text=t["time"], bg=C["card"], fg=C["faint"] if done else C["muted"],
                          font=self.f_task, width=5, anchor="w")
            tl.pack(side="left", anchor="n", padx=(0, 4))
            drag_parts.append(tl)
            wrap -= int(44 * self.scale())
        txt = tk.Label(line, text=t["text"], bg=C["card"], fg=C["muted"] if done else C["fg"],
                       font=self.f_task, anchor="w", justify="left", wraplength=wrap)
        txt.pack(side="left", fill="x", expand=True)
        autowrap(txt)
        drag_parts.append(txt)
        row.txt, row.line = txt, line

        meta = []
        if t.get("eis") in EIS:
            name, _, color = EIS[t["eis"]]
            meta.append((f"■ {name}", C["muted"] if done else color, lambda: self.open_card(tid)))
        badge = deadline_badge(t, self.today)
        if badge and not done:
            meta.append((badge[0], badge[1], lambda: self.ask_deadline(tid)))
        if t.get("est"):
            meta.append((f"⏱ {fmt_est(t['est'])}", C["muted"], lambda: self.open_card(tid)))
        for tg in t.get("tags") or []:
            meta.append((f"#{tg}", tag_color(tg), lambda g=tg: self.set_filter("#" + g)))
        goal = self.find_goal(t.get("goal"))
        if goal:
            meta.append(("○ " + short(goal["text"], 16), C["rest"],
                         lambda g=goal["id"]: self.set_filter("goal:" + g)))
        subs = t.get("subs") or []
        if subs:
            sd = sum(s["done"] for s in subs)
            meta.append((f"☰ {sd}/{len(subs)} " + ("▾" if t.get("open") else "▸"),
                         C["ok"] if sd == len(subs) else C["muted"], lambda: self.toggle_open(tid)))
        if t.get("rec"):
            r = self.find_rec(t["rec"])
            if r:
                meta.append(("↻ " + rule_text(r["rule"]), C["muted"], None))
        if t.get("pomos"):
            meta.append((f"● {t['pomos']}", C["accent"], None))
        if self.s.get("pomo_task") == tid:
            meta.append(("в помодоро", C["rest"], None))
        if (t.get("note") or "").strip():
            meta.append(("✎ заметка", C["muted"], lambda: self.open_card(tid)))
        moved = t.get("moves", 0) + t.get("carries", 0)
        if moved >= 3 and not done:
            meta.append((f"↷ {moved}", C["warn"], lambda: self.open_card(tid)))
        if meta:
            mf = tk.Frame(col, bg=C["card"])
            mf.pack(fill="x")
            line_w, limit = 0, self.text_wrap()
            for text, color, cmd in meta:
                ml = tk.Label(mf, text=text, bg=C["card"], fg=color, font=self.f_task_tiny)
                w = self.f_task_tiny.measure(text) + 8
                if line_w and line_w + w > limit:  # перенос значков на новую строку
                    mf = tk.Frame(col, bg=C["card"])
                    mf.pack(fill="x")
                    ml.destroy()
                    ml = tk.Label(mf, text=text, bg=C["card"], fg=color, font=self.f_task_tiny)
                    line_w = 0
                line_w += w
                ml.pack(side="left", padx=(0, 8))
                if cmd:
                    ml.config(cursor="hand2")
                    ml.bind("<Button-1>", lambda e, c=cmd: c())
        if note:
            tk.Label(col, text=note, bg=C["card"], fg=C["faint"] if done else C["warn"],
                     font=self.f_task_italic, anchor="w").pack(fill="x")
        elif self.held(t):  # тихая пометка: переноса нет, задача просто ждёт конца выходных
            tk.Label(col, text=WD_FROM[dt.date.fromisoformat(t["date"]).weekday()], bg=C["card"],
                     fg=C["faint"], font=self.f_task_italic, anchor="w").pack(fill="x")

        if t.get("open"):
            sf = tk.Frame(col, bg=C["card"])
            sf.pack(fill="x", pady=(2, 2))
            for s in subs:
                sr = tk.Frame(sf, bg=C["card"])
                sr.pack(fill="x")
                sb = tk.Label(sr, text="✔" if s["done"] else "☐", bg=C["card"],
                              fg=C["ok"] if s["done"] else C["muted"], font=self.f_task_small,
                              width=2, cursor="hand2")
                sb.pack(side="left", anchor="n")
                st = tk.Label(sr, text=s["text"], bg=C["card"],
                              fg=C["muted"] if s["done"] else C["fg"], font=self.f_task_small,
                              anchor="w", justify="left", wraplength=wrap - 30, cursor="hand2")
                st.pack(side="left", fill="x", expand=True)
                autowrap(st)
                for w in (sb, st):
                    w.bind("<Button-1>", lambda e, s_id=s["id"]: self.toggle_sub(tid, s_id))
                for w in (sr, sb, st):
                    w.bind("<Button-3>", lambda e, s_id=s["id"]: self.sub_menu(e, tid, s_id))
            se = self.make_entry(sf, "Подзадача и Enter", font=self.f_task_small, bg=C["card"],
                                 on_enter=lambda e: self.sub_enter(tid, e),
                                 on_paste=lambda lines: self.add_subtask(tid, lines))
            se.pack(fill="x", pady=(2, 0), ipady=2)
            row.sub_entry = se

        for w in (arrow, box):
            w.bind("<Button-1>", lambda e: self.toggle_task(tid))
        dele.bind("<Button-1>", lambda e: self.delete_task(tid))
        more.bind("<Button-1>", lambda e: self.open_card(tid))
        play.bind("<Button-1>", lambda e: self.link_pomo(tid))
        later.bind("<Button-1>", lambda e: self.move_task_date(tid, self.next_day_for(tid)))
        for w in drag_parts:
            w.bind("<ButtonPress-1>", lambda e: self.tdrag_press(e, tid))
            w.bind("<B1-Motion>", self.tdrag_motion)
            w.bind("<ButtonRelease-1>", self.tdrag_release)
            w.bind("<Double-Button-1>", lambda e: self.edit_task(tid))
            w.config(cursor="hand2")
        for w in drag_parts + [col, row]:
            w.bind("<ButtonPress-1>", lambda e: self.select_row(tid), add="+")
        self.bind_tree(row, "<Button-3>", lambda e: self.task_menu(e, tid))
        # скрытые значки «прячутся» цветом фона строки — у выделенной строки он другой
        self.bind_tree(row, "<Enter>", lambda e: [w.config(fg=c) for w, c in hover_icons])
        self.bind_tree(row, "<Leave>", lambda e: [w.config(fg=w.cget("bg")) for w, c in hover_icons])

    def next_day_for(self, tid):
        """Сегодняшняя и просроченная задача — на завтра, будущая — на день позже своей даты."""
        t = self.find_task(tid)
        d = dt.date.fromisoformat(t["date"]) if t else self.today
        return max(d, self.today) + dt.timedelta(days=1)

    def sub_enter(self, tid, e):
        text = e.get().strip()
        if text:
            self.add_subtask(tid, [text])
        return "break"

    def sub_menu(self, e, tid, sid):
        m = tk.Menu(self.root, tearoff=0)
        m.add_command(label="Удалить подзадачу", command=lambda: self.delete_sub(tid, sid))
        self.popup(m, e)
        return "break"

    # ===================== правка задачи =====================
    def edit_task(self, tid):
        t = self.find_task(tid)
        row = next((r for i, r in self.task_rows if i == tid), None)
        if not t or row is None:
            return
        self._tdrag = None
        raw = (("! " if t.get("priority") == "high" else "")
               + (t["time"] + " " if t.get("time") else "") + t["text"]
               + (" " + est_token(t["est"]) if t.get("est") else "")
               + "".join(f" #{g}" for g in t.get("tags") or [])
               + (f" до {short_date(dt.date.fromisoformat(t['deadline']), self.today)}"
                  if t.get("deadline") else ""))
        if tid in self._row_cache:  # строка временно превращается в поле ввода — потом пересоздать
            self._row_cache[tid] = (None, self._row_cache[tid][1])
        for w in row.line.winfo_children():
            w.pack_forget()
        e = tk.Entry(row.line, bg=C["bg"], fg=C["fg"], insertbackground=C["fg"], relief="flat",
                     font=self.f_norm, highlightthickness=1, highlightbackground=C["accent"],
                     highlightcolor=C["accent"])
        e.insert(0, raw)
        e.pack(fill="x", expand=True, ipady=2)
        self._editing = tid
        e.bind("<Return>", lambda ev: self.finish_edit(tid, e.get()))
        e.bind("<Escape>", lambda ev: (self.finish_edit(tid, None), "break")[1])
        e.bind("<FocusOut>", lambda ev: self.finish_edit(tid, e.get()))
        e.bind("<Control-KeyPress>", lambda ev: self.entry_ctrl(ev, e, None))
        self.root.focus_force()
        e.focus_set()
        e.select_range(0, "end")
        e.icursor("end")

    def finish_edit(self, tid, raw):
        if self._editing != tid:
            return
        self._editing = None
        t = self.find_task(tid)
        if t and raw is not None and raw.strip():
            text, prio, time = parse_task_text(raw)
            text, ex = parse_extras(text or raw.strip(), self.today)
            self.apply_extras(t, ex, replace=True)
            if time != t.get("time"):
                t.pop("reminded", None)
            t["text"] = text or raw.strip()
            if prio:
                t["priority"] = "high"
            elif t.get("priority") == "high":  # «!» стёрли — высокий приоритет снимаем
                t.pop("priority", None)
            if time:
                t["time"] = time
            else:
                t.pop("time", None)
            r = self.find_rec(t.get("rec"))
            if r:
                r.update(text=t["text"], priority=t.get("priority"), time=t.get("time"))
            self.after_tasks_changed()
        elif t and raw is not None:  # стёрли весь текст — удаляем задачу
            self.delete_task(tid)
        else:
            self.render_tasks()

    # ===================== перетаскивание задач =====================
    def tdrag_press(self, e, tid, on_click=None):
        self._tdrag = {"id": tid, "x": e.x_root, "y": e.y_root, "active": False, "ghost": None,
                       "click": on_click}

    def tdrag_motion(self, e):
        d = self._tdrag
        if not d:
            return
        if not d["active"]:
            if abs(e.x_root - d["x"]) + abs(e.y_root - d["y"]) < 6:
                return
            d["active"] = True
            self.hide_tip()
            t = self.find_task(d["id"])
            g = tk.Toplevel(self.root)
            g.overrideredirect(True)
            g.attributes("-topmost", True)
            try:
                g.attributes("-alpha", 0.85)
            except tk.TclError:
                pass
            tk.Label(g, text=short(t["text"] if t else "", 40), bg=C["selected"], fg=C["fg"],
                     font=self.f_norm, padx=8, pady=3).pack()
            d["ghost"] = g
        d["ghost"].geometry(f"+{e.x_root + 14}+{e.y_root + 6}")
        self.drag_nav_check(self.root.winfo_containing(e.x_root, e.y_root))
        target = self.drop_target(e)
        key = (target[0], target[1]) if target else None
        if key == d.get("last") and (self.view_y, self.view_m) == d.get("month"):
            return  # цель та же — ничего не перерисовываем
        d["last"], d["month"] = key, (self.view_y, self.view_m)
        if d.get("cal_marked"):
            self.render_calendar()  # снять прежнюю подсветку дня
            d["cal_marked"] = False
        self.drop_line.place_forget()
        self.set_drop_highlight(target[2] if target and target[0] in ("date", "eis") else None)
        if target and target[0] == "day":
            self.day_cells[target[2]].config(bg=C["warn"], fg=C["on_accent"])
            d["cal_marked"] = True
        elif target and target[0] == "list":
            idx = target[1]
            if idx < len(self.task_rows):
                y = self.task_rows[idx][1].winfo_y() - 1
            else:
                last = self.task_rows[-1][1]
                y = last.winfo_y() + last.winfo_height()
            self.drop_line.place(x=0, y=max(0, y), relwidth=1.0)
            self.drop_line.lift()

    def tdrag_release(self, e):
        d, self._tdrag = self._tdrag, None
        self.drag_nav_check(None)
        if not d:
            return
        if not d["active"]:
            if d.get("click"):
                d["click"]()
            return
        if d["ghost"]:
            d["ghost"].destroy()
        self.drop_line.place_forget()
        self.set_drop_highlight(None)
        target = self.drop_target(e)
        if target and target[0] == "eis":
            self.set_field(d["id"], "eis", None if target[1] == "none" else target[1])
            return
        if target and target[0] in ("day", "date"):
            if target[1] < self.today:
                self.render_all()  # в прошлое не переносим
                return
            self.move_task_date(d["id"], target[1])
        elif target and target[0] == "list":
            self.move_task_order(d["id"], target[1])
        else:
            self.render_calendar()

    def drag_nav_check(self, w):
        """Задержали задачу над стрелкой календаря — листаем месяц."""
        direction = -1 if w is self.btn_prev else 1 if w is self.btn_next else 0
        if direction == self._nav_dir:
            return
        if self._nav_after:
            self.root.after_cancel(self._nav_after)
            self._nav_after = None
        self._nav_dir = direction
        if direction:
            self._nav_after = self.root.after(600, self._drag_nav_step)

    def _drag_nav_step(self):
        self._nav_after = None
        if not self._tdrag or not self._nav_dir:
            return
        self.shift_month(self._nav_dir)
        self._nav_after = self.root.after(900, self._drag_nav_step)

    def drop_target(self, e):
        w = self.root.winfo_containing(e.x_root, e.y_root)
        if w in self.day_cells:
            i = self.day_cells.index(w)
            return ("day", self.cell_dates[i], i)
        x = w
        while x is not None:  # дата (будущие задачи, неделя) или квадрант матрицы
            if getattr(x, "drop_date", None):
                return ("date", x.drop_date, x)
            if getattr(x, "drop_eis", None):
                return ("eis", x.drop_eis, x)
            x = x.master
        if self.pointer_inside(e, self.tasks_wrap) and self.task_rows:
            for i, (tid, row) in enumerate(self.task_rows):
                if e.y_root < row.winfo_rooty() + row.winfo_height() / 2:
                    return ("list", i)
            return ("list", len(self.task_rows))
        return None

    def set_drop_highlight(self, widget):
        """Подсвечивает цель перетаскивания и возвращает прежний цвет предыдущей цели."""
        if self._hl and self._hl[0] is not widget:
            old, bg = self._hl
            try:
                old.config(bg=bg)
            except tk.TclError:
                pass
            self._hl = None
        if widget is not None and self._hl is None:
            self._hl = (widget, widget.cget("bg"))
            widget.config(bg=C["warn"])

    def move_task_order(self, tid, idx):
        if self.s["sort"] != "manual" or self.s["filter"] != "all":
            # порядок задаёт сортировка — меняем только день, если задачу притащили из другого
            t = self.find_task(tid)
            if t and t["date"] != self.selected.isoformat():
                self.move_task_date(tid, self.selected)
            else:
                self.render_calendar()
            return
        ids = [i for i, _ in self.task_rows]
        before = ids[idx] if idx < len(ids) else None
        if before == tid or (idx > 0 and ids[idx - 1] == tid):
            self.render_calendar()
            return
        tasks = self.data["tasks"]
        t = self.find_task(tid)
        if t["date"] != self.selected.isoformat():  # притащили из будущих задач
            t["date"] = self.selected.isoformat()
            t.pop("from", None)
            t.pop("reminded", None)
            t["moves"] = t.get("moves", 0) + 1
            self.add_log(t, f"перенесена на {short_date(self.selected, self.today)}")
        tasks.remove(t)
        if before:
            tasks.insert(next(i for i, x in enumerate(tasks) if x["id"] == before), t)
        else:
            others = [i for i in ids if i != tid]
            last = max(i for i, x in enumerate(tasks) if x["id"] in others)
            tasks.insert(last + 1, t)
        self.after_tasks_changed()

    # ===================== меню задачи =====================
    def popup(self, menu, e):
        try:
            menu.tk_popup(e.x_root, e.y_root)
        finally:
            menu.grab_release()

    def task_menu(self, e, tid):
        t = self.find_task(tid)
        if not t:
            return "break"
        m = tk.Menu(self.root, tearoff=0)
        m.add_command(label="Открыть карточку…", command=lambda: self.open_card(tid))
        m.add_command(label="Изменить текст", command=lambda: self.edit_task(tid))
        m.add_command(label="Добавить подзадачу", command=lambda: self.open_subs(tid))
        m.add_separator()
        d = dt.date.fromisoformat(t["date"])
        if d != self.today:
            m.add_command(label="Перенести на сегодня", command=lambda: self.move_task_date(tid, self.today))
        tomorrow = self.today + dt.timedelta(days=1)
        if d != tomorrow:
            m.add_command(label="Перенести на завтра", command=lambda: self.move_task_date(tid, tomorrow))
        monday = self.today + dt.timedelta(days=7 - self.today.weekday())
        m.add_command(label=f"Перенести на понедельник, {monday.day} {MONTHS_GEN[monday.month - 1]}",
                      command=lambda: self.move_task_date(tid, monday))
        m.add_command(label="Перенести на дату…", command=lambda: self.ask_date(tid))
        m.add_command(label="Перенести на день в календаре…", command=lambda: self.start_pick(tid))
        m.add_separator()
        pm = tk.Menu(m, tearoff=0)
        var_prio = tk.StringVar(value=t.get("priority") or "")
        for value, name, _ in PRIORITIES:
            pm.add_radiobutton(label=name, variable=var_prio, value=value or "",
                               command=lambda v=value: self.set_field(tid, "priority", v))
        m.add_cascade(label="Приоритет", menu=pm)
        em = tk.Menu(m, tearoff=0)
        var_eis = tk.StringVar(value=t.get("eis") or "")
        em.add_radiobutton(label="Не задано", variable=var_eis, value="",
                           command=lambda: self.set_field(tid, "eis", None))
        for q, (name, desc, _) in EIS.items():
            em.add_radiobutton(label=f"{name} ({desc})", variable=var_eis, value=q,
                               command=lambda q=q: self.set_field(tid, "eis", q))
        m.add_cascade(label="Матрица Эйзенхауэра", menu=em)
        m.add_command(label="Время и напоминание…" if not t.get("time") else f"Время: {t['time']}…",
                      command=lambda: self.ask_time(tid))
        m.add_command(label="Дедлайн…" if not t.get("deadline") else
                      f"Дедлайн: {short_date(dt.date.fromisoformat(t['deadline']), self.today)}…",
                      command=lambda: self.ask_deadline(tid))
        m.add_command(label="Оценка времени…" if not t.get("est") else f"Оценка: {fmt_est(t['est'])}…",
                      command=lambda: self.ask_est(tid))
        rep = tk.Menu(m, tearoff=0)
        r = self.find_rec(t.get("rec"))
        var_rule = tk.StringVar(value=r["rule"] if r else "")
        rep.add_radiobutton(label="Не повторять", variable=var_rule, value="",
                            command=lambda: self.set_repeat(tid, None))
        rep.add_radiobutton(label="Каждый день", variable=var_rule, value="daily",
                            command=lambda: self.set_repeat(tid, "daily"))
        rep.add_radiobutton(label="По будням", variable=var_rule, value="weekdays",
                            command=lambda: self.set_repeat(tid, "weekdays"))
        wd = d.weekday()
        rep.add_radiobutton(label=f"Каждую неделю (в {WD_ACC[wd]})", variable=var_rule,
                            value=f"w{wd}", command=lambda: self.set_repeat(tid, f"w{wd}"))
        cur = r["rule"] if r else ""
        if cur and cur not in BASIC_RULES and cur != f"w{wd}":
            rep.add_radiobutton(label="↻ " + rule_text(cur), variable=var_rule, value=cur,
                                command=lambda: self.ask_repeat(tid))
        rep.add_separator()
        rep.add_command(label="Другое правило…", command=lambda: self.ask_repeat(tid))
        m.add_cascade(label="Повторять", menu=rep)
        goals = self.week_goals(d)
        var_goal = tk.StringVar(value=t.get("goal") or "")
        if goals:
            gm = tk.Menu(m, tearoff=0)
            gm.add_radiobutton(label="Нет", variable=var_goal, value="",
                               command=lambda: self.set_field(tid, "goal", None))
            for g in goals:
                gm.add_radiobutton(label="○ " + short(g["text"], 40), variable=var_goal, value=g["id"],
                                   command=lambda x=g["id"]: self.set_field(tid, "goal", x))
            m.add_cascade(label="Цель недели", menu=gm)
        if self.s.get("pomo_task") == tid:
            m.add_command(label="Отвязать от помодоро", command=lambda: self.link_pomo(None))
        else:
            m.add_command(label="Работать над ней (помодоро)", command=lambda: self.link_pomo(tid))
        m.add_command(label="Сохранить как шаблон…", command=lambda: self.save_task_template(tid))
        m.add_separator()
        m.add_command(label="Удалить", command=lambda: self.delete_task(tid))
        m._vars = (var_prio, var_eis, var_rule, var_goal)  # переменные должны жить, пока открыто меню
        self.popup(m, e)
        return "break"

    def open_subs(self, tid):
        t = self.find_task(tid)
        if t:
            t["open"] = True
            self._focus_sub = tid
            self.after_tasks_changed(calendar=False)

    def start_pick(self, tid):
        self.pick_task = tid
        if self.s["collapsed"].get("calendar"):
            self.toggle_section("calendar")
        self.render_tasks()

    def on_escape(self, e):
        self.drag_nav_check(None)
        if self.kb_sel:
            self.kb_sel = None
            self.highlight_rows()
        if self.pick_task:
            self.pick_task = None
            self.render_tasks()
        if self._tdrag:
            d, self._tdrag = self._tdrag, None
            if d.get("ghost"):
                d["ghost"].destroy()
            self.drop_line.place_forget()
            self.render_calendar()

    def global_ctrl(self, e):
        try:
            focus = self.root.focus_get()
        except KeyError:  # фокус во всплывающем списке ttk — Tk не знает такого виджета
            focus = None
        typing = isinstance(focus, (tk.Text, tk.Entry, tk.Spinbox))
        if e.keycode == VK_Z and not typing:
            self.redo() if e.state & 0x1 else self.undo()  # Ctrl+Shift+Z — повтор
            return "break"
        if e.keycode == VK_Y and not typing:
            self.redo()
            return "break"
        if e.keycode == 70:  # Ctrl+F в любой раскладке
            self.open_search()
            return "break"
        return None

    # ===================== выбор задачи и клавиши =====================
    def bind_list_keys(self):
        keys = (("<Up>", lambda: self.kb_move(-1)), ("<Down>", lambda: self.kb_move(1)),
                ("<space>", self.kb_toggle), ("<Return>", self.kb_open), ("<KP_Enter>", self.kb_open),
                ("<Delete>", self.kb_delete), ("<F2>", self.kb_edit),
                ("<Control-Up>", lambda: self.kb_shift_date(-1)),
                ("<Control-Down>", lambda: self.kb_shift_date(1)))
        for seq, fn in keys:
            self.root.bind_all(seq, lambda e, f=fn: self.on_list_key(f), add="+")

    def on_list_key(self, fn):
        """Клавиши действуют, только когда фокус на самой панели, а не в поле ввода или другом окне."""
        try:
            w = self.root.focus_get()
        except KeyError:
            return None
        if (w is None or isinstance(w, (tk.Entry, tk.Text, tk.Spinbox, ttk.Combobox))
                or w.winfo_toplevel() is not self.root or self.focus_active or self._editing):
            return None
        fn()
        return "break"

    def select_row(self, tid, focus=True):
        self.kb_sel = tid
        self.highlight_rows()
        row = dict(self.task_rows).get(tid)
        if row is not None:
            self.ensure_visible(row)
        if focus:
            try:
                self.root.focus_force()  # окно без рамки само фокус не получает
            except tk.TclError:
                pass

    def highlight_rows(self):
        for tid, row in self.task_rows:
            self.recolor(row, C["selected"] if tid == self.kb_sel else C["card"])

    def recolor(self, w, color):
        if getattr(w, "keep_bg", False) or isinstance(w, (tk.Entry, tk.Text)):
            return
        try:
            old = w.cget("bg")
            w.config(bg=color)
            if w.cget("fg") == old:  # значок, спрятанный цветом фона, остаётся спрятанным
                w.config(fg=color)
        except tk.TclError:
            pass  # у Frame нет fg — это нормально
        for ch in w.winfo_children():
            self.recolor(ch, color)

    def ensure_visible(self, row):
        self.tasks_frame.update_idletasks()
        total = max(self.tasks_frame.winfo_height(), 1)
        view_h = self.tasks_canvas.winfo_height()
        top = row.winfo_y()
        bottom = top + row.winfo_height()
        y0 = self.tasks_canvas.canvasy(0)
        if top < y0:
            self.tasks_canvas.yview_moveto(top / total)
        elif bottom > y0 + view_h:
            self.tasks_canvas.yview_moveto((bottom - view_h) / total)

    def kb_ids(self):
        return [i for i, _ in self.task_rows]

    def kb_move(self, step):
        ids = self.kb_ids()
        if not ids:
            return
        if self.kb_sel in ids:
            i = max(0, min(len(ids) - 1, ids.index(self.kb_sel) + step))
        else:
            i = 0 if step > 0 else len(ids) - 1
        self.select_row(ids[i], focus=False)

    def kb_neighbor(self):
        ids = self.kb_ids()
        if self.kb_sel not in ids or len(ids) < 2:
            return None
        i = ids.index(self.kb_sel)
        return ids[i + 1] if i + 1 < len(ids) else ids[i - 1]

    def kb_toggle(self):
        if self.kb_sel:
            self.toggle_task(self.kb_sel)

    def kb_open(self):
        if self.kb_sel:
            self.open_card(self.kb_sel)

    def kb_edit(self):
        if self.kb_sel:
            self.edit_task(self.kb_sel)

    def kb_delete(self):
        if not self.kb_sel:
            return
        nxt = self.kb_neighbor()
        self.delete_task(self.kb_sel)
        self.kb_sel = nxt
        self.highlight_rows()

    def kb_shift_date(self, delta):
        t = self.find_task(self.kb_sel) if self.kb_sel else None
        if not t:
            return
        d = dt.date.fromisoformat(t["date"]) + dt.timedelta(days=delta)
        if d < self.today:
            self.flash_status("В прошлое не переносим", C["muted"])
            return
        nxt = self.kb_neighbor()
        self.move_task_date(t["id"], d)
        self.kb_sel = nxt
        self.highlight_rows()
        self.flash_status(f"→ {WD_SHORT[d.weekday()].lower()}, {d.day} {MONTHS_GEN[d.month - 1]}")

    # ===================== подсказка с текстом =====================
    def text_tip(self, widget, lines):
        self.hide_tip()
        if self._tdrag:
            return
        self._tip_after = self.root.after(400, lambda: self._show_text_tip(widget, lines))

    def _show_text_tip(self, widget, lines):
        self._tip_after = None
        if not widget.winfo_exists():
            return
        tip = tk.Toplevel(self.root)
        tip.overrideredirect(True)
        tip.attributes("-topmost", True)
        tip.configure(bg=C["faint"])
        box = tk.Frame(tip, bg=C["card"], padx=8, pady=5)
        box.pack(padx=1, pady=1)
        for text, color in lines:
            tk.Label(box, text=text, bg=C["card"], fg=color, font=self.f_small, anchor="w",
                     justify="left", wraplength=int(260 * self.scale())).pack(fill="x")
        tip.update_idletasks()
        x, y = widget.winfo_rootx(), widget.winfo_rooty() + widget.winfo_height() + 4
        vl, vt, vr, vb = virtual_screen(self.root)
        x = min(x, vr - tip.winfo_reqwidth() - 4)
        if y + tip.winfo_reqheight() > vb:
            y = widget.winfo_rooty() - tip.winfo_reqheight() - 4
        tip.geometry(f"+{x}+{y}")
        self._tip = tip

    # ===================== напоминания =====================
    def check_reminders(self, now):
        today = self.today.isoformat()
        for t in self.data["tasks"]:
            if t["done"]:
                continue
            if t.get("snooze"):  # отложенное напоминание — в любой день
                if now >= dt.datetime.fromisoformat(t["snooze"]):
                    t.pop("snooze")
                    self.rebase_undo()
                    self.save()
                    self.remind(t, "Напоминание")
                continue
            if t["date"] != today or not t.get("time") or t.get("reminded") == t["time"]:
                continue
            h, m = map(int, t["time"].split(":"))
            due = dt.datetime.combine(self.today, dt.time(h, m))
            if now >= due - dt.timedelta(minutes=REMIND_BEFORE):
                t["reminded"] = t["time"]
                self.rebase_undo()
                self.save()
                if now <= due + dt.timedelta(minutes=1):
                    mins = max(0, int((due - now).total_seconds() // 60))
                    when = "Сейчас" if mins == 0 else f"Через {plural(mins, 'минуту', 'минуты', 'минут')}"
                    self.remind(t, f"{when} · {t['time']}")

    def remind(self, t, title):
        tid = t["id"]
        self.toast(title, t["text"], C["accent"],
                   actions=[("через 10 мин", lambda: self.snooze(tid, 10)),
                            ("через час", lambda: self.snooze(tid, 60)),
                            ("завтра", lambda: self.snooze_tomorrow(tid)),
                            ("открыть", lambda: self.open_card(tid))])

    def snooze(self, tid, minutes):
        t = self.find_task(tid)
        if not t:
            return
        t["snooze"] = (dt.datetime.now() + dt.timedelta(minutes=minutes)).isoformat(timespec="minutes")
        self.rebase_undo()
        self.save()

    def snooze_tomorrow(self, tid):
        t = self.find_task(tid)
        if t:
            self.move_task_date(tid, max(self.today + dt.timedelta(days=1), dt.date.fromisoformat(t["date"])))

    def toast(self, title, text, color=None, timeout=60000, sound=None, actions=None):
        """sound: None — системный звук, "work"/"break" — звук из настроек помодоро.
        actions: [(подпись, функция)] — кнопки; после нажатия уведомление закрывается."""
        Sound.play(self.s["sounds"].get(sound) if sound else {"file": "default"})
        w = tk.Toplevel(self.root)
        w.overrideredirect(True)
        w.attributes("-topmost", True)
        w.configure(bg=color or C["accent"])
        box = tk.Frame(w, bg=C["card"], padx=14, pady=10)
        box.pack(padx=(4, 1), pady=1)
        tk.Label(box, text=title, bg=C["card"], fg=color or C["accent"], font=self.f_title,
                 anchor="w").pack(fill="x")
        tk.Label(box, text=text, bg=C["card"], fg=C["fg"], font=self.f_norm, anchor="w",
                 justify="left", wraplength=int(280 * self.scale())).pack(fill="x", pady=(2, 0))
        if actions:
            row = tk.Frame(box, bg=C["card"])
            row.pack(fill="x", pady=(6, 0))
            for label, fn in actions:
                self.button(row, label, fn, fg=C["accent"], font=self.f_small, padx=6).pack(side="left")
        tk.Label(box, text="нажмите, чтобы закрыть", bg=C["card"], fg=C["faint"],
                 font=self.f_tiny, anchor="w").pack(fill="x", pady=(4, 0))
        w.update_idletasks()
        l, t, r, b = work_area(self.root)
        y = b - MARGIN - sum(x.winfo_height() + 8 for x in self.toasts) - w.winfo_reqheight()
        w.geometry(f"+{r - w.winfo_reqwidth() - MARGIN}+{max(t, y)}")
        self.toasts.append(w)

        def close(_=None):
            if w in self.toasts:
                self.toasts.remove(w)
                w.destroy()

        self.bind_tree(w, "<Button-1>", close)
        self.root.after(timeout, close)

    # ===================== сортировка, фильтр, нагрузка дня =====================
    def view_tasks(self, d):
        items = self.tasks_for(d)
        f = self.s["filter"]
        if f in EIS:
            items = [t for t in items if t.get("eis") == f]
        elif f == "none":
            items = [t for t in items if t.get("eis") not in EIS]
        elif f.startswith("#"):
            items = [t for t in items if f[1:] in (t.get("tags") or [])]
        elif f.startswith("goal:"):
            items = [t for t in items if t.get("goal") == f[5:]]
        sort = self.s["sort"]
        if sort == "priority":
            items = sorted(items, key=lambda t: (PRIO_RANK.get(t.get("priority"), 3),
                                                 EIS_ORDER.get(t.get("eis"), 4)))
        elif sort == "eis":
            items = sorted(items, key=lambda t: (EIS_ORDER.get(t.get("eis"), 4),
                                                 PRIO_RANK.get(t.get("priority"), 3)))
        elif sort == "deadline":
            items = sorted(items, key=lambda t: (t.get("deadline") or "9999-12-31",
                                                 PRIO_RANK.get(t.get("priority"), 3)))
        return items

    def render_task_controls(self, items):
        self.lbl_sort.config(text="↕ " + SORTS.get(self.s["sort"], ""),
                             fg=C["muted"] if self.s["sort"] == "manual" else C["accent"])
        f = self.s["filter"]
        if f.startswith("goal:"):
            g = self.find_goal(f[5:])
            if not g:  # цель удалили — фильтр больше не нужен
                self.s["filter"] = f = "all"
        label = FILTERS.get(f) or ("○ " + short(self.find_goal(f[5:])["text"], 20)
                                   if f.startswith("goal:") else f)
        self.lbl_filter.config(text="⚲ " + label,
                               fg=C["muted"] if f == "all" else C["warn"])
        undone = [t for t in items if not t["done"]]
        est = sum(t.get("est") or 0 for t in undone)
        limit_min = float(self.s["day_hours"]) * 60
        self.lbl_load.config(text="")
        over_load = est > limit_min
        if est and limit_min > 0:
            hours = f"{float(self.s['day_hours']):g}".replace(".", ",")
            self.lbl_day_load.config(text=f"{fmt_est(est)} из {hours} ч",
                                     fg=C["danger"] if over_load else C["muted"])
            self.load_frac = min(1.0, est / limit_min)
            self.load_bar.itemconfig(self.load_bar_fill, fill=C["danger"] if over_load else C["accent"])
            if not self.load_bar.winfo_manager():
                self.load_bar.pack(fill="x", pady=(6, 0), before=self.entry)
            self.draw_load_bar()
        else:
            self.lbl_day_load.config(text="")
            self.load_bar.pack_forget()
        q1 = sum(1 for t in undone if t.get("eis") == "q1")
        over = []
        if q1 > int(self.s["q1_limit"]):
            over.append(f"«Сделать сейчас»: {q1} при лимите {self.s['q1_limit']}")
        if est > limit_min:
            hours = f"{float(self.s['day_hours']):g}".replace(".", ",")
            over.append(f"запланировано {fmt_est(est)} из {hours} ч")
        if over:
            self.over_lbl.config(text="⚠ Перегруз: " + "; ".join(over))
            if not self.over_bar.winfo_manager():
                self.over_bar.pack(fill="x", pady=(0, 4), before=self.tasks_wrap_ref)
        else:
            self.over_bar.pack_forget()

    def draw_load_bar(self):
        w = self.load_bar.winfo_width()
        self.load_bar.coords(self.load_bar_fill, 0, 0, int(w * self.load_frac), 3)

    def set_sort(self, value):
        self.s["sort"] = value
        self.save()
        self.render_tasks(keep_scroll=False)

    def set_filter(self, value):
        self.s["filter"] = value
        self.save()
        self.render_tasks(keep_scroll=False)

    def sort_menu(self, e):
        m = tk.Menu(self.root, tearoff=0)
        var = tk.StringVar(value=self.s["sort"])
        for key, label in SORTS.items():
            m.add_radiobutton(label=label, variable=var, value=key, command=lambda k=key: self.set_sort(k))
        m._var = var
        self.popup(m, e)
        return "break"

    def filter_menu(self, e):
        m = tk.Menu(self.root, tearoff=0)
        var = tk.StringVar(value=self.s["filter"])
        for key, label in FILTERS.items():
            m.add_radiobutton(label=label, variable=var, value=key, command=lambda k=key: self.set_filter(k))
        goals = self.week_goals()
        if goals:
            m.add_separator()
            for g in goals:
                m.add_radiobutton(label="○ " + short(g["text"], 30), variable=var, value="goal:" + g["id"],
                                  command=lambda k="goal:" + g["id"]: self.set_filter(k))
        tags = sorted({g for t in self.data["tasks"] for g in t.get("tags") or []})
        if tags:
            m.add_separator()
            for g in tags:
                m.add_radiobutton(label=f"#{g}", variable=var, value=f"#{g}",
                                  command=lambda k=f"#{g}": self.set_filter(k))
        m._var = var
        self.popup(m, e)
        return "break"

    def ask_limits(self):
        def ok(vals):
            try:
                q1 = int(vals[0])
                hours = float(vals[1].replace(",", "."))
            except ValueError:
                return "Введите числа"
            if not (1 <= q1 <= 50 and 0.5 <= hours <= 24):
                return "Лимит задач 1–50, часов 0,5–24"
            self.s.update(q1_limit=q1, day_hours=hours)
            self.save()
            self.render_tasks()
            self.render_week()
            return None

        self.input_dialog("Лимиты дня", "Когда предупреждать о перегрузе дня.",
                          [("«Сделать сейчас», шт.", self.s["q1_limit"]),
                           ("Рабочих часов", f"{float(self.s['day_hours']):g}".replace(".", ","))], ok)

    def unload_day(self):
        day = self.selected.isoformat()
        # первыми — то, что проще всего перенести: менее важное и менее срочное
        order = {"q4": 0, "q3": 1, None: 2, "q2": 3, "q1": 4}
        ReviewDialog(self, "Разгрузить день",
                     f"{date_title(self.selected, self.today)}. Перенесите часть задач — "
                     "вверху то, что проще всего отложить.",
                     keep=lambda t: t["date"] == day and not t["done"],
                     order_key=lambda t: (order.get(t.get("eis") if t.get("eis") in EIS else None, 2),
                                          -PRIO_RANK.get(t.get("priority"), 3)),
                     keep_label="Оставить")

    def maybe_morning_review(self):
        today = self.today.isoformat()
        if not self.s.get("review", True) or self.s.get("review_date") == today:
            return
        self.s["review_date"] = today
        self.save()

        def carried(t):
            return t["date"] == today and not t["done"] and (t.get("from") or today) < today

        n = sum(1 for t in self.data["tasks"] if carried(t))
        if n:
            ReviewDialog(self, "Доброе утро! Разберём хвосты",
                         f"С прошлых дней не закрыто: {plural(n, 'задача', 'задачи', 'задач')}. "
                         "Решите для каждой: сделать сегодня, перенести или удалить.",
                         keep=carried, keep_label="Сегодня")
