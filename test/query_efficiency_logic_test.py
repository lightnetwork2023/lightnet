#!/usr/bin/env python3
import os
import sys
import unittest
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts'))
from query_efficiency import (
    SEARCH_PAYMENTS_LIMIT,
    clamp_limit,
    daily_average,
    payment_summary_bounds,
    payment_summary_params,
    payment_summary_sql,
    search_phone_ok,
)


class QueryEfficiencyTest(unittest.TestCase):
    def test_clamp_limit(self):
        self.assertEqual(clamp_limit(None), 500)
        self.assertEqual(clamp_limit('12'), 12)
        self.assertEqual(clamp_limit('99999'), 2000)
        self.assertEqual(clamp_limit(0), 1)

    def test_search_phone(self):
        self.assertFalse(search_phone_ok('07659'))
        self.assertTrue(search_phone_ok('0765908208'))
        self.assertEqual(SEARCH_PAYMENTS_LIMIT, 100)

    def test_summary_bounds_and_sql(self):
        now = datetime(2026, 9, 11, 12, 0, 0)
        bounds = payment_summary_bounds(now)
        self.assertEqual(bounds['today_start'], datetime(2026, 9, 11))
        self.assertEqual(bounds['start_of_month'], datetime(2026, 9, 1))
        self.assertEqual(bounds['start_of_last_month'], datetime(2026, 8, 1))
        self.assertEqual(bounds['start_of_year'], datetime(2026, 1, 1))
        self.assertEqual(bounds['days_in_month'], 11)
        sql = payment_summary_sql(" AND location = %s")
        self.assertIn('timestamp >= %s', sql)
        self.assertNotIn('DATE(timestamp)', sql)
        params = payment_summary_params(bounds, ['Kigamboni'])
        self.assertEqual(len(params), 7)
        self.assertEqual(params[-1], 'Kigamboni')
        self.assertAlmostEqual(daily_average(1100, 11), 100.0)


if __name__ == '__main__':
    unittest.main()
