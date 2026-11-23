"""Быстрые проверки логики без окна: разбор ввода, даты, склонения."""
import datetime as dt
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from panel.core import fmt_est, parse_quick, plural, short_date  # noqa: E402

TODAY = dt.date(2026, 11, 23)  # понедельник


class ParseQuick(unittest.TestCase):
    def test_plain_text(self):
        q = parse_quick("Купить хлеб", TODAY)
        self.assertEqual(q["text"], "Купить хлеб")
        self.assertIsNone(q["date"])

    def test_time_tags_estimate(self):
        q = parse_quick("15:00 отчёт #работа ~2ч", TODAY)
        self.assertEqual(q["time"], "15:00")
        self.assertEqual(q["tags"], ["работа"])
        self.assertEqual(q["est"], 120)
        self.assertEqual(q["text"], "отчёт")

    def test_date_prefix(self):
        q = parse_quick("25.11 позвонить", TODAY)
        self.assertEqual(q["date"], dt.date(2026, 11, 25))


class Formatting(unittest.TestCase):
    def test_plural(self):
        self.assertEqual(plural(1, "задача", "задачи", "задач"), "1 задача")
        self.assertEqual(plural(3, "задача", "задачи", "задач"), "3 задачи")
        self.assertEqual(plural(11, "задача", "задачи", "задач"), "11 задач")

    def test_est(self):
        self.assertEqual(fmt_est(30), "30 мин")
        self.assertEqual(fmt_est(90), "1,5 ч")

    def test_short_date(self):
        self.assertEqual(short_date(dt.date(2026, 12, 1), TODAY), "01.12")
        self.assertEqual(short_date(dt.date(2027, 1, 2), TODAY), "02.01.2027")


if __name__ == "__main__":
    unittest.main()
