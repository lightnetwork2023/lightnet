"""Home-internet billing on MySQL (replaces Firestore home_customers)."""
from __future__ import annotations

import json
import logging
import random
import uuid
from datetime import datetime

log = logging.getLogger(__name__)


def _widen_columns(cur) -> None:
    cur.execute("ALTER TABLE hi_payments MODIFY reference TEXT NULL")
    cur.execute("ALTER TABLE hi_payments MODIFY notes TEXT NULL")
    cur.execute("ALTER TABLE hi_customers MODIFY notes TEXT NULL")
    cur.execute("ALTER TABLE hi_customers MODIFY address TEXT NULL")


def ensure_tables(cur) -> None:
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS hi_customers (
            id VARCHAR(16) NOT NULL PRIMARY KEY,
            name VARCHAR(191) NOT NULL DEFAULT '',
            phone VARCHAR(32) NOT NULL DEFAULT '',
            location VARCHAR(191) NOT NULL DEFAULT '',
            zone VARCHAR(191) NOT NULL DEFAULT '',
            speed_mbps INT NOT NULL DEFAULT 0,
            customer_type VARCHAR(64) NOT NULL DEFAULT '',
            plan_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
            currency VARCHAR(8) NOT NULL DEFAULT 'TZS',
            schedule VARCHAR(16) NOT NULL DEFAULT 'monthly',
            start_date DATETIME NULL,
            billing_day_of_month INT NULL,
            billing_weekday INT NULL,
            address TEXT NULL,
            notes TEXT NULL,
            created_by_uid VARCHAR(128) NULL,
            created_by_name VARCHAR(191) NULL,
            created_at DATETIME NULL,
            updated_at DATETIME NULL,
            updated_by_uid VARCHAR(128) NULL,
            updated_by_name VARCHAR(191) NULL,
            active TINYINT(1) NOT NULL DEFAULT 1,
            archived TINYINT(1) NOT NULL DEFAULT 0,
            archived_at DATETIME NULL,
            archived_by_uid VARCHAR(128) NULL,
            archived_by_name VARCHAR(191) NULL,
            restored_at DATETIME NULL,
            restored_by_uid VARCHAR(128) NULL,
            restored_by_name VARCHAR(191) NULL,
            login_email VARCHAR(191) NULL,
            status_json JSON NULL,
            sort_key DOUBLE NULL,
            extra_json JSON NULL,
            KEY idx_hi_cust_arch (archived, created_at),
            KEY idx_hi_cust_zone (zone),
            KEY idx_hi_cust_type (customer_type)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS hi_payments (
            id VARCHAR(64) NOT NULL PRIMARY KEY,
            customer_id VARCHAR(16) NOT NULL,
            amount_paid DECIMAL(12,2) NOT NULL DEFAULT 0,
            currency VARCHAR(8) NOT NULL DEFAULT 'TZS',
            attachments_json JSON NULL,
            status VARCHAR(32) NOT NULL DEFAULT 'pendingApproval',
            created_by_uid VARCHAR(128) NULL,
            created_by_name VARCHAR(191) NULL,
            created_at DATETIME NULL,
            approved_by_uid VARCHAR(128) NULL,
            approved_by_name VARCHAR(191) NULL,
            approved_at DATETIME NULL,
            schedule VARCHAR(16) NULL,
            period_start DATETIME NULL,
            period_end DATETIME NULL,
            due_date DATETIME NULL,
            reference TEXT NULL,
            notes TEXT NULL,
            payment_type VARCHAR(64) NULL,
            customer_zone VARCHAR(191) NULL,
            customer_type VARCHAR(64) NULL,
            extra_json JSON NULL,
            KEY idx_hi_pay_cust (customer_id, created_at),
            KEY idx_hi_pay_status (status, created_at),
            KEY idx_hi_pay_approved (approved_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS hi_plan_snapshots (
            id VARCHAR(64) NOT NULL PRIMARY KEY,
            customer_id VARCHAR(16) NOT NULL,
            amount DECIMAL(12,2) NOT NULL DEFAULT 0,
            currency VARCHAR(8) NOT NULL DEFAULT 'TZS',
            effective_from DATETIME NULL,
            extra_json JSON NULL,
            KEY idx_hi_plan_cust (customer_id, effective_from)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS hi_config (
            id VARCHAR(64) NOT NULL PRIMARY KEY,
            zones_json JSON NULL,
            customer_types_json JSON NULL,
            updated_at DATETIME NULL,
            updated_by_uid VARCHAR(128) NULL,
            updated_by_name VARCHAR(191) NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS firestore_export (
            collection_path VARCHAR(255) NOT NULL,
            doc_id VARCHAR(191) NOT NULL,
            data_json LONGTEXT NULL,
            exported_at DATETIME NOT NULL,
            PRIMARY KEY (collection_path, doc_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    try:
        _widen_columns(cur)
    except Exception as e:
        log.debug('hi widen skip: %s', e)
    try:
        import lightnet_hi_billing as hb
        hb.ensure_invoice_table(cur)
    except Exception as e:
        log.debug('hi invoices skip: %s', e)


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


def _json(v):
    if v is None:
        return None
    if isinstance(v, (dict, list)):
        return json.dumps(v, default=str)
    if isinstance(v, str):
        return v
    return json.dumps(v, default=str)


def _loads(v, default=None):
    if v is None:
        return default
    if isinstance(v, (dict, list)):
        return v
    try:
        return json.loads(v)
    except Exception:
        return default


def new_id() -> str:
    return uuid.uuid4().hex


def public_customer(row: dict) -> dict:
    extra = _loads(row.get('extra_json'), {}) or {}
    status = _loads(row.get('status_json'), extra.get('status'))
    out = {
        'id': row.get('id'),
        'name': row.get('name') or '',
        'phone': row.get('phone') or '',
        'location': row.get('location') or '',
        'zone': row.get('zone') or '',
        'speed_mbps': int(row.get('speed_mbps') or 0),
        'customer_type': row.get('customer_type') or '',
        'plan_amount': float(row.get('plan_amount') or 0),
        'currency': row.get('currency') or 'TZS',
        'schedule': row.get('schedule') or 'monthly',
        'start_date': _iso(row.get('start_date')),
        'billing_day_of_month': row.get('billing_day_of_month'),
        'billing_weekday': row.get('billing_weekday'),
        'address': row.get('address'),
        'notes': row.get('notes'),
        'created_by_uid': row.get('created_by_uid') or '',
        'created_by_name': row.get('created_by_name') or '',
        'created_at': _iso(row.get('created_at')),
        'updated_at': _iso(row.get('updated_at')),
        'active': bool(row.get('active')),
        'archived': bool(row.get('archived')),
        'archived_at': _iso(row.get('archived_at')),
        'login_email': row.get('login_email'),
        'status': status,
    }
    return out


def public_payment(row: dict) -> dict:
    return {
        'id': row.get('id'),
        'customer_id': row.get('customer_id'),
        'amount_paid': float(row.get('amount_paid') or 0),
        'currency': row.get('currency') or 'TZS',
        'attachments': _loads(row.get('attachments_json'), []) or [],
        'status': row.get('status') or 'pendingApproval',
        'created_by_uid': row.get('created_by_uid') or '',
        'created_by_name': row.get('created_by_name') or '',
        'created_at': _iso(row.get('created_at')),
        'approved_by_uid': row.get('approved_by_uid'),
        'approved_by_name': row.get('approved_by_name'),
        'approved_at': _iso(row.get('approved_at')),
        'schedule': row.get('schedule') or 'monthly',
        'period_start': _iso(row.get('period_start')),
        'period_end': _iso(row.get('period_end')),
        'due_date': _iso(row.get('due_date')),
        'reference': row.get('reference'),
        'notes': row.get('notes'),
        'payment_type': row.get('payment_type'),
        'customer_zone': row.get('customer_zone'),
        'customer_type': row.get('customer_type'),
    }


def get_customer(cur, customer_id, include_archived=False):
    sql = "SELECT * FROM hi_customers WHERE id=%s"
    if not include_archived:
        sql += " AND archived=0"
    cur.execute(sql, (customer_id,))
    return cur.fetchone()


def list_customers(cur, archived=False):
    cur.execute(
        "SELECT * FROM hi_customers WHERE archived=%s ORDER BY created_at DESC",
        (1 if archived else 0,),
    )
    return cur.fetchall() or []


def upsert_customer(cur, data: dict, archived=0):
    cid = str(data['id'])
    cur.execute(
        """
        INSERT INTO hi_customers (
            id, name, phone, location, zone, speed_mbps, customer_type, plan_amount,
            currency, schedule, start_date, billing_day_of_month, billing_weekday,
            address, notes, created_by_uid, created_by_name, created_at, updated_at,
            updated_by_uid, updated_by_name, active, archived, archived_at,
            archived_by_uid, archived_by_name, restored_at, restored_by_uid,
            restored_by_name, login_email, status_json, sort_key, extra_json
        ) VALUES (
            %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
        )
        ON DUPLICATE KEY UPDATE
            name=VALUES(name), phone=VALUES(phone), location=VALUES(location),
            zone=VALUES(zone), speed_mbps=VALUES(speed_mbps),
            customer_type=VALUES(customer_type), plan_amount=VALUES(plan_amount),
            currency=VALUES(currency), schedule=VALUES(schedule),
            start_date=VALUES(start_date), billing_day_of_month=VALUES(billing_day_of_month),
            billing_weekday=VALUES(billing_weekday), address=VALUES(address),
            notes=VALUES(notes), updated_at=VALUES(updated_at),
            updated_by_uid=VALUES(updated_by_uid), updated_by_name=VALUES(updated_by_name),
            active=VALUES(active), archived=VALUES(archived),
            archived_at=VALUES(archived_at), archived_by_uid=VALUES(archived_by_uid),
            archived_by_name=VALUES(archived_by_name), restored_at=VALUES(restored_at),
            login_email=VALUES(login_email), status_json=VALUES(status_json),
            extra_json=VALUES(extra_json)
        """,
        (
            cid,
            data.get('name') or '',
            data.get('phone') or '',
            data.get('location') or '',
            data.get('zone') or '',
            int(data.get('speed_mbps') or 0),
            data.get('customer_type') or '',
            float(data.get('plan_amount') or 0),
            data.get('currency') or 'TZS',
            data.get('schedule') or 'monthly',
            _dt(data.get('start_date')),
            data.get('billing_day_of_month'),
            data.get('billing_weekday'),
            data.get('address'),
            data.get('notes'),
            data.get('created_by_uid'),
            data.get('created_by_name'),
            _dt(data.get('created_at')) or datetime.utcnow(),
            _dt(data.get('updated_at')),
            data.get('updated_by_uid'),
            data.get('updated_by_name'),
            1 if data.get('active', True) else 0,
            archived,
            _dt(data.get('archived_at')),
            data.get('archived_by_uid'),
            data.get('archived_by_name'),
            _dt(data.get('restored_at')),
            data.get('restored_by_uid'),
            data.get('restored_by_name'),
            data.get('login_email'),
            _json(data.get('status')),
            data.get('sort_key'),
            _json(data.get('extra_json') or {}),
        ),
    )
    _sync_customer_doc(cur, cid)
    return cid


def _sync_customer_doc(cur, customer_id):
    try:
        import lightnet_app_docs as ad
        ad.ensure_tables(cur)
        row = get_customer(cur, customer_id, include_archived=True)
        if not row:
            ad.delete_doc(cur, 'home_customers', customer_id)
            ad.delete_doc(cur, 'archived_home_customers', customer_id)
            return
        payload = public_customer(row)
        active_col = 'archived_home_customers' if row.get('archived') else 'home_customers'
        other = 'home_customers' if row.get('archived') else 'archived_home_customers'
        ad.delete_doc(cur, other, customer_id)
        ad.set_doc(cur, active_col, customer_id, payload, merge=False)
    except Exception as e:
        log.warning('hi app_docs sync: %s', e)


def upsert_payment(cur, data: dict):
    pid = str(data['id'])
    cur.execute(
        """
        INSERT INTO hi_payments (
            id, customer_id, amount_paid, currency, attachments_json, status,
            created_by_uid, created_by_name, created_at, approved_by_uid,
            approved_by_name, approved_at, schedule, period_start, period_end,
            due_date, reference, notes, payment_type, customer_zone, customer_type,
            extra_json
        ) VALUES (
            %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
        )
        ON DUPLICATE KEY UPDATE
            amount_paid=VALUES(amount_paid), status=VALUES(status),
            attachments_json=VALUES(attachments_json),
            approved_by_uid=VALUES(approved_by_uid),
            approved_by_name=VALUES(approved_by_name),
            approved_at=VALUES(approved_at), notes=VALUES(notes),
            reference=VALUES(reference)
        """,
        (
            pid,
            str(data.get('customer_id') or ''),
            float(data.get('amount_paid') or 0),
            data.get('currency') or 'TZS',
            _json(data.get('attachments') or []),
            data.get('status') or 'pendingApproval',
            data.get('created_by_uid'),
            data.get('created_by_name'),
            _dt(data.get('created_at')) or datetime.utcnow(),
            data.get('approved_by_uid'),
            data.get('approved_by_name'),
            _dt(data.get('approved_at')),
            data.get('schedule'),
            _dt(data.get('period_start')),
            _dt(data.get('period_end')),
            _dt(data.get('due_date')),
            data.get('reference'),
            data.get('notes'),
            data.get('payment_type'),
            data.get('customer_zone'),
            data.get('customer_type'),
            _json(data.get('extra_json') or {}),
        ),
    )
    return pid


def upsert_plan(cur, data: dict):
    pid = str(data.get('id') or new_id())
    cur.execute(
        """
        INSERT INTO hi_plan_snapshots (id, customer_id, amount, currency, effective_from, extra_json)
        VALUES (%s,%s,%s,%s,%s,%s)
        ON DUPLICATE KEY UPDATE
            amount=VALUES(amount), currency=VALUES(currency),
            effective_from=VALUES(effective_from)
        """,
        (
            pid,
            str(data.get('customer_id') or ''),
            float(data.get('amount') or 0),
            data.get('currency') or 'TZS',
            _dt(data.get('effective_from')),
            _json(data.get('extra_json') or {}),
        ),
    )
    return pid


def unique_customer_id(cur, attempts=50) -> str:
    for _ in range(attempts):
        cid = str(random.randint(0, 99999)).zfill(5)
        cur.execute("SELECT id FROM hi_customers WHERE id=%s", (cid,))
        if not cur.fetchone():
            return cid
    raise ValueError('Could not generate unique customer id')


def get_config(cur):
    cur.execute("SELECT * FROM hi_config WHERE id='enums'")
    row = cur.fetchone()
    if not row:
        return {'zones': [], 'customer_types': []}
    return {
        'zones': _loads(row.get('zones_json'), []) or [],
        'customer_types': _loads(row.get('customer_types_json'), []) or [],
        'updated_at': _iso(row.get('updated_at')),
    }


def set_config(cur, zones, types, uid=None, name=None):
    cur.execute(
        """
        INSERT INTO hi_config (id, zones_json, customer_types_json, updated_at, updated_by_uid, updated_by_name)
        VALUES ('enums', %s, %s, UTC_TIMESTAMP(), %s, %s)
        ON DUPLICATE KEY UPDATE
            zones_json=VALUES(zones_json),
            customer_types_json=VALUES(customer_types_json),
            updated_at=VALUES(updated_at),
            updated_by_uid=VALUES(updated_by_uid),
            updated_by_name=VALUES(updated_by_name)
        """,
        (_json(zones or []), _json(types or []), uid, name),
    )


def list_payments(cur, customer_id, limit=50, status=None):
    sql = "SELECT * FROM hi_payments WHERE customer_id=%s"
    params = [customer_id]
    if status:
        sql += " AND status=%s"
        params.append(status)
    sql += " ORDER BY created_at DESC LIMIT %s"
    params.append(int(limit))
    cur.execute(sql, params)
    return cur.fetchall() or []


def list_pending(cur, limit=100):
    cur.execute(
        """
        SELECT * FROM hi_payments
        WHERE status='pendingApproval'
        ORDER BY created_at DESC LIMIT %s
        """,
        (int(limit),),
    )
    return cur.fetchall() or []


def payments_total(cur, start, end, zone=None, customer_type=None):
    sql = """
        SELECT COALESCE(SUM(amount_paid),0) AS total_amount, COUNT(*) AS count
        FROM hi_payments
        WHERE status='approved' AND approved_at >= %s AND approved_at < %s
    """
    params = [_dt(start), _dt(end)]
    if zone:
        sql += " AND customer_zone=%s"
        params.append(zone)
    if customer_type:
        sql += " AND customer_type=%s"
        params.append(customer_type)
    cur.execute(sql, params)
    row = cur.fetchone() or {}
    return {
        'total_amount': float(row.get('total_amount') or 0),
        'count': int(row.get('count') or 0),
    }


def list_plans(cur, customer_id):
    cur.execute(
        """
        SELECT * FROM hi_plan_snapshots
        WHERE customer_id=%s
        ORDER BY effective_from ASC
        """,
        (customer_id,),
    )
    return cur.fetchall() or []


def public_plan(row: dict) -> dict:
    return {
        'id': row.get('id'),
        'customer_id': row.get('customer_id'),
        'amount': float(row.get('amount') or 0),
        'currency': row.get('currency') or 'TZS',
        'effective_from': _iso(row.get('effective_from')),
    }


def get_payment(cur, payment_id, customer_id=None):
    sql = "SELECT * FROM hi_payments WHERE id=%s"
    params = [payment_id]
    if customer_id:
        sql += " AND customer_id=%s"
        params.append(customer_id)
    cur.execute(sql, params)
    return cur.fetchone()


def archive_customer(cur, customer_id, uid=None, name=None):
    cur.execute(
        """
        UPDATE hi_customers
        SET archived=1, archived_at=UTC_TIMESTAMP(), archived_by_uid=%s, archived_by_name=%s
        WHERE id=%s AND archived=0
        """,
        (uid, name, customer_id),
    )
    ok = cur.rowcount > 0
    if ok:
        _sync_customer_doc(cur, customer_id)
    return ok


def restore_customer(cur, customer_id, uid=None, name=None):
    cur.execute(
        """
        UPDATE hi_customers
        SET archived=0, archived_at=NULL, archived_by_uid=NULL, archived_by_name=NULL,
            restored_at=UTC_TIMESTAMP(), restored_by_uid=%s, restored_by_name=%s
        WHERE id=%s AND archived=1
        """,
        (uid, name, customer_id),
    )
    ok = cur.rowcount > 0
    if ok:
        _sync_customer_doc(cur, customer_id)
    return ok


def _refresh_billing(cur, customer_id, source='live'):
    try:
        import lightnet_hi_billing as hb
        hb.materialize_customer(cur, customer_id, source=source)
    except Exception as e:
        log.warning('hi billing refresh %s: %s', customer_id, e)


def delete_customer(cur, customer_id):
    try:
        import lightnet_hi_billing as hb
        hb.delete_invoices(cur, customer_id)
    except Exception as e:
        log.warning('hi invoice delete %s: %s', customer_id, e)
    cur.execute("DELETE FROM hi_payments WHERE customer_id=%s", (customer_id,))
    cur.execute("DELETE FROM hi_plan_snapshots WHERE customer_id=%s", (customer_id,))
    cur.execute("DELETE FROM hi_customers WHERE id=%s", (customer_id,))
    ok = cur.rowcount > 0
    _sync_customer_doc(cur, customer_id)
    return ok


def set_login_email(cur, customer_id, email):
    cur.execute(
        "UPDATE hi_customers SET login_email=%s WHERE id=%s",
        (email, customer_id),
    )
    return cur.rowcount > 0


def record_auto_payment(cur, customer: dict, amount, phone, provider, reference=None, created_by_name=None):
    now = datetime.utcnow()
    pid = new_id()
    upsert_payment(
        cur,
        {
            'id': pid,
            'customer_id': customer.get('id'),
            'amount_paid': amount,
            'currency': customer.get('currency') or 'TZS',
            'attachments': [],
            'status': 'approved',
            'created_by_uid': 'system',
            'created_by_name': created_by_name or customer.get('name') or 'Home User',
            'created_at': now,
            'approved_by_uid': 'system',
            'approved_by_name': 'Auto-Approved',
            'approved_at': now,
            'schedule': customer.get('schedule') or 'monthly',
            'period_start': now,
            'period_end': now,
            'due_date': now,
            'reference': reference or '%s-%s' % (provider, phone),
            'notes': 'Mobile money payment via %s' % provider,
            'payment_type': provider,
            'customer_zone': customer.get('zone') or '',
            'customer_type': customer.get('customer_type') or '',
        },
    )
    _refresh_billing(cur, customer.get('id'), source='live')
    return pid


def export_doc(cur, collection_path, doc_id, data):
    cur.execute(
        """
        INSERT INTO firestore_export (collection_path, doc_id, data_json, exported_at)
        VALUES (%s, %s, %s, UTC_TIMESTAMP())
        ON DUPLICATE KEY UPDATE data_json=VALUES(data_json), exported_at=VALUES(exported_at)
        """,
        (collection_path, str(doc_id), _json(data)),
    )


def resolve_actor(request, firebase_auth=None, db_config=None, firestore_db=None):
    """Signed-in Firebase user. Profile comes from MySQL app_docs, not Firestore."""
    remote = (request.remote_addr or '').strip()
    if remote in ('127.0.0.1', '::1') and request.headers.get('X-Hi-Local') == '1':
        return {
            'uid': request.headers.get('X-Hi-Uid') or 'local-test',
            'name': request.headers.get('X-Hi-Name') or 'Local Test',
            'role': (request.headers.get('X-Hi-Role') or 'boss').strip().lower(),
            'home_customer_id': request.headers.get('X-Hi-Customer') or '',
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
        log.warning('hi auth token failed: %s', e)
        return None
    uid = decoded.get('uid')
    actor = {
        'uid': uid,
        'name': decoded.get('name') or '',
        'role': 'technician',
        'home_customer_id': '',
        'email': decoded.get('email') or '',
    }
    if db_config and uid:
        try:
            import lightnet_app_docs
            conn, cur = lightnet_app_docs.store_connect(db_config)
            try:
                user = lightnet_app_docs.user_by_uid(cur, uid)
                if user:
                    data = user.get('data') or {}
                    actor['role'] = str(data.get('role') or actor['role']).strip().lower()
                    actor['name'] = data.get('name') or actor['name']
                    actor['home_customer_id'] = str(data.get('home_customer_id') or '')
                    actor['email'] = data.get('email') or actor['email']
            finally:
                cur.close(); conn.close()
        except Exception as e:
            log.warning('hi actor profile failed: %s', e)
    return actor


def can_view_customer(actor, customer_id):
    if not actor:
        return False
    if actor.get('role') in ('boss', 'admin', 'technician', 'superagent', 'agent'):
        return True
    if actor.get('role') == 'homeuser':
        return str(actor.get('home_customer_id') or '') == str(customer_id)
    return False


def register_hi_routes(app, db_config, firebase_auth=None, firestore_db=None):
    from flask import jsonify, request
    import mysql.connector

    def _conn():
        conn = mysql.connector.connect(**db_config)
        cur = conn.cursor(dictionary=True)
        ensure_tables(cur)
        conn.commit()
        return conn, cur

    def _auth(required_roles=None):
        actor = resolve_actor(request, firebase_auth, db_config=db_config)
        if not actor:
            return None, (jsonify({'success': False, 'error': 'Sign in required'}), 401)
        if required_roles and actor.get('role') not in required_roles:
            return None, (jsonify({'success': False, 'error': 'Not allowed'}), 403)
        return actor, None

    def _body():
        return request.get_json(silent=True) or {}

    @app.route('/api/hi/config', methods=['GET'])
    def hi_get_config():
        actor, err = _auth()
        if err:
            return err
        conn, cur = _conn()
        try:
            return jsonify({'success': True, **get_config(cur)})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/config', methods=['PUT', 'POST'])
    def hi_set_config():
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        data = _body()
        conn, cur = _conn()
        try:
            set_config(
                cur,
                data.get('zones') or [],
                data.get('customer_types') or data.get('customerTypes') or [],
                uid=actor.get('uid'),
                name=actor.get('name'),
            )
            conn.commit()
            return jsonify({'success': True, **get_config(cur)})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/new-id', methods=['GET'])
    def hi_new_id():
        actor, err = _auth()
        if err:
            return err
        conn, cur = _conn()
        try:
            return jsonify({'success': True, 'id': unique_customer_id(cur)})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers', methods=['GET'])
    def hi_list_customers():
        actor, err = _auth()
        if err:
            return err
        archived = str(request.args.get('archived') or '0') in ('1', 'true', 'yes')
        if archived and actor.get('role') not in ('boss', 'admin'):
            return jsonify({'success': False, 'error': 'Only boss can view archived customers'}), 403
        if actor.get('role') == 'homeuser':
            conn, cur = _conn()
            try:
                row = get_customer(cur, actor.get('home_customer_id'), include_archived=True)
                items = [public_customer(row)] if row else []
                return jsonify({'success': True, 'customers': items})
            finally:
                cur.close(); conn.close()
        conn, cur = _conn()
        try:
            rows = list_customers(cur, archived=archived)
            return jsonify({'success': True, 'customers': [public_customer(r) for r in rows]})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>', methods=['GET'])
    def hi_get_customer(customer_id):
        actor, err = _auth()
        if err:
            return err
        if not can_view_customer(actor, customer_id):
            return jsonify({'success': False, 'error': 'Not allowed'}), 403
        conn, cur = _conn()
        try:
            row = get_customer(cur, customer_id, include_archived=True)
            if not row:
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            return jsonify({'success': True, 'customer': public_customer(row)})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers', methods=['POST'])
    def hi_create_customer():
        actor, err = _auth()
        if err:
            return err
        if actor.get('role') == 'homeuser':
            return jsonify({'success': False, 'error': 'Not allowed'}), 403
        data = _body()
        conn, cur = _conn()
        try:
            cid = str(data.get('id') or '').strip() or unique_customer_id(cur)
            now = datetime.utcnow()
            payload = dict(data)
            payload['id'] = cid
            payload.setdefault('created_by_uid', actor.get('uid'))
            payload.setdefault('created_by_name', actor.get('name'))
            payload.setdefault('created_at', data.get('created_at') or now)
            payload.setdefault('active', True)
            upsert_customer(cur, payload, archived=0)
            if data.get('plan_amount') is not None:
                upsert_plan(
                    cur,
                    {
                        'id': new_id(),
                        'customer_id': cid,
                        'amount': data.get('plan_amount'),
                        'currency': data.get('currency') or 'TZS',
                        'effective_from': data.get('start_date') or now,
                    },
                )
            _refresh_billing(cur, cid, source='live')
            conn.commit()
            row = get_customer(cur, cid, include_archived=True)
            return jsonify({'success': True, 'customer': public_customer(row)}), 201
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>', methods=['PATCH', 'PUT'])
    def hi_update_customer(customer_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        data = _body()
        conn, cur = _conn()
        try:
            existing = get_customer(cur, customer_id, include_archived=True)
            if not existing:
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            merged = public_customer(existing)
            for key in (
                'name', 'phone', 'location', 'zone', 'speed_mbps', 'customer_type',
                'plan_amount', 'currency', 'schedule', 'start_date',
                'billing_day_of_month', 'billing_weekday', 'address', 'notes',
                'active', 'login_email',
            ):
                if key in data:
                    merged[key] = data[key]
            merged['updated_at'] = datetime.utcnow()
            merged['updated_by_uid'] = actor.get('uid')
            merged['updated_by_name'] = actor.get('name')
            upsert_customer(cur, merged, archived=1 if existing.get('archived') else 0)
            old_amt = float(existing.get('plan_amount') or 0)
            old_cur = existing.get('currency') or 'TZS'
            new_amt = float(merged.get('plan_amount') or 0)
            new_cur = merged.get('currency') or 'TZS'
            if new_amt != old_amt or new_cur != old_cur:
                upsert_plan(
                    cur,
                    {
                        'id': new_id(),
                        'customer_id': customer_id,
                        'amount': new_amt,
                        'currency': new_cur,
                        'effective_from': datetime.utcnow(),
                    },
                )
            _refresh_billing(cur, customer_id, source='live')
            conn.commit()
            row = get_customer(cur, customer_id, include_archived=True)
            return jsonify({'success': True, 'customer': public_customer(row)})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/archive', methods=['POST'])
    def hi_archive_customer(customer_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        conn, cur = _conn()
        try:
            pending = list_payments(cur, customer_id, limit=1, status='pendingApproval')
            if pending:
                return jsonify({'success': False, 'error': 'Cannot archive: customer has pending approval payments'}), 400
            if not archive_customer(cur, customer_id, actor.get('uid'), actor.get('name')):
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            conn.commit()
            return jsonify({'success': True})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/restore', methods=['POST'])
    def hi_restore_customer(customer_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        conn, cur = _conn()
        try:
            active = get_customer(cur, customer_id, include_archived=False)
            if active:
                return jsonify({'success': False, 'error': 'Customer already exists in active collection'}), 400
            if not restore_customer(cur, customer_id, actor.get('uid'), actor.get('name')):
                return jsonify({'success': False, 'error': 'Archived customer not found'}), 404
            conn.commit()
            return jsonify({'success': True})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>', methods=['DELETE'])
    def hi_delete_customer(customer_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        conn, cur = _conn()
        try:
            if not delete_customer(cur, customer_id):
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            conn.commit()
            return jsonify({'success': True})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/login-email', methods=['POST'])
    def hi_set_login_email(customer_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        email = (_body().get('email') or '').strip()
        if not email:
            return jsonify({'success': False, 'error': 'email required'}), 400
        conn, cur = _conn()
        try:
            if not get_customer(cur, customer_id, include_archived=True):
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            set_login_email(cur, customer_id, email)
            conn.commit()
            return jsonify({'success': True, 'login_email': email})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/payments', methods=['GET'])
    def hi_list_payments(customer_id):
        actor, err = _auth()
        if err:
            return err
        if not can_view_customer(actor, customer_id):
            return jsonify({'success': False, 'error': 'Not allowed'}), 403
        status = request.args.get('status')
        limit = int(request.args.get('limit') or 50)
        conn, cur = _conn()
        try:
            rows = list_payments(cur, customer_id, limit=limit, status=status)
            return jsonify({'success': True, 'payments': [public_payment(r) for r in rows]})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/payments', methods=['POST'])
    def hi_add_payment(customer_id):
        actor, err = _auth()
        if err:
            return err
        if not can_view_customer(actor, customer_id):
            return jsonify({'success': False, 'error': 'Not allowed'}), 403
        data = _body()
        conn, cur = _conn()
        try:
            cust = get_customer(cur, customer_id, include_archived=False)
            if not cust:
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            pid = str(data.get('id') or new_id())
            payload = dict(data)
            payload['id'] = pid
            payload['customer_id'] = customer_id
            payload.setdefault('status', 'pendingApproval')
            payload.setdefault('created_by_uid', actor.get('uid'))
            payload.setdefault('created_by_name', actor.get('name'))
            payload.setdefault('created_at', datetime.utcnow())
            payload.setdefault('schedule', cust.get('schedule'))
            payload.setdefault('customer_zone', cust.get('zone'))
            payload.setdefault('customer_type', cust.get('customer_type'))
            payload.setdefault('currency', cust.get('currency') or 'TZS')
            upsert_payment(cur, payload)
            conn.commit()
            row = get_payment(cur, pid)
            return jsonify({'success': True, 'payment': public_payment(row)}), 201
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/payments/<payment_id>/approve', methods=['POST'])
    def hi_approve_payment(customer_id, payment_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        conn, cur = _conn()
        try:
            row = get_payment(cur, payment_id, customer_id)
            if not row:
                return jsonify({'success': False, 'error': 'Payment not found'}), 404
            if row.get('created_by_uid') and row.get('created_by_uid') == actor.get('uid'):
                return jsonify({'success': False, 'error': 'You cannot approve your own entry'}), 400
            payload = public_payment(row)
            payload['status'] = 'approved'
            payload['approved_by_uid'] = actor.get('uid')
            payload['approved_by_name'] = actor.get('name')
            payload['approved_at'] = datetime.utcnow()
            upsert_payment(cur, payload)
            _refresh_billing(cur, customer_id, source='live')
            conn.commit()
            return jsonify({'success': True, 'payment': public_payment(get_payment(cur, payment_id))})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/payments/<payment_id>/reject', methods=['POST'])
    def hi_reject_payment(customer_id, payment_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        data = _body()
        conn, cur = _conn()
        try:
            row = get_payment(cur, payment_id, customer_id)
            if not row:
                return jsonify({'success': False, 'error': 'Payment not found'}), 404
            if row.get('created_by_uid') and row.get('created_by_uid') == actor.get('uid'):
                return jsonify({'success': False, 'error': 'You cannot reject your own entry'}), 400
            payload = public_payment(row)
            payload['status'] = 'rejected'
            payload['approved_by_uid'] = actor.get('uid')
            payload['approved_by_name'] = actor.get('name')
            payload['approved_at'] = datetime.utcnow()
            if data.get('reason'):
                payload['notes'] = 'Rejected: %s' % data.get('reason')
            upsert_payment(cur, payload)
            _refresh_billing(cur, customer_id, source='live')
            conn.commit()
            return jsonify({'success': True, 'payment': public_payment(get_payment(cur, payment_id))})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/pending', methods=['GET'])
    def hi_pending():
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        limit = int(request.args.get('limit') or 100)
        conn, cur = _conn()
        try:
            rows = list_pending(cur, limit=limit)
            return jsonify({'success': True, 'payments': [public_payment(r) for r in rows]})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/plans', methods=['GET'])
    def hi_list_plans(customer_id):
        actor, err = _auth()
        if err:
            return err
        if not can_view_customer(actor, customer_id):
            return jsonify({'success': False, 'error': 'Not allowed'}), 403
        conn, cur = _conn()
        try:
            rows = list_plans(cur, customer_id)
            return jsonify({'success': True, 'plans': [public_plan(r) for r in rows]})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/plans', methods=['POST'])
    def hi_add_plan(customer_id):
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        data = _body()
        conn, cur = _conn()
        try:
            if not get_customer(cur, customer_id, include_archived=True):
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            pid = upsert_plan(
                cur,
                {
                    'id': data.get('id') or new_id(),
                    'customer_id': customer_id,
                    'amount': data.get('amount'),
                    'currency': data.get('currency') or 'TZS',
                    'effective_from': data.get('effective_from') or datetime.utcnow(),
                },
            )
            _refresh_billing(cur, customer_id, source='live')
            conn.commit()
            rows = list_plans(cur, customer_id)
            return jsonify({'success': True, 'id': pid, 'plans': [public_plan(r) for r in rows]}), 201
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/status', methods=['GET'])
    def hi_customer_status(customer_id):
        actor, err = _auth()
        if err:
            return err
        if not can_view_customer(actor, customer_id):
            return jsonify({'success': False, 'error': 'Not allowed'}), 403
        conn, cur = _conn()
        try:
            import lightnet_hi_billing as hb
            statement = hb.materialize_customer(cur, customer_id, source='live')
            if not statement:
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            conn.commit()
            return jsonify({'success': True, **statement})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/customers/<customer_id>/invoices', methods=['GET'])
    def hi_customer_invoices(customer_id):
        actor, err = _auth()
        if err:
            return err
        if not can_view_customer(actor, customer_id):
            return jsonify({'success': False, 'error': 'Not allowed'}), 403
        conn, cur = _conn()
        try:
            import lightnet_hi_billing as hb
            statement = hb.materialize_customer(cur, customer_id, source='live')
            if not statement:
                return jsonify({'success': False, 'error': 'Customer not found'}), 404
            conn.commit()
            return jsonify({
                'success': True,
                'invoices': statement.get('invoices') or [],
                'periods': statement.get('periods') or [],
                'statement': {k: v for k, v in statement.items() if k not in ('invoices', 'periods')},
            })
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/invoices/materialize', methods=['POST', 'GET'])
    def hi_materialize_invoices():
        actor, err = _auth(('boss', 'admin'))
        if err:
            return err
        source = (request.args.get('source') or (_body().get('source') if request.method == 'POST' else None) or 'rollover')
        if source not in ('backfill', 'rollover', 'live'):
            source = 'rollover'
        archived = str(request.args.get('archived') or '0') in ('1', 'true', 'yes')
        conn, cur = _conn()
        try:
            import lightnet_hi_billing as hb
            result = hb.materialize_all(cur, source=source, archived=archived)
            conn.commit()
            return jsonify({'success': True, **result})
        finally:
            cur.close(); conn.close()

    @app.route('/api/hi/analytics/payments', methods=['GET'])
    def hi_payments_total():
        actor, err = _auth()
        if err:
            return err
        start = request.args.get('start')
        end = request.args.get('end')
        if not start or not end:
            return jsonify({'success': False, 'error': 'start and end required'}), 400
        conn, cur = _conn()
        try:
            result = payments_total(
                cur,
                start,
                end,
                zone=request.args.get('zone'),
                customer_type=request.args.get('customer_type'),
            )
            return jsonify({'success': True, **result})
        finally:
            cur.close(); conn.close()

    return app

