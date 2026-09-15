#!/usr/bin/env python3
"""Home-internet customers stay on their MikroTik owner tenant."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lightnet_home_internet as hi


class HomeCustomerOwnerTest(unittest.TestCase):
    def test_other_owner_cannot_see_lightnet_customer(self):
        row = {'id': '16268', 'name': 'PROTUS TARIMO', 'owner_id': 13}
        self.assertTrue(
            hi.can_access_customer({'role': 'boss', 'mikrotik_owner_id': 13}, row)
        )
        self.assertFalse(
            hi.can_access_customer({'role': 'boss', 'mikrotik_owner_id': 10}, row)
        )

    def test_unstamped_customer_is_default_owner_only(self):
        row = {'id': '16268', 'name': 'PROTUS TARIMO'}
        self.assertFalse(
            hi.can_access_customer({'role': 'boss', 'mikrotik_owner_id': 10}, row)
        )

    def test_homeuser_sees_only_own_id(self):
        row = {'id': '16268', 'owner_id': 13}
        actor = {'role': 'homeuser', 'home_customer_id': '16268', 'mikrotik_owner_id': 10}
        self.assertTrue(hi.can_access_customer(actor, row))
        actor['home_customer_id'] = '99999'
        self.assertFalse(hi.can_access_customer(actor, row))


if __name__ == '__main__':
    unittest.main()
