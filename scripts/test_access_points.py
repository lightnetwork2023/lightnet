"""Offline/online split for Nokia beacon DHCP leases."""
import lightnet_access_points as ap


def test_duration():
    assert ap.routeros_duration_seconds('10m51s') == 10 * 60 + 51
    assert ap.routeros_duration_seconds('1h28m12s') == 3600 + 28 * 60 + 12
    assert ap.routeros_duration_seconds('2h35m58s') == 2 * 3600 + 35 * 60 + 58
    assert ap.routeros_duration_seconds('never') is None
    assert ap.routeros_duration_seconds('') is None


def test_online_window():
    fresh = ap.lease_to_point({
        'mac-address': 'b4:63:6f:95:da:81',
        'host-name': 'Nokia WiFi Beacon 1.1',
        'address': '10.5.50.26',
        'status': 'bound',
        'last-seen': '11m1s',
    })
    assert fresh['status'] == 'online'
    assert fresh['mac'] == 'B4:63:6F:95:DA:81'
    stale = ap.lease_to_point({
        'mac-address': 'B4:63:6F:49:4D:91',
        'host-name': 'Nokia WiFi Beacon 1.1',
        'address': '10.5.50.254',
        'status': 'bound',
        'last-seen': '2h35m58s',
    })
    assert stale['status'] == 'online'
    phone = {'mac-address': '12:6A:FA:50:DA:37', 'host-name': 'Pixel', 'status': 'bound', 'last-seen': '1m'}
    assert ap.is_beacon_lease(phone) is False
    halo = ap.lease_to_point({
        'mac-address': '08:8A:F1:B7:86:B4',
        'host-name': 'halo-H30G',
        'address': '192.168.88.58',
        'status': 'bound',
        'last-seen': '9m24s',
    })
    assert halo['status'] == 'online'
    assert halo['hostname'] == 'halo-H30G'
    assert ap.is_beacon_lease({'mac-address': '08:8A:F1:B7:8C:4C', 'host-name': 'halo-H30'}) is True


def test_missing_lease_stays_offline():
    previous = [{
        'mac': 'B4:63:6F:49:4D:91',
        'ip': '10.5.50.254',
        'hostname': 'Nokia WiFi Beacon 1.1',
        'status': 'online',
        'last_seen': '1m',
        'last_seen_seconds': 60,
        'present': True,
    }]
    merged = ap.merge_points(previous, [])
    assert merged[0]['status'] == 'offline'
    assert merged[0]['present'] is False
    assert 'name' not in merged[0]


def test_ping_match():
    mac = '08:8A:F1:B7:8C:4C'
    ip = '192.168.88.70'
    arp_ok = [{'host': mac, 'received': 1, 'time': '2ms'}]
    assert ap.ping_rows_reached(arp_ok, ip, mac) is True
    other = [{'host': '34:BA:9A:C7:54:B8', 'received': 1, 'time': '29ms'}]
    assert ap.ping_rows_reached(other, ip, mac) is False
    timeout = [{'host': ip, 'status': 'timeout', 'received': 0}]
    assert ap.ping_rows_reached(timeout, ip, mac) is False
    icmp = [{'host': ip, 'received': 1, 'time': '1ms'}]
    assert ap.ping_rows_reached(icmp, ip, mac) is True
    quiet = {'mac': mac, 'ip': ip, 'status': 'offline', 'last_seen_seconds': 7200}
    assert ap.note_ping(quiet, True)['status'] == 'online'
    assert ap.note_ping(quiet, True)['ping'] == 'replied'
    fresh = {'mac': mac, 'ip': ip, 'status': 'online', 'last_seen_seconds': 60}
    assert ap.note_ping(fresh, False)['status'] == 'offline'
    assert ap.note_ping(fresh, False)['ping'] == 'no-reply'
    assert ap.lan_interface_for_ip(
        [{'address': '192.168.88.1/23', 'interface': 'bridgelan'}],
        '192.168.88.70',
    ) == 'bridgelan'


def test_models_and_links():
    nokia = ap.lease_to_point({
        'mac-address': 'B4:63:6F:95:DA:81',
        'host-name': 'Nokia WiFi Beacon 1.1',
        'status': 'bound',
        'last-seen': '1m',
    })
    assert nokia['kind'] == 'access_point'
    assert nokia['model'] == 'Nokia beacon'
    assert nokia['blocked'] is False
    link = ap.lease_to_point(
        {
            'mac-address': '58:C1:7A:47:02:85',
            'host-name': 'cambium-office',
            'status': 'bound',
            'last-seen': '1m',
            'block-access': 'true',
            'server': 'dhcp1',
        },
        {'identity': 'cambium-office', 'board': '5G Force 200 (ROW)'},
    )
    assert link['kind'] == 'link'
    assert link['model'] == 'Cambium Force 200'
    assert link['blocked'] is True
    assert link['status'] == 'offline'
    m5 = ap.classify_lease({
        'mac-address': '80:2A:A8:26:35:F4',
        'host-name': 'm5-zakhem hospital',
        'status': 'bound',
    })
    assert m5 == ('link', 'NanoStation M5')
    phone = ap.classify_lease({'mac-address': '12:6A:FA:50:DA:37', 'host-name': 'Pixel', 'status': 'bound'})
    assert phone == ('', '')
    pinged = ap.note_ping(dict(link), True)
    assert pinged['status'] == 'offline'


def test_merge_keeps_model():
    previous = [{
        'mac': '24:A4:3C:E6:20:BB',
        'ip': '192.168.88.18',
        'hostname': 'AP -ZAKHEM',
        'model': 'PowerBeam M5',
        'kind': 'link',
        'blocked': False,
        'status': 'online',
        'present': True,
    }]
    merged = ap.merge_points(previous, [])
    assert merged[0]['model'] == 'PowerBeam M5'
    assert merged[0]['kind'] == 'link'
    assert merged[0]['status'] == 'offline'


class _FakeRouter:
    def __init__(self):
        self.leases = [{
            '.id': '*1',
            'mac-address': 'DC:9F:DB:24:96:BA',
            'address': '192.168.90.7',
            'server': 'dhcp-lan',
            'dynamic': True,
            'blocked': False,
        }]
        self.bridge = []
        self.firewall = [{'.id': '*F', 'chain': 'forward', 'action': 'jump'}]
        self.calls = []
        self._seq = 10

    def __call__(self, cmd, **kwargs):
        self.calls.append(cmd)
        if cmd == '/ip/dhcp-server/lease/print':
            return iter(dict(row) for row in self.leases)
        if cmd == '/ip/dhcp-server/print':
            return iter([{'name': 'dhcp-lan'}])
        if cmd == '/interface/bridge/filter/print':
            return iter(dict(row) for row in self.bridge)
        if cmd == '/ip/firewall/filter/print':
            return iter(dict(row) for row in self.firewall)
        if cmd == '/ip/dhcp-server/lease/make-static':
            for lease in self.leases:
                if lease['.id'] == kwargs['.id']:
                    lease['dynamic'] = False
            return iter(())
        if cmd == '/ip/dhcp-server/lease/set':
            for lease in self.leases:
                if lease['.id'] == kwargs['.id']:
                    if 'block-access' in kwargs:
                        lease['blocked'] = str(kwargs['block-access']).lower() in ('yes', 'true')
                        lease['block-access'] = lease['blocked']
                    if 'comment' in kwargs:
                        lease['comment'] = kwargs['comment']
            return iter(())
        if cmd == '/interface/bridge/filter/add':
            self._seq += 1
            self.bridge.append({'.id': '*%s' % self._seq, **kwargs})
            return iter(())
        if cmd == '/ip/firewall/filter/add':
            self._seq += 1
            self.firewall.append({'.id': '*%s' % self._seq, **kwargs})
            return iter(())
        if cmd.endswith('/remove'):
            target = self.bridge if 'bridge' in cmd else self.firewall
            if 'lease' in cmd:
                target = self.leases
            kept = [row for row in target if row['.id'] != kwargs['.id']]
            target[:] = kept
            return iter(())
        raise AssertionError(cmd)


def test_block_stays_until_unblock():
    router = _FakeRouter()
    ap.install_link_block(router, 'dc:9f:db:24:96:ba', server_name='dhcp-lan', address='192.168.90.7')
    assert '/ip/dhcp-server/lease/make-static' in router.calls
    assert '/ip/dhcp-server/lease/set' in router.calls
    assert router.leases[0]['dynamic'] is False
    assert router.leases[0]['blocked'] is True
    assert len(router.bridge) == 2
    assert len(router.firewall) == 2
    ap.install_link_block(router, 'DC:9F:DB:24:96:BA')
    assert len(router.bridge) == 2
    rows = ap.mark_blocked(
        [{'mac': 'DC:9F:DB:24:96:BA', 'status': 'online', 'blocked': False, 'kind': 'link'}],
        ['DC:9F:DB:24:96:BA'],
    )
    assert rows[0]['status'] == 'offline'
    assert rows[0]['blocked'] is True
    ap.clear_link_block(router, 'DC:9F:DB:24:96:BA')
    assert router.bridge == []
    assert router.leases[0]['blocked'] is False


if __name__ == '__main__':
    test_duration()
    test_online_window()
    test_missing_lease_stays_offline()
    test_ping_match()
    test_models_and_links()
    test_merge_keeps_model()
    test_block_stays_until_unblock()
    print('ok')
