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


def query_mysql_payments(cur, filters=None, order_by=None, limit=None):
    filters = filters or []
    sql = """
        SELECT id, location, amount, duration, username, timestamp, phone, payment_method
        FROM payments WHERE 1=1
    """
    params = []
    leftover = []
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


def bump_location_metadata(cur, location, amount):
    if not location:
        return
    existing = get_doc(cur, 'locations', location)
    data = (existing or {}).get('data') or {}
    set_doc(
        cur,
        'locations',
        location,
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
        extra = {'type': 'main', 'auto_created': True, 'parent_location': None}
        extra.update(data)
        set_doc(cur, 'locations', location, extra, merge=True)


def user_by_uid(cur, uid):
    return get_doc(cur, 'users', uid)


def register_routes(app, db_config, firebase_auth=None):
    from flask import jsonify, request
    import mysql.connector

    def _conn():
        conn = mysql.connector.connect(**db_config)
        cur = conn.cursor(dictionary=True)
        ensure_tables(cur)
        conn.commit()
        return conn, cur

    def _actor():
        remote = (request.remote_addr or '').strip()
        if remote in ('127.0.0.1', '::1') and request.headers.get('X-Hi-Local') == '1':
            return {
                'uid': request.headers.get('X-Hi-Uid') or 'local-test',
                'role': (request.headers.get('X-Hi-Role') or 'boss').strip().lower(),
                'name': request.headers.get('X-Hi-Name') or 'Local Test',
                'email': request.headers.get('X-Hi-Email') or '',
            }
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
        }
        try:
            conn, cur = _conn()
            try:
                user = user_by_uid(cur, uid)
                if user:
                    data = user.get('data') or {}
                    actor['role'] = str(data.get('role') or actor['role']).strip().lower()
                    actor['name'] = data.get('name') or actor['name']
                    actor['email'] = data.get('email') or actor['email']
            finally:
                cur.close(); conn.close()
        except Exception as e:
            log.warning('app_docs actor profile: %s', e)
        return actor

    def _require(roles=None):
        actor = _actor()
        if not actor:
            return None, (jsonify({'success': False, 'error': 'Sign in required'}), 401)
        if roles and actor.get('role') not in roles:
            return None, (jsonify({'success': False, 'error': 'Not allowed'}), 403)
        return actor, None

    def _body():
        return request.get_json(silent=True) or {}

    def _query_collection(cur, collection, payload):
        filters = payload.get('filters') or []
        order_by = payload.get('orderBy') or payload.get('order_by')
        limit = payload.get('limit')
        if collection == 'payments':
            return query_mysql_payments(cur, filters, order_by, limit)
        return query_docs(cur, collection, filters, order_by, limit)

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
            docs = _query_collection(cur, collection, data)
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
            if collection == 'payments':
                cur.execute("SELECT id, location, amount, duration, username, timestamp, phone, payment_method FROM payments WHERE id=%s", (doc_id,))
                row = cur.fetchone()
                if not row:
                    return jsonify({'success': True, 'exists': False, 'doc': None})
                return jsonify({'success': True, 'exists': True, 'doc': _payment_doc(row)})
            doc = get_doc(cur, collection, doc_id)
            if not doc:
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
            if collection == 'payments' and request.method == 'POST':
                cur.execute(
                    """
                    INSERT INTO payments (location, amount, duration, username, phone, payment_method)
                    VALUES (%s,%s,%s,%s,%s,%s)
                    """,
                    (
                        payload.get('location'),
                        payload.get('amount') or 0,
                        payload.get('duration'),
                        payload.get('username') or payload.get('voucher'),
                        payload.get('phone'),
                        payload.get('payment_method'),
                    ),
                )
                doc_id = str(cur.lastrowid)
                bump_location_metadata(cur, payload.get('location'), payload.get('amount') or 0)
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
                if kind == 'delete':
                    delete_doc(cur, collection, doc_id)
                else:
                    set_doc(cur, collection, doc_id, op.get('data') or {}, merge=bool(op.get('merge') or kind == 'update'))
                ids.append(doc_id)
            conn.commit()
            return jsonify({'success': True, 'ids': ids})
        finally:
            cur.close(); conn.close()

    @app.route('/api/auth/create-user', methods=['POST'])
    def app_create_user():
        actor, err = _require(('boss', 'admin'))
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
            location = (data.get('location') or '').strip()
            locations = data.get('locations') or []
            if role == 'agent' and location:
                if not get_doc(cur, 'locations', location):
                    return jsonify({'success': False, 'error': "Location '%s' does not exist in the system" % location}), 400
            if role == 'superagent':
                for loc in locations:
                    if loc and not get_doc(cur, 'locations', str(loc).strip()):
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
        actor, err = _require(('boss', 'admin'))
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
        actor, err = _require(('boss', 'admin'))
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

    return app
