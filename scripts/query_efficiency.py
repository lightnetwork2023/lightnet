"""Shared MySQL query bounds used by Flask and unit tests.

Keeps dashboard and payment summaries on range predicates (index-friendly)
instead of DATE(timestamp) or unbounded SELECT *.
"""
from datetime import datetime, timedelta


DEFAULT_LIST_LIMIT = 500
SEARCH_PAYMENTS_LIMIT = 100
SEARCH_PHONE_MIN_DIGITS = 9
OWNER_USAGE_ROW_CAP = 5000


def clamp_limit(raw, default=DEFAULT_LIST_LIMIT, maximum=2000):
    try:
        value = int(raw)
    except (TypeError, ValueError):
        value = default
    return max(1, min(value, maximum))


def phone_digits(phone):
    return ''.join(ch for ch in str(phone or '') if ch.isdigit())


def search_phone_ok(phone):
    return len(phone_digits(phone)) >= SEARCH_PHONE_MIN_DIGITS


def payment_summary_bounds(now):
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    last_24h = now - timedelta(hours=24)
    start_of_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    start_of_last_month = (start_of_month - timedelta(days=1)).replace(
        day=1, hour=0, minute=0, second=0, microsecond=0
    )
    start_of_year = now.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)
    return {
        'today_start': today_start,
        'last_24h': last_24h,
        'start_of_month': start_of_month,
        'start_of_last_month': start_of_last_month,
        'start_of_year': start_of_year,
        'days_in_month': (now - start_of_month).days + 1,
    }


def payment_summary_sql(extra_where=''):
    return (
        "SELECT "
        "COALESCE(SUM(CASE WHEN timestamp >= %s THEN amount END), 0) AS today, "
        "COALESCE(SUM(CASE WHEN timestamp >= %s THEN amount END), 0) AS last_24_hours, "
        "COALESCE(SUM(CASE WHEN timestamp >= %s AND timestamp < %s THEN amount END), 0) AS last_month, "
        "COALESCE(SUM(CASE WHEN timestamp >= %s THEN amount END), 0) AS this_month, "
        "COALESCE(SUM(CASE WHEN timestamp >= %s THEN amount END), 0) AS this_year "
        "FROM payments WHERE 1=1 " + extra_where
    )


def payment_summary_params(bounds, extra_params=None):
    params = [
        bounds['today_start'],
        bounds['last_24h'],
        bounds['start_of_last_month'],
        bounds['start_of_month'],
        bounds['start_of_month'],
        bounds['start_of_year'],
    ]
    if extra_params:
        params.extend(extra_params)
    return params


def daily_average(this_month, days_in_month):
    if days_in_month <= 0:
        return 0.0
    return float(this_month) / days_in_month
