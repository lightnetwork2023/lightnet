"""Generic app document store — replaces Firestore collections except Auth."""
from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime

log = logging.getLogger(__name__)

SPECIAL = '__fv'


def ensure_tables(cur) -> None:
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS app_docs (
            collection VARCHAR(255) NOT NULL,
            doc_id VARCHAR(191) NOT NULL,
            data_json LONGTEXT NOT NULL,
            created_at DATETIME NULL,
            updated_at DATETIME NOT NULL,
            PRIMARY KEY (collection, doc_id),
            KEY idx_app_coll_created (collection, created_at),
            KEY idx_app_coll_updated (collection, updated_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )


def _now():
    return datetime.utcnow()


def _iso(v):
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.replace(microsecond=0).isoformat()
    return str(v)


def _dt(v):
    if v is None:
        return None
    if isinstance(v, datetime):
        return v.replace(tzinfo=None) if v.tzinfo else v
    if isinstance(v, (int, float)):
        n = int(v)
        if n > 9999999999:
            return datetime.utcfromtimestamp(n / 1000.0)
        return datetime.utcfromtimestamp(n)
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


def _loads(raw):
    if raw is None:
        return {}
    if isinstance(raw, dict):
        return raw
    try:
        return json.loads(raw)
    except Exception:
        return {}


def _dumps(data):
    return json.dumps(data if data is not None else {}, default=str)


def new_id() -> str:
    return uuid.uuid4().hex


def _is_special(v):
    return isinstance(v, dict) and v.get(SPECIAL)


def _resolve_value(v, now=None):
    now = now or _now()
    if _is_special(v):
        kind = v.get(SPECIAL)
        if kind == 'serverTimestamp':
            return _iso(now)
        if kind == 'timestamp':
            return v.get('iso') or _iso(_dt(v.get('value')) or now)
        if kind == 'delete':
            return None
        if kind == 'increment':
            return float(v.get('n') or 0)
    if isinstance(v, dict):
        return {k: _resolve_value(x, now) for k, x in v.items() if not (_is_special(x) and x.get(SPECIAL) == 'delete')}
    if isinstance(v, list):
        return [_resolve_value(x, now) for x in v]
    return v


def _deep_merge(dst, src, now=None):
    now = now or _now()
    if not isinstance(dst, dict):
        dst = {}
    for k, v in (src or {}).items():
        if _is_special(v):
            kind = v.get(SPECIAL)
            if kind == 'delete':
                dst.pop(k, None)
            elif kind == 'increment':
                try:
                    dst[k] = float(dst.get(k) or 0) + float(v.get('n') or 0)
                except Exception:
                    dst[k] = float(v.get('n') or 0)
            elif kind == 'serverTimestamp':
                dst[k] = _iso(now)
            elif kind == 'timestamp':
                dst[k] = v.get('iso') or _iso(_dt(v.get('value')) or now)
            else:
                dst[k] = _resolve_value(v, now)
        elif isinstance(v, dict) and isinstance(dst.get(k), dict):
            _deep_merge(dst[k], v, now)
        else:
            dst[k] = _resolve_value(v, now)
    return dst


def _extract_created(data: dict):
    for key in ('created_at', 'createdAt', 'timestamp', 'submitted_at'):
        if key in (data or {}):
            dt = _dt(data.get(key))
            if dt:
                return dt
    return None


def get_doc(cur, collection, doc_id):
    cur.execute(
        "SELECT collection, doc_id, data_json, created_at, updated_at FROM app_docs WHERE collection=%s AND doc_id=%s",
        (collection, str(doc_id)),
    )
    row = cur.fetchone()
    if not row:
        return None
    return {
        'id': row['doc_id'],
        'collection': row['collection'],
        'data': _loads(row['data_json']),
        'created_at': _iso(row.get('created_at')),
        'updated_at': _iso(row.get('updated_at')),
    }


def set_doc(cur, collection, doc_id, data, merge=False):
    now = _now()
    existing = get_doc(cur, collection, doc_id)
    if merge and existing:
        merged = _deep_merge(dict(existing.get('data') or {}), data or {}, now)
    else:
        merged = _resolve_value(data or {}, now)
        if not isinstance(merged, dict):
            merged = {}
    created = _extract_created(merged) or (existing or {}).get('created_at')
    created_dt = _dt(created) or (None if existing else now)
    cur.execute(
        """
        INSERT INTO app_docs (collection, doc_id, data_json, created_at, updated_at)
        VALUES (%s, %s, %s, %s, %s)
        ON DUPLICATE KEY UPDATE
            data_json=VALUES(data_json),
            created_at=COALESCE(VALUES(created_at), created_at),
            updated_at=VALUES(updated_at)
        """,
        (collection, str(doc_id), _dumps(merged), created_dt, now),
    )
    return {'id': str(doc_id), 'collection': collection, 'data': merged}


def delete_doc(cur, collection, doc_id):
    cur.execute("DELETE FROM app_docs WHERE collection=%s AND doc_id=%s", (collection, str(doc_id)))
    return cur.rowcount > 0


def _nested_get(data, field):
    if data is None:
        return None
    if '.' not in field:
        return data.get(field) if isinstance(data, dict) else None
    cur = data
    for part in field.split('.'):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(part)
    return cur


def _cmp(a, b):
    da, db = _dt(a), _dt(b)
    if da and db:
        a, b = da, db
    try:
        if a is None and b is None:
            return 0
        if a is None:
            return -1
        if b is None:
            return 1
        if a < b:
            return -1
        if a > b:
            return 1
        return 0
    except Exception:
        sa, sb = str(a), str(b)
        return (sa > sb) - (sa < sb)


def _filter_value(val):
    if _is_special(val) and val.get(SPECIAL) == 'timestamp':
        return val.get('iso')
    return val


def _match(data, filt):
    field = filt.get('field')
    op = filt.get('op') or '=='
    val = _filter_value(filt.get('value'))
    got = _nested_get(data, field)
    if op == '==':
        if isinstance(got, bool) or isinstance(val, bool):
            return bool(got) == bool(val)
        return got == val or str(got) == str(val)
    if op == '!=':
        return not _match(data, {'field': field, 'op': '==', 'value': val})
    if op == '>':
        return _cmp(got, val) > 0
    if op == '>=':
        return _cmp(got, val) >= 0
    if op == '<':
        return _cmp(got, val) < 0
    if op == '<=':
        return _cmp(got, val) <= 0
    if op == 'in':
        values = val if isinstance(val, list) else [val]
        return got in values or str(got) in [str(x) for x in values]
    if op == 'array-contains':
        return isinstance(got, list) and (val in got or str(val) in [str(x) for x in got])
    return False


def list_docs(cur, collection):
    cur.execute(
        "SELECT collection, doc_id, data_json, created_at, updated_at FROM app_docs WHERE collection=%s",
        (collection,),
    )
    out = []
    for row in cur.fetchall() or []:
        out.append({
            'id': row['doc_id'],
            'collection': row['collection'],
            'data': _loads(row['data_json']),
            'created_at': _iso(row.get('created_at')),
            'updated_at': _iso(row.get('updated_at')),
        })
    return out


def query_docs(cur, collection, filters=None, order_by=None, limit=None):
    filters = filters or []
    created_filters = [f for f in filters if f.get('field') in ('created_at', 'createdAt', 'timestamp')]
    other_filters = [f for f in filters if f not in created_filters]
    sql = "SELECT collection, doc_id, data_json, created_at, updated_at FROM app_docs WHERE collection=%s"
    params = [collection]
    for f in created_filters:
        op = {'==': '=', '!=': '<>', '>': '>', '>=': '>=', '<': '<', '<=': '<='}.get(f.get('op'))
        if not op:
            other_filters.append(f)
            continue
        sql += " AND created_at %s %%s" % op
        params.append(_dt(_filter_value(f.get('value'))) or _filter_value(f.get('value')))
    cur.execute(sql, params)
    rows = []
    for row in cur.fetchall() or []:
        data = _loads(row['data_json'])
        if all(_match(data, f) for f in other_filters):
            rows.append({
                'id': row['doc_id'],
                'collection': row['collection'],
                'data': data,
                'created_at': _iso(row.get('created_at')),
                'updated_at': _iso(row.get('updated_at')),
            })
    if order_by:
        field = order_by.get('field')
        desc = bool(order_by.get('descending'))
        rows.sort(key=lambda r: _nested_get(r['data'], field) or '', reverse=desc)
    if limit:
        rows = rows[: int(limit)]
    return rows


def query_mysql_payments(cur, filters=None, order_by=None, limit=None, location_ids=None):
    filters = filters or []
    sql = """
        SELECT id, location, amount, duration, username, timestamp, phone, payment_method
        FROM payments WHERE 1=1
    """
    params = []
    leftover = []
    if location_ids is not None:
        ids = [str(x).strip() for x in location_ids if str(x).strip()]
        if not ids:
            return []
        sql += " AND location IN (" + ",".join(["%s"] * len(ids)) + ")"
        params.extend(ids)
    for f in filters:
        field = f.get('field')
        op = {'==': '=', '!=': '<>', '>': '>', '>=': '>=', '<': '<', '<=': '<='}.get(f.get('op'))
        val = f.get('value')
        if field in ('created_at', 'timestamp') and op:
            sql += " AND timestamp %s %%s" % op
            params.append(_dt(_filter_value(val)) or _filter_value(val))
        elif field == 'location' and op:
            sql += " AND location %s %%s" % op
            params.append(val)
        else:
            leftover.append(f)
    order_field = (order_by or {}).get('field')
    desc = bool((order_by or {}).get('descending'))
    if order_field in ('created_at', 'timestamp', None):
        sql += " ORDER BY timestamp " + ('DESC' if desc else 'ASC')
    if limit:
        sql += " LIMIT %s"
        params.append(int(limit) if not leftover else int(limit) * 5)
    cur.execute(sql, params)
    rows = []
    for row in cur.fetchall() or []:
        data = {
            'location': row.get('location'),
            'amount': float(row.get('amount') or 0),
            'duration': row.get('duration'),
            'username': row.get('username'),
            'voucher': row.get('username'),
            'phone': row.get('phone'),
            'payment_method': row.get('payment_method'),
            'created_at': _iso(row.get('timestamp')),
        }
        if all(_match(data, f) for f in leftover):
            rows.append({'id': str(row['id']), 'collection': 'payments', 'data': data})
    if leftover and order_by and order_by.get('field') not in ('created_at', 'timestamp', None):
        rows.sort(key=lambda r: _nested_get(r['data'], order_by.get('field')) or '', reverse=desc)
    if limit:
        rows = rows[: int(limit)]
    return rows


def server_ts():
    return {SPECIAL: 'serverTimestamp'}


def store_connect(db_config):
    import mysql.connector
    conn = mysql.connector.connect(**db_config)
    cur = conn.cursor(dictionary=True)
    ensure_tables(cur)
    ensure_owner_tenancy(cur)
    conn.commit()
    return conn, cur


def docs_update(db_config, collection, doc_id, data):
    conn, cur = store_connect(db_config)
    try:
        set_doc(cur, collection, str(doc_id), data, merge=True)
        conn.commit()
    finally:
        cur.close(); conn.close()


def docs_list(db_config, collection):
    conn, cur = store_connect(db_config)
    try:
        return list_docs(cur, collection)
    finally:
        cur.close(); conn.close()


DEFAULT_MIKROTIK_OWNER_EMAIL = 'lightnetwork2023@gmail.com'
_OWNER_TENANCY_READY = False
OWNER_SCOPED_COLLECTIONS = frozenset({
    'mikrotik_devices',
    'sites',
    'expenses',
    'float_transactions',
    'technician_vouchers',
    'tech_checkins',
    'sa_withdrawal_requests',
    'technician_one_user_logs',
    'technician_one_user_daily',
    'technician_one_user_monthly',
})
OPS_BACKFILL_COLLECTIONS = (
    'expenses',
    'float_transactions',
    'technician_vouchers',
    'tech_checkins',
    'sa_withdrawal_requests',
    'technician_one_user_logs',
    'technician_one_user_daily',
    'technician_one_user_monthly',
)


def coerce_owner_id(val):
    if val is None or val == '':
        return None
    try:
        return int(val)
    except (TypeError, ValueError):
        return None


def default_mikrotik_owner_id(cur):
    try:
        cur.execute(
            "SELECT id FROM mikrotik_owners WHERE email=%s AND status='active' LIMIT 1",
            (DEFAULT_MIKROTIK_OWNER_EMAIL,),
        )
        row = cur.fetchone()
        if row:
            return int(row['id'] if isinstance(row, dict) else row[0])
        cur.execute("SELECT id FROM mikrotik_owners ORDER BY id ASC LIMIT 1")
        row = cur.fetchone()
        if row:
            return int(row['id'] if isinstance(row, dict) else row[0])
    except Exception as e:
        log.warning('default_mikrotik_owner_id: %s', e)
    return None


def same_owner(a, b):
    aa, bb = coerce_owner_id(a), coerce_owner_id(b)
    return aa is not None and aa == bb


def pick_actor_owner_id(email_owner_id, user_owner_id, default_owner_id):
    """Owner email wins so a registered owner is not kept on the LightNet tenant."""
    return (
        coerce_owner_id(email_owner_id)
        or coerce_owner_id(user_owner_id)
        or coerce_owner_id(default_owner_id)
    )


def site_location_candidates(site):
    name = str((site or {}).get('name') or '').strip()
    if name:
        return [name]
    sid = (site or {}).get('id')
    return ['site-%s' % sid] if sid is not None else []


def scoped_location_doc_id(owner_id, loc_id):
    oid = coerce_owner_id(owner_id)
    name = str(loc_id or '').strip()
    if not oid or not name:
        return name
    prefix = '%s::' % oid
    if name.startswith(prefix):
        return name
    return prefix + name


def public_location_id(doc):
    loc_id = str((doc or {}).get('id') or '')
    data = (doc or {}).get('data') or {}
    name = str(data.get('name') or '').strip()
    oid = coerce_owner_id(data.get('owner_id'))
    prefix = '%s::' % oid if oid is not None else ''
    if prefix and loc_id.startswith(prefix):
        return loc_id[len(prefix):]
    if data.get('from_site') and name:
        return name
    return loc_id


def location_storage_id(cur, loc_id, owner_id=None):
    loc_id = (loc_id or '').strip()
    oid = coerce_owner_id(owner_id)
    if not loc_id:
        return None
    if oid is not None:
        scoped = scoped_location_doc_id(oid, loc_id)
        if get_doc(cur, 'locations', scoped):
            return scoped
        doc = get_doc(cur, 'locations', loc_id)
        if doc and same_owner(oid, (doc.get('data') or {}).get('owner_id')):
            return loc_id
        return None
    if get_doc(cur, 'locations', loc_id):
        return loc_id
    return None


def location_storage_id_for_write(cur, loc_id, owner_id=None):
    loc_id = (loc_id or '').strip()
    oid = coerce_owner_id(owner_id)
    if not loc_id:
        return loc_id
    existing_id = location_storage_id(cur, loc_id, oid)
    if existing_id:
        return existing_id
    if oid is None:
        return loc_id
    taken = get_doc(cur, 'locations', loc_id)
    if taken and not same_owner(oid, (taken.get('data') or {}).get('owner_id')):
        return scoped_location_doc_id(oid, loc_id)
    return loc_id


def choose_site_location_id(cur, site):
    oid = coerce_owner_id((site or {}).get('owner_id'))
    for loc_id in site_location_candidates(site):
        return location_storage_id_for_write(cur, loc_id, oid)
    return scoped_location_doc_id(oid, 'site-%s' % (site or {}).get('id'))


def ensure_owner_site_locations(cur, owner_id):
    """Create a main location for each active MikroTik site this owner has."""
    oid = coerce_owner_id(owner_id)
    if not oid:
        return 0
    try:
        cur.execute(
            "SELECT id, name, wg_ip, owner_id FROM sites WHERE owner_id=%s AND status='active'",
            (oid,),
        )
        sites = cur.fetchall() or []
    except Exception as e:
        log.warning('ensure_owner_site_locations: %s', e)
        return 0
    n = 0
    keep = set()
    for site in sites:
        display = str(site.get('name') or '').strip() or ('site-%s' % site.get('id'))
        loc_id = location_storage_id_for_write(cur, display, oid)
        keep.add(loc_id)
        payload = {
            'type': 'main',
            'parent_location': None,
            'owner_id': oid,
            'name': display,
            'site_id': site.get('id'),
            'wg_ip': site.get('wg_ip'),
            'from_site': True,
        }
        set_doc(cur, 'locations', loc_id, payload, merge=True)
        n += 1
    for doc in list_docs(cur, 'locations'):
        data = doc.get('data') or {}
        if not data.get('from_site') or not same_owner(oid, data.get('owner_id')):
            continue
        if doc.get('id') in keep:
            continue
        if public_location_id(doc) in {str(s.get('name') or '').strip() for s in sites}:
            delete_doc(cur, 'locations', doc['id'])
    return n


def owner_id_for_email(cur, email):
    em = (email or '').strip().lower()
    if not em:
        return None
    try:
        cur.execute(
            "SELECT id FROM mikrotik_owners WHERE LOWER(email)=%s AND status='active' "
            "ORDER BY id ASC LIMIT 1",
            (em,),
        )
        row = cur.fetchone()
        if row:
            return int(row['id'] if isinstance(row, dict) else row[0])
    except Exception as e:
        log.warning('owner_id_for_email: %s', e)
    return None


def bind_users_to_owner_emails(cur):
    """Move app users onto the tenant that owns their email address."""
    try:
        cur.execute(
            "SELECT id, email FROM mikrotik_owners "
            "WHERE status='active' AND email IS NOT NULL AND email<>'' "
            "ORDER BY id ASC"
        )
    except Exception as e:
        log.warning('bind_users_to_owner_emails: %s', e)
        return 0
    by_email = {}
    for row in cur.fetchall() or []:
        em = str(row.get('email') or '').strip().lower()
        if em and em not in by_email:
            by_email[em] = int(row['id'])
    n = 0
    for doc in list_docs(cur, 'users'):
        data = doc.get('data') or {}
        em = str(data.get('email') or '').strip().lower()
        oid = by_email.get(em)
        if not oid:
            continue
        if coerce_owner_id(data.get('mikrotik_owner_id')) == oid:
            continue
        set_doc(cur, 'users', doc['id'], {'mikrotik_owner_id': oid}, merge=True)
        n += 1
    return n


def stamp_legacy_owner_collection(cur, collection, owner_id):
    oid = coerce_owner_id(owner_id)
    if not oid:
        return 0
    n = 0
    for doc in list_docs(cur, collection):
        data = doc.get('data') or {}
        if coerce_owner_id(data.get('mikrotik_owner_id') or data.get('owner_id')):
            continue
        set_doc(cur, collection, doc['id'], {'mikrotik_owner_id': oid}, merge=True)
        n += 1
    return n


def stamp_legacy_mikrotik_devices(cur, owner_id):
    return stamp_legacy_owner_collection(cur, 'mikrotik_devices', owner_id)


def stamp_legacy_sites(cur, owner_id):
    return stamp_legacy_owner_collection(cur, 'sites', owner_id)


def ensure_owner_tenancy(cur):
    """Stamp existing app users/locations onto the default LightNet owner once."""
    global _OWNER_TENANCY_READY
    if _OWNER_TENANCY_READY:
        return
    try:
        marker = get_doc(cur, 'app_meta', 'owner_tenancy')
        marker_data = (marker or {}).get('data') or {}
        oid = coerce_owner_id(marker_data.get('owner_id')) or default_mikrotik_owner_id(cur)
        if not oid:
            return
        if not marker_data.get('backfilled'):
            for doc in list_docs(cur, 'locations'):
                data = doc.get('data') or {}
                if coerce_owner_id(data.get('owner_id')):
                    continue
                set_doc(cur, 'locations', doc['id'], {'owner_id': oid}, merge=True)
            for doc in list_docs(cur, 'users'):
                data = doc.get('data') or {}
                if coerce_owner_id(data.get('mikrotik_owner_id')):
                    continue
                set_doc(cur, 'users', doc['id'], {'mikrotik_owner_id': oid}, merge=True)
        if not marker_data.get('devices_backfilled'):
            stamp_legacy_mikrotik_devices(cur, oid)
        if not marker_data.get('sites_backfilled'):
            stamp_legacy_sites(cur, oid)
        if not marker_data.get('ops_backfilled'):
            for collection in OPS_BACKFILL_COLLECTIONS:
                stamp_legacy_owner_collection(cur, collection, oid)
        if not marker_data.get('email_owner_bind'):
            bind_users_to_owner_emails(cur)
        set_doc(
            cur,
            'app_meta',
            'owner_tenancy',
            {
                'backfilled': True,
                'devices_backfilled': True,
                'sites_backfilled': True,
                'ops_backfilled': True,
                'email_owner_bind': True,
                'owner_id': oid,
                'at': _iso(_now()),
            },
            merge=True,
        )
        _OWNER_TENANCY_READY = True
    except Exception as e:
        log.warning('ensure_owner_tenancy: %s', e)


def provision_owner_app_boss(cur, firebase_auth, owner_id, name, email, password, phone=None):
    """Create (or attach) a Firebase app user with role=boss for this MikroTik owner."""
    owner_id = coerce_owner_id(owner_id)
    app_email = (email or '').strip().lower()
    if not app_email:
        app_email = 'owner%s@owners.lightnetwork.pro' % owner_id
    if firebase_auth is None or not owner_id:
        return {'uid': None, 'email': app_email, 'created': False, 'skipped': True, 'reason': 'unavailable'}
    uid = None
    created = False
    try:
        user_record = firebase_auth.create_user(
            email=app_email,
            password=password,
            display_name=name or '',
        )
        uid = user_record.uid
        created = True
    except Exception as e:
        msg = str(e)
        if 'EMAIL_EXISTS' in msg or 'already exists' in msg.lower():
            try:
                existing = firebase_auth.get_user_by_email(app_email)
                uid = existing.uid
            except Exception as e2:
                log.warning('provision_owner_app_boss get existing: %s', e2)
                return {'uid': None, 'email': app_email, 'created': False, 'error': str(e2)}
            doc = user_by_uid(cur, uid)
            data = (doc or {}).get('data') or {}
            existing_owner = coerce_owner_id(data.get('mikrotik_owner_id'))
            if existing_owner and existing_owner != owner_id:
                return {
                    'uid': None,
                    'email': app_email,
                    'created': False,
                    'skipped': True,
                    'reason': 'email already used',
                }
        else:
            log.exception('provision_owner_app_boss firebase')
            return {'uid': None, 'email': app_email, 'created': False, 'error': msg}
    if not uid:
        return {'uid': None, 'email': app_email, 'created': False, 'skipped': True}
    profile = {
        'email': app_email,
        'role': 'boss',
        'name': name or '',
        'phone': phone or '',
        'mikrotik_owner_id': owner_id,
        'created_at': _iso(_now()),
        'created_by': 'owner-register',
    }
    if created:
        profile['password'] = password
    set_doc(cur, 'users', uid, profile, merge=True)
    return {'uid': uid, 'email': app_email, 'created': created}


def resolve_actor(request, db_config, firebase_auth=None):
    """Firebase (or local-test) actor, including mikrotik_owner_id."""
    import mysql.connector

    def _load_owner(cur, actor, explicit=None):
        ensure_owner_tenancy(cur)
        email_oid = owner_id_for_email(cur, actor.get('email'))
        oid = pick_actor_owner_id(email_oid, explicit, default_mikrotik_owner_id(cur))
        actor['mikrotik_owner_id'] = oid
        uid = str(actor.get('uid') or '')
        if uid and uid != 'local-test' and email_oid and coerce_owner_id(explicit) != email_oid:
            set_doc(cur, 'users', uid, {'mikrotik_owner_id': email_oid}, merge=True)
        ensure_owner_site_locations(cur, oid)
        return actor

    remote = (request.remote_addr or '').strip()
    if remote in ('127.0.0.1', '::1') and request.headers.get('X-Hi-Local') == '1':
        loc = (request.headers.get('X-Hi-Location') or '').strip()
        locs_raw = (request.headers.get('X-Hi-Locations') or '').strip()
        locs = [x.strip() for x in locs_raw.split(',') if x.strip()] if locs_raw else ([loc] if loc else [])
        actor = {
            'uid': request.headers.get('X-Hi-Uid') or 'local-test',
            'role': (request.headers.get('X-Hi-Role') or 'boss').strip().lower(),
            'name': request.headers.get('X-Hi-Name') or 'Local Test',
            'email': request.headers.get('X-Hi-Email') or '',
            'location': loc,
            'locations': locs,
            'mikrotik_owner_id': coerce_owner_id(request.headers.get('X-Hi-Owner-Id')),
        }
        try:
            conn = mysql.connector.connect(**db_config)
            cur = conn.cursor(dictionary=True)
            try:
                ensure_tables(cur)
                _load_owner(cur, actor, actor.get('mikrotik_owner_id'))
                conn.commit()
            finally:
                cur.close(); conn.close()
        except Exception as e:
            log.warning('resolve_actor local: %s', e)
        return actor
    header = request.headers.get('Authorization') or ''
    if not header.startswith('Bearer ') or firebase_auth is None:
        return None
    token = header.split(' ', 1)[1].strip()
    if not token:
        return None
    try:
        decoded = firebase_auth.verify_id_token(token)
    except Exception as e:
        log.warning('app_docs token failed: %s', e)
        return None
    uid = decoded.get('uid')
    actor = {
        'uid': uid,
        'role': 'technician',
        'name': decoded.get('name') or '',
        'email': decoded.get('email') or '',
        'location': '',
        'locations': [],
        'mikrotik_owner_id': None,
    }
    try:
        conn = mysql.connector.connect(**db_config)
        cur = conn.cursor(dictionary=True)
        try:
            ensure_tables(cur)
            ensure_owner_tenancy(cur)
            conn.commit()
            user = user_by_uid(cur, uid)
            if user:
                data = user.get('data') or {}
                actor['role'] = str(data.get('role') or actor['role']).strip().lower()
                actor['name'] = data.get('name') or actor['name']
                actor['email'] = data.get('email') or actor['email']
                actor['location'] = str(data.get('location') or '').strip()
                locs = data.get('locations')
                if isinstance(locs, list):
                    actor['locations'] = [str(x).strip() for x in locs if x]
                elif actor['location']:
                    actor['locations'] = [actor['location']]
                else:
                    actor['locations'] = []
                actor['mikrotik_owner_id'] = coerce_owner_id(data.get('mikrotik_owner_id'))
            _load_owner(cur, actor, actor.get('mikrotik_owner_id'))
            conn.commit()
        finally:
            cur.close(); conn.close()
    except Exception as e:
        log.warning('app_docs actor profile: %s', e)
    return actor


def bump_location_metadata(cur, location, amount, owner_id=None):
    if not location:
        return
    oid = coerce_owner_id(owner_id)
    storage_id = location_storage_id_for_write(cur, location, oid)
    existing = get_doc(cur, 'locations', storage_id)
    data = (existing or {}).get('data') or {}
    set_doc(
        cur,
        'locations',
        storage_id,
        {
            'metadata': {
                'total_revenue': {SPECIAL: 'increment', 'n': float(amount or 0)},
                'payment_count': {SPECIAL: 'increment', 'n': 1},
                'last_payment_at': {SPECIAL: 'serverTimestamp'},
                'last_updated': {SPECIAL: 'serverTimestamp'},
            }
        },
        merge=True,
    )
    if not existing:
        extra = {'type': 'main', 'auto_created': True, 'parent_location': None, 'name': location}
        if oid:
            extra['owner_id'] = oid
        extra.update(data)
        set_doc(cur, 'locations', storage_id, extra, merge=True)


def serialize_location(doc):
    data = dict((doc or {}).get('data') or {})
    loc_id = str((doc or {}).get('id') or '')
    parent = data.get('parent_location')
    if parent is None or str(parent).strip() in ('', 'null'):
        parent = None
    else:
        parent = str(parent).strip()
    loc_type = data.get('type')
    if loc_type is not None:
        loc_type = str(loc_type).strip() or None
    meta = data.get('metadata')
    public_id = public_location_id(doc)
    return {
        'id': public_id,
        'name': str(data.get('name') or public_id).strip() or public_id,
        'type': loc_type,
        'parent_location': parent,
        'owner_id': coerce_owner_id(data.get('owner_id')),
        'auto_created': bool(data.get('auto_created')),
        'metadata': meta if isinstance(meta, dict) else {},
        'created_at': (doc or {}).get('created_at'),
        'updated_at': (doc or {}).get('updated_at'),
    }


def list_locations(cur):
    out = [serialize_location(d) for d in list_docs(cur, 'locations')]
    out.sort(key=lambda x: (
        0 if (x.get('type') == 'main' or not x.get('type')) else 1,
        (x.get('id') or '').lower(),
    ))
    return out


def get_location(cur, loc_id, owner_id=None):
    loc_id = (loc_id or '').strip()
    if not loc_id:
        return None
    storage_id = location_storage_id(cur, loc_id, owner_id)
    if not storage_id:
        return None
    doc = get_doc(cur, 'locations', storage_id)
    if not doc:
        return None
    loc = serialize_location(doc)
    oid = coerce_owner_id(owner_id)
    if oid is not None and not same_owner(oid, loc.get('owner_id')):
        return None
    return loc


def create_location(cur, loc_id, loc_type=None, parent_location=None, owner_id=None):
    loc_id = (loc_id or '').strip()
    if not loc_id:
        raise ValueError('id required')
    oid = coerce_owner_id(owner_id)
    if location_storage_id(cur, loc_id, oid):
        raise ValueError('Location already exists')
    storage_id = location_storage_id_for_write(cur, loc_id, oid)
    loc_type = (loc_type or 'main').strip().lower()
    if loc_type not in ('main', 'sublocation'):
        raise ValueError('type must be main or sublocation')
    parent = (parent_location or '').strip() or None
    payload = {'type': loc_type, 'auto_created': False, 'name': loc_id}
    if oid:
        payload['owner_id'] = oid
    if loc_type == 'sublocation':
        if not parent:
            raise ValueError('parent_location is required for sublocations')
        parent_loc = get_location(cur, parent, oid)
        if not parent_loc:
            raise ValueError("Parent location '%s' does not exist" % parent)
        payload['parent_location'] = parent_loc.get('id') or parent
    set_doc(cur, 'locations', storage_id, payload, merge=False)
    return get_location(cur, loc_id, oid)


def update_location(cur, loc_id, loc_type=None, parent_location=None, clear_parent=False, owner_id=None):
    loc_id = (loc_id or '').strip()
    oid = coerce_owner_id(owner_id)
    storage_id = location_storage_id(cur, loc_id, oid)
    existing = get_doc(cur, 'locations', storage_id) if storage_id else None
    if not existing:
        raise KeyError('not found')
    patch = {}
    if loc_type is not None:
        loc_type = str(loc_type).strip().lower()
        if loc_type not in ('main', 'sublocation'):
            raise ValueError('type must be main or sublocation')
        patch['type'] = loc_type
        if loc_type == 'main':
            clear_parent = True
    if clear_parent:
        patch['parent_location'] = {SPECIAL: 'delete'}
        if 'type' not in patch:
            patch['type'] = 'main'
    elif parent_location is not None:
        parent = str(parent_location).strip()
        if not parent:
            patch['parent_location'] = {SPECIAL: 'delete'}
            if 'type' not in patch:
                patch['type'] = 'main'
        else:
            if parent == loc_id:
                raise ValueError('Location cannot be its own parent')
            parent_loc = get_location(cur, parent, oid)
            if not parent_loc:
                raise ValueError("Parent location '%s' does not exist" % parent)
            patch['parent_location'] = parent_loc.get('id') or parent
            if 'type' not in patch:
                patch['type'] = 'sublocation'
    if not patch:
        return serialize_location(existing)
    set_doc(cur, 'locations', storage_id, patch, merge=True)
    return get_location(cur, loc_id, oid)


def delete_location(cur, loc_id, owner_id=None):
    loc_id = (loc_id or '').strip()
    if not loc_id:
        raise ValueError('id required')
    storage_id = location_storage_id(cur, loc_id, owner_id)
    if not storage_id or not get_doc(cur, 'locations', storage_id):
        raise KeyError('not found')
    public_id = public_location_id(get_doc(cur, 'locations', storage_id))
    for loc in list_locations(cur):
        if loc.get('parent_location') == public_id and same_owner(owner_id, loc.get('owner_id')):
            raise ValueError('Cannot delete location with sublocations')
    delete_doc(cur, 'locations', storage_id)
    return True


FULL_LOCATION_ROLES = {'boss', 'admin', 'md'}
LOCATION_WRITE_ROLES = {'boss', 'admin', 'md'}
LOCATION_CREATE_SUB_ROLES = {'agent', 'superagent', 'technician'}


def actor_assigned_location_names(actor):
    names = set()
    loc = str((actor or {}).get('location') or '').strip()
    if loc:
        names.add(loc)
    for x in (actor or {}).get('locations') or []:
        s = str(x).strip()
        if s:
            names.add(s)
    return names


def expand_allowed_locations(all_locs, assigned):
    allowed = set(assigned or [])
    if not allowed:
        return set()
    changed = True
    while changed:
        changed = False
        for loc in all_locs:
            loc_id = loc.get('id')
            parent = loc.get('parent_location')
            if loc_id and parent and parent in allowed and loc_id not in allowed:
                allowed.add(loc_id)
                changed = True
    return allowed


def owned_locations(all_locs, owner_id):
    oid = coerce_owner_id(owner_id)
    if oid is None:
        return []
    out = []
    for loc in all_locs or []:
        if coerce_owner_id(loc.get('owner_id')) == oid:
            out.append(loc)
    return out


def allowed_location_ids(actor, all_locs):
    owned = owned_locations(all_locs, (actor or {}).get('mikrotik_owner_id'))
    owned_ids = {loc.get('id') for loc in owned if loc.get('id')}
    role = str((actor or {}).get('role') or '').strip().lower()
    if role in FULL_LOCATION_ROLES:
        return owned_ids
    if role == 'homeuser':
        return set()
    assigned = expand_allowed_locations(owned, actor_assigned_location_names(actor))
    return set(assigned or []) & owned_ids


def filter_locations_for_actor(actor, all_locs):
    allowed = allowed_location_ids(actor, all_locs)
    oid = (actor or {}).get('mikrotik_owner_id')
    return [
        loc for loc in all_locs
        if loc.get('id') in allowed and same_owner(oid, loc.get('owner_id'))
    ]


def location_access_ok(actor, loc_id, all_locs):
    allowed = allowed_location_ids(actor, all_locs)
    return str(loc_id or '').strip() in allowed


def doc_owner_id(data, default_owner_id=None):
    oid = coerce_owner_id((data or {}).get('mikrotik_owner_id') or (data or {}).get('owner_id'))
    if oid is None:
        return coerce_owner_id(default_owner_id)
    return oid


def site_location_name(data):
    return str((data or {}).get('main_location') or (data or {}).get('location') or '').strip()


def doc_location_name(collection, data):
    data = data or {}
    if collection == 'sites':
        return site_location_name(data)
    if collection == 'technician_vouchers':
        return str(data.get('agent_location') or data.get('location') or '').strip()
    if collection == 'expenses':
        return str(data.get('location_id') or data.get('location_name') or data.get('location') or '').strip()
    if collection == 'tech_checkins':
        return str(data.get('destination_name') or data.get('location') or '').strip()
    return str(data.get('location') or '').strip()


def tenant_docs_visible(actor, collection, doc, allowed_locs, default_owner_id=None):
    data = (doc or {}).get('data') or {}
    owner_id = (actor or {}).get('mikrotik_owner_id')
    role = str((actor or {}).get('role') or '').strip().lower()
    if collection == 'users':
        return same_owner(owner_id, data.get('mikrotik_owner_id'))
    if collection == 'locations':
        return (doc or {}).get('id') in (allowed_locs or set())
    if collection in OWNER_SCOPED_COLLECTIONS:
        if not same_owner(owner_id, doc_owner_id(data, default_owner_id)):
            return False
        if role in FULL_LOCATION_ROLES:
            return True
        loc = doc_location_name(collection, data)
        if collection in ('mikrotik_devices', 'sites'):
            return bool(loc) and loc in (allowed_locs or set())
        if loc:
            return loc in (allowed_locs or set())
        return True
    loc = data.get('location')
    if loc:
        return str(loc).strip() in (allowed_locs or set())
    oid = data.get('mikrotik_owner_id')
    if oid is not None and collection != 'field_registrations':
        return same_owner(owner_id, oid)
    return True


def stamp_write_owner(actor, collection, payload):
    if payload is None:
        return payload
    payload = dict(payload)
    if collection in OWNER_SCOPED_COLLECTIONS:
        payload.pop('mikrotik_owner_id', None)
        if collection in ('mikrotik_devices', 'sites'):
            payload.pop('owner_id', None)
        payload['mikrotik_owner_id'] = coerce_owner_id(actor.get('mikrotik_owner_id'))
    return payload


def location_id_from_collection(collection, doc_id=None):
    c = (collection or '').strip()
    if c == 'locations':
        return (doc_id or '').strip() or None
    if c.startswith('locations/'):
        parts = c.split('/')
        if len(parts) >= 2 and parts[1]:
            return parts[1]
    return None


def is_location_scoped_collection(collection):
    c = (collection or '').strip()
    return c == 'locations' or c.startswith('locations/')


def user_by_uid(cur, uid):
    return get_doc(cur, 'users', uid)


def user_by_email(cur, email):
    em = (email or '').strip().lower()
    if not em:
        return None
    for doc in list_docs(cur, 'users'):
        data = doc.get('data') or {}
        if str(data.get('email') or '').strip().lower() == em:
            return doc
    return None


def _firebase_user_missing(exc):
    msg = str(exc or '').lower()
    name = type(exc).__name__.lower()
    return (
        'user_not_found' in msg
        or 'no user record' in msg
        or 'usernotfound' in name
    )


def existing_login_account(cur, email, firebase_auth=None):
    """True if this email is already staff, an app user, or a Firebase login."""
    em = (email or '').strip().lower()
    if not em:
        return False
    if user_by_email(cur, em):
        return True
    if firebase_auth is None:
        return False
    try:
        firebase_auth.get_user_by_email(em)
        return True
    except Exception as e:
        if _firebase_user_missing(e):
            return False
        log.warning('existing_login_account firebase: %s', e)
        return False


def register_routes(app, db_config, firebase_auth=None):
    from flask import jsonify, request
    import mysql.connector

    def _conn():
        conn = mysql.connector.connect(**db_config)
        cur = conn.cursor(dictionary=True)
        ensure_tables(cur)
        ensure_owner_tenancy(cur)
        conn.commit()
        return conn, cur

    def _actor():
        return resolve_actor(request, db_config, firebase_auth)

    def _require(roles=None):
        actor = _actor()
        if not actor:
            return None, (jsonify({'success': False, 'error': 'Sign in required'}), 401)
        if roles and actor.get('role') not in roles:
            return None, (jsonify({'success': False, 'error': 'Not allowed'}), 403)
        return actor, None

    def _location_guard(cur, actor, collection, doc_id=None):
        if not is_location_scoped_collection(collection):
            return None
        all_locs = list_locations(cur)
        if collection == 'locations' and not doc_id:
            return None
        loc_id = location_id_from_collection(collection, doc_id)
        if not loc_id:
            return None
        if location_access_ok(actor, loc_id, all_locs):
            return None
        return jsonify({'success': False, 'error': 'Not allowed'}), 403

    def _body():
        return request.get_json(silent=True) or {}

    def _query_collection(cur, actor, collection, payload):
        filters = payload.get('filters') or []
        order_by = payload.get('orderBy') or payload.get('order_by')
        limit = payload.get('limit')
        allowed = allowed_location_ids(actor, list_locations(cur))
        default_oid = default_mikrotik_owner_id(cur)
        if collection == 'payments':
            return query_mysql_payments(cur, filters, order_by, limit, location_ids=allowed)
        docs = query_docs(cur, collection, filters, order_by, limit)
        return [d for d in docs if tenant_docs_visible(actor, collection, d, allowed, default_oid)]

    def _user_guard(cur, actor, collection, doc_id=None, payload=None, writing=False):
        if collection != 'users':
            return None, payload
        owner_id = coerce_owner_id(actor.get('mikrotik_owner_id'))
        role = str(actor.get('role') or '').strip().lower()
        if writing and payload is not None:
            payload = dict(payload)
            payload.pop('mikrotik_owner_id', None)
        existing = get_doc(cur, 'users', doc_id) if doc_id else None
        if existing:
            existing_oid = coerce_owner_id((existing.get('data') or {}).get('mikrotik_owner_id'))
            if existing_oid and not same_owner(owner_id, existing_oid):
                return (jsonify({'success': False, 'error': 'Not allowed'}), 403), payload
        elif writing:
            if payload is None:
                payload = {}
            payload['mikrotik_owner_id'] = owner_id
        if writing and doc_id and str(doc_id) != str(actor.get('uid')) and role not in ('boss', 'admin', 'md'):
            return (jsonify({'success': False, 'error': 'Not allowed'}), 403), payload
        return None, payload

    def _tenant_write_guard(cur, actor, collection, doc_id):
        if collection not in OWNER_SCOPED_COLLECTIONS or not doc_id:
            return None
        existing = get_doc(cur, collection, doc_id)
        if not existing:
            return None
        allowed = allowed_location_ids(actor, list_locations(cur))
        if tenant_docs_visible(actor, collection, existing, allowed, default_mikrotik_owner_id(cur)):
            return None
        return jsonify({'success': False, 'error': 'Not allowed'}), 403

    def _payment_doc(row):
        return {
            'id': str(row['id']),
            'collection': 'payments',
            'data': {
                'location': row.get('location'),
                'amount': float(row.get('amount') or 0),
                'duration': row.get('duration'),
                'username': row.get('username'),
                'voucher': row.get('username'),
                'phone': row.get('phone'),
                'payment_method': row.get('payment_method'),
                'created_at': _iso(row.get('timestamp')),
            },
        }

    @app.route('/api/app/query', methods=['POST'])
    def app_query():
        actor, err = _require()
        if err:
            return err
        data = _body()
        collection = (data.get('collection') or '').strip()
        if not collection:
            return jsonify({'success': False, 'error': 'collection required'}), 400
        conn, cur = _conn()
        try:
            docs = _query_collection(cur, actor, collection, data)
            if is_location_scoped_collection(collection) and collection != 'locations':
                loc_id = location_id_from_collection(collection)
                if loc_id and not location_access_ok(actor, loc_id, list_locations(cur)):
                    return jsonify({'success': True, 'docs': []})
            return jsonify({'success': True, 'docs': docs})
        finally:
            cur.close(); conn.close()

    @app.route('/api/app/doc', methods=['GET'])
    def app_get():
        actor, err = _require()
        if err:
            return err
        collection = (request.args.get('c') or request.args.get('collection') or '').strip()
        doc_id = (request.args.get('id') or '').strip()
        if not collection or not doc_id:
            return jsonify({'success': False, 'error': 'collection and id required'}), 400
        conn, cur = _conn()
        try:
            denied = _location_guard(cur, actor, collection, doc_id)
            if denied:
                return denied
            denied, _ = _user_guard(cur, actor, collection, doc_id)
            if denied:
                if collection == 'users':
                    return jsonify({'success': True, 'exists': False, 'doc': None})
                return denied
            if collection == 'payments':
                cur.execute("SELECT id, location, amount, duration, username, timestamp, phone, payment_method FROM payments WHERE id=%s", (doc_id,))
                row = cur.fetchone()
                if not row:
                    return jsonify({'success': True, 'exists': False, 'doc': None})
                if not location_access_ok(actor, row.get('location'), list_locations(cur)):
                    return jsonify({'success': True, 'exists': False, 'doc': None})
                return jsonify({'success': True, 'exists': True, 'doc': _payment_doc(row)})
            doc = get_doc(cur, collection, doc_id)
            if not doc:
                return jsonify({'success': True, 'exists': False, 'doc': None})
            allowed = allowed_location_ids(actor, list_locations(cur))
            if not tenant_docs_visible(actor, collection, doc, allowed, default_mikrotik_owner_id(cur)):
                return jsonify({'success': True, 'exists': False, 'doc': None})
            return jsonify({'success': True, 'exists': True, 'doc': doc})
        finally:
            cur.close(); conn.close()

    @app.route('/api/app/doc', methods=['POST', 'PUT', 'PATCH'])
    def app_set():
        actor, err = _require()
        if err:
            return err
        data = _body()
        collection = (data.get('collection') or '').strip()
        if not collection:
            return jsonify({'success': False, 'error': 'collection required'}), 400
        doc_id = str(data.get('id') or new_id())
        payload = data.get('data') if 'data' in data else {k: v for k, v in data.items() if k not in ('collection', 'id', 'merge')}
        merge = bool(data.get('merge')) or request.method in ('PATCH',)
        conn, cur = _conn()
        try:
            if is_location_scoped_collection(collection):
                if collection == 'locations' and actor.get('role') not in LOCATION_WRITE_ROLES:
                    return jsonify({'success': False, 'error': 'Not allowed'}), 403
                denied = _location_guard(cur, actor, collection, doc_id)
                if denied:
                    return denied
            denied, payload = _user_guard(cur, actor, collection, doc_id, payload=payload, writing=True)
            if denied:
                return denied
            denied = _tenant_write_guard(cur, actor, collection, doc_id)
            if denied:
                return denied
            payload = stamp_write_owner(actor, collection, payload)
            if collection == 'locations' and payload is not None:
                payload = dict(payload)
                payload.pop('owner_id', None)
                payload['owner_id'] = coerce_owner_id(actor.get('mikrotik_owner_id'))
            loc_name = (payload or {}).get('location')
            if collection == 'sites':
                loc_name = loc_name or (payload or {}).get('main_location')
            if (
                loc_name
                and collection != 'mikrotik_devices'
                and not location_access_ok(actor, loc_name, list_locations(cur))
            ):
                return jsonify({'success': False, 'error': 'Not allowed'}), 403
            if collection == 'payments' and request.method == 'POST':
                cur.execute(
                    """
                    INSERT INTO payments (location, amount, duration, username, phone, payment_method, owner_id)
                    VALUES (%s,%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        payload.get('location'),
                        payload.get('amount') or 0,
                        payload.get('duration'),
                        payload.get('username') or payload.get('voucher'),
                        payload.get('phone'),
                        payload.get('payment_method'),
                        coerce_owner_id(actor.get('mikrotik_owner_id')),
                    ),
                )
                doc_id = str(cur.lastrowid)
                bump_location_metadata(
                    cur,
                    payload.get('location'),
                    payload.get('amount') or 0,
                    owner_id=actor.get('mikrotik_owner_id'),
                )
                conn.commit()
                return jsonify({'success': True, 'id': doc_id}), 201
            doc = set_doc(cur, collection, doc_id, payload, merge=merge)
            conn.commit()
            return jsonify({'success': True, 'id': doc['id'], 'doc': doc})
        finally:
            cur.close(); conn.close()

    @app.route('/api/app/doc', methods=['DELETE'])
    def app_delete():
        actor, err = _require()
        if err:
            return err
        collection = (request.args.get('c') or request.args.get('collection') or '').strip()
        doc_id = (request.args.get('id') or '').strip()
        if not collection or not doc_id:
            return jsonify({'success': False, 'error': 'collection and id required'}), 400
        conn, cur = _conn()
        try:
            if is_location_scoped_collection(collection):
                if collection == 'locations' and actor.get('role') not in LOCATION_WRITE_ROLES:
                    return jsonify({'success': False, 'error': 'Not allowed'}), 403
                denied = _location_guard(cur, actor, collection, doc_id)
                if denied:
                    return denied
            denied, _ = _user_guard(cur, actor, collection, doc_id, writing=True)
            if denied:
                return denied
            denied = _tenant_write_guard(cur, actor, collection, doc_id)
            if denied:
                return denied
            delete_doc(cur, collection, doc_id)
            conn.commit()
            return jsonify({'success': True})
        finally:
            cur.close(); conn.close()

    @app.route('/api/app/batch', methods=['POST'])
    def app_batch():
        actor, err = _require()
        if err:
            return err
        ops = _body().get('ops') or []
        conn, cur = _conn()
        try:
            ids = []
            for op in ops:
                kind = op.get('op')
                collection = op.get('collection')
                doc_id = str(op.get('id') or new_id())
                if is_location_scoped_collection(collection):
                    if collection == 'locations' and actor.get('role') not in LOCATION_WRITE_ROLES:
                        return jsonify({'success': False, 'error': 'Not allowed'}), 403
                    denied = _location_guard(cur, actor, collection, doc_id)
                    if denied:
                        return denied
                denied, op_data = _user_guard(
                    cur, actor, collection, doc_id,
                    payload=op.get('data') or {},
                    writing=True,
                )
                if denied:
                    return denied
                denied = _tenant_write_guard(cur, actor, collection, doc_id)
                if denied:
                    return denied
                op_data = stamp_write_owner(actor, collection, op_data)
                if kind == 'delete':
                    delete_doc(cur, collection, doc_id)
                else:
                    set_doc(cur, collection, doc_id, op_data, merge=bool(op.get('merge') or kind == 'update'))
                ids.append(doc_id)
            conn.commit()
            return jsonify({'success': True, 'ids': ids})
        finally:
            cur.close(); conn.close()

    @app.route('/api/auth/create-user', methods=['POST'])
    def app_create_user():
        actor, err = _require(('boss', 'admin', 'md'))
        if err:
            return err
        data = _body()
        email = (data.get('email') or '').strip()
        password = data.get('password') or ''
        role = (data.get('role') or '').strip().lower()
        if not email or not password or not role:
            return jsonify({'success': False, 'error': 'email, password, and role are required'}), 400
        if role not in ('technician', 'agent', 'superagent', 'boss', 'homeuser', 'md'):
            return jsonify({'success': False, 'error': 'Invalid role'}), 400
        if len(password) < 6:
            return jsonify({'success': False, 'error': 'Password must be at least 6 characters long'}), 400
        conn, cur = _conn()
        try:
            all_locs = list_locations(cur)
            location = (data.get('location') or '').strip()
            locations = [str(x).strip() for x in (data.get('locations') or []) if str(x).strip()]
            check_locs = list(locations)
            if location:
                check_locs.append(location)
            for loc in check_locs:
                if loc and not location_access_ok(actor, loc, all_locs):
                    return jsonify({'success': False, 'error': "Location '%s' does not exist in the system" % loc}), 400
            user_record = firebase_auth.create_user(email=email, password=password)
            uid = user_record.uid
            profile = {
                'email': email,
                'role': role,
                'name': data.get('name') or '',
                'password': password,
                'created_at': _iso(_now()),
                'created_by': actor.get('uid'),
                'mikrotik_owner_id': coerce_owner_id(actor.get('mikrotik_owner_id')),
            }
            if role == 'agent':
                profile['location'] = location
            elif role == 'superagent':
                profile['locations'] = locations
                profile['location'] = locations[0] if locations else ''
            elif role == 'technician':
                if locations:
                    profile['locations'] = locations
                elif location:
                    profile['locations'] = [location]
                else:
                    profile['locations'] = []
                profile['location'] = location
            else:
                profile['location'] = location
            if data.get('home_customer_id'):
                profile['home_customer_id'] = data.get('home_customer_id')
            if data.get('commission_divisor') is not None:
                profile['commission_divisor'] = data.get('commission_divisor')
            set_doc(cur, 'users', uid, profile, merge=False)
            conn.commit()
            return jsonify({'success': True, 'uid': uid})
        except Exception as e:
            msg = str(e)
            if 'EMAIL_EXISTS' in msg or 'already exists' in msg.lower():
                return jsonify({'success': False, 'error': 'An account already exists for that email.'}), 400
            log.exception('create-user')
            return jsonify({'success': False, 'error': msg}), 500
        finally:
            cur.close(); conn.close()

    @app.route('/api/auth/delete-user', methods=['POST'])
    def app_delete_user():
        actor, err = _require(('boss', 'admin', 'md'))
        if err:
            return err
        data = _body()
        uid = (data.get('uid') or '').strip()
        email = (data.get('email') or '').strip()
        conn, cur = _conn()
        try:
            if not uid and email:
                user = firebase_auth.get_user_by_email(email)
                uid = user.uid
            if not uid:
                return jsonify({'success': False, 'error': 'Provide uid or email'}), 400
            denied, _ = _user_guard(cur, actor, 'users', uid)
            if denied:
                return jsonify({'success': False, 'error': 'Not allowed'}), 403
            try:
                firebase_auth.delete_user(uid)
            except Exception as e:
                if 'USER_NOT_FOUND' not in str(e) and 'user not found' not in str(e).lower():
                    raise
            delete_doc(cur, 'users', uid)
            conn.commit()
            return jsonify({'success': True})
        except Exception as e:
            log.exception('delete-user')
            return jsonify({'success': False, 'error': str(e)}), 500
        finally:
            cur.close(); conn.close()

    @app.route('/api/auth/reset-password', methods=['POST'])
    def app_reset_password():
        actor, err = _require(('boss', 'admin', 'md'))
        if err:
            return err
        data = _body()
        email = (data.get('email') or '').strip()
        new_password = data.get('newPassword') or data.get('password') or ''
        if not email or not new_password:
            return jsonify({'success': False, 'error': 'email and newPassword are required'}), 400
        if len(new_password) < 6:
            return jsonify({'success': False, 'error': 'Password must be at least 6 characters long'}), 400
        conn, cur = _conn()
        try:
            user = firebase_auth.get_user_by_email(email)
            denied, _ = _user_guard(cur, actor, 'users', user.uid)
            if denied:
                return jsonify({'success': False, 'error': 'Not allowed'}), 403
            firebase_auth.update_user(user.uid, password=new_password)
            set_doc(cur, 'users', user.uid, {'password': new_password}, merge=True)
            conn.commit()
            return jsonify({'success': True})
        except Exception as e:
            msg = str(e)
            if 'USER_NOT_FOUND' in msg or 'user not found' in msg.lower():
                return jsonify({'success': False, 'error': 'User not found with this email'}), 404
            log.exception('reset-password')
            return jsonify({'success': False, 'error': msg}), 500
        finally:
            cur.close(); conn.close()

    @app.route('/api/nokia/beacon-status', methods=['POST'])
    def app_nokia_beacon_status():
        data = _body()
        mikrotik_id = (data.get('mikrotik_id') or '').strip()
        visible = [str(m).upper().strip() for m in (data.get('visible_macs') or [])]
        if not mikrotik_id:
            return jsonify({'success': False, 'error': 'mikrotik_id required'}), 400
        conn, cur = _conn()
        try:
            beacons = query_docs(cur, 'nokia_beacons', [{'field': 'mikrotik_id', 'op': '==', 'value': mikrotik_id}])
            online = offline = 0
            now = {SPECIAL: 'serverTimestamp'}
            for b in beacons:
                mac = str((b.get('data') or {}).get('mac_address') or '').upper().strip()
                visible_now = mac in visible
                update = {'status': 'online' if visible_now else 'offline', 'last_checked': now}
                if visible_now:
                    update['last_seen'] = now
                    online += 1
                else:
                    offline += 1
                set_doc(cur, 'nokia_beacons', b['id'], update, merge=True)
            conn.commit()
            return jsonify({'success': True, 'online': online, 'offline': offline})
        finally:
            cur.close(); conn.close()

    @app.route('/api/locations', methods=['GET'])
    @app.route('/locations', methods=['GET'])
    def api_locations_list():
        actor, err = _require()
        if err:
            return err
        conn, cur = _conn()
        try:
            rows = list_locations(cur)
            return jsonify({'success': True, 'locations': filter_locations_for_actor(actor, rows)})
        finally:
            cur.close(); conn.close()

    @app.route('/api/locations', methods=['POST'])
    def api_locations_create():
        actor, err = _require()
        if err:
            return err
        data = _body()
        loc_id = str(data.get('id') or data.get('name') or '').strip()
        loc_type = (data.get('type') or 'main')
        parent = data.get('parent_location') or data.get('parentLocation')
        role = str(actor.get('role') or '').strip().lower()
        conn, cur = _conn()
        try:
            all_locs = list_locations(cur)
            if role not in FULL_LOCATION_ROLES:
                if role not in LOCATION_CREATE_SUB_ROLES:
                    return jsonify({'success': False, 'error': 'Not allowed'}), 403
                if str(loc_type).strip().lower() != 'sublocation':
                    return jsonify({'success': False, 'error': 'You can only add sublocations under your assigned locations'}), 403
                if not location_access_ok(actor, parent, all_locs):
                    return jsonify({'success': False, 'error': 'Not allowed'}), 403
            loc = create_location(
                cur,
                loc_id,
                loc_type=loc_type,
                parent_location=parent,
                owner_id=actor.get('mikrotik_owner_id'),
            )
            conn.commit()
            return jsonify({'success': True, 'location': loc}), 201
        except ValueError as e:
            conn.rollback()
            status = 409 if 'already exists' in str(e).lower() else 400
            return jsonify({'success': False, 'error': str(e)}), status
        finally:
            cur.close(); conn.close()

    @app.route('/api/locations/<path:loc_id>', methods=['GET'])
    def api_locations_get(loc_id):
        actor, err = _require()
        if err:
            return err
        conn, cur = _conn()
        try:
            loc = get_location(cur, loc_id, actor.get('mikrotik_owner_id'))
            if not loc:
                return jsonify({'success': False, 'error': 'Location not found'}), 404
            if not location_access_ok(actor, loc.get('id') or loc_id, list_locations(cur)):
                return jsonify({'success': False, 'error': 'Location not found'}), 404
            return jsonify({'success': True, 'location': loc})
        finally:
            cur.close(); conn.close()

    @app.route('/api/locations/<path:loc_id>', methods=['PATCH', 'PUT'])
    def api_locations_update(loc_id):
        actor, err = _require(tuple(LOCATION_WRITE_ROLES))
        if err:
            return err
        data = _body()
        clear_parent = bool(data.get('clear_parent'))
        parent = None
        if 'parent_location' in data or 'parentLocation' in data:
            parent = data.get('parent_location') if 'parent_location' in data else data.get('parentLocation')
            if parent in (None, ''):
                clear_parent = True
                parent = None
        conn, cur = _conn()
        try:
            if not location_access_ok(actor, loc_id, list_locations(cur)):
                return jsonify({'success': False, 'error': 'Location not found'}), 404
            loc = update_location(
                cur,
                loc_id,
                loc_type=data.get('type'),
                parent_location=parent,
                clear_parent=clear_parent,
                owner_id=actor.get('mikrotik_owner_id'),
            )
            conn.commit()
            return jsonify({'success': True, 'location': loc})
        except KeyError:
            conn.rollback()
            return jsonify({'success': False, 'error': 'Location not found'}), 404
        except ValueError as e:
            conn.rollback()
            return jsonify({'success': False, 'error': str(e)}), 400
        finally:
            cur.close(); conn.close()

    @app.route('/api/locations/<path:loc_id>', methods=['DELETE'])
    def api_locations_delete(loc_id):
        actor, err = _require(tuple(LOCATION_WRITE_ROLES))
        if err:
            return err
        conn, cur = _conn()
        try:
            if not location_access_ok(actor, loc_id, list_locations(cur)):
                return jsonify({'success': False, 'error': 'Location not found'}), 404
            delete_location(cur, loc_id, owner_id=actor.get('mikrotik_owner_id'))
            conn.commit()
            return jsonify({'success': True})
        except KeyError:
            conn.rollback()
            return jsonify({'success': False, 'error': 'Location not found'}), 404
        except ValueError as e:
            conn.rollback()
            return jsonify({'success': False, 'error': str(e)}), 409
        finally:
            cur.close(); conn.close()

    return app
