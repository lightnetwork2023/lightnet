#!/usr/bin/env python3
"""Visibility rules for MikroTik monitoring devices."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lightnet_app_docs as ad


def device(location, owner_id=None):
    data = {'location': location, 'name': 'RB', 'ipAddress': '10.0.1.9'}
    if owner_id is not None:
        data['mikrotik_owner_id'] = owner_id
    return {'id': 'd1', 'collection': 'mikrotik_devices', 'data': data}


class MikroTikDeviceVisibilityTest(unittest.TestCase):
    def test_boss_sees_device_even_if_location_is_not_a_location_id(self):
        actor = {'role': 'boss', 'mikrotik_owner_id': 13}
        doc = device('CHALINZE', 13)
        self.assertTrue(ad.tenant_docs_visible(actor, 'mikrotik_devices', doc, {'KIWANGWA'}, 13))

    def test_other_owner_cannot_see_lightnet_devices(self):
        actor = {'role': 'boss', 'mikrotik_owner_id': 21}
        doc = device('CHALINZE', 13)
        self.assertFalse(ad.tenant_docs_visible(actor, 'mikrotik_devices', doc, {'CHALINZE'}, 13))

    def test_unstamped_legacy_device_visible_only_to_default_owner(self):
        doc = device('CHALINZE')
        self.assertTrue(
            ad.tenant_docs_visible(
                {'role': 'boss', 'mikrotik_owner_id': 13},
                'mikrotik_devices',
                doc,
                set(),
                13,
            )
        )
        self.assertFalse(
            ad.tenant_docs_visible(
                {'role': 'boss', 'mikrotik_owner_id': 21},
                'mikrotik_devices',
                doc,
                set(),
                13,
            )
        )

    def test_agent_still_filtered_by_assigned_location(self):
        actor = {'role': 'agent', 'mikrotik_owner_id': 13}
        visible = device('KIWANGWA', 13)
        hidden = device('CHALINZE', 13)
        allowed = {'KIWANGWA'}
        self.assertTrue(ad.tenant_docs_visible(actor, 'mikrotik_devices', visible, allowed, 13))
        self.assertFalse(ad.tenant_docs_visible(actor, 'mikrotik_devices', hidden, allowed, 13))

    def test_write_stamps_actor_owner_and_ignores_client_owner(self):
        payload = ad.stamp_write_owner(
            {'mikrotik_owner_id': 13},
            'mikrotik_devices',
            {'name': 'RB', 'location': 'CHALINZE', 'mikrotik_owner_id': 99},
        )
        self.assertEqual(payload['mikrotik_owner_id'], 13)
        self.assertEqual(payload['location'], 'CHALINZE')

    def test_unstamped_sites_visible_only_to_default_owner(self):
        doc = {
            'id': 'h2HBwbTIJFVdM1gaLGNm',
            'collection': 'sites',
            'data': {'name': 'CHALINZE', 'main_location': 'Chalinze'},
        }
        self.assertTrue(
            ad.tenant_docs_visible(
                {'role': 'boss', 'mikrotik_owner_id': 13},
                'sites',
                doc,
                set(),
                13,
            )
        )
        self.assertFalse(
            ad.tenant_docs_visible(
                {'role': 'boss', 'mikrotik_owner_id': 10},
                'sites',
                doc,
                set(),
                13,
            )
        )

    def test_owner_cannot_see_other_owner_sites(self):
        doc = {
            'id': 'site1',
            'collection': 'sites',
            'data': {'name': 'MBAGALA', 'main_location': 'Mbagala', 'mikrotik_owner_id': 13},
        }
        self.assertFalse(
            ad.tenant_docs_visible(
                {'role': 'boss', 'mikrotik_owner_id': 10},
                'sites',
                doc,
                {'Mbagala', 'BABUU'},
                13,
            )
        )

    def test_site_write_stamps_actor_owner(self):
        payload = ad.stamp_write_owner(
            {'mikrotik_owner_id': 10},
            'sites',
            {'name': 'BABUU', 'main_location': 'BABUU', 'mikrotik_owner_id': 13},
        )
        self.assertEqual(payload['mikrotik_owner_id'], 10)
        self.assertEqual(payload['name'], 'BABUU')

    def test_lightnet_ops_hidden_from_other_owner(self):
        cases = [
            ('expenses', {'title': 'server payment', 'status': 'pending', 'location_id': 'Chalinze'}),
            ('float_transactions', {'type': 'credit', 'amount': 100000}),
            ('technician_vouchers', {'agent_name': 'HARDWARE', 'agent_location': 'HARDWARE CHALINZE'}),
            ('tech_checkins', {'destination_type': 'site', 'destination_name': 'MLANDIZI'}),
        ]
        actor = {'role': 'boss', 'mikrotik_owner_id': 10}
        lightnet = {'role': 'boss', 'mikrotik_owner_id': 13}
        for collection, data in cases:
            doc = {'id': collection, 'collection': collection, 'data': data}
            self.assertFalse(
                ad.tenant_docs_visible(actor, collection, doc, set(), 13),
                collection,
            )
            self.assertTrue(
                ad.tenant_docs_visible(lightnet, collection, doc, set(), 13),
                collection,
            )

    def test_expense_write_stamps_actor_owner(self):
        payload = ad.stamp_write_owner(
            {'mikrotik_owner_id': 10},
            'expenses',
            {'title': 'fuel', 'status': 'pending', 'mikrotik_owner_id': 13},
        )
        self.assertEqual(payload['mikrotik_owner_id'], 10)
        self.assertEqual(payload['title'], 'fuel')

    def test_owner_email_wins_over_backfilled_lightnet_staff_stamp(self):
        self.assertEqual(ad.pick_actor_owner_id(10, 13, 13), 10)

    def test_lightnet_staff_without_owner_email_stays_on_default(self):
        self.assertEqual(ad.pick_actor_owner_id(None, 13, 13), 13)

    def test_unstamped_user_falls_back_to_default_owner(self):
        self.assertEqual(ad.pick_actor_owner_id(None, None, 13), 13)

    def test_site_location_prefers_name_then_disambiguates_with_ip(self):
        site = {'id': 61, 'name': 'BABUU', 'wg_ip': '10.0.1.73', 'owner_id': 10}
        self.assertEqual(ad.site_location_candidates(site), ['BABUU'])

    def test_public_id_hides_owner_namespace_and_ip_suffix(self):
        self.assertEqual(
            ad.public_location_id({
                'id': '10::BABUU',
                'data': {'owner_id': 10, 'name': 'BABUU', 'from_site': True},
            }),
            'BABUU',
        )
        self.assertEqual(
            ad.public_location_id({
                'id': 'BABUU (10.0.1.73)',
                'data': {'owner_id': 10, 'name': 'BABUU', 'from_site': True},
            }),
            'BABUU',
        )

    def test_location_filter_does_not_leak_same_name_from_other_owner(self):
        rows = [
            {'id': 'BABUU', 'owner_id': 10, 'name': 'BABUU'},
            {'id': 'BABUU', 'owner_id': 13, 'name': 'BABUU'},
        ]
        mine = ad.filter_locations_for_actor({'role': 'boss', 'mikrotik_owner_id': 10}, rows)
        self.assertEqual(len(mine), 1)
        self.assertEqual(mine[0]['owner_id'], 10)


class FakeFirebase:
    def __init__(self, emails=None):
        self.emails = {e.lower() for e in (emails or [])}

    def get_user_by_email(self, email):
        if (email or '').lower() not in self.emails:
            raise Exception('No user record found for the given identifier (USER_NOT_FOUND).')
        return object()


class ExistingAccountGuardTest(unittest.TestCase):
    def setUp(self):
        self._orig = ad.user_by_email
        ad.user_by_email = lambda cur, email: (
            {'id': 'staff1'} if (email or '').lower() == 'abdallachalinze@gmail.com' else None
        )

    def tearDown(self):
        ad.user_by_email = self._orig

    def test_staff_email_cannot_register_as_owner(self):
        self.assertTrue(ad.existing_login_account(None, 'abdallachalinze@gmail.com'))

    def test_new_email_is_not_existing(self):
        self.assertFalse(ad.existing_login_account(None, 'brand-new-owner@owners.lightnetwork.pro'))

    def test_firebase_only_account_is_existing(self):
        auth = FakeFirebase(emails=['oldfirebase@gmail.com'])
        self.assertTrue(ad.existing_login_account(None, 'oldfirebase@gmail.com', auth))
        self.assertFalse(ad.existing_login_account(None, 'nobody@gmail.com', auth))


if __name__ == '__main__':
    unittest.main()
