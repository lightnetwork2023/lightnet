#!/usr/bin/env python3
"""Owner isolation: other tenants must not see LightNet or each other's data."""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)

import lightnet_app_docs as ad  # noqa: E402
import lightnet_home_internet as hi  # noqa: E402


LIGHTNET = 13
OTHER = 10


def _actor(owner_id, role='boss', loc=None):
    return {
        'uid': 'u-%s' % owner_id,
        'role': role,
        'mikrotik_owner_id': owner_id,
        'location': loc or '',
        'locations': [loc] if loc else [],
    }


def _doc(data, doc_id='d1'):
    return {'id': doc_id, 'data': data}


def test_unstamped_ops_docs_are_hidden_from_other_owners():
    other = _actor(OTHER)
    allowed = {'CHALINZE', 'MBAGALA'}
    for collection in (
        'internet_payments',
        'simcards',
        'devices',
        'debt_payables',
        'bundle_configurations',
        'sold_vouchers',
        'expenses',
        'float_transactions',
        'technician_vouchers',
        'home_customers',
        'home_customers/c1/payments',
    ):
        unstamped = _doc({'location': 'CHALINZE', 'amount': 1000})
        assert ad.tenant_docs_visible(other, collection, unstamped, allowed, LIGHTNET) is False, collection
        lightnet = _doc({'mikrotik_owner_id': LIGHTNET, 'location': 'CHALINZE'})
        assert ad.tenant_docs_visible(other, collection, lightnet, allowed, LIGHTNET) is False, collection
        own = _doc({'mikrotik_owner_id': OTHER, 'location': 'OWN-SITE'})
        own_allowed = {'OWN-SITE'}
        assert ad.tenant_docs_visible(other, collection, own, own_allowed, LIGHTNET) is True, collection
    print('ok unstamped and LightNet docs hidden from other owners')


def test_field_registration_home_owner_id_is_not_mikrotik_owner():
    other = _actor(OTHER)
    allowed = {'OWN-SITE'}
    doc = _doc({
        'mikrotik_owner_id': OTHER,
        'owner_id': LIGHTNET,
        'location': 'OWN-SITE',
    })
    assert ad.doc_owner_id(doc['data'], LIGHTNET, collection='field_registrations') == OTHER
    assert ad.tenant_docs_visible(other, 'field_registrations', doc, allowed, LIGHTNET) is True
    leak = _doc({
        'owner_id': OTHER,
        'location': 'OWN-SITE',
    })
    assert ad.doc_owner_id(leak['data'], LIGHTNET, collection='field_registrations') == LIGHTNET
    assert ad.tenant_docs_visible(other, 'field_registrations', leak, allowed, LIGHTNET) is False
    print('ok field_registrations home owner_id is not the MikroTik tenant')


def test_sites_use_main_location_and_owner():
    other = _actor(OTHER, loc='CHALINZE')
    allowed = {'CHALINZE', 'MBAGALA'}
    site = _doc({'main_location': 'CHALINZE', 'mikrotik_owner_id': LIGHTNET, 'name': 'CHALINZE'})
    assert ad.tenant_docs_visible(other, 'sites', site, allowed, LIGHTNET) is False
    own = _doc({'main_location': 'BABUU', 'mikrotik_owner_id': OTHER, 'name': 'BABUU'})
    assert ad.tenant_docs_visible(other, 'sites', own, {'BABUU'}, LIGHTNET) is True
    print('ok sites are owner-scoped')


def test_staff_created_keeps_profile_owner():
    assert ad.staff_created_keeps_profile_owner('0pVT8bHr0jao5qGA8LADnxgbQfZ2') is True
    assert ad.staff_created_keeps_profile_owner('owner-register') is False
    assert ad.pick_actor_owner_id(10, 13, 13, created_by='avitus-uid') == 13
    assert ad.pick_actor_owner_id(10, 13, 13, created_by='owner-register') == 10
    assert ad.pick_actor_owner_id(10, None, 13, created_by=None) == 10
    print('ok staff-created users stay on creator tenant')


def test_app_meta_is_visible():
    other = _actor(OTHER)
    meta = _doc({'backfilled': True})
    assert ad.tenant_docs_visible(other, 'app_meta', meta, set(), LIGHTNET) is True
    print('ok app_meta stays readable')


def test_hi_config_is_owner_keyed():
    class _Cur:
        def __init__(self):
            self.row = {'id': LIGHTNET}

        def execute(self, sql, params=None):
            self.sql = sql
            self.params = params

        def fetchone(self):
            if 'mikrotik_owners' in (self.sql or ''):
                return self.row
            return None

    cur = _Cur()
    assert hi._config_id(cur, LIGHTNET) == 'enums'
    assert hi._config_id(cur, OTHER) == 'enums-%s' % OTHER
    print('ok home-internet config is per owner')


if __name__ == '__main__':
    test_unstamped_ops_docs_are_hidden_from_other_owners()
    test_field_registration_home_owner_id_is_not_mikrotik_owner()
    test_sites_use_main_location_and_owner()
    test_staff_created_keeps_profile_owner()
    test_app_meta_is_visible()
    test_hi_config_is_owner_keyed()
    print('all owner isolation tests passed')
