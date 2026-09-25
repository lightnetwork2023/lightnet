"""Nokia WiFi Beacon and Mercusys Halo rows from a MikroTik DHCP lease table.

A current DHCP lease means online. No lease means offline.
Refresh can still mark a leased unit offline when the router ping fails.
Names are not stored here. The app keeps those on access_point_names,
keyed by MAC, so a lease refresh cannot wipe them.
"""
from __future__ import annotations

NOKIA_BEACON_OUI = 'B4:63:6F'
# Mercusys Halo mesh nodes (sold as Mercury). They announce hostnames like halo-H30.
MERCUSYS_HALO_OUI = '08:8A:F1'

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


def is_beacon_lease(lease):
    if not isinstance(lease, dict):
        return False
    mac = _mac(lease)
    host = str(lease.get('host-name') or '').lower()
    if mac.startswith(NOKIA_BEACON_OUI):
        return True
    if 'nokia' in host and 'beacon' in host:
        return True
    if host.startswith('halo-') or 'mercusys' in host or 'mercury' in host:
        return True
    return mac.startswith(MERCUSYS_HALO_OUI) and ('halo' in host or 'h30' in host)


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
    if not ip or not replied:
        row['ping'] = 'no-ip' if not ip else 'no-reply'
        row['status'] = 'offline'
        return row
    row['ping'] = 'replied'
    row['status'] = 'online'
    return row


def lease_to_point(lease):
    seconds = routeros_duration_seconds(lease.get('last-seen'))
    bound = str(lease.get('status') or '').lower() == 'bound'
    return {
        'mac': _mac(lease),
        'ip': lease.get('active-address') or lease.get('address') or '',
        'hostname': lease.get('host-name') or '',
        'status': 'online' if bound else 'offline',
        'last_seen': lease.get('last-seen') or '',
        'last_seen_seconds': seconds if seconds is not None else -1,
        'present': True,
    }


def merge_points(previous, current):
    """Keep a beacon that has left the lease table so it still shows offline."""
    by_mac = {}
    for item in previous or []:
        if not isinstance(item, dict):
            continue
        mac = str(item.get('mac') or '').strip().upper()
        if not mac:
            continue
        kept = {
            'mac': mac,
            'ip': item.get('ip') or '',
            'hostname': item.get('hostname') or '',
            'status': 'offline',
            'last_seen': '',
            'last_seen_seconds': -1,
            'present': False,
        }
        by_mac[mac] = kept
    for item in current or []:
        if not isinstance(item, dict):
            continue
        mac = str(item.get('mac') or '').strip().upper()
        if not mac:
            continue
        row = dict(item)
        row['mac'] = mac
        row['present'] = True
        by_mac[mac] = row
    rows = list(by_mac.values())
    rows.sort(key=lambda r: (0 if r.get('status') != 'online' else 1, r.get('mac') or ''))
    return rows
