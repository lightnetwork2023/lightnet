#!/usr/bin/env python3
"""One-shot: remove leftover usage fields from mikrotik_devices.

Run on the LightNet server as root (Admin SDK bypasses client rules):

  sudo python3 scripts/clear_mikrotik_usage_fields.py

Does not delete routers. Only strips usage blobs the old app still displays.
Flask will write them again only if POST /check_mikrotik_status is called.
"""
import firebase_admin
from firebase_admin import credentials, firestore

KEY = '/root/lightnetwork-firebase-key.json'
FIELDS = (
    'live_speed',
    'wan_traffic_total',
    'wan_stats',
    'wan_updated_at',
    'system_resources',
    'connected_clients',
    'clients_count',
    'clients_updated_at',
)


def main():
    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(KEY))
    db = firestore.client()
    deleted = firestore.DELETE_FIELD
    updated = 0
    skipped = 0
    for doc in db.collection('mikrotik_devices').stream():
        data = doc.to_dict() or {}
        patch = {key: deleted for key in FIELDS if key in data}
        if not patch:
            skipped += 1
            continue
        doc.reference.update(patch)
        updated += 1
    print(f'updated={updated} already_clean={skipped}')


if __name__ == '__main__':
    main()
