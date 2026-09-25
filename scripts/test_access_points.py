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
    assert stale['status'] == 'offline'
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
    assert ap.note_ping(fresh, False)['status'] == 'online'
    assert ap.note_ping(fresh, False)['ping'] == 'no-reply'
    assert ap.lan_interface_for_ip(
        [{'address': '192.168.88.1/23', 'interface': 'bridgelan'}],
        '192.168.88.70',
    ) == 'bridgelan'


if __name__ == '__main__':
    test_duration()
    test_online_window()
    test_missing_lease_stays_offline()
    test_ping_match()
    print('ok')
