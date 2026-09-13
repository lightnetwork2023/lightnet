"""Home-internet invoices and account statements.

Period math is a line-for-line port of Flutter HomeInternetService so stored
invoices keep the same outstanding as the live FIFO calculation. Payments and
plan snapshots are not rewritten; invoices are derived and re-allocated.

Notifications are out of scope here.
"""
from __future__ import annotations

import logging
import uuid
from datetime import datetime, timedelta
from decimal import Decimal

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

log = logging.getLogger(__name__)

BILLING_TZ_NAME = 'Africa/Dar_es_Salaam'


def billing_now(now=None) -> datetime:
    if now is not None:
        return now.replace(tzinfo=None) if getattr(now, 'tzinfo', None) else now
    if ZoneInfo is not None:
        return datetime.now(ZoneInfo(BILLING_TZ_NAME)).replace(tzinfo=None)
    return datetime.now()


def _dt(v):
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.replace(tzinfo=None) if v.tzinfo else v
    if hasattr(v, 'timestamp'):
        try:
            return datetime.utcfromtimestamp(v.timestamp())
        except Exception:
            pass
    if isinstance(v, str):
        s = v.strip().replace('Z', '').replace('T', ' ')
        if '.' in s:
            s = s.split('.', 1)[0]
        s = s[:19]
        for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y-%m-%d'):
            try:
                return datetime.strptime(s, fmt)
            except Exception:
                continue
        return None
    return None


def _iso(v):
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.isoformat()
    return str(v)


def _money(v) -> float:
    if v is None:
        return 0.0
    if isinstance(v, Decimal):
        return float(v)
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(v)
    except Exception:
        return 0.0


def _round_money(v) -> float:
    return round(_money(v), 2)


def dart_date(year, month, day, hour=0, minute=0, second=0, microsecond=0):
    """Match Dart DateTime(year, month, day, ...) including month overflow."""
    y = year + (month - 1) // 12
    m = ((month - 1) % 12) + 1
    if m <= 0:
        y -= 1
        m += 12
    return datetime(y, m, day, hour, minute, second, microsecond)


def dart_weekday(dt: datetime) -> int:
    """Dart DateTime.weekday: Monday=1 ... Sunday=7."""
    return dt.weekday() + 1


def dart_days_between(later: datetime, earlier: datetime) -> int:
    """Dart later.difference(earlier).inDays (truncates toward zero)."""
    micros = int((later - earlier).total_seconds() * 1_000_000)
    return int(micros // 86_400_000_000)


def ensure_invoice_table(cur) -> None:
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS hi_invoices (
            id VARCHAR(64) NOT NULL PRIMARY KEY,
            customer_id VARCHAR(16) NOT NULL,
            invoice_no VARCHAR(64) NOT NULL,
            period_start DATETIME NOT NULL,
            period_end DATETIME NOT NULL,
            issue_date DATETIME NOT NULL,
            due_date DATETIME NOT NULL,
            amount DECIMAL(12,2) NOT NULL DEFAULT 0,
            amount_paid DECIMAL(12,2) NOT NULL DEFAULT 0,
            balance DECIMAL(12,2) NOT NULL DEFAULT 0,
            status VARCHAR(16) NOT NULL DEFAULT 'open',
            currency VARCHAR(8) NOT NULL DEFAULT 'TZS',
            schedule VARCHAR(16) NOT NULL DEFAULT 'monthly',
            source VARCHAR(16) NOT NULL DEFAULT 'live',
            created_at DATETIME NULL,
            updated_at DATETIME NULL,
            extra_json JSON NULL,
            UNIQUE KEY uq_hi_inv_cust_period (customer_id, period_start),
            UNIQUE KEY uq_hi_inv_no (invoice_no),
            KEY idx_hi_inv_cust_due (customer_id, due_date),
            KEY idx_hi_inv_status (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


def customer_view(row: dict, now=None) -> dict:
    now = billing_now(now)
    start = _dt(row.get('start_date')) or now
    schedule = (row.get('schedule') or 'monthly').strip().lower()
    if schedule not in ('weekly', 'monthly'):
        schedule = 'monthly'
    return {
        'id': str(row.get('id') or ''),
        'name': row.get('name') or '',
        'plan_amount': _money(row.get('plan_amount')),
        'currency': row.get('currency') or 'TZS',
        'schedule': schedule,
        'start_date': start,
        'billing_day_of_month': row.get('billing_day_of_month'),
        'billing_weekday': row.get('billing_weekday'),
    }


def _anchor_day(c: dict) -> int:
    day = c.get('billing_day_of_month')
    if day is None:
        day = c['start_date'].day
    try:
        day = int(day)
    except Exception:
        day = c['start_date'].day
    return max(1, min(28, day))


def _anchor_weekday(c: dict) -> int:
    wd = c.get('billing_weekday')
    if wd is None:
        return dart_weekday(c['start_date'])
    try:
        wd = int(wd)
    except Exception:
        return dart_weekday(c['start_date'])
    if wd < 1 or wd > 7:
        return dart_weekday(c['start_date'])
    return wd


def _monthly_first_due_count(c: dict) -> datetime:
    """firstDue used by _monthsDueUpTo / _monthPeriod (!isAfter)."""
    anchor = _anchor_day(c)
    start = c['start_date']
    first = dart_date(start.year, start.month, anchor, start.hour, start.minute, start.second, start.microsecond)
    if not (first > start):
        first = dart_date(first.year, first.month + 1, anchor, first.hour, first.minute, first.second, first.microsecond)
    return first


def _monthly_first_due_list(c: dict) -> datetime:
    """firstDue used by listPeriodStatuses (isBefore only)."""
    anchor = _anchor_day(c)
    start = c['start_date']
    first = dart_date(start.year, start.month, anchor, start.hour, start.minute, start.second, start.microsecond)
    if first < start:
        first = dart_date(first.year, first.month + 1, anchor, first.hour, first.minute, first.second, first.microsecond)
    return first


def _weekly_first_due_count(c: dict) -> datetime:
    """firstDue used by _weeksDueUpTo / _weekPeriod (diff==0 adds 7 days)."""
    anchor = _anchor_weekday(c)
    first = c['start_date']
    diff = anchor - dart_weekday(first)
    if diff > 0:
        first = first + timedelta(days=diff)
    elif diff < 0:
        first = first + timedelta(days=(7 + diff))
    else:
        first = first + timedelta(days=7)
    return first


def _weekly_first_due_list(c: dict) -> datetime:
    """firstDue used by listPeriodStatuses (diff==0 keeps startDate)."""
    anchor = _anchor_weekday(c)
    first = c['start_date']
    diff = anchor - dart_weekday(first)
    if diff > 0:
        first = first + timedelta(days=diff)
    elif diff < 0:
        first = first + timedelta(days=(7 + diff))
    return first


def months_due_up_to(c: dict, ref: datetime) -> int:
    first = _monthly_first_due_count(c)
    if ref < first:
        return 0
    months_diff = (ref.year - first.year) * 12 + (ref.month - first.month)
    due_this = dart_date(first.year, first.month + months_diff, _anchor_day(c), first.hour, first.minute, first.second, first.microsecond)
    return months_diff if ref < due_this else months_diff + 1


def weeks_due_up_to(c: dict, ref: datetime) -> int:
    first = _weekly_first_due_count(c)
    if ref < first:
        return 0
    days_diff = dart_days_between(ref, first)
    weeks_diff = days_diff // 7
    due_this = first + timedelta(days=7 * weeks_diff)
    return weeks_diff if ref < due_this else weeks_diff + 1


def periods_due_up_to_now(c: dict, now: datetime) -> int:
    if c['schedule'] == 'weekly':
        return weeks_due_up_to(c, now)
    return months_due_up_to(c, now)


def month_period(c: dict, ref: datetime) -> dict:
    anchor = _anchor_day(c)
    first = _monthly_first_due_count(c)
    start_date = c['start_date']
    if ref < first:
        return {
            'start': start_date,
            'end': first - timedelta(seconds=1),
            'due': first,
        }
    months = (ref.year - first.year) * 12 + (ref.month - first.month) + 1
    start = dart_date(first.year, first.month + (months - 1), anchor, first.hour, first.minute, first.second, first.microsecond)
    end = dart_date(start.year, start.month + 1, anchor) - timedelta(seconds=1)
    return {'start': start, 'end': end, 'due': start}


def week_period(c: dict, ref: datetime) -> dict:
    first = _weekly_first_due_count(c)
    start_date = c['start_date']
    if ref < first:
        return {
            'start': start_date,
            'end': first - timedelta(seconds=1),
            'due': first,
        }
    weeks = (dart_days_between(ref, first) // 7) + 1
    start = first + timedelta(days=7 * (weeks - 1))
    end = start + timedelta(days=7) - timedelta(seconds=1)
    return {'start': start, 'end': end, 'due': start}


def current_due_period(c: dict, now: datetime) -> dict:
    if c['schedule'] == 'weekly':
        return week_period(c, now)
    return month_period(c, now)


def required_for(date: datetime, snapshots: list, plan_amount: float) -> float:
    if not snapshots:
        return _money(plan_amount)
    current = snapshots[0]
    for snap in snapshots:
        eff = snap['effective_from']
        if not (date < eff):
            current = snap
        else:
            break
    return _money(current['amount'])


def list_period_statuses(c: dict, snapshots: list, approved: list, now: datetime) -> list:
    periods_due = periods_due_up_to_now(c, now)
    if periods_due <= 0:
        remaining = sum(_money(p.get('amount_paid')) for p in approved)
        return [], remaining

    periods = []
    if c['schedule'] == 'weekly':
        first = _weekly_first_due_list(c)
        for i in range(periods_due):
            start = first + timedelta(days=7 * i)
            end = start + timedelta(days=7) - timedelta(seconds=1)
            periods.append({'start': start, 'end': end, 'due': start})
    else:
        anchor = _anchor_day(c)
        first = _monthly_first_due_list(c)
        for i in range(periods_due):
            start = dart_date(first.year, first.month + i, anchor, first.hour, first.minute, first.second, first.microsecond)
            end = dart_date(start.year, start.month + 1, anchor) - timedelta(seconds=1)
            periods.append({'start': start, 'end': end, 'due': start})

    remaining = sum(_money(p.get('amount_paid')) for p in approved)
    results = []
    for p in periods:
        required = required_for(p['start'], snapshots, c['plan_amount'])
        allocated = required if remaining >= required else (remaining if remaining > 0 else 0.0)
        remaining = remaining - allocated
        if allocated >= required:
            state = 'paid'
        elif allocated > 0:
            state = 'partial'
        else:
            state = 'unpaid'
        results.append({
            'start': p['start'],
            'end': p['end'],
            'due': p['due'],
            'required_amount': required,
            'paid_amount': allocated,
            'balance': required - allocated,
            'state': state,
        })
    results.append({'_unallocated': remaining})
    credit = results.pop()
    for row in results:
        row['credit_after'] = credit['_unallocated']
    return results, credit['_unallocated']


def load_snapshots(cur, customer_id) -> list:
    cur.execute(
        """
        SELECT amount, currency, effective_from
        FROM hi_plan_snapshots
        WHERE customer_id=%s
        ORDER BY effective_from ASC
        """,
        (customer_id,),
    )
    rows = cur.fetchall() or []
    out = []
    for row in rows:
        out.append({
            'amount': _money(row.get('amount')),
            'currency': row.get('currency') or 'TZS',
            'effective_from': _dt(row.get('effective_from')) or datetime(1970, 1, 1),
        })
    return out


def load_approved_payments(cur, customer_id) -> list:
    cur.execute(
        """
        SELECT amount_paid, approved_at, created_at
        FROM hi_payments
        WHERE customer_id=%s AND status='approved'
        """,
        (customer_id,),
    )
    rows = cur.fetchall() or []
    items = []
    for row in rows:
        paid_at = _dt(row.get('approved_at')) or _dt(row.get('created_at')) or datetime(1970, 1, 1)
        items.append({
            'amount_paid': _money(row.get('amount_paid')),
            'paid_at': paid_at,
        })
    items.sort(key=lambda p: p['paid_at'])
    return items


def invoice_no_for(customer_id, period_start: datetime) -> str:
    return 'HI-%s-%s' % (customer_id, period_start.strftime('%Y%m%d'))


def public_invoice(row: dict, now=None) -> dict:
    now = billing_now(now)
    due = _dt(row.get('due_date')) or _dt(row.get('period_start'))
    days_overdue = 0
    if due is not None:
        days_overdue = (now.date() - due.date()).days
    amount = _round_money(row.get('amount'))
    paid = _round_money(row.get('amount_paid'))
    balance = _round_money(row.get('balance') if row.get('balance') is not None else (amount - paid))
    status = row.get('status') or ('paid' if balance <= 0 else ('partial' if paid > 0 else 'open'))
    return {
        'id': row.get('id'),
        'customer_id': row.get('customer_id'),
        'invoice_no': row.get('invoice_no'),
        'period_start': _iso(row.get('period_start')),
        'period_end': _iso(row.get('period_end')),
        'issue_date': _iso(row.get('issue_date') or row.get('period_start')),
        'due_date': _iso(due),
        'amount': amount,
        'amount_paid': paid,
        'balance': balance,
        'status': status,
        'currency': row.get('currency') or 'TZS',
        'schedule': row.get('schedule') or 'monthly',
        'source': row.get('source') or 'live',
        'days_overdue': days_overdue,
        'created_at': _iso(row.get('created_at')),
        'updated_at': _iso(row.get('updated_at')),
    }


def _aging_buckets(invoices: list, now: datetime) -> dict:
    buckets = {
        'current': 0.0,
        'days_1_30': 0.0,
        'days_31_60': 0.0,
        'days_61_90': 0.0,
        'days_90_plus': 0.0,
    }
    for inv in invoices:
        balance = _money(inv.get('balance'))
        if balance <= 0:
            continue
        due = _dt(inv.get('due_date')) or _dt(inv.get('period_start'))
        days = (now.date() - due.date()).days if due else 0
        if days <= 0:
            buckets['current'] += balance
        elif days <= 30:
            buckets['days_1_30'] += balance
        elif days <= 60:
            buckets['days_31_60'] += balance
        elif days <= 90:
            buckets['days_61_90'] += balance
        else:
            buckets['days_90_plus'] += balance
    return {k: _round_money(v) for k, v in buckets.items()}


def build_statement(c: dict, periods: list, credit: float, approved: list, now: datetime) -> dict:
    total_due = sum(_money(p['required_amount']) for p in periods)
    total_paid = sum(_money(p.get('amount_paid')) for p in approved)
    outstanding = total_due - total_paid
    latest = current_due_period(c, now)
    last_paid = None
    for p in approved:
        at = p.get('paid_at')
        if at is not None and (last_paid is None or at > last_paid):
            last_paid = at

    current = periods[-1] if periods else None
    this_month_bill = _money(current['required_amount']) if current else 0.0
    this_month_paid = _money(current['paid_amount']) if current else 0.0
    this_month_balance = _money(current['balance']) if current else 0.0
    arrears = sum(_money(p['balance']) for p in periods[:-1]) if periods else 0.0
    credit_amt = _money(credit)
    pay_now = outstanding if outstanding > 0 else 0.0
    is_overdue = outstanding > 0 and now > latest['due']

    invoices = []
    for p in periods:
        invoices.append({
            'invoice_no': invoice_no_for(c['id'], p['start']),
            'period_start': p['start'],
            'period_end': p['end'],
            'issue_date': p['start'],
            'due_date': p['due'],
            'amount': p['required_amount'],
            'amount_paid': p['paid_amount'],
            'balance': p['balance'],
            'status': 'paid' if p['state'] == 'paid' else ('partial' if p['state'] == 'partial' else 'open'),
            'state': p['state'],
            'currency': c['currency'],
            'schedule': c['schedule'],
            'customer_id': c['id'],
        })

    return {
        'account_number': c['id'],
        'currency': c['currency'],
        'schedule': c['schedule'],
        'as_of': _iso(now),
        'periods_due': len(periods),
        'total_due_amount': _round_money(total_due),
        'total_paid_amount': _round_money(total_paid),
        'outstanding_amount': _round_money(outstanding),
        'this_month_bill': _round_money(this_month_bill),
        'this_month_paid': _round_money(this_month_paid),
        'this_month_balance': _round_money(this_month_balance),
        'arrears': _round_money(arrears),
        'credit': _round_money(credit_amt),
        'pay_now': _round_money(pay_now),
        'overdue': bool(is_overdue),
        'next_due_date': _iso(latest['due']),
        'last_paid_at': _iso(last_paid),
        'current_invoice_no': invoices[-1]['invoice_no'] if invoices else None,
        'invoice_count': len(invoices),
        'aging': _aging_buckets(invoices, now),
        'invoices': [public_invoice(inv, now) for inv in invoices],
        'periods': [
            {
                'start': _iso(p['start']),
                'end': _iso(p['end']),
                'due': _iso(p['due']),
                'required_amount': _round_money(p['required_amount']),
                'paid_amount': _round_money(p['paid_amount']),
                'balance': _round_money(p['balance']),
                'state': p['state'],
                'invoice_no': invoice_no_for(c['id'], p['start']),
            }
            for p in periods
        ],
    }


def _persist_invoices(cur, customer_id, statement: dict, source: str) -> None:
    ensure_invoice_table(cur)
    now_utc = datetime.utcnow()
    for inv in statement.get('invoices') or []:
        period_start = _dt(inv.get('period_start'))
        if period_start is None:
            continue
        invoice_no = inv.get('invoice_no') or invoice_no_for(customer_id, period_start)
        cur.execute(
            """
            SELECT id, source FROM hi_invoices
            WHERE customer_id=%s AND period_start=%s
            LIMIT 1
            """,
            (customer_id, period_start),
        )
        existing = cur.fetchone()
        payload = (
            _dt(inv.get('period_end')),
            _dt(inv.get('issue_date')) or period_start,
            _dt(inv.get('due_date')) or period_start,
            _round_money(inv.get('amount')),
            _round_money(inv.get('amount_paid')),
            _round_money(inv.get('balance')),
            inv.get('status') or 'open',
            inv.get('currency') or 'TZS',
            inv.get('schedule') or 'monthly',
            now_utc,
        )
        if existing:
            cur.execute(
                """
                UPDATE hi_invoices
                SET period_end=%s, issue_date=%s, due_date=%s,
                    amount=%s, amount_paid=%s, balance=%s, status=%s,
                    currency=%s, schedule=%s, updated_at=%s
                WHERE id=%s
                """,
                payload + (existing['id'],),
            )
            inv['id'] = existing['id']
            inv['source'] = existing.get('source') or source
        else:
            iid = uuid.uuid4().hex
            try:
                cur.execute(
                    """
                    INSERT INTO hi_invoices (
                        id, customer_id, invoice_no, period_start, period_end,
                        issue_date, due_date, amount, amount_paid, balance,
                        status, currency, schedule, source, created_at, updated_at
                    ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        iid,
                        customer_id,
                        invoice_no,
                        period_start,
                    ) + payload[:-1] + (source, now_utc, now_utc),
                )
            except Exception:
                invoice_no = '%s-%s' % (invoice_no, iid[:6])
                cur.execute(
                    """
                    INSERT INTO hi_invoices (
                        id, customer_id, invoice_no, period_start, period_end,
                        issue_date, due_date, amount, amount_paid, balance,
                        status, currency, schedule, source, created_at, updated_at
                    ) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        iid,
                        customer_id,
                        invoice_no,
                        period_start,
                    ) + payload[:-1] + (source, now_utc, now_utc),
                )
            inv['id'] = iid
            inv['invoice_no'] = invoice_no
            inv['source'] = source


def _cache_status(cur, customer_id, statement: dict) -> None:
    import json
    cache = {k: v for k, v in statement.items() if k not in ('invoices', 'periods')}
    cache['current_invoice_no'] = statement.get('current_invoice_no')
    cur.execute(
        "UPDATE hi_customers SET status_json=%s WHERE id=%s",
        (json.dumps(cache, default=str), customer_id),
    )


def compute_customer_statement(cur, row: dict, now=None) -> dict:
    now = billing_now(now)
    c = customer_view(row, now)
    snapshots = load_snapshots(cur, c['id'])
    approved = load_approved_payments(cur, c['id'])
    periods, credit = list_period_statuses(c, snapshots, approved, now)
    return build_statement(c, periods, credit, approved, now)


def materialize_customer(cur, customer_id, now=None, source='live') -> dict:
    ensure_invoice_table(cur)
    cur.execute("SELECT * FROM hi_customers WHERE id=%s", (customer_id,))
    row = cur.fetchone()
    if not row:
        return {}
    statement = compute_customer_statement(cur, row, now=now)
    _persist_invoices(cur, str(customer_id), statement, source)
    _cache_status(cur, str(customer_id), statement)
    return statement


def materialize_all(cur, now=None, source='backfill', archived=False) -> dict:
    ensure_invoice_table(cur)
    now = billing_now(now)
    cur.execute(
        "SELECT id FROM hi_customers WHERE archived=%s",
        (1 if archived else 0,),
    )
    ids = [r['id'] for r in (cur.fetchall() or [])]
    results = []
    for cid in ids:
        statement = materialize_customer(cur, cid, now=now, source=source)
        results.append({
            'customer_id': cid,
            'outstanding_amount': statement.get('outstanding_amount'),
            'pay_now': statement.get('pay_now'),
            'invoice_count': statement.get('invoice_count'),
            'overdue': statement.get('overdue'),
        })
    return {
        'as_of': _iso(now),
        'source': source,
        'count': len(results),
        'customers': results,
    }


def list_invoices(cur, customer_id) -> list:
    ensure_invoice_table(cur)
    cur.execute(
        """
        SELECT * FROM hi_invoices
        WHERE customer_id=%s
        ORDER BY period_start ASC
        """,
        (customer_id,),
    )
    return [public_invoice(r) for r in (cur.fetchall() or [])]


def delete_invoices(cur, customer_id) -> None:
    ensure_invoice_table(cur)
    cur.execute("DELETE FROM hi_invoices WHERE customer_id=%s", (customer_id,))
