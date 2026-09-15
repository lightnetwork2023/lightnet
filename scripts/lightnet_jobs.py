"""Server jobs that replaced Cloud Functions (SA monthly credit, Nokia stale)."""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from decimal import Decimal

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover
    ZoneInfo = None

log = logging.getLogger(__name__)
TZ_NAME = 'Africa/Dar_es_Salaam'


def _now():
    if ZoneInfo is not None:
        return datetime.now(ZoneInfo(TZ_NAME)).replace(tzinfo=None)
    return datetime.now()


def _dt(v):
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.replace(tzinfo=None) if v.tzinfo else v
    if isinstance(v, (int, float, Decimal)):
        try:
            return datetime.utcfromtimestamp(float(v))
        except Exception:
            return None
    if isinstance(v, dict):
        if 'iso' in v:
            return _dt(v.get('iso'))
        secs = v.get('seconds') or v.get('_seconds')
        if secs is not None:
            return datetime.utcfromtimestamp(float(secs))
        return None
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


def _money(v) -> float:
    if v is None:
        return 0.0
    if isinstance(v, Decimal):
        return float(v)
    try:
        return float(v)
    except Exception:
        return 0.0


def _sa_share(data: dict) -> float:
    share = 0.63
    commission = data.get('commission')
    if isinstance(commission, dict):
        parsed = _money(commission.get('superagent'))
        if parsed:
            share = parsed
    elif data.get('superagent_percent') is not None:
        parsed = _money(data.get('superagent_percent'))
        if parsed:
            share = parsed
    return min(1.0, max(0.0, share))


def _prev_month_label(now=None) -> str:
    now = now or _now()
    if now.month == 1:
        return '%04d-12' % (now.year - 1)
    return '%04d-%02d' % (now.year, now.month - 1)


def last_month_revenue(cur, locations):
    if not locations:
        return 0.0
    placeholders = ','.join(['%s'] * len(locations))
    now = _now()
    first_this = datetime(now.year, now.month, 1)
    if first_this.month == 1:
        first_prev = datetime(first_this.year - 1, 12, 1)
    else:
        first_prev = datetime(first_this.year, first_this.month - 1, 1)
    cur.execute(
        """
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM payments
        WHERE COALESCE(kind, IF(phone = '12345678', 'agent_stock', 'customer'))
              NOT IN ('agent_stock', 'test')
          AND timestamp >= %s AND timestamp < %s
          AND location IN ({})
        """.format(placeholders),
        [first_prev, first_this, *locations],
    )
    row = cur.fetchone() or {}
    return _money(row.get('total'))


def mark_stale_nokia_beacons(cur, now=None) -> dict:
    import lightnet_app_docs as ad
    now = now or _now()
    stale_after = now - timedelta(hours=6)
    offline_after = now - timedelta(hours=24)
    beacons = ad.list_docs(cur, 'nokia_beacons')
    changed = 0
    skipped = 0
    for row in beacons:
        data = row.get('data') or {}
        status = (data.get('status') or 'unknown').strip().lower() or 'unknown'
        last_seen = _dt(data.get('last_seen'))
        if last_seen is None:
            skipped += 1
            continue
        new_status = status
        if last_seen < offline_after:
            new_status = 'offline'
        elif last_seen < stale_after and status == 'online':
            new_status = 'stale'
        if new_status != status:
            ad.set_doc(cur, 'nokia_beacons', row['id'], {'status': new_status}, merge=True)
            changed += 1
    return {
        'as_of': now.isoformat(),
        'checked': len(beacons),
        'changed': changed,
        'skipped': skipped,
    }


def monthly_sa_balance_update(cur, now=None, force=False, dry_run=False) -> dict:
    import lightnet_app_docs as ad
    now = now or _now()
    month_str = _prev_month_label(now)
    agents = ad.query_docs(cur, 'users', [{'field': 'role', 'op': '==', 'value': 'superagent'}])
    results = []
    for row in agents:
        data = dict(row.get('data') or {})
        uid = row['id']
        locations = data.get('locations') if isinstance(data.get('locations'), list) else []
        locations = [str(x).strip() for x in locations if str(x).strip()]
        if not locations and data.get('location'):
            locations = [str(data.get('location')).strip()]
        settlement = data.get('last_monthly_settlement') if isinstance(data.get('last_monthly_settlement'), dict) else {}
        already = str(settlement.get('month') or '') == month_str
        if not locations:
            results.append({'uid': uid, 'name': data.get('name') or data.get('email'), 'skipped': 'no_locations'})
            continue
        if already and not force:
            results.append({
                'uid': uid,
                'name': data.get('name') or data.get('email'),
                'skipped': 'already_settled',
                'month': month_str,
            })
            continue
        last_month_total = last_month_revenue(cur, locations)
        sa_share = _sa_share(data)
        sa_revenue = last_month_total * sa_share
        regs = ad.query_docs(cur, 'field_registrations', [{'field': 'owner_id', 'op': '==', 'value': uid}])
        total_deduction = sum(_money((r.get('data') or {}).get('monthly_deduction')) for r in regs)
        net_amount = max(0.0, sa_revenue - total_deduction)
        payload = {
            'withdrawable_balance': {ad.SPECIAL: 'increment', 'n': net_amount},
            'last_monthly_settlement': {
                'month': month_str,
                'gross_revenue': last_month_total,
                'sa_revenue': sa_revenue,
                'deductions': total_deduction,
                'net_credited': net_amount,
                'processed_at': now.isoformat(),
            },
        }
        if not dry_run:
            ad.set_doc(cur, 'users', uid, payload, merge=True)
        results.append({
            'uid': uid,
            'name': data.get('name') or data.get('email'),
            'locations': locations,
            'month': month_str,
            'gross_revenue': last_month_total,
            'sa_share': sa_share,
            'sa_revenue': sa_revenue,
            'deductions': total_deduction,
            'net_credited': net_amount,
            'dry_run': dry_run,
        })
    return {
        'as_of': now.isoformat(),
        'month': month_str,
        'dry_run': dry_run,
        'force': force,
        'count': len(results),
        'superagents': results,
    }


def register_job_routes(app, db_config, firebase_auth=None):
    from flask import jsonify, request
    import mysql.connector
    import lightnet_home_internet as hi

    def _conn():
        conn = mysql.connector.connect(**db_config)
        cur = conn.cursor(dictionary=True)
        return conn, cur

    def _auth(required_roles=None):
        actor = hi.resolve_actor(request, firebase_auth, db_config=db_config)
        if not actor:
            return None, (jsonify({'success': False, 'error': 'Sign in required'}), 401)
        if required_roles and actor.get('role') not in required_roles:
            return None, (jsonify({'success': False, 'error': 'Not allowed'}), 403)
        return actor, None

    @app.route('/api/jobs/nokia-stale', methods=['POST', 'GET'])
    def job_nokia_stale():
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        conn, cur = _conn()
        try:
            result = mark_stale_nokia_beacons(cur)
            conn.commit()
            return jsonify({'success': True, **result})
        finally:
            cur.close()
            conn.close()

    @app.route('/api/jobs/sa-monthly-balance', methods=['POST', 'GET'])
    def job_sa_monthly_balance():
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        data = request.get_json(silent=True) or {}
        dry_run = str(request.args.get('dry_run') or data.get('dry_run') or '0') in ('1', 'true', 'yes')
        force = str(request.args.get('force') or data.get('force') or '0') in ('1', 'true', 'yes')
        conn, cur = _conn()
        try:
            result = monthly_sa_balance_update(cur, force=force, dry_run=dry_run)
            if not dry_run:
                conn.commit()
            return jsonify({'success': True, **result})
        finally:
            cur.close()
            conn.close()

    return app
