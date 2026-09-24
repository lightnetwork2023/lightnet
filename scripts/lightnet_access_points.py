"""Nokia WiFi Beacon and Mercusys Halo rows from a MikroTik DHCP lease table.

Online means the lease is bound and the router heard the beacon within
BEACON_ONLINE_SECONDS. On the live sites a healthy beacon renews about
every 11–15 minutes, so a 5-minute cutoff marks working beacons offline.
Names are not stored here. The app keeps those on access_point_names,
keyed by MAC, so a lease refresh cannot wipe them.
"""
from __future__ import annotations

NOKIA_BEACON_OUI = 'B4:63:6F'
# Mercusys Halo mesh nodes (sold as Mercury). They announce hostnames like halo-H30.
MERCUSYS_HALO_OUI = '08:8A:F1'
BEACON_ONLINE_SECONDS = 30 * 60

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


def lease_to_point(lease):
    seconds = routeros_duration_seconds(lease.get('last-seen'))
    bound = str(lease.get('status') or '').lower() == 'bound'
    online = bound and seconds is not None and seconds <= BEACON_ONLINE_SECONDS
    return {
        'mac': _mac(lease),
        'ip': lease.get('active-address') or lease.get('address') or '',
        'hostname': lease.get('host-name') or '',
        'status': 'online' if online else 'offline',
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
