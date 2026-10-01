"""Radios seen in a MikroTik DHCP lease table.

Nokia beacons and Mercusys Halo nodes are access points.
Cambium and Ubiquiti airMax units (NanoStation, PowerBeam, LiteBeam) are links.
A current DHCP lease means online. No lease means offline.
A blocked link stays offline until Unblock. The block is a bridge rule plus a
static DHCP lease, and a later poll puts that rule back if the router drops it.
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


def block_comment(mac):
    compact = ''.join(ch for ch in str(mac or '').upper() if ch in '0123456789ABCDEF')
    return 'lightnet-block-' + compact


def blocked_macs(data):
    """MACs the app has blocked. The lease table is not the source of this list."""
    found = []
    for item in (data or {}).get('blocked_links') or []:
        raw = item if isinstance(item, str) else (item or {}).get('mac')
        mac = _mac({'mac-address': raw})
        if mac and mac not in found:
            found.append(mac)
    return found


def mark_blocked(rows, macs):
    """A saved block stays offline even when the lease flag or a ping says otherwise."""
    want = set(blocked_macs({'blocked_links': list(macs or [])}))
    if not want:
        return list(rows or [])
    out = []
    seen = set()
    for row in rows or []:
        item = dict(row)
        mac = str(item.get('mac') or '').upper()
        seen.add(mac)
        if mac in want:
            item['blocked'] = True
            item['status'] = 'offline'
            if not item.get('kind'):
                item['kind'] = 'link'
        out.append(item)
    for mac in sorted(want - seen):
        out.append({
            'mac': mac,
            'ip': '',
            'hostname': '',
            'model': '',
            'kind': 'link',
            'server': '',
            'blocked': True,
            'status': 'offline',
            'last_seen': '',
            'last_seen_seconds': -1,
            'present': False,
        })
    out.sort(key=lambda r: (0 if r.get('status') != 'online' else 1, r.get('mac') or ''))
    return out


def _call(api, cmd, **kwargs):
    """RouterOS calls return a generator. It has to be read or the command is never sent."""
    return list(api(cmd, **kwargs))


def _dynamic(lease):
    return str((lease or {}).get('dynamic')).lower() in ('true', 'yes')


def _same_mac(value, mac):
    return str(value or '').upper().split('/')[0] == mac


def _mac_mask(mac):
    """Bridge and firewall MAC matchers require an explicit mask."""
    return mac + '/FF:FF:FF:FF:FF:FF'


def _has_drop(rules, comment, field, mac):
    for rule in rules or []:
        if rule.get('comment') != comment:
            continue
        if _same_mac(rule.get(field), mac):
            return True
    return False


def _place_before(rules):
    for rule in rules or []:
        if rule.get('chain') != 'forward':
            continue
        if str(rule.get('comment') or '').startswith('lightnet-block-'):
            continue
        return rule.get('.id')
    return None


def _ensure_drop(api, path, rules, mac, comment, field, place=False, masked=False):
    if _has_drop(rules, comment, field, mac):
        return
    kwargs = {
        'chain': 'forward',
        'action': 'drop',
        field: _mac_mask(mac) if masked else mac,
        'comment': comment,
    }
    if place:
        before = _place_before(rules)
        if before:
            kwargs['place-before'] = before
    _call(api, path + '/add', **kwargs)


def _ensure_drop_rules(api, mac, comment):
    bridge = _call(api, '/interface/bridge/filter/print')
    firewall = _call(api, '/ip/firewall/filter/print')
    _ensure_drop(api, '/interface/bridge/filter', bridge, mac, comment, 'src-mac-address', masked=True)
    _ensure_drop(api, '/interface/bridge/filter', bridge, mac, comment, 'dst-mac-address', masked=True)
    _ensure_drop(api, '/ip/firewall/filter', firewall, mac, comment, 'src-mac-address', place=True)
    bridge = _call(api, '/interface/bridge/filter/print')
    firewall = _call(api, '/ip/firewall/filter/print')
    if not _has_drop(bridge, comment, 'src-mac-address', mac):
        raise RuntimeError('router did not keep the bridge block')
    if not _has_drop(firewall, comment, 'src-mac-address', mac):
        raise RuntimeError('router did not keep the firewall block')


def _leases_for(api, mac):
    return [lease for lease in _call(api, '/ip/dhcp-server/lease/print') if _mac(lease) == mac]


def _ensure_static_blocked_lease(api, mac, comment, server_name='', address=''):
    matches = _leases_for(api, mac)
    chosen = next((lease for lease in matches if not _dynamic(lease)), None)
    if chosen is None and matches:
        current = matches[0]
        address = address or current.get('address') or current.get('active-address') or ''
        server_name = server_name or current.get('server') or current.get('active-server') or ''
        if _dynamic(current):
            _call(api, '/ip/dhcp-server/lease/make-static', **{'.id': current.get('.id')})
            matches = _leases_for(api, mac)
            chosen = next((lease for lease in matches if not _dynamic(lease)), None)
        if chosen is None and matches and _dynamic(matches[0]):
            _call(api, '/ip/dhcp-server/lease/remove', **{'.id': matches[0].get('.id')})
            chosen = None
    if chosen is None:
        if not server_name:
            servers = _call(api, '/ip/dhcp-server/print')
            server_name = (servers[0].get('name') if servers else '') or ''
        kwargs = {'mac-address': mac, 'block-access': 'yes', 'comment': comment}
        if server_name:
            kwargs['server'] = server_name
        if address:
            kwargs['address'] = address
        _call(api, '/ip/dhcp-server/lease/add', **kwargs)
    elif not lease_blocked(chosen):
        fields = {'.id': chosen.get('.id'), 'block-access': 'yes'}
        if not chosen.get('comment'):
            fields['comment'] = comment
        _call(api, '/ip/dhcp-server/lease/set', **fields)
    held = _leases_for(api, mac)
    if not any(lease_blocked(lease) for lease in held):
        raise RuntimeError('router did not keep the DHCP block')


def install_link_block(api, mac, server_name='', address=''):
    """Drop this MAC on the bridge until clear_link_block. Also freeze its DHCP lease."""
    mac = _mac({'mac-address': mac})
    if not mac:
        raise RuntimeError('mac is required')
    comment = block_comment(mac)
    _ensure_drop_rules(api, mac, comment)
    _ensure_static_blocked_lease(api, mac, comment, server_name, address)


def clear_link_block(api, mac):
    """Remove the drop rules and turn DHCP block-access off. The lease itself stays."""
    mac = _mac({'mac-address': mac})
    comment = block_comment(mac)
    for path in ('/interface/bridge/filter', '/ip/firewall/filter'):
        for rule in _call(api, path + '/print'):
            if rule.get('comment') == comment:
                _call(api, path + '/remove', **{'.id': rule.get('.id')})
    for lease in _leases_for(api, mac):
        if not lease_blocked(lease) and lease.get('comment') != comment:
            continue
        fields = {'.id': lease.get('.id'), 'block-access': 'no'}
        if lease.get('comment') == comment:
            fields['comment'] = ''
        _call(api, '/ip/dhcp-server/lease/set', **fields)


def reassert_link_blocks(api, macs):
    """Put a saved block back. One radio failing does not stop the others."""
    errors = []
    for mac in blocked_macs({'blocked_links': list(macs or [])}):
        try:
            install_link_block(api, mac)
        except Exception as exc:
            errors.append((mac, exc))
    return errors
