"""Radios seen in a MikroTik DHCP lease table.

Nokia beacons and Mercusys Halo nodes are access points.
Cambium and Ubiquiti airMax units (NanoStation, PowerBeam, LiteBeam) are links.
A current DHCP lease means online. No lease means offline.
A link with DHCP block-access stays offline until it is unblocked.
Refresh can still mark a leased unit offline when the router ping fails.
Names are not stored here. The app keeps those on access_point_names,
keyed by MAC, so a lease refresh cannot wipe them.
"""
from __future__ import annotations

NOKIA_BEACON_OUI = 'B4:63:6F'
# Mercusys Halo mesh nodes (sold as Mercury). They announce hostnames like halo-H30.
MERCUSYS_HALO_OUI = '08:8A:F1'
CAMBIUM_OUIS = ('00:04:56', '58:C1:7A')
# airMax radios. UniFi uses some of the same prefixes; the model text distinguishes them.
UBIQUITI_OUIS = (
    '24:A4:3C', '80:2A:A8', 'DC:9F:DB', 'B4:FB:E4', '24:5A:4C', '70:A7:41',
    'F4:E2:C6', '74:83:C2', '68:72:51', '78:8A:20', '04:18:D6', 'E0:63:DA',
    'F0:9F:C2', '44:D9:E7', 'FC:EC:DA', 'AC:8B:A9', '18:E8:29', '68:D7:9A',
    '74:AC:B9', 'D0:21:F9', '00:27:22', '00:15:6D',
)

_UNITS = {'w': 604800, 'd': 86400, 'h': 3600, 'm': 60, 's': 1}


def routeros_duration_seconds(value):
    if value is None:
        return None
    text = str(value).strip().lower()
    if not text or text == 'never':
        return None
    total = 0
    num = ''
    seen = False
    for ch in text:
        if ch.isdigit():
            num += ch
            continue
        if ch in _UNITS and num:
            total += int(num) * _UNITS[ch]
            num = ''
            seen = True
            continue
        return None
    if num or not seen:
        return None
    return total


def _mac(lease):
    raw = lease.get('mac-address') or lease.get('active-mac-address') or ''
    return str(raw).strip().upper()


def _text(lease, neighbor=None):
    parts = [
        str((lease or {}).get('host-name') or ''),
        str((neighbor or {}).get('identity') or ''),
        str((neighbor or {}).get('board') or ''),
        str((neighbor or {}).get('platform') or ''),
    ]
    return ' '.join(parts).lower()


def _oui(mac):
    return str(mac or '').upper()[:8]


def radio_model(text):
    """Best model name we can read from a hostname or a neighbor board."""
    t = str(text or '').lower()
    if 'force 200' in t or 'force200' in t:
        return 'Cambium Force 200'
    if 'force 190' in t or 'force190' in t:
        return 'Cambium Force 190'
    if 'litebeam' in t:
        return 'LiteBeam'
    if 'powerbeam' in t:
        return 'PowerBeam M5' if 'm5' in t else 'PowerBeam'
    if 'nanostation' in t or 'nano station' in t:
        return 'NanoStation M5' if 'm5' in t or 'nanostation' in t else 'NanoStation'
    if 'epmp' in t or 'cambium' in t:
        return 'Cambium'
    if 'nokia' in t and 'beacon' in t:
        return 'Nokia beacon'
    if 'halo' in t or 'mercusys' in t or 'mercury' in t:
        return 'Mercusys Halo'
    return ''


def classify_lease(lease, neighbor=None):
    """Return (kind, model). kind is access_point, link, or '' when this is not our radio."""
    if not isinstance(lease, dict):
        return '', ''
    mac = _mac(lease)
    host = str(lease.get('host-name') or '').lower()
    text = _text(lease, neighbor)
    oui = _oui(mac)
    if mac.startswith(NOKIA_BEACON_OUI) or ('nokia' in host and 'beacon' in host):
        return 'access_point', 'Nokia beacon'
    if host.startswith('halo-') or 'mercusys' in host or 'mercury' in host:
        return 'access_point', 'Mercusys Halo'
    if mac.startswith(MERCUSYS_HALO_OUI) and ('halo' in host or 'h30' in host):
        return 'access_point', 'Mercusys Halo'
    named = radio_model(text)
    if oui in CAMBIUM_OUIS or named.startswith('Cambium'):
        return 'link', named or 'Cambium'
    if named in ('LiteBeam', 'PowerBeam', 'PowerBeam M5', 'NanoStation', 'NanoStation M5'):
        return 'link', named
    if oui in UBIQUITI_OUIS or host.startswith('m5-') or 'airlink' in host:
        if named:
            return 'link', named
        if host.startswith('m5-') or ' m5' in host:
            return 'link', 'NanoStation M5'
        return 'link', 'Ubiquiti'
    return '', ''


def is_beacon_lease(lease):
    return classify_lease(lease)[0] == 'access_point'


def neighbor_for(mac, hostname, neighbors):
    """Neighbor row for this MAC, or the same hostname when the radio uses a second MAC."""
    want = str(mac or '').upper()
    host = str(hostname or '').strip().lower()
    exact = None
    named = None
    for row in neighbors or []:
        if not isinstance(row, dict):
            continue
        nmac = str(row.get('mac-address') or '').upper()
        if nmac == want:
            exact = row
        ident = str(row.get('identity') or '').strip().lower()
        board = str(row.get('board') or row.get('platform') or '').strip()
        if host and ident == host and board:
            named = row
    if exact and (exact.get('board') or exact.get('platform')):
        return exact
    return named or exact


def lease_blocked(lease):
    for key in ('block-access', 'blocked'):
        if str((lease or {}).get(key) or '').lower() in ('true', 'yes'):
            return True
    return False


def lan_interface_for_ip(addresses, ip):
    """Interface whose own subnet contains this access-point address."""
    import ipaddress
    try:
        host = ipaddress.ip_address(str(ip or '').strip())
    except ValueError:
        return None
    for row in addresses or []:
        if not isinstance(row, dict):
            continue
        cidr = str(row.get('address') or '').strip()
        iface = str(row.get('interface') or '').strip()
        if not cidr or not iface:
            continue
        try:
            if host in ipaddress.ip_interface(cidr).network:
                return iface
        except ValueError:
            continue
    return None


def ping_rows_reached(rows, ip, mac):
    """True only when the ping answer is this access point, not another gateway."""
    expect_mac = str(mac or '').strip().upper()
    expect_ip = str(ip or '').strip().upper()
    for row in rows or []:
        if not isinstance(row, dict):
            continue
        try:
            received = int(row.get('received') or 0)
        except (TypeError, ValueError):
            received = 0
        if received <= 0:
            continue
        if str(row.get('status') or '').lower() == 'timeout':
            continue
        host = str(row.get('host') or '').strip().upper()
        if expect_mac and host == expect_mac:
            return True
        if expect_ip and host == expect_ip and row.get('time'):
            return True
    return False


def note_ping(point, replied):
    """Refresh only. A failed ping is offline even when the DHCP lease is still there."""
    row = dict(point or {})
    ip = str(row.get('ip') or '').strip()
    if row.get('blocked') or not ip or not replied:
        row['ping'] = 'no-ip' if not ip else ('blocked' if row.get('blocked') else 'no-reply')
        row['status'] = 'offline'
        return row
    row['ping'] = 'replied'
    row['status'] = 'online'
    return row


def lease_to_point(lease, neighbor=None):
    seconds = routeros_duration_seconds(lease.get('last-seen'))
    bound = str(lease.get('status') or '').lower() == 'bound'
    blocked = lease_blocked(lease)
    kind, model = classify_lease(lease, neighbor)
    if not model:
        model = radio_model(_text(lease, neighbor))
    return {
        'mac': _mac(lease),
        'ip': lease.get('active-address') or lease.get('address') or '',
        'hostname': lease.get('host-name') or '',
        'model': model,
        'kind': kind or 'access_point',
        'server': lease.get('server') or lease.get('active-server') or '',
        'blocked': blocked,
        'status': 'offline' if blocked or not bound else 'online',
        'last_seen': lease.get('last-seen') or '',
        'last_seen_seconds': seconds if seconds is not None else -1,
        'present': True,
    }


def _kept_offline(item, mac):
    host = item.get('hostname') or ''
    kind = item.get('kind') or ''
    model = item.get('model') or ''
    guessed_kind, guessed_model = classify_lease({'mac-address': mac, 'host-name': host})
    if not kind:
        kind = guessed_kind or 'access_point'
    if not model:
        model = guessed_model or radio_model(host)
    return {
        'mac': mac,
        'ip': item.get('ip') or '',
        'hostname': host,
        'model': model,
        'kind': kind,
        'server': item.get('server') or '',
        'blocked': bool(item.get('blocked')),
        'status': 'offline',
        'last_seen': '',
        'last_seen_seconds': -1,
        'present': False,
    }


def merge_points(previous, current):
    """Keep a radio that has left the lease table so it still shows offline."""
    by_mac = {}
    for item in previous or []:
        if not isinstance(item, dict):
            continue
        mac = str(item.get('mac') or '').strip().upper()
        if not mac:
            continue
        by_mac[mac] = _kept_offline(item, mac)
    for item in current or []:
        if not isinstance(item, dict):
            continue
        mac = str(item.get('mac') or '').strip().upper()
        if not mac:
            continue
        row = dict(item)
        row['mac'] = mac
        row['present'] = True
        old = by_mac.get(mac) or {}
        if not row.get('model'):
            row['model'] = old.get('model') or ''
        if not row.get('kind'):
            row['kind'] = old.get('kind') or 'access_point'
        by_mac[mac] = row
    rows = list(by_mac.values())
    rows.sort(key=lambda r: (0 if r.get('status') != 'online' else 1, r.get('mac') or ''))
    return rows
