"""Pending Azam checkouts and payment kind helpers.

Live-safe: additive schema only (payment_intents table + payments.kind columns).
Callback fulfills from this row when Azam omits additionalProperties.
"""
from __future__ import annotations

import json
from datetime import datetime

KIND_CUSTOMER = 'customer'
KIND_AGENT_STOCK = 'agent_stock'
KIND_TEST = 'test'
KIND_HOME_USER = 'home_user'

VALID_KINDS = (KIND_CUSTOMER, KIND_AGENT_STOCK, KIND_TEST, KIND_HOME_USER)
_SCHEMA_READY = False


def _row_val(row, idx=0):
    if row is None:
        return None
    if isinstance(row, dict):
        return next(iter(row.values()))
    return row[idx]


def _has_column(cur, table, column):
    cur.execute(
        """
        SELECT COUNT(*) FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME=%s AND COLUMN_NAME=%s
        """,
        (table, column),
    )
    return int(_row_val(cur.fetchone()) or 0) > 0


def _has_index(cur, table, index_name):
    cur.execute(
        """
        SELECT COUNT(*) FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME=%s AND INDEX_NAME=%s
        """,
        (table, index_name),
    )
    return int(_row_val(cur.fetchone()) or 0) > 0


def ensure_schema(cur):
    """Create payment_intents and add payments.kind columns if missing."""
    global _SCHEMA_READY
    if _SCHEMA_READY:
        return
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS payment_intents (
          id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
          external_id VARCHAR(64) NOT NULL,
          azam_transaction_id VARCHAR(128) NULL,
          kind VARCHAR(32) NOT NULL DEFAULT 'customer',
          status VARCHAR(16) NOT NULL DEFAULT 'pending',
          phone VARCHAR(32) NULL,
          amount DECIMAL(12,2) NULL,
          quantity INT NULL,
          days INT NULL,
          duration_seconds INT NULL,
          location VARCHAR(191) NULL,
          provider VARCHAR(32) NULL,
          mac_address VARCHAR(64) NULL,
          nas_ip VARCHAR(64) NULL,
          ap_mac VARCHAR(64) NULL,
          voucher VARCHAR(64) NULL,
          speed_limit VARCHAR(32) NULL,
          payment_method VARCHAR(32) NULL,
          owner_id INT UNSIGNED NULL,
          site_id INT UNSIGNED NULL,
          buy_payment_id INT UNSIGNED NULL,
          customer_id VARCHAR(64) NULL,
          extra_json TEXT NULL,
          created_at DATETIME NOT NULL,
          paid_at DATETIME NULL,
          UNIQUE KEY uq_payment_intents_external (external_id),
          KEY idx_payment_intents_status (status),
          KEY idx_payment_intents_azam_tx (azam_transaction_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        """
    )
    for col, ddl in (
        ('kind', "ALTER TABLE payments ADD COLUMN kind VARCHAR(32) NULL"),
        ('quantity', "ALTER TABLE payments ADD COLUMN quantity INT NULL"),
        ('external_id', "ALTER TABLE payments ADD COLUMN external_id VARCHAR(64) NULL"),
        ('intent_id', "ALTER TABLE payments ADD COLUMN intent_id INT UNSIGNED NULL"),
    ):
        if not _has_column(cur, 'payments', col):
            cur.execute(ddl)
    if _has_column(cur, 'payments', 'kind') and not _has_index(cur, 'payments', 'idx_payments_kind'):
        cur.execute("ALTER TABLE payments ADD KEY idx_payments_kind (kind)")
    if _has_column(cur, 'payments', 'external_id') and not _has_index(cur, 'payments', 'idx_payments_external_id'):
        try:
            cur.execute("ALTER TABLE payments ADD UNIQUE KEY idx_payments_external_id (external_id)")
        except Exception:
            cur.execute("ALTER TABLE payments ADD KEY idx_payments_external_id (external_id)")
    if _has_column(cur, 'payments', 'kind'):
        cur.execute(
            "SELECT 1 FROM payments WHERE kind IS NULL OR kind='' LIMIT 1"
        )
        if cur.fetchone():
            cur.execute(
                """
                UPDATE payments
                SET kind='agent_stock'
                WHERE (kind IS NULL OR kind='') AND (phone='12345678' OR username='12345678')
                """
            )
            cur.execute(
                """
                UPDATE payments
                SET kind='customer'
                WHERE (kind IS NULL OR kind='')
                """
            )
    _SCHEMA_READY = True


def azam_status(data):
    data = data or {}
    raw = (
        data.get('transactionstatus')
        or data.get('transactionStatus')
        or data.get('status')
        or ''
    )
    return str(raw).strip().lower()


def azam_external_id(data, extra=None):
    extra = extra or {}
    data = data or {}
    val = (
        extra.get('external_id')
        or extra.get('externalId')
        or data.get('externalId')
        or data.get('externalid')
        or data.get('external_id')
        or ''
    )
    val = str(val).strip()
    return val or None


def azam_transaction_id(data):
    data = data or {}
    val = (
        data.get('transactionId')
        or data.get('transactionid')
        or data.get('transid')
        or ''
    )
    val = str(val).strip()
    return val or None


def azam_phone(data, intent=None):
    data = data or {}
    intent = intent or {}
    phone = (
        data.get('msisdn')
        or data.get('accountNumber')
        or data.get('accountnumber')
        or intent.get('phone')
        or ''
    )
    return str(phone).strip()


def azam_amount(data, intent=None, default=0):
    data = data or {}
    intent = intent or {}
    raw = data.get('amount')
    if raw in (None, ''):
        raw = intent.get('amount')
    if raw in (None, ''):
        raw = default
    try:
        return float(raw)
    except (TypeError, ValueError):
        return float(default or 0)


def create_intent(
    cur,
    *,
    external_id,
    kind,
    phone=None,
    amount=None,
    quantity=None,
    days=None,
    duration_seconds=None,
    location=None,
    provider=None,
    mac_address=None,
    nas_ip=None,
    ap_mac=None,
    voucher=None,
    speed_limit=None,
    payment_method=None,
    owner_id=None,
    site_id=None,
    buy_payment_id=None,
    customer_id=None,
    extra=None,
):
    extra_json = json.dumps(extra) if extra else None
    cur.execute(
        """
        INSERT INTO payment_intents (
          external_id, kind, status, phone, amount, quantity, days, duration_seconds,
          location, provider, mac_address, nas_ip, ap_mac, voucher, speed_limit,
          payment_method, owner_id, site_id, buy_payment_id, customer_id, extra_json, created_at
        ) VALUES (
          %s,%s,'pending',%s,%s,%s,%s,%s,
          %s,%s,%s,%s,%s,%s,%s,
          %s,%s,%s,%s,%s,%s,%s
        )
        """,
        (
            external_id, kind, phone, amount, quantity, days, duration_seconds,
            location, provider, mac_address, nas_ip, ap_mac, voucher, speed_limit,
            payment_method, owner_id, site_id, buy_payment_id, customer_id, extra_json,
            datetime.now(),
        ),
    )
    return cur.lastrowid


def get_intent_by_external_id(cur, external_id):
    if not external_id:
        return None
    cur.execute("SELECT * FROM payment_intents WHERE external_id=%s LIMIT 1", (external_id,))
    return cur.fetchone()


def get_intent_by_azam_tx(cur, azam_tx):
    if not azam_tx:
        return None
    cur.execute(
        "SELECT * FROM payment_intents WHERE azam_transaction_id=%s LIMIT 1",
        (azam_tx,),
    )
    return cur.fetchone()


def get_payment_by_external_id(cur, external_id):
    if not external_id:
        return None
    cur.execute("SELECT id FROM payments WHERE external_id=%s LIMIT 1", (external_id,))
    return cur.fetchone()


def intent_as_additional_properties(intent):
    """Rebuild Azam additionalProperties from a stored pending row."""
    if not intent:
        return {}
    extra = {}
    raw = intent.get('extra_json') if isinstance(intent, dict) else None
    if raw:
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict):
                extra.update(parsed)
        except Exception:
            pass
    mapping = {
        'voucher': intent.get('voucher'),
        'duration': intent.get('duration_seconds'),
        'location': intent.get('location'),
        'mac_address': intent.get('mac_address'),
        'nas_ip': intent.get('nas_ip'),
        'ap_mac': intent.get('ap_mac'),
        'payment_method': intent.get('payment_method'),
        'quantity': intent.get('quantity'),
        'days': intent.get('days'),
        'kind': intent.get('kind'),
        'external_id': intent.get('external_id'),
        'customer_id': intent.get('customer_id'),
        'speed_limit': intent.get('speed_limit'),
        'intent_id': intent.get('id'),
        'buy_payment_id': intent.get('buy_payment_id'),
    }
    for key, val in mapping.items():
        if val is not None and val != '':
            extra.setdefault(key, val)
    if intent.get('kind') == KIND_HOME_USER and intent.get('customer_id'):
        extra.setdefault('quantity', intent.get('customer_id'))
    return extra


def merge_additional_properties(callback_data, intent):
    extra = dict((callback_data or {}).get('additionalProperties') or {})
    if not extra:
        extra = {}
    stored = intent_as_additional_properties(intent)
    for key, val in stored.items():
        if extra.get(key) in (None, ''):
            extra[key] = val
    return extra


def set_azam_transaction_id(cur, intent_id, azam_tx):
    if not intent_id or not azam_tx:
        return
    cur.execute(
        """
        UPDATE payment_intents
        SET azam_transaction_id=%s
        WHERE id=%s AND (azam_transaction_id IS NULL OR azam_transaction_id='')
        """,
        (azam_tx, intent_id),
    )


def mark_intent_failed(cur, intent_id):
    if not intent_id:
        return
    cur.execute(
        "UPDATE payment_intents SET status='failed' WHERE id=%s AND status='pending'",
        (intent_id,),
    )


def mark_intent_paid(cur, intent_id, azam_tx=None):
    if not intent_id:
        return
    cur.execute(
        """
        UPDATE payment_intents
        SET status='paid', paid_at=%s, azam_transaction_id=COALESCE(%s, azam_transaction_id)
        WHERE id=%s
        """,
        (datetime.now(), azam_tx, intent_id),
    )


def claim_intent_for_fulfill(cur, intent_id):
    """Lock a pending intent. Returns the row, or None if already paid."""
    if not intent_id:
        return None
    cur.execute("SELECT * FROM payment_intents WHERE id=%s FOR UPDATE", (intent_id,))
    row = cur.fetchone()
    if not row:
        return None
    if row.get('status') == 'paid':
        return row
    cur.execute(
        "UPDATE payment_intents SET status='processing' WHERE id=%s AND status IN ('pending','failed','processing')",
        (intent_id,),
    )
    cur.execute("SELECT * FROM payment_intents WHERE id=%s FOR UPDATE", (intent_id,))
    return cur.fetchone()


def checkout_response_transaction_id(payload):
    if not isinstance(payload, dict):
        return None
    val = payload.get('transactionId') or payload.get('transactionid')
    data = payload.get('data')
    if not val and isinstance(data, dict):
        val = data.get('transactionId') or data.get('transactionid')
    val = str(val or '').strip()
    return val or None
