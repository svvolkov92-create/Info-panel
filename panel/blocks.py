# -*- coding: utf-8 -*-
"""Блоки панели: заметки, итоги, события, порядок, сворачивание, высота.
Примесь к классу Panel: методы работают с его состоянием (self)."""
from .core import *  # noqa: F401,F403 — общие константы и функции
from .widgets import ScrollArea  # noqa: F401
from .windows import (MatrixWindow, ReviewDialog, SearchWindow, TaskCard,  # noqa: F401
                      WeeklyReview, WeekView, WeekWindow)


class BlocksMixin:
    # ===================== ссылки в заметках =====================
    def setup_links(self, widget):
        widget.tag_config("link", foreground=C["accent"], underline=1)
        widget.tag_bind("link", "<Enter>", lambda e: widget.config(cursor="hand2"))
        widget.tag_bind("link", "<Leave>", lambda e: widget.config(cursor="xterm"))
        widget.tag_bind("link", "<Button-1>", lambda e: self.open_link_at(widget, e))
        self.linkify(widget)

    @staticmethod
    def linkify(widget):
        widget.tag_remove("link", "1.0", "end")
        content = widget.get("1.0", "end-1c")
        for m in LINK_RE.finditer(content):
            widget.tag_add("link", f"1.0+{m.start()}c", f"1.0+{m.end()}c")

    def open_link_at(self, widget, e):
        idx = widget.index(f"@{e.x},{e.y}")
        rng = widget.tag_prevrange("link", f"{idx}+1c")
        if not rng:
            return
        target = widget.get(*rng)
        try:
            open_target(target)
        except Exception as exc:
            log_error(f"Не открылось: {target}\n{exc}")
            self.toast("Не получилось открыть", f"{short(target, 60)}\n{exc}", C["danger"], timeout=8000)

    # ===================== заметки =====================
    def build_notes(self):
        head, body = self.section("notes")
        self.title_label(head, "notes", "Заметки")
        self.lbl_notes_state = tk.Label(head, bg=C["card"], fg=C["faint"], font=self.f_tiny)
        self.lbl_notes_state.pack(side="right")
        self.notes = tk.Text(body, height=5, wrap="word", bg=C["bg"], fg=C["fg"],
                             insertbackground=C["fg"], relief="flat", font=self.f_small,
                             highlightthickness=1, highlightbackground=C["faint"],
                             highlightcolor=C["accent"], padx=6, pady=4, undo=True)
        self.notes.pack(fill="both", expand=True, pady=(6, 0))
        self.notes.insert("1.0", self.data.get("notes", ""))
        self.setup_links(self.notes)
        self.notes.edit_reset()
        self.notes.bind("<<Modified>>", self.notes_modified)
        self.notes.bind("<Button-1>", lambda e: (self.root.focus_force(), self.notes.focus_set()))
        self.notes.bind("<Control-KeyPress>", lambda e: self.text_ctrl(e, self.notes))
        self.notes.edit_modified(False)

    def text_ctrl(self, e, widget):
        """Ctrl-клавиши в многострочном поле по коду клавиши — работают в любой раскладке."""
        k = e.keycode
        events = {VK_V: "<<Paste>>", VK_C: "<<Copy>>", VK_X: "<<Cut>>",
                  VK_Z: "<<Undo>>", VK_Y: "<<Redo>>"}
        if k in events:
            try:
                widget.event_generate(events[k])
            except tk.TclError:
                pass
            return "break"
        if k == VK_A:
            widget.tag_add("sel", "1.0", "end-1c")
            return "break"
        return None

    def notes_modified(self, e):
        if not self.notes.edit_modified():
            return
        self.notes.edit_modified(False)
        self.linkify(self.notes)
        self.lbl_notes_state.config(text="…")
        if self._notes_after:
            self.root.after_cancel(self._notes_after)
        self._notes_after = self.root.after(800, self.save_notes)

    def save_notes(self):
        if self._notes_after:
            self.root.after_cancel(self._notes_after)
        self._notes_after = None
        self.data["notes"] = self.notes.get("1.0", "end-1c")
        self.save()
        self.lbl_notes_state.config(text="сохранено")

    # ===================== итоги недели =====================
    def build_stats(self):
        head, body = self.section("stats")
        self.title_label(head, "stats", "Итоги недели")
        self.lbl_stats = tk.Label(head, bg=C["card"], fg=C["muted"], font=self.f_tiny)
        self.lbl_stats.pack(side="right")
        self.stats_canvas = tk.Canvas(body, width=1, height=int(78 * self.scale()), bg=C["card"],
                                      highlightthickness=0)
        self.stats_canvas.pack(fill="both", expand=True, pady=(6, 0))
        # на изменение размера перерисовываем только график: список ниже от размера не зависит,
        # а его перестройка снова меняла бы размер холста (бесконечный цикл)
        self.stats_canvas.bind("<Configure>", lambda e: self.render_chart())
        mode_row = tk.Frame(body, bg=C["card"])
        mode_row.pack(fill="x", pady=(6, 2))
        tk.Label(mode_row, text="Помидоры за 7 дней:", bg=C["card"], fg=C["muted"],
                 font=self.f_tiny).pack(side="left")
        self.stats_mode_lbls = {}
        for key, label in (("task", "по задачам"), ("tag", "по меткам")):
            lbl = tk.Label(mode_row, text=label, bg=C["card"], font=self.f_tiny, cursor="hand2")
            lbl.pack(side="left", padx=(6, 0))
            lbl.bind("<Button-1>", lambda e, k=key: self.set_stats_by(k))
            self.stats_mode_lbls[key] = lbl
        self.stats_list = tk.Frame(body, bg=C["card"])
        self.stats_list.pack(fill="x")

    def set_stats_by(self, key):
        self.s["stats_by"] = key
        self.save()
        self.render_stats()

    def render_pomo_stats(self):
        for w in self.stats_list.winfo_children():
            w.destroy()
        by = self.s.get("stats_by", "task")
        for key, lbl in self.stats_mode_lbls.items():
            lbl.config(fg=C["accent"] if key == by else C["faint"],
                       font=self.f_title if key == by else self.f_tiny)
        since = (self.today - dt.timedelta(days=6)).isoformat()
        counts = {}
        for x in self.data["pomo_log"]:
            if x["date"] < since:
                continue
            if by == "task":
                keys = [x.get("text") or "без задачи"]
            else:
                keys = ["#" + g for g in x.get("tags") or []] or ["без метки"]
            for k in keys:
                counts[k] = counts.get(k, 0) + 1
        if not counts:
            tk.Label(self.stats_list, text="Пока нет — запустите помидор из карточки задачи",
                     bg=C["card"], fg=C["faint"], font=self.f_tiny, anchor="w").pack(fill="x")
            return
        top = sorted(counts.items(), key=lambda kv: -kv[1])[:5]
        peak = top[0][1]
        for name, n in top:
            row = tk.Frame(self.stats_list, bg=C["card"])
            row.pack(fill="x")
            color = tag_color(name[1:]) if name.startswith("#") else C["fg"]
            tk.Label(row, text=short(name, 26), bg=C["card"], fg=color, font=self.f_tiny,
                     anchor="w").pack(side="left")
            tk.Label(row, text=str(n), bg=C["card"], fg=C["muted"], font=self.f_tiny).pack(side="right")
            bar = tk.Frame(row, bg=C["accent"], height=4,
                           width=max(4, int(70 * self.scale() * n / peak)))
            bar.pack(side="right", padx=6)

    def render_stats(self):
        self.render_chart()
        self.render_pomo_stats()

    def render_chart(self):
        c = self.stats_canvas
        c.delete("all")
        k = self.scale()
        w = c.winfo_width()
        if w < 50:
            w = int((WIDTH - 50) * k)
        h = c.winfo_height() if c.winfo_height() > 40 else int(78 * k)
        days = [self.today - dt.timedelta(days=6 - i) for i in range(7)]
        done = {d.isoformat(): 0 for d in days}
        for t in self.data["tasks"]:
            if t["done"]:
                key = t.get("done_at") or t["date"]
                if key in done:
                    done[key] += 1
        pom = [self.data["pomodoros"].get(d.isoformat(), 0) for d in days]
        dn = [done[d.isoformat()] for d in days]
        top = max(max(dn), max(pom), 1)
        base = h - int(20 * k)
        area = base - int(14 * k)
        colw = w / 7
        bw = max(4, min(int(9 * k), int(colw / 4)))
        for i, d in enumerate(days):
            cx = colw * (i + 0.5)
            for j, (val, color) in enumerate(((dn[i], C["ok"]), (pom[i], C["accent"]))):
                x0 = cx - bw - 1 if j == 0 else cx + 1
                bh = area * val / top
                if val:
                    c.create_rectangle(x0, base - bh, x0 + bw, base, fill=color, width=0)
                    c.create_text(x0 + bw / 2, base - bh - 2, text=str(val), anchor="s",
                                  fill=C["muted"], font=self.f_tiny)
                else:
                    c.create_line(x0, base - 1, x0 + bw, base - 1, fill=C["faint"])
            is_today = d == self.today
            c.create_text(cx, base + 3, text=WD_SHORT[d.weekday()], anchor="n",
                          fill=C["accent"] if is_today else C["muted"],
                          font=self.f_title if is_today else self.f_tiny)
        self.lbl_stats.config(text=f"■ задачи {sum(dn)}   ■ помодоро {sum(pom)}")
        self.lbl_stats.config(fg=C["muted"])

    # ===================== события =====================
    def build_events(self):
        head, body = self.section("events")
        self.title_label(head, "events", "События")
        self.ev_entry = self.make_entry(body, "Событие ДД.ММ и Enter", on_enter=lambda e: self.add_event())
        self.ev_entry.pack(fill="x", pady=(6, 4), ipady=3)
        self.ev_hint = tk.Label(body, bg=C["card"], fg=C["danger"], font=self.f_tiny, anchor="w")
        self.ev_frame = tk.Frame(body, bg=C["card"])
        self.ev_frame.pack(fill="x")

    def add_event(self):
        raw = self.ev_entry.get().strip()
        m = EVENT_RE.match(raw)
        if not m:
            self.ev_hint.config(text="Формат: «Отпуск 15.11» или «Дедлайн 01.12.2026»")
            self.ev_hint.pack(fill="x", before=self.ev_frame)
            self.root.after(4000, self.ev_hint.pack_forget)
            return
        title, day, mon, year = m.group(1).strip(), int(m.group(2)), int(m.group(3)), m.group(4)
        try:
            if year:
                y = int(year) + (2000 if len(year) == 2 else 0)
                d = dt.date(y, mon, day)
            else:
                d = dt.date(self.today.year, mon, day)
                if d < self.today:
                    d = dt.date(self.today.year + 1, mon, day)
        except ValueError:
            self.ev_hint.config(text="Такой даты нет")
            self.ev_hint.pack(fill="x", before=self.ev_frame)
            self.root.after(4000, self.ev_hint.pack_forget)
            return
        if d < self.today:
            self.ev_hint.config(text="Эта дата уже прошла")
            self.ev_hint.pack(fill="x", before=self.ev_frame)
            self.root.after(4000, self.ev_hint.pack_forget)
            return
        self.ev_hint.pack_forget()
        self.data["events"].append({"id": uuid.uuid4().hex, "title": title, "date": d.isoformat()})
        self.ev_entry.delete(0, "end")
        self.save()
        self.render_events()
        self.update_summaries()

    def delete_event(self, eid):
        self.data["events"] = [e for e in self.data["events"] if e["id"] != eid]
        self.save()
        self.render_events()
        self.update_summaries()

    def render_events(self):
        for w in self.ev_frame.winfo_children():
            w.destroy()
        evs = sorted(self.data["events"], key=lambda e: e["date"])
        if not evs:
            tk.Label(self.ev_frame, text="Нет событий", bg=C["card"], fg=C["faint"],
                     font=self.f_small, anchor="w").pack(fill="x")
            return
        for ev in evs:
            d = dt.date.fromisoformat(ev["date"])
            n = (d - self.today).days
            if n == 0:
                when, color = "сегодня", C["ok"]
            elif n == 1:
                when, color = "завтра", C["warn"]
            else:
                when = f"через {plural_days(n)}"
                color = C["warn"] if n <= 3 else C["muted"]
            row = tk.Frame(self.ev_frame, bg=C["card"])
            row.pack(fill="x", pady=1)
            dele = tk.Label(row, text="✕", bg=C["card"], fg=C["card"], font=self.f_small,
                            cursor="hand2")
            dele.pack(side="right")
            tk.Label(row, text=when, bg=C["card"], fg=color, font=self.f_small).pack(side="right")
            tk.Label(row, text=f"{short(ev['title'], 26)}", bg=C["card"], fg=C["fg"],
                     font=self.f_small, anchor="w").pack(side="left")
            tk.Label(row, text=f" {d.day:02d}.{d.month:02d}", bg=C["card"], fg=C["faint"],
                     font=self.f_tiny).pack(side="left")
            dele.bind("<Button-1>", lambda e, i=ev["id"]: self.delete_event(i))
            self.bind_tree(row, "<Enter>", lambda e, x=dele: x.config(fg=C["danger"]))
            self.bind_tree(row, "<Leave>", lambda e, x=dele: x.config(fg=C["card"]))

    # ===================== блоки =====================
    def apply_order(self):
        for sec in self.sections.values():
            sec["card"].pack_forget()
        if self.focus_active:  # в режиме фокуса блоки скрыты
            return
        for key in self.s["order"]:
            if key in self.sections and key not in self.s["hidden_blocks"]:
                self.sections[key]["card"].pack(fill="x", padx=12, pady=(0, 10))
        self.apply_collapsed()

    def block_summary(self, key):
        """Короткий итог для заголовка свёрнутого блока; у остальных блоков итог уже в заголовке."""
        today = self.today
        if key == "calendar":
            return f"{today.day} {MONTHS_GEN[today.month - 1]}, {WD_SHORT[today.weekday()].lower()}"
        if key == "future":
            iso = today.isoformat()
            dates = sorted(t["date"] for t in self.data["tasks"] if t["date"] > iso and not t["done"])
            return f"ближайшая {self.future_date_text(dt.date.fromisoformat(dates[0]))}" if dates else ""
        if key == "events":
            evs = sorted(e["date"] for e in self.data["events"] if e["date"] >= today.isoformat())
            if not evs:
                return ""
            ev = next(e for e in self.data["events"] if e["date"] == evs[0])
            n = (dt.date.fromisoformat(ev["date"]) - today).days
            return f"{short(ev['title'], 18)}, " + ("сегодня" if n == 0 else f"через {plural_days(n)}")
        return ""

    def update_summaries(self):
        for key, sec in self.sections.items():
            text = self.block_summary(key) if self.s["collapsed"].get(key) else ""
            sec["summary"].config(text=text)
            if text and not sec["summary"].winfo_manager():
                sec["summary"].pack(side="right", padx=(8, 0))
            elif not text:
                sec["summary"].pack_forget()

    def apply_collapsed(self):
        for key, sec in self.sections.items():
            collapsed = self.s["collapsed"].get(key, False)
            if collapsed:
                sec["body"].pack_forget()
                sec["grip"].pack_forget()
            else:
                if not sec["grip"].winfo_manager():
                    sec["grip"].pack(side="bottom", fill="x", pady=(2, 0))
                if not sec["body"].winfo_manager():
                    sec["body"].pack(fill="both", expand=True)
            sec["arrow"].config(text="▸" if collapsed else "▾")
        self.update_summaries()
        card = self.sections["tasks"]["card"]
        if card.winfo_manager():
            grow = not self.s["collapsed"].get("tasks", False) and not self.s["block_h"].get("tasks")
            card.pack_configure(fill="both" if grow else "x", expand=grow)
        self.render_pomo()
        self.layout_tasks(self.tasks_canvas.yview()[0])

    # ===================== высота блоков =====================
    def apply_block_heights(self):
        for key, sec in self.sections.items():
            h = self.s["block_h"].get(key)
            body = sec["body"]
            if h:
                body.pack_propagate(False)
                body.config(height=int(h))
            else:
                body.pack_propagate(True)
                body.config(height=0)

    def block_resize_start(self, e, key):
        body = self.sections[key]["body"]
        self.root.update_idletasks()
        self._block_drag = (e.y_root, body.winfo_height())

    def block_resize_move(self, e, key):
        """Движения мыши приходят чаще, чем экран успевает перерисоваться, поэтому здесь только
        запоминаем нужную высоту, а применяем её не чаще раза за кадр (~60 раз в секунду)."""
        y0, h0 = self._block_drag
        self._resize_target = (key, max(int(30 * self.scale()), h0 + e.y_root - y0))
        if getattr(self, "_resize_after", None) is None:
            self._resize_after = self.root.after(RESIZE_FRAME_MS, self._apply_block_resize)

    def _apply_block_resize(self):
        self._resize_after = None
        key, h = self._resize_target
        if self.s["block_h"].get(key) == h:
            return
        self.s["block_h"][key] = h
        body = self.sections[key]["body"]
        # меняем только этот блок, а не перестраиваем все (как apply_block_heights + apply_collapsed)
        body.pack_propagate(False)
        body.config(height=h)
        if key == "tasks":
            self.layout_tasks(self.tasks_canvas.yview()[0])
        elif key == "future":
            self.fut_area.layout(fill=True, max_h=0)

    def block_resize_end(self, key):
        if getattr(self, "_resize_after", None) is not None:  # применить последнее положение
            self.root.after_cancel(self._resize_after)
            self._apply_block_resize()
        self.apply_block_heights()
        self.apply_collapsed()
        self.save()
        self.render_stats()
        self.apply_position()

    def reset_block_height(self, key):
        self.s["block_h"].pop(key, None)
        self.after_block_heights_changed()

    def reset_all_block_heights(self):
        self.s["block_h"].clear()
        self.after_block_heights_changed()

    def after_block_heights_changed(self):
        self.save()
        self.apply_block_heights()
        self.apply_collapsed()
        self.render_stats()
        self.apply_position()

    def toggle_section(self, key):
        self.s["collapsed"][key] = not self.s["collapsed"].get(key, False)
        self.save()
        self.apply_collapsed()

    def toggle_all(self):
        visible = [k for k in self.s["order"] if k not in self.s["hidden_blocks"]]
        collapse = not all(self.s["collapsed"].get(k) for k in visible)
        for key in visible:
            self.s["collapsed"][key] = collapse
        self.save()
        self.apply_collapsed()

    def blocks_dialog(self):
        dlg = tk.Toplevel(self.root)
        dlg.title("Блоки панели")
        dlg.configure(bg=C["bg"], padx=14, pady=12)
        dlg.attributes("-topmost", True)
        dlg.resizable(False, False)
        tk.Label(dlg, text="Галочка — показывать блок, стрелки — порядок.", bg=C["bg"],
                 fg=C["muted"], font=self.f_small).pack(anchor="w", pady=(0, 8))
        rows = tk.Frame(dlg, bg=C["bg"])
        rows.pack(fill="x")

        def move(key, delta):
            o = self.s["order"]
            i = o.index(key)
            j = i + delta
            if 0 <= j < len(o):
                o[i], o[j] = o[j], o[i]
                changed()

        def toggle(key):
            h = self.s["hidden_blocks"]
            if key in h:
                h.remove(key)
            else:
                h.append(key)
            changed()

        def changed():
            self.save()
            self.apply_order()
            fill()

        def fill():
            for w in rows.winfo_children():
                w.destroy()
            for i, key in enumerate(self.s["order"]):
                shown = key not in self.s["hidden_blocks"]
                r = tk.Frame(rows, bg=C["card"], padx=8, pady=3)
                r.pack(fill="x", pady=1)
                cb = tk.Label(r, text="✔" if shown else "☐", width=2, bg=C["card"],
                              fg=C["ok"] if shown else C["muted"], font=self.f_norm, cursor="hand2")
                cb.pack(side="left")
                cb.bind("<Button-1>", lambda e, k=key: toggle(k))
                tk.Label(r, text=BLOCKS[key], bg=C["card"], fg=C["fg"] if shown else C["muted"],
                         font=self.f_norm, width=14, anchor="w").pack(side="left")
                self.button(r, "↓", lambda k=key: move(k, 1), fg=C["muted"], padx=6).pack(side="right")
                self.button(r, "↑", lambda k=key: move(k, -1), fg=C["muted"], padx=6).pack(side="right")

        fill()
        self.button(dlg, "Готово", dlg.destroy, fg=C["accent"], bg=C["bg"]).pack(anchor="e", pady=(8, 0))
        dlg.bind("<Escape>", lambda e: dlg.destroy())
        dlg.update_idletasks()
        dlg.geometry(f"+{max(0, self.root.winfo_x())}+{max(0, self.root.winfo_y() + 60)}")
        dlg.focus_force()
