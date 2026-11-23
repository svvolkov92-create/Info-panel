# -*- coding: utf-8 -*-
"""Окно панели: главное меню, трей, сквозные клики, размер и положение.
Примесь к классу Panel: методы работают с его состоянием (self)."""
from .core import *  # noqa: F401,F403 — общие константы и функции
from .widgets import ScrollArea  # noqa: F401
from .windows import (MatrixWindow, ReviewDialog, SearchWindow, TaskCard,  # noqa: F401
                      WeeklyReview, WeekView, WeekWindow)
from .tray import Tray  # noqa: F401
from .settings import SettingsWindow


class WindowMixin:
    # ===================== меню =====================
    def make_menu(self):
        m = tk.Menu(self.root, tearoff=0)
        m.add_command(label="Настройки…", command=self.open_settings)
        m.add_separator()
        self.var_top = tk.BooleanVar(value=self.s["topmost"])
        m.add_checkbutton(label="Поверх всех окон", variable=self.var_top, command=self.toggle_topmost)
        self.var_ct = tk.BooleanVar(value=self.s.get("click_through", False))
        m.add_checkbutton(label="Сквозные клики (нажать на панель — с зажатым Ctrl)",
                          variable=self.var_ct, command=lambda: self.set_click_through_mode(self.var_ct.get()))
        self.var_desk = tk.BooleanVar(value=self.s.get("desktop_layer", False))
        m.add_checkbutton(label="Под ярлыками рабочего стола", variable=self.var_desk,
                          command=lambda: self.set_desktop_layer(self.var_desk.get()))
        self.var_auto = tk.BooleanVar(value=autostart_enabled())
        m.add_checkbutton(label="Запускать вместе с Windows", variable=self.var_auto,
                          command=lambda: set_autostart(self.var_auto.get()))
        self.menu_hide_index = None
        m.add_separator()

        pos = tk.Menu(m, tearoff=0)
        self.var_pinned = tk.BooleanVar(value=self.s["pinned"])
        pos.add_checkbutton(label="Закрепить на текущем месте", variable=self.var_pinned,
                            command=self.toggle_pinned)
        pos.add_separator()
        self.var_anchor = tk.StringVar(value=self.s["anchor"])
        for key, label in ANCHORS.items():
            pos.add_radiobutton(label=label, variable=self.var_anchor, value=key,
                                command=lambda k=key: self.pin_to_anchor(k))
        pos.add_separator()
        pos.add_command(label="Задать координаты…", command=self.ask_coords)
        pos.add_command(label="Вернуть в угол экрана", command=self.reset_position)
        m.add_cascade(label="Положение", menu=pos)

        size = tk.Menu(m, tearoff=0)
        self.var_fixed = tk.BooleanVar(value=self.s["size_fixed"])
        size.add_checkbutton(label="Зафиксировать текущую ширину", variable=self.var_fixed,
                             command=lambda: self.set_fixed_size(self.var_fixed.get()))
        size.add_command(label="Задать ширину…", command=self.ask_size)
        size.add_command(label="Автоматическая ширина", command=lambda: self.set_fixed_size(False))
        lh = tk.Menu(size, tearoff=0)
        self.var_lh = tk.IntVar(value=self.s.get("tasks_max", 260))
        for v, label in ((160, "Низкий"), (260, "Средний"), (380, "Высокий"), (520, "Очень высокий")):
            lh.add_radiobutton(label=label, variable=self.var_lh, value=v,
                               command=lambda v=v: self.set_list_height(v))
        size.add_cascade(label="Предел высоты списка задач", menu=lh)
        m.add_cascade(label="Размер окна", menu=size)

        m.add_command(label="Блоки и их порядок…", command=self.blocks_dialog)
        m.add_command(label="Свернуть / развернуть все блоки", command=self.toggle_all)
        m.add_command(label="Сбросить высоту блоков", command=self.reset_all_block_heights)

        alpha = tk.Menu(m, tearoff=0)
        self.var_alpha = tk.DoubleVar(value=self.s["alpha"])
        for v in (1.0, 0.94, 0.85, 0.75, 0.6):
            alpha.add_radiobutton(label=f"{int(v * 100)}%", variable=self.var_alpha, value=v,
                                  command=self.set_alpha)
        m.add_cascade(label="Непрозрачность", menu=alpha)

        pomo = tk.Menu(m, tearoff=0)
        self.var_preset = tk.StringVar()
        for w, b, lg in POMO_PRESETS:
            pomo.add_radiobutton(label=f"{w} / {b} мин, длинный {lg}", variable=self.var_preset,
                                 value=f"{w}/{b}/{lg}",
                                 command=lambda w=w, b=b, lg=lg: self.set_preset(w, b, lg))
        pomo.add_command(label="Своя длительность…", command=self.ask_durations)
        pomo.add_command(label="Звуки и громкость…", command=self.sounds_dialog)
        pomo.add_separator()
        self.var_auto_break = tk.BooleanVar(value=self.s["auto_break"])
        pomo.add_checkbutton(label="Сразу запускать перерыв", variable=self.var_auto_break,
                             command=self.toggle_auto_break)
        self.var_focus = tk.BooleanVar(value=self.s["focus_mode"])
        pomo.add_checkbutton(label="Режим фокуса во время работы", variable=self.var_focus,
                             command=self.toggle_focus_setting)
        m.add_cascade(label="Помодоро", menu=pomo)

        plan = tk.Menu(m, tearoff=0)
        plan.add_command(label="Матрица Эйзенхауэра…", command=self.open_matrix)
        plan.add_command(label="Неделя…", command=self.open_week_window)
        plan.add_command(label="Разгрузить выбранный день…", command=self.unload_day)
        plan.add_command(label="Обзор недели…", command=self.open_weekly_review)
        plan.add_separator()
        plan.add_command(label="Лимиты дня…", command=self.ask_limits)
        self.var_review = tk.BooleanVar(value=self.s["review"])
        plan.add_checkbutton(label="Утренний разбор хвостов", variable=self.var_review,
                             command=lambda: (self.s.update(review=self.var_review.get()),
                                              self.save()))
        self.var_weekly = tk.BooleanVar(value=self.s["weekly_review"])
        plan.add_checkbutton(label="Обзор недели по пятницам", variable=self.var_weekly,
                             command=lambda: (self.s.update(weekly_review=self.var_weekly.get()),
                                              self.save()))
        m.add_cascade(label="Планирование", menu=plan)
        self.tpl_menu = tk.Menu(m, tearoff=0, postcommand=self.fill_template_menu)
        m.add_cascade(label="Шаблоны", menu=self.tpl_menu)
        undo = tk.Menu(m, tearoff=0)
        undo.add_command(label="Отменить   Ctrl+Z", command=self.undo)
        undo.add_command(label="Повторить   Ctrl+Y", command=self.redo)
        m.add_cascade(label="Правка", menu=undo)
        m.add_command(label="Поиск задач…   Ctrl+F", command=self.open_search)

        self.var_prod = tk.BooleanVar(value=self.s["prod_cal"])
        m.add_checkbutton(label="Производственный календарь РФ", variable=self.var_prod,
                          command=self.toggle_prod_cal)
        m.add_command(label="Убрать выполненные задачи дня", command=self.clear_done)
        m.add_separator()
        self.main_menu_tail = m.index("end")
        m.add_command(label="Выход", command=self.quit)
        self.menu = m

    def show_menu(self, e):
        self.var_pinned.set(self.s["pinned"])
        self.var_anchor.set(self.s["anchor"])
        self.var_fixed.set(self.s["size_fixed"])
        self.var_preset.set(f"{self.s['work']}/{self.s['break']}/{self.s['long']}")
        self.popup(self.menu, e)

    def toggle_topmost(self):
        self.s["topmost"] = self.var_top.get()
        self.root.attributes("-topmost", self.s["topmost"])
        self.save()

    def toggle_auto_break(self):
        self.s["auto_break"] = self.var_auto_break.get()
        self.save()

    def toggle_prod_cal(self):
        self.s["prod_cal"] = self.var_prod.get()
        self.save()
        self.render_calendar()

    # ===================== окно настроек =====================
    def open_settings(self):
        if self.settings_win:
            self.settings_win.win.lift()
            self.settings_win.win.focus_force()
            return
        self.settings_win = SettingsWindow(self)

    def set_weekend_hold(self, on):
        self.s["weekend_hold"] = bool(on)
        self.carry_over_tasks()  # выключили посреди выходных — хвосты сразу переносятся на сегодня
        self.rebase_undo()
        self.save()
        self.render_all()

    def set_alpha_percent(self, percent):
        self.var_alpha.set(round(percent / 100, 2))
        self.set_alpha()

    def set_task_font(self, size):
        size = max(7, min(16, int(size)))
        if size == self.s.get("task_font", 10):
            return
        self.s["task_font"] = size
        self.configure_task_fonts(size)  # Tk сам перерисует все метки с этими шрифтами
        self.drop_row_cache()
        self.render_tasks()
        self.save()
        self.request_render("tasks_layout")

    def set_task_gap(self, gap):
        gap = max(0, min(12, int(gap)))
        if gap == self.s.get("task_gap", 1):
            return
        self.s["task_gap"] = gap
        for _, row in self.task_rows:  # без перестройки списка — только отступы строк
            row.pack_configure(pady=gap)
        self.save()
        self.request_render("tasks_layout")

    def set_pomo_durations(self, work, brk, long_brk, cycle):
        if not (1 <= work <= 180 and 1 <= brk <= 60 and 1 <= long_brk <= 90 and 1 <= cycle <= 12):
            return
        if (work, brk, long_brk, cycle) == (self.s["work"], self.s["break"], self.s["long"], self.s["cycle"]):
            return
        self.s.update(work=work, long=long_brk, cycle=cycle, **{"break": brk})
        self.save()
        if not self.pomo_running:
            self.pomo_reset()
        self.render_pomo()

    def set_day_limits(self, q1, hours):
        if not (1 <= q1 <= 50 and 0.5 <= hours <= 24):
            return
        if (q1, hours) == (self.s["q1_limit"], float(self.s["day_hours"])):
            return
        self.s.update(q1_limit=q1, day_hours=hours)
        self.save()
        self.render_tasks()
        self.request_render("week")

    def set_alpha(self):
        self.s["alpha"] = self.var_alpha.get()
        self.root.attributes("-alpha", self.s["alpha"])
        self.save()
        if self.ct_active:  # Tk мог сбросить слоистый стиль — восстанавливаем
            set_click_through(self.root, True, self.s["alpha"])

    # ===================== сквозные клики =====================
    def set_click_through_mode(self, on):
        if on and not (IS_WIN and ctypes):
            self.var_ct.set(False)
            self.toast("Сквозные клики", "Работают только в Windows.", C["warn"], timeout=6000)
            return
        self.s["click_through"] = bool(on)
        self.var_ct.set(bool(on))
        self.save()
        self.apply_click_through()
        if on and not self.s.get("ct_hint_shown"):
            self.s["ct_hint_shown"] = True
            self.save()
            self.toast("Сквозные клики включены",
                       "Клики проходят сквозь панель к окнам под ней. Чтобы нажать на саму "
                       "панель, держите Ctrl. Выключить: Ctrl + правый клик → меню, "
                       "или меню значка в трее.", C["accent"], timeout=15000)

    def apply_click_through(self):
        """Ставит стиль окна по режиму и состоянию Ctrl; пока режим включён, следит за Ctrl."""
        mode = bool(self.s.get("click_through"))
        want = mode and not self.ct_peek
        if want != self.ct_active:
            if set_click_through(self.root, want, self.s["alpha"]):
                self.ct_active = want
            elif want:  # не вышло — режим выключаем, чтобы не обещать того, чего нет
                self.s["click_through"] = False
                mode = False
        self.update_pin_label()
        if self._ct_after:
            self.root.after_cancel(self._ct_after)
            self._ct_after = None
        if mode:
            self._ct_after = self.root.after(80, self._ct_poll)
        else:
            self.ct_peek = False

    def _ct_poll(self):
        self._ct_after = None
        peek = ctrl_pressed()
        if peek != self.ct_peek:
            self.ct_peek = peek
            self.apply_click_through()
        elif self.s.get("click_through"):  # ничего не изменилось — просто следим дальше
            self._ct_after = self.root.after(80, self._ct_poll)

    def quit(self):
        for card in list(self.cards.values()):
            card.close()
        for view in list(self.live_views):
            try:
                view.close()
            except Exception:
                log_error("Окно не закрылось при выходе:\n" + traceback.format_exc())
        if self._notes_after:
            self.save_notes()
        self.flush_save()
        if self.tray:
            self.tray.remove()
        for after_id in self.root.tk.splitlist(self.root.tk.call("after", "info")):
            self.root.after_cancel(after_id)  # иначе таймеры срабатывают уже после закрытия окна
        self.root.destroy()

    # ===================== трей =====================
    def init_tray(self):
        if not (IS_WIN and ctypes):
            return
        try:
            self.tray = Tray("Панель: задачи и календарь",
                             on_left=lambda: self.root.after(0, self.tray_click),
                             on_right=lambda: self.root.after(0, self.tray_menu),
                             on_show=lambda: self.root.after(0, self.rescue_panel))
        except Exception:
            log_error("Не удалось создать значок в трее:\n" + traceback.format_exc())
            self.tray = None
            return
        self.menu.insert_command(self.main_menu_tail, label="Скрыть в трей", command=self.hide_panel)

    def tray_menu(self):
        m = tk.Menu(self.root, tearoff=0)
        m.add_command(label="Скрыть панель" if not self.hidden else "Показать панель",
                      command=self.toggle_visible)
        if self.desk_active:
            m.add_command(label="Поднять поверх окон, чтобы поработать", command=self.raise_from_desktop)
        elif self.s.get("desktop_layer"):
            m.add_command(label="Вернуть под ярлыки", command=self.enter_desktop_layer)
        m.add_checkbutton(label="Под ярлыками рабочего стола", variable=self.var_desk,
                          command=lambda: self.set_desktop_layer(self.var_desk.get()))
        m.add_command(label="Вернуть в угол экрана", command=self.reset_position)
        m.add_command(label="Аварийно вернуть панель (сбросить режимы)", command=self.rescue_panel)
        m.add_command(label="Настройки…", command=self.open_settings)
        m.add_checkbutton(label="Поверх всех окон", variable=self.var_top, command=self.toggle_topmost)
        m.add_checkbutton(label="Сквозные клики", variable=self.var_ct,
                          command=lambda: self.set_click_through_mode(self.var_ct.get()))
        m.add_separator()
        m.add_command(label="Выход", command=self.quit)
        try:
            pt = wintypes.POINT()
            ctypes.windll.user32.GetCursorPos(ctypes.byref(pt))
            x, y = pt.x, pt.y
            ctypes.windll.user32.SetForegroundWindow(int(self.root.wm_frame(), 16))
        except Exception:
            x, y = self.root.winfo_pointerxy()
        try:
            m.tk_popup(x, y)
        finally:
            m.grab_release()

    def toggle_visible(self):
        if self.hidden:
            self.show_panel()
        else:
            self.hide_panel()

    def tray_click(self):
        """Левый клик по значку: из слоя рабочего стола — поднять для работы, иначе скрыть/показать."""
        if self.desk_active:
            self.raise_from_desktop()
            self.hidden = False
            self.set_visible(True)
        else:
            self.toggle_visible()

    def set_visible(self, visible):
        if IS_WIN and ctypes:
            try:
                native_show(self.root, visible)
                return
            except Exception:
                log_error("ShowWindow не сработал, пробую средствами Tk:\n" + traceback.format_exc())
        if visible:
            self.root.deiconify()
        else:
            self.root.withdraw()

    def hide_panel(self):
        self.hide_tip()
        self.hidden = True
        self.set_visible(False)

    def show_panel(self):
        self.hidden = False
        self.set_visible(True)
        self.apply_position()
        if not self.desk_active:
            self.root.lift()
            try:
                self.root.focus_force()
            except tk.TclError:
                pass
        if self.s.get("click_through"):  # стиль окна ставим заново на всякий случай
            self.ct_active = False
            self.apply_click_through()

    # ===================== под ярлыками рабочего стола =====================
    def set_desktop_layer(self, on):
        if on and not (IS_WIN and ctypes):
            self.var_desk.set(False)
            self.toast("Под ярлыками", "Работает только в Windows.", C["warn"], timeout=6000)
            return
        self.s["desktop_layer"] = bool(on)
        self.var_desk.set(bool(on))
        self.save()
        if on:
            self.enter_desktop_layer()
            if self.desk_active and not self.s.get("desk_hint_shown"):
                self.s["desk_hint_shown"] = True
                self.save()
                self.toast("Панель под ярлыками",
                           "Теперь она часть рабочего стола: не закрывает окна и не пропадает по Win+D, "
                           "но и нажимать на неё нельзя. Чтобы поработать с задачами — щёлкните по "
                           "значку в трее; вернуть под ярлыки — правый клик по значку.",
                           C["accent"], timeout=20000)
        else:
            self.leave_desktop_layer()

    def enter_desktop_layer(self):
        if self.desk_active:
            return
        try:
            parent = desktop_layer_window()
        except Exception:
            log_error("Не нашёл слой рабочего стола:\n" + traceback.format_exc())
            parent = None
        if not parent:
            self.s["desktop_layer"] = False
            self.var_desk.set(False)
            self.save()
            self.toast("Не получилось", "Не нашёл слой рабочего стола под ярлыками в этой версии "
                                        "Windows. Подробности в error.log.", C["danger"], timeout=12000)
            return
        if self.hidden:
            self.show_panel()
        self.exit_focus()
        self.hide_tip()
        if self.ct_active:  # сквозные клики дочернему окну не нужны: клики и так у рабочего стола
            set_click_through(self.root, False, self.s["alpha"])
            self.ct_active = False
        self.root.update_idletasks()
        x, y = self.root.winfo_rootx(), self.root.winfo_rooty()
        try:
            self.desk_origin = embed_in_desktop(self.root, parent, x, y)
        except Exception:
            log_error("Не удалось встроить панель в рабочий стол:\n" + traceback.format_exc())
            self.rescue_panel()
            return
        self.desk_active = True
        self.update_pin_label()
        if not self.s.get("desk_confirmed"):
            self.ask_desk_confirm()

    def ask_desk_confirm(self):
        """Не видно панель под ярлыками — сама вернётся через 15 секунд."""
        answered = {"ok": False}

        def yes():
            answered["ok"] = True
            self.s["desk_confirmed"] = True
            self.save()

        def timeout():
            if not answered["ok"] and self.desk_active:
                self.set_desktop_layer(False)
                self.toast("Вернул панель", "Под ярлыками её не было видно, поэтому режим выключен. "
                                            "Пришлите, пожалуйста, error.log — там сведения о рабочем столе.",
                           C["warn"], timeout=30000)

        self.toast("Панель видна под ярлыками?",
                   "Если нет — ничего не нажимайте: через 15 секунд она вернётся сама.",
                   C["accent"], timeout=15000,
                   actions=[("Да, видна", yes), ("Нет, вернуть", lambda: self.set_desktop_layer(False))])
        self.root.after(15500, timeout)

    def rescue_panel(self):
        """Аварийный возврат: обычное окно, без сквозных кликов, в углу экрана, поверх остальных."""
        if self.desk_active:
            self.leave_desktop_layer()
        self.s["desktop_layer"] = False
        self.var_desk.set(False)
        if self.s.get("click_through"):
            self.set_click_through_mode(False)
        self.hidden = False
        self.set_visible(True)
        self.reset_position()
        self.root.lift()
        self.root.attributes("-topmost", True)  # вытащить наверх…
        self.root.after(1500, lambda: self.root.attributes("-topmost", self.s["topmost"]))  # …и вернуть
        try:
            self.root.focus_force()
        except tk.TclError:
            pass
        self.save()

    def leave_desktop_layer(self):
        if not self.desk_active:
            return
        self.desk_active = False
        ox, oy = getattr(self, "desk_origin", (0, 0))
        try:
            release_from_desktop(self.root, self.root.winfo_x() + ox, self.root.winfo_y() + oy)
        except Exception:
            log_error("Не удалось вернуть окно из слоя рабочего стола:\n" + traceback.format_exc())
        self.root.attributes("-alpha", self.s["alpha"])  # прозрачность снимали при встраивании
        self.root.attributes("-topmost", self.s["topmost"])
        self.apply_position()
        self.root.lift()
        if self.s.get("click_through"):
            self.ct_active = False
            self.apply_click_through()
        self.update_pin_label()

    def raise_from_desktop(self):
        """Поднять для работы, не выключая режим: вернуть — из меню значка в трее."""
        self.leave_desktop_layer()
        try:
            self.root.focus_force()
        except tk.TclError:
            pass
        self.flash_status("вернуть под ярлыки — меню значка в трее", C["muted"])

    # ===================== размер и положение =====================
    def set_fixed_size(self, on, w=None):
        """Фиксируется только ширина: высота окна всегда равна сумме высот блоков."""
        if on:
            self.root.update_idletasks()
            self.s["w"] = max(MIN_W, int(w or self.root.winfo_width()))
        self.s["size_fixed"] = bool(on)
        self.save()
        self.apply_size()

    def apply_size(self):
        width = int(self.s["w"]) if self.s["size_fixed"] and self.s["w"] else WIDTH
        self.spacer.config(width=width)
        self.root.geometry("")  # размер окна — по содержимому, без явной высоты
        self.grip.place(relx=1.0, rely=1.0, anchor="se")
        tk.Misc.tkraise(self.grip)  # у Canvas lift() двигает фигуры, а не виджет
        self.render_tasks()
        self.render_stats()
        self.apply_position()

    def grip_start(self, e):
        """Уголок: по горизонтали — ширина окна, по вертикали — высота блока задач."""
        self.root.update_idletasks()
        body = self.sections["tasks"]["body"]
        tasks_h = body.winfo_height() if body.winfo_ismapped() else None
        self._grip = (e.x_root, e.y_root, self.root.winfo_width(), tasks_h)
        if not self.s["size_fixed"]:
            self.s["size_fixed"], self.s["w"] = True, self.root.winfo_width()

    def grip_move(self, e):
        """Как и для блоков: запоминаем, применяем не чаще раза за кадр."""
        self._grip_target = (e.x_root, e.y_root)
        if getattr(self, "_grip_after", None) is None:
            self._grip_after = self.root.after(RESIZE_FRAME_MS, self._apply_grip)

    def _apply_grip(self):
        self._grip_after = None
        x0, y0, w0, tasks_h0 = self._grip
        ex, ey = self._grip_target
        w = max(MIN_W, w0 + ex - x0)
        if w != self.s["w"]:
            self.s["w"] = w
            self.spacer.config(width=w)
        if tasks_h0 is not None:
            h = max(int(30 * self.scale()), tasks_h0 + ey - y0)
            if h != self.s["block_h"].get("tasks"):
                self.s["block_h"]["tasks"] = h
                body = self.sections["tasks"]["body"]
                body.pack_propagate(False)
                body.config(height=h)
                self.layout_tasks(self.tasks_canvas.yview()[0])

    def grip_end(self, e):
        if getattr(self, "_grip_after", None) is not None:
            self.root.after_cancel(self._grip_after)
            self._apply_grip()
        self.apply_block_heights()
        self.apply_collapsed()
        self.save()
        tk.Misc.tkraise(self.grip)
        self.render_tasks()
        self.render_stats()
        self.apply_position()

    def ask_size(self):
        self.root.update_idletasks()

        def ok(vals):
            try:
                w = int(vals[0])
            except ValueError:
                return "Введите целое число"
            if w < MIN_W:
                return f"Не меньше {MIN_W}"
            self.set_fixed_size(True, w)
            return None

        self.input_dialog("Ширина панели",
                          f"Ширина в пикселях, минимум {MIN_W}.\n"
                          "Высота складывается из высот блоков: меняйте её полоской внизу блока.",
                          [("Ширина", self.root.winfo_width())], ok)

    def apply_position(self):
        self.root.update_idletasks()
        w, h = self.root.winfo_reqwidth(), self.root.winfo_reqheight()
        a = self.s["anchor"]
        if a in ANCHORS:
            l, t, r, b = work_area(self.root)
            x = {"nw": l + MARGIN, "sw": l + MARGIN, "ne": r - w - MARGIN,
                 "se": r - w - MARGIN, "c": (l + r - w) // 2}[a]
            y = {"nw": t + MARGIN, "ne": t + MARGIN, "sw": b - h - MARGIN,
                 "se": b - h - MARGIN, "c": (t + b - h) // 2}[a]
        else:
            vl, vt, vr, vb = virtual_screen(self.root)
            x, y = self.s.get("x"), self.s.get("y")
            if x is None or y is None or not (vl - w // 2 < x < vr - 40) or not (vt <= y < vb - 40):
                l, t, r, b = work_area(self.root)
                x, y = r - w - 40, t + 60
        if self.desk_active:
            # дочернее окно слоя рабочего стола: координаты считаются от угла родителя
            ox, oy = getattr(self, "desk_origin", (0, 0))
            x, y = x - ox, y - oy
        geo = f"+{int(x)}+{int(y)}"
        if self.root.geometry().split("+", 1)[-1] != geo[1:]:
            self.root.geometry(geo)

    def on_configure(self, e):
        if e.widget is self.root and self.s["anchor"] in ANCHORS:
            self.root.after_idle(self.apply_position)

    def reset_position(self):
        if self.hidden:
            self.show_panel()
        self.s.update(anchor="free", x=None, pinned=False)
        self.save()
        self.apply_position()
        self.update_pin_label()

    def toggle_pinned(self):
        self.s["pinned"] = self.var_pinned.get()
        if not self.s["pinned"] or self.s["anchor"] not in ANCHORS:
            self.s["anchor"] = "free"
            self.s["x"], self.s["y"] = self.root.winfo_x(), self.root.winfo_y()
        self.save()
        self.update_pin_label()

    def pin_to_anchor(self, key):
        self.s["anchor"] = key
        self.s["pinned"] = True
        self.save()
        self.apply_position()
        self.update_pin_label()

    def ask_coords(self):
        vl, vt, vr, vb = virtual_screen(self.root)

        def ok(vals):
            try:
                x, y = int(vals[0]), int(vals[1])
            except ValueError:
                return "Введите целые числа"
            if not (vl - WIDTH // 2 < x < vr - 40 and vt <= y < vb - 40):
                return "Эта точка за пределами экрана"
            self.s.update(x=x, y=y, anchor="free", pinned=True)
            self.save()
            self.apply_position()
            self.update_pin_label()
            return None

        self.input_dialog("Положение панели",
                          f"Левый верхний угол панели, в пикселях.\n"
                          f"Доступно: X от {vl} до {vr - 40}, Y от {vt} до {vb - 40}.",
                          [("X", self.root.winfo_x()), ("Y", self.root.winfo_y())], ok, "Закрепить")

    def update_pin_label(self):
        parts = []
        if self.s["pinned"]:
            a = self.s["anchor"]
            parts.append("◆ " + (ANCHORS[a].lower() if a in ANCHORS else "закреплено"))
            cursor = "arrow"
        else:
            cursor = "fleur"
        if getattr(self, "desk_active", False):
            parts.append("▣ под ярлыками")
        if self.s.get("click_through"):
            parts.append("✋ можно нажимать" if getattr(self, "ct_peek", False) else "⇢ сквозь · Ctrl")
        self.lbl_pin.config(text="\n".join(parts),
                            fg=C["accent"] if getattr(self, "ct_peek", False) else C["faint"])
        for w in self.drag_widgets:
            w.config(cursor=cursor)

    def drag_start(self, e):
        self._dragging = not self.s["pinned"]
        self._dx = e.x_root - self.root.winfo_x()
        self._dy = e.y_root - self.root.winfo_y()

    def drag_move(self, e):
        if self._dragging:
            self.root.geometry(f"+{e.x_root - self._dx}+{e.y_root - self._dy}")

    def drag_end(self, e):
        if self._dragging:
            self.s["anchor"] = "free"
            self.s["x"], self.s["y"] = self.root.winfo_x(), self.root.winfo_y()
            self.save()
        self._dragging = False
