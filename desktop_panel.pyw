# -*- coding: utf-8 -*-
"""Запуск информационной панели. Рядом с этим файлом должна лежать папка panel.

Двойной клик — запуск без консоли. Тесты: python run_tests.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

try:
    from panel.app import main
except Exception:
    import traceback
    error = traceback.format_exc()
    try:
        import tkinter as tk
        from tkinter import messagebox
        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("Панель: не запускается",
                             "Не удалось загрузить программу. Рядом с desktop_panel.pyw должна лежать "
                             "папка panel со всеми файлами.\n\n" + error[-1200:])
        root.destroy()
    except Exception:
        print(error, file=sys.stderr)
    sys.exit(1)

if __name__ == "__main__":
    main()
