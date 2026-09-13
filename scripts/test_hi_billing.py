#!/usr/bin/env python3
"""Verify home-internet invoice math matches the historical Flutter FIFO formula."""
from __future__ import annotations

import os
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
sys.path.insert(0, '/opt')

import lightnet_hi_billing as hb  # noqa: E402


def _customer(**kwargs):
    base = {
        'id': '28525',
        'name': 'Doctor',
        'plan_amount': 40000,
        'currency': 'TZS',
        'schedule': 'monthly',
        'start_date': datetime(2025, 8, 31, 0, 0, 0),
        'billing_day_of_month': 28,
        'billing_weekday': None,
    }
    base.update(kwargs)
    return base


def test_doctor_hand_calc():
    c = _customer()
    now = datetime(2026, 9, 13, 15, 0, 0)
    assert hb.months_due_up_to(c, now) == 12
    approved = [{'amount_paid': 400000, 'paid_at': datetime(2026, 1, 1)}]
    periods, credit = hb.list_period_statuses(c, [], approved, now)
    assert len(periods) == 12
    assert periods[0]['start'].date().isoformat() == '2025-09-28'
    assert periods[-1]['start'].date().isoformat() == '2026-08-28'
    statement = hb.build_statement(c, periods, credit, approved, now)
    assert statement['total_due_amount'] == 480000
    assert statement['total_paid_amount'] == 400000
    assert statement['outstanding_amount'] == 80000
    assert statement['this_month_bill'] == 40000
    assert statement['arrears'] + statement['this_month_balance'] == 80000
    assert statement['credit'] == 0
    assert statement['pay_now'] == 80000
    print('ok doctor hand-calc outstanding=80000 pay_now=80000')


def test_first_due_inconsistency_preserved():
    """listPeriodStatuses keeps start-day equality; monthsDue does not."""
    c = _customer(start_date=datetime(2025, 8, 28, 10, 0, 0), billing_day_of_month=28)
    now = datetime(2026, 9, 13, 12, 0, 0)
    assert hb._monthly_first_due_list(c).date().isoformat() == '2025-08-28'
    assert hb._monthly_first_due_count(c).date().isoformat() == '2025-09-28'
    print('ok firstDue inconsistency preserved')


def test_credit_and_fifo():
    c = _customer()
    now = datetime(2026, 9, 13, 15, 0, 0)
    approved = [{'amount_paid': 500000, 'paid_at': datetime(2026, 1, 1)}]
    periods, credit = hb.list_period_statuses(c, [], approved, now)
    statement = hb.build_statement(c, periods, credit, approved, now)
    assert statement['outstanding_amount'] == -20000
    assert statement['credit'] == 20000
    assert statement['pay_now'] == 0
    assert statement['arrears'] == 0
    print('ok credit 20000 after 500000 paid vs 480000 billed')


def _live_mysql():
    import ast
    import mysql.connector
    src = open('/opt/app.py').read()
    cfg = None
    for node in ast.parse(src).body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == 'db_config':
                    cfg = ast.literal_eval(node.value)
    if not cfg:
        raise RuntimeError('db_config not found')
    conn = mysql.connector.connect(**cfg)
    cur = conn.cursor(dictionary=True)
    return conn, cur


def test_live_backfill_matches_engine():
    conn, cur = _live_mysql()
    try:
        hb.ensure_invoice_table(cur)
        cur.execute("SELECT * FROM hi_customers WHERE archived=0")
        rows = cur.fetchall() or []
        mismatches = []
        for row in rows:
            statement = hb.compute_customer_statement(cur, row, now=datetime(2026, 9, 13, 15, 0, 0))
            expected = hb._round_money(statement['total_due_amount'] - statement['total_paid_amount'])
            got = hb._round_money(statement['outstanding_amount'])
            if expected != got:
                mismatches.append((row['id'], expected, got))
            pay = statement['pay_now']
            if pay != max(got, 0) and not (got < 0 and pay == 0):
                if got > 0 and pay != got:
                    mismatches.append((row['id'], 'pay_now', pay, got))
        print('live customers=%s mismatches=%s' % (len(rows), mismatches))
        assert not mismatches
        print('ok live engine identity for all active customers')
    finally:
        cur.close()
        conn.close()


def main():
    test_doctor_hand_calc()
    test_first_due_inconsistency_preserved()
    test_credit_and_fifo()
    if '--live' in sys.argv:
        test_live_backfill_matches_engine()
    print('ALL TESTS PASSED')


if __name__ == '__main__':
    main()
