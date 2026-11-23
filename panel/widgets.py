# -*- coding: utf-8 -*-
"""Общие элементы интерфейса."""
from .core import *  # noqa: F401,F403 — общие константы и функции


class ScrollArea:
    """Холст с вложенным фреймом и тонкой полосой прокрутки, как у списка задач."""

    def __init__(self, panel, parent):
        self.p = panel
        self.fill = False
        self.wrap = tk.Frame(parent, bg=C["card"])
        self.sb = tk.Canvas(self.wrap, width=6, height=1, bg=C["card"], highlightthickness=0,
                            cursor="hand2")
        self.canvas = tk.Canvas(self.wrap, width=1, height=1, bg=C["card"],
                                highlightthickness=0, yscrollincrement=1)
        self.canvas.pack(side="left", fill="both", expand=True)
        self.frame = tk.Frame(self.canvas, bg=C["card"])
        self.win = self.canvas.create_window((0, 0), window=self.frame, anchor="nw")
        self.canvas.bind("<Configure>", self._on_configure)
        self.canvas.config(yscrollcommand=self._update_sb)
        self.thumb = self.sb.create_rectangle(0, 0, 6, 0, fill=C["faint"], width=0)
        self.sb.bind("<ButtonPress-1>", self._press)
        self.sb.bind("<B1-Motion>", self._drag)
        self.sb.bind("<Configure>", lambda e: self._update_sb(*self.canvas.yview()))
        self.sb.bind("<Enter>", lambda e: self.sb.itemconfig(self.thumb, fill=C["accent"]))
        self.sb.bind("<Leave>", lambda e: self.sb.itemconfig(self.thumb, fill=C["faint"]))
        panel.scroll_areas.append(self)

    def layout(self, fill, max_h):
        """fill=True — занять всю высоту блока; иначе высота по содержимому, но не больше max_h."""
        self.fill = fill
        pos = self.canvas.yview()[0]
        self.frame.update_idletasks()
        h = self.frame.winfo_reqheight()
        if fill:
            self.canvas.config(height=40, scrollregion=(0, 0, 0, h))
            self.p.root.update_idletasks()
            limit = max(self.canvas.winfo_height(), 1)
        else:
            limit = max_h
            self.canvas.config(height=max(1, min(h, limit)), scrollregion=(0, 0, 0, h))
        if h > limit + 1:
            if not self.sb.winfo_manager():
                self.sb.pack(side="right", fill="y", padx=(4, 0))
            self.canvas.yview_moveto(pos)
        else:
            self.sb.pack_forget()
            self.canvas.yview_moveto(0)

    def _on_configure(self, e):
        self.canvas.itemconfigure(self.win, width=e.width)
        if self.fill:
            need = self.frame.winfo_reqheight() > e.height + 1
            if need != bool(self.sb.winfo_manager()):
                self.p.root.after_idle(lambda: self.layout(True, 0))

    def _update_sb(self, first, last):
        first, last = float(first), float(last)
        self._view = (first, last)
        h = max(self.sb.winfo_height(), 1)
        self.sb.coords(self.thumb, 0, first * h, 6, min(max(last * h, first * h + 16), h))

    def _press(self, e):
        first, last = getattr(self, "_view", (0.0, 1.0))
        frac = e.y / max(self.sb.winfo_height(), 1)
        if not first <= frac <= last:
            self.canvas.yview_moveto(frac - (last - first) / 2)
            first, last = self.canvas.yview()
        self._start = (e.y, first)

    def _drag(self, e):
        y0, first0 = self._start
        self.canvas.yview_moveto(first0 + (e.y - y0) / max(self.sb.winfo_height(), 1))

    def scroll(self, pixels):
        if self.sb.winfo_manager():
            self.canvas.yview_scroll(int(pixels), "units")

    def unregister(self):
        if self in self.p.scroll_areas:
            self.p.scroll_areas.remove(self)
