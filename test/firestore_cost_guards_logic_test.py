"""Mirrors lib/services/firestore_cost_guards.dart so we can run tests on this server."""
from datetime import datetime, timedelta
import unittest

MAX_PAYMENT_QUERY_DAYS = 31


def payment_query_bounds(period, now, custom_start=None, custom_end=None):
    if period == "today":
        start = datetime(now.year, now.month, now.day)
        end = start + timedelta(days=1)
    elif period == "last24Hours":
        start = now - timedelta(hours=24)
        end = now
    elif period == "thisMonth":
        start = datetime(now.year, now.month, 1)
        end = datetime(now.year + (1 if now.month == 12 else 0), 1 if now.month == 12 else now.month + 1, 1)
    elif period == "lastMonth":
        start = datetime(now.year, now.month - 1, 1) if now.month > 1 else datetime(now.year - 1, 12, 1)
        end = datetime(now.year, now.month, 1)
    elif period in ("thisYear", "allTime"):
        return None
    elif period == "custom":
        if custom_start is None or custom_end is None:
            raise ValueError("Custom period requires start and end dates")
        start = datetime(custom_start.year, custom_start.month, custom_start.day)
        end = datetime(custom_end.year, custom_end.month, custom_end.day) + timedelta(days=1)
    else:
        raise ValueError(f"Unknown period: {period}")

    if (end - start).days > MAX_PAYMENT_QUERY_DAYS:
        raise ValueError("span exceeds max")
    return start, end


def inline_wan_stats(data):
    nested = data.get("wan_stats")
    if isinstance(nested, dict):
        return dict(nested)
    live = data.get("live_speed")
    total = data.get("wan_traffic_total")
    if not isinstance(live, dict) and not isinstance(total, dict):
        return None
    live = live if isinstance(live, dict) else {}
    total = total if isinstance(total, dict) else {}
    return {
        "rx_bps": live.get("rx_bps", 0),
        "tx_bps": live.get("tx_bps", 0),
        "rx_bytes": total.get("rx_bytes", 0),
        "tx_bytes": total.get("tx_bytes", 0),
    }


class GuardsTest(unittest.TestCase):
    now = datetime(2026, 9, 11, 12, 0, 0)

    def test_today(self):
        start, end = payment_query_bounds("today", self.now)
        self.assertEqual(start, datetime(2026, 9, 11))
        self.assertEqual(end, datetime(2026, 9, 12))

    def test_this_month(self):
        start, end = payment_query_bounds("thisMonth", self.now)
        self.assertEqual(start, datetime(2026, 9, 1))
        self.assertEqual(end, datetime(2026, 10, 1))
        self.assertEqual((end - start).days, 30)

    def test_this_year_uses_metadata(self):
        self.assertIsNone(payment_query_bounds("thisYear", self.now))

    def test_custom_requires_dates(self):
        with self.assertRaises(ValueError):
            payment_query_bounds("custom", self.now)

    def test_custom_too_long(self):
        with self.assertRaises(ValueError):
            payment_query_bounds(
                "custom",
                self.now,
                datetime(2026, 1, 1),
                datetime(2026, 9, 11),
            )

    def test_custom_week(self):
        start, end = payment_query_bounds(
            "custom", self.now, datetime(2026, 9, 1), datetime(2026, 9, 7)
        )
        self.assertEqual(start, datetime(2026, 9, 1))
        self.assertEqual(end, datetime(2026, 9, 8))

    def test_inline_wan(self):
        self.assertIsNone(inline_wan_stats({}))
        flask = inline_wan_stats({
            "live_speed": {"rx_bps": 1000, "tx_bps": 2000},
            "wan_traffic_total": {"rx_bytes": 10, "tx_bytes": 20},
        })
        self.assertEqual(flask["rx_bps"], 1000)
        self.assertEqual(flask["tx_bytes"], 20)
        self.assertEqual(inline_wan_stats({"wan_stats": {"rx_bps": 5}})["rx_bps"], 5)


if __name__ == "__main__":
    unittest.main()
