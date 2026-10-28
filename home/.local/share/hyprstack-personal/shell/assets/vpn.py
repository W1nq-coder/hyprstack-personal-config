#!/usr/bin/env python3
"""On-demand controls for upstream sing-box and Xray. No resident manager.

Personal overlay: subscriptions are fetched the way VPN apps fetch them, several
subscriptions can be kept and removed one by one, all servers are pinged at
once, and the server list carries its address and protocol for the VPN window.

Only the selected core runs while connected. Imports use stdin, profile files
are private, and the shell never receives server credentials or native configs.
"""
from __future__ import annotations

import argparse
import base64
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request
import zipfile

from concurrent.futures import ThreadPoolExecutor

from vpn_profiles import parse, unwrap, ProfileError

DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'hyprstack'
ROOT = Path(os.environ.get('HYPRSTACK_VPN_STATE', DATA / 'vpn'))
RUNTIME = Path(os.environ.get('HYPRSTACK_VPN_RUNTIME', DATA / 'runtime/vpn/cores'))
PRIVILEGED = Path('/usr/local/lib/hyprstack-vpn')
DNS_RULE = Path(f'/etc/polkit-1/rules.d/49-hyprstack-vpn-{os.getuid()}.rules')
SERVICE = 'hyprstack-vpn.service'
MAX_IMPORT = 8 * 1024 * 1024
CAPS = (1 << 10) | (1 << 12) | (1 << 13)  # bind_service, net_admin, net_raw
RELEASES = {
    'sing-box': ('1.14.4', 'https://github.com/SagerNet/sing-box/releases/download/v1.14.4/', {
        'x86_64': ('sing-box-1.14.4-linux-amd64.tar.gz', '699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968'),
        'aarch64': ('sing-box-1.14.4-linux-arm64.tar.gz', '436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26')}),
    'xray': ('26.10.21', 'https://github.com/XTLS/Xray-core/releases/download/v26.10.21/', {
        'x86_64': ('Xray-linux-64.zip', '0eec3ed4163c273d8c8bf821f7d219e257921cf584aa3fb970715e458e631978'),
        'aarch64': ('Xray-linux-arm64-v8a.zip', 'd1304946c486d98e6b886e9b931eaaaebb23835b30e217638037b7f2721d4e9c')})}


class VpnError(Exception):
    pass


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temp = path.with_name(path.name + '.' + secrets.token_hex(4))
    descriptor = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, 'w') as output:
            json.dump(value, output, ensure_ascii=False)
            output.write('\n')
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def model():
    return read_json(ROOT / 'profiles.json', {'profiles': [], 'groups': [], 'selectedProfile': -1,
                                             'mode': 'tun', 'route': 'all'})


def selected(value):
    profile = next((p for p in value['profiles'] if p['id'] == value['selectedProfile']), None)
    if profile is None:
        raise VpnError('Add or select a VPN profile first')
    return profile


def can_tun(path):
    try:
        stat = path.stat()
        caps = struct.unpack_from('<III', os.getxattr(path, 'security.capability'))
        return bool(stat.st_uid == 0 and not stat.st_mode & 0o022 and caps[0] & 1 and caps[1] & CAPS == CAPS)
    except (OSError, struct.error):
        return False


def dns_policy():
    user = json.dumps(pwd.getpwuid(os.getuid()).pw_name)
    return ('// Hyprstack: DNS changes for its own tunnel only.\n'
            'polkit.addRule(function(action, subject) {\n'
            f'    if (subject.user !== {user}) return;\n'
            '    if (action.id === "org.freedesktop.resolve1.flush-caches") return polkit.Result.YES;\n'
            '    if (action.lookup("interface") !== "hyprstack-vpn") return;\n'
            '    var allowed = ["org.freedesktop.resolve1.set-dns-servers",\n'
            '        "org.freedesktop.resolve1.set-domains", "org.freedesktop.resolve1.set-default-route",\n'
            '        "org.freedesktop.resolve1.revert"];\n'
            '    if (allowed.indexOf(action.id) !== -1) return polkit.Result.YES;\n'
            '});\n')


def dns_authorized():
    return read_json(ROOT / 'authorization.json', {}).get('dnsPolicy') == hashlib.sha256(dns_policy().encode()).hexdigest()


def binary(engine):
    privileged = PRIVILEGED / engine
    if can_tun(privileged):
        return privileged
    system = shutil.which(engine)
    return Path(system) if system else RUNTIME / engine


def required(value):
    return {'sing-box'} | {p['engine'] for p in value['profiles']}


HEADERS = {}


def download(url, limit=MAX_IMPORT, agent='Hyprstack-VPN/1'):
    request = urllib.request.Request(url, headers={'User-Agent': agent, 'Accept': '*/*'})
    with urllib.request.urlopen(request, timeout=30) as response:
        HEADERS.clear()
        HEADERS.update({k.lower(): v for k, v in response.headers.items()})
        content = response.read(limit + 1)
    if len(content) > limit:
        raise VpnError('The download is too large')
    return content


# Subscription panels answer according to the app asking: plain share links
# for v2rayN, sing-box JSON for Hiddify, sometimes a web page for anything else.
AGENTS = ('v2rayN/7.10.5', 'Happ/3.6.0', 'Hiddify/2.5.7', 'Hyprstack-VPN/1')


def fetch_profiles(link):
    problem = None
    for agent in AGENTS:
        try:
            return parse(download(link, agent=agent).decode('utf-8-sig', 'replace'))
        except ProfileError as error:
            problem = error
        except OSError as error:
            raise VpnError('Could not download the subscription: check the link and the internet connection') from error
    raise problem or VpnError('No supported profiles were found')


def subscription_title(link):
    """Name the panel gives its subscription (profile-title header), else the site."""
    title = HEADERS.get('profile-title', '').strip()
    if title.lower().startswith('base64:'):
        try:
            title = base64.b64decode(title[7:] + '=' * (-len(title[7:]) % 4)).decode('utf-8', 'replace').strip()
        except ValueError:
            title = ''
    return (title or urllib.parse.urlsplit(link).hostname or 'Subscription')[:60]


def details(profile):
    """Address and a short protocol label for the server list (no credentials)."""
    out = profile.get('outbound', {})
    if profile.get('engine') == 'xray':
        settings = out.get('settings', {})
        node = (settings.get('vnext') or settings.get('servers') or [settings])[0]
        server, port = node.get('address', ''), node.get('port', 0)
        flow = settings.get('flow') or ((node.get('users') or [{}])[0].get('flow', ''))
        stream = out.get('streamSettings', {})
        security, network = stream.get('security', 'none'), stream.get('network', 'tcp')
    else:
        server, port, flow = out.get('server', ''), out.get('server_port', 0), out.get('flow', '')
        tls = out.get('tls') or {}
        security = 'reality' if (tls.get('reality') or {}).get('enabled') else 'tls' if tls.get('enabled') else 'none'
        network = (out.get('transport') or {}).get('type', 'tcp')
    names = {'vless': 'VLESS', 'vmess': 'VMess', 'trojan': 'Trojan', 'shadowsocks': 'Shadowsocks',
             'hysteria2': 'Hysteria2', 'tuic': 'TUIC', 'socks': 'SOCKS', 'http': 'HTTP', 'wireguard': 'WireGuard'}
    parts = [names.get(profile.get('type', ''), str(profile.get('type', '')).upper())]
    tail = {'reality': 'Reality', 'tls': 'TLS'}.get(security, '')
    if 'vision' in str(flow):
        tail = (tail + ' XTLS').strip()
    if tail:
        parts.append(tail)
    if network not in ('tcp', 'raw', ''):
        parts.append(str(network).upper())
    return {'server': str(server), 'port': int(port or 0), 'protocol': ' · '.join(parts)}


def install(engine):
    if binary(engine).is_file():
        return
    version, prefix, platforms = RELEASES[engine]
    asset = platforms.get(os.uname().machine)
    if not asset:
        raise VpnError('Install the VPN core using your package manager')
    filename, checksum = asset
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.install-', dir=RUNTIME) as temporary:
        archive = Path(temporary) / filename
        archive.write_bytes(download(prefix + filename, 128 * 1024 * 1024))
        if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
            raise VpnError('The VPN core download did not pass verification')
        target = Path(temporary) / engine
        if engine == 'xray':
            with zipfile.ZipFile(archive) as files, files.open('xray') as source, target.open('wb') as output:
                shutil.copyfileobj(source, output)
        else:
            with tarfile.open(archive) as files:
                entry = next(e for e in files.getmembers() if e.isfile() and e.name.endswith('/sing-box'))
                with files.extractfile(entry) as source, target.open('wb') as output:
                    shutil.copyfileobj(source, output)
        os.chmod(target, 0o755)
        os.replace(target, RUNTIME / engine)


def routing_rules():
    cache = ROOT / 'rules.json'
    if cache.exists() and time.time() - cache.stat().st_mtime < 86400:
        return read_json(cache)
    install('sing-box')
    result = {}
    try:
        with tempfile.TemporaryDirectory(prefix='.rules-', dir=ROOT) as temporary:
            for name in ('geoip-ru', 'geosite-category-ru', 'geosite-ru-available-only-inside'):
                directory = 'rule-set-geoip' if name.startswith('geoip-') else 'rule-set-geosite'
                url = 'https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/' + directory + '/' + name + '.srs'
                source, dest = Path(temporary) / (name + '.srs'), Path(temporary) / (name + '.json')
                source.write_bytes(download(url))
                completed = subprocess.run([str(binary('sing-box')), 'rule-set', 'decompile', '--output', str(dest), str(source)], capture_output=True, timeout=20)
                if completed.returncode:
                    raise VpnError('Unable to update routing rules')
                for rule in read_json(dest)['rules']:
                    if any(k not in ('domain', 'domain_suffix', 'domain_keyword', 'domain_regex', 'ip_cidr') for k in rule):
                        raise VpnError('Unsupported routing rule format')
                    for key, values in rule.items():
                        result.setdefault(key, []).extend(values)
        result.setdefault('domain_suffix', []).extend(['ru', 'xn--p1ai'])
        result = {k: sorted(set(v)) for k, v in result.items()}
        atomic_json(cache, result)
        return result
    except Exception:
        if cache.exists():
            return read_json(cache)
        raise VpnError('Unable to update routing rules') from None


def direct_ipv6_available(routes_path=Path('/proc/net/ipv6_route')):
    """Ignore the VPN's own IPv6 route when checking the underlying connection."""
    try:
        for line in routes_path.read_text().splitlines():
            fields = line.split()
            if len(fields) < 10 or fields[0] != '0' * 32 or fields[1] != '00':
                continue
            flags = int(fields[-2], 16)
            if fields[-1] not in ('lo', 'hyprstack-vpn') and flags & 1 and not flags & 0x200:
                return True
    except OSError:
        pass
    return False


# Remote DNS choices of the VPN window (the AdGuard one also blocks ads and trackers).
DNS_SERVERS = {'cloudflare': '1.1.1.1', 'google': '8.8.8.8', 'quad9': '9.9.9.9', 'adguard': '94.140.14.14'}


def options(value):
    """Connection settings of the VPN window, with safe defaults."""
    port = value.get('port', 2080)
    port = port if isinstance(port, int) and 1024 <= port <= 65534 else 2080
    direct = [d for d in value.get('direct', []) if isinstance(d, str) and d][:200]
    return {'dns': value.get('dns') if value.get('dns') in DNS_SERVERS else 'cloudflare', 'port': port, 'direct': direct}


def configuration(profile, mode='proxy', route='all', port=2080, http_port=2081, dns='cloudflare', direct=(), exclude=(), interface=''):
    outbound = copy.deepcopy(profile['outbound'])
    dns_ip = DNS_SERVERS.get(dns, '1.1.1.1')
    outbound['tag'] = 'vpn'
    private = ['127.0.0.0/8', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16', '::1/128', 'fc00::/7', 'fe80::/10']
    bypass = copy.deepcopy(routing_rules()) if route == 'bypass-ru' else {}
    if direct:
        # the user's own sites that skip the VPN
        bypass.setdefault('domain_suffix', []).extend(direct)
    ipv4_bypass = bool(bypass) and not direct_ipv6_available()
    if profile['engine'] == 'sing-box':
        inbounds = [{'type': 'socks', 'tag': 'socks', 'listen': '127.0.0.1', 'listen_port': port}]
        if http_port:
            inbounds.append({'type': 'http', 'tag': 'http', 'listen': '127.0.0.1', 'listen_port': http_port})
        if mode == 'tun':
            inbounds.append({'type': 'tun', 'tag': 'tun', 'interface_name': 'hyprstack-vpn',
                             'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'], 'mtu': 1500,
                             'auto_route': True, 'auto_redirect': True, 'strict_route': True, 'stack': 'mixed'})
            if exclude:
                # the VPN server itself must stay outside the tunnel
                inbounds[-1]['route_exclude_address'] = list(exclude)
        rules = [{'action': 'sniff'}, {'protocol': 'dns', 'action': 'hijack-dns'}, {'ip_cidr': private, 'outbound': 'direct'}]
        direct = {'type': 'direct', 'tag': 'direct'}
        dns_rules = []
        if ipv4_bypass:
            # A TUN can acknowledge IPv6 TCP before the direct dial fails. That
            # prevents browsers from falling back to IPv4 after TLS resets.
            direct['domain_resolver'] = {'server': 'bootstrap', 'strategy': 'ipv4_only'}
            rules.append({'ip_version': 6, 'outbound': 'vpn'})
            dns_rules = [{key: values, 'query_type': ['AAAA'], 'action': 'predefined', 'rcode': 'NOERROR'}
                         for key, values in bypass.items() if key != 'ip_cidr']
        for key, values in bypass.items():
            rules.append({key: values, 'outbound': 'direct'})
        dns_section = {'servers': [{'type': 'https', 'tag': 'remote', 'server': dns_ip, 'detour': 'vpn'},
                                   {'type': 'udp', 'tag': 'bootstrap', 'server': '1.1.1.1'}], 'final': 'remote', 'rules': dns_rules}
        if mode == 'tun':
            # Most VPN servers have no IPv6, and apps that get an IPv6 address
            # through the tunnel just hang. VPN apps answer with IPv4 only too.
            dns_section['strategy'] = 'ipv4_only'
        return {'log': {'level': 'warn', 'timestamp': False}, 'inbounds': inbounds,
                'outbounds': [outbound, direct],
                'dns': dns_section,
                'route': {**({'default_interface': interface} if interface else {'auto_detect_interface': True}),
                          'default_domain_resolver': 'bootstrap', 'rules': rules, 'final': 'vpn'}}
    inbounds = [{'tag': 'socks', 'listen': '127.0.0.1', 'port': port, 'protocol': 'socks', 'settings': {'auth': 'noauth', 'udp': True}}]
    if http_port:
        inbounds.append({'tag': 'http', 'listen': '127.0.0.1', 'port': http_port, 'protocol': 'http'})
    if mode == 'tun':
        inbounds.append({'tag': 'tun', 'protocol': 'tun', 'settings': {'name': 'hyprstack-vpn', 'mtu': 1500,
                         'gateway': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
                         'autoSystemRoutingTable': ['0.0.0.0/0', '::/0'], 'autoOutboundsInterface': 'auto'},
                         'sniffing': {'enabled': True, 'destOverride': ['http', 'tls', 'quic'], 'routeOnly': True}})
    rules = [{'type': 'field', 'inboundTag': ['tun'], 'port': 53, 'outboundTag': 'dns'},
             {'type': 'field', 'ip': private, 'outboundTag': 'direct'}]
    direct = {'tag': 'direct', 'protocol': 'freedom'}
    if ipv4_bypass:
        direct['settings'] = {'domainStrategy': 'UseIPv4'}
        rules.append({'type': 'field', 'ip': ['::/0'], 'outboundTag': 'vpn'})
    domains = []
    for key, prefix in (('domain', 'full:'), ('domain_suffix', 'domain:'), ('domain_keyword', 'keyword:'), ('domain_regex', 'regexp:')):
        domains.extend(prefix + text for text in bypass.get(key, []))
    if domains:
        rules.append({'type': 'field', 'domain': domains, 'outboundTag': 'direct'})
    if bypass.get('ip_cidr'):
        rules.append({'type': 'field', 'ip': bypass['ip_cidr'], 'outboundTag': 'direct'})
    dns_servers = [f'https://{dns_ip}/dns-query']
    if ipv4_bypass and domains:
        dns_servers.insert(0, {'address': dns_servers[0], 'domains': domains, 'queryStrategy': 'UseIPv4', 'skipFallback': True})
    return {'log': {'loglevel': 'warning'}, 'inbounds': inbounds,
            'outbounds': [outbound, direct, {'tag': 'dns', 'protocol': 'dns'}],
            'dns': {'servers': dns_servers, 'queryStrategy': 'UseIP'},
            'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': rules}}


def free_port():
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        return reservation.getsockname()[1]


def pinned(profile):
    """Xray profile with server addresses resolved to IPs, and those IPs.

    The tunnel catches every DNS query, so Xray must not look up its own
    server through it. TLS names and hosts keep the original domain.
    """
    profile = copy.deepcopy(profile)
    outbound = profile['outbound']
    settings = outbound.get('settings', {})
    stream = outbound.setdefault('streamSettings', {})
    ips = []
    for server in settings.get('vnext', []) + settings.get('servers', []) + ([settings] if 'address' in settings else []):
        host = str(server.get('address', ''))
        try:
            socket.inet_pton(socket.AF_INET6 if ':' in host else socket.AF_INET, host)
            ip = host
        except OSError:
            try:
                infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
            except OSError as error:
                raise VpnError('The VPN server address could not be resolved') from error
            ip = sorted(infos, key=lambda info: info[0] != socket.AF_INET)[0][4][0]
            server['address'] = ip
            for key in ('tlsSettings', 'realitySettings'):
                if key in stream and not stream[key].get('serverName'):
                    stream[key]['serverName'] = host
            for key in ('wsSettings', 'httpupgradeSettings', 'xhttpSettings'):
                if key in stream and not stream[key].get('host') and not stream[key].get('headers', {}).get('Host'):
                    stream[key]['host'] = host
        ips.append(ip + ('/128' if ':' in ip else '/32'))
    if not ips:
        raise VpnError('The profile configuration is invalid or unsupported')
    return profile, ips


def command(engine, config, check=False):
    args = [str(binary(engine))]
    return (args + (['check'] if check else ['run']) + ['-c', str(config)] if engine == 'sing-box'
            else args + ['run'] + (['-test'] if check else []) + ['-config', str(config)])


def validate(profile):
    install(profile['engine'])
    with tempfile.TemporaryDirectory(prefix='.check-', dir=ROOT) as temporary:
        path = Path(temporary) / 'config.json'
        atomic_json(path, configuration(profile, http_port=0))
        result = subprocess.run(command(profile['engine'], path, True), capture_output=True, timeout=15)
        if result.returncode:
            raise VpnError('The profile configuration is invalid or unsupported')


def valid_entries(entries):
    """Servers the core accepts; the others are skipped instead of failing all."""
    if entries:
        install(entries[0]['engine'])
    good = []
    for entry in entries:
        try:
            validate(entry)
            good.append(entry)
        except (VpnError, subprocess.TimeoutExpired):
            continue
    if not good:
        raise VpnError('The profile configuration is invalid or unsupported')
    return good


def proc_start(pid):
    return Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]


def status():
    value = model()
    session = read_json(ROOT / 'process.json', {})
    alive = False
    try:
        alive = proc_start(session['pid']) == session['start']
        os.kill(session['pid'], 0)
    except (OSError, KeyError):
        alive = False
    connected = alive and (session.get('mode') == 'proxy' or Path('/sys/class/net/hyprstack-vpn').exists())
    engines = required(value)
    return {'connected': bool(connected), 'state': 'connected' if connected else 'disconnected',
            'reason': '', 'authUrl': '', 'server': session.get('name', '') if connected else '',
            'selectedProfile': value['selectedProfile'], 'mode': value['mode'],
            'installed': all(binary(e).is_file() for e in engines),
            'canTun': all(can_tun(binary(e)) for e in engines) and dns_authorized(),
            'engine': session.get('engine', '') if connected else '', 'engines': sorted(engines)}


def overview():
    value = model()
    return {**status(), 'options': options(value), 'otherTunnels': other_tunnels(), 'profiles': [{**{k: p[k] for k in ('id', 'name', 'type', 'group', 'latency_ms', 'engine')}, **details(p)} for p in value['profiles']],
            'groups': [{**{k: g[k] for k in ('id', 'name', 'subscription')}, 'count': sum(p['group'] == g['id'] for p in value['profiles'])} for g in value['groups']],
            'routes': [{'id': 'all', 'name': 'All traffic', 'active': value['route'] == 'all'},
                       {'id': 'bypass-ru', 'name': 'Bypass Russia', 'active': value['route'] == 'bypass-ru'}]}


def service(action):
    completed = subprocess.run(['systemctl', '--user', action, SERVICE], capture_output=True, timeout=30)
    if completed.returncode:
        load = subprocess.run(['systemctl', '--user', 'show', SERVICE, '-p', 'LoadState', '--value'], capture_output=True, text=True, timeout=5)
        if load.stdout.strip() == 'not-found':
            if action == 'stop':
                return
            result = subprocess.run(['systemd-run', '--user', '--collect', '--unit=hyprstack-vpn',
                                     '--property=Restart=on-failure', '--property=UMask=0077',
                                     f'--setenv=HYPRSTACK_VPN_STATE={ROOT}', f'--setenv=HYPRSTACK_VPN_RUNTIME={RUNTIME}',
                                     sys.executable, str(Path(__file__).resolve()), 'serve'], capture_output=True, timeout=15)
            if result.returncode == 0:
                return
        raise VpnError('The VPN service could not complete the operation')


def ready(port=2080):
    if not status()['connected']:
        return False
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=.5) as stream:
            stream.sendall(b'\x05\x01\x00')
            return stream.recv(2) == b'\x05\x00'
    except OSError:
        return False


def connect(value=None):
    value = value or model()
    profile = selected(value)
    if not binary(profile['engine']).is_file():
        raise VpnError('The VPN core is not installed')
    # Xray's own tunnel cannot share routes with other VPN apps and often fails
    # to start, so in tunnel mode sing-box holds the tunnel and hands the
    # traffic to Xray, which only talks to the server.
    chain = value['mode'] == 'tun' and profile['engine'] == 'xray'
    tunnel_engine = 'sing-box' if chain else profile['engine']
    if value['mode'] == 'tun' and (not binary(tunnel_engine).is_file() or not can_tun(binary(tunnel_engine)) or not dns_authorized()):
        raise VpnError('Authorize the VPN tunnel in VPN settings first')
    opts = options(value)
    session = {k: profile[k] for k in ('id', 'name', 'type', 'engine')} | {'mode': value['mode']}
    core = None
    # With another VPN app running, its tunnel looks like the main connection;
    # sites that skip the VPN must still go out through Wi-Fi or cable.
    interface = physical_interface() if other_tunnels() else ''
    if chain:
        backend, exclude = pinned(profile)
        session['corePort'] = free_port()
        core = configuration(backend, 'proxy', 'all', port=session['corePort'], http_port=0)
        front = {'engine': 'sing-box', 'outbound': {'type': 'socks', 'server': '127.0.0.1', 'server_port': session['corePort']}}
        config = configuration(front, 'tun', value['route'], port=opts['port'], http_port=opts['port'] + 1,
                               dns=opts['dns'], direct=opts['direct'], exclude=exclude, interface=interface)
        session['chain'] = True
    else:
        config = configuration(profile, value['mode'], value['route'], port=opts['port'], http_port=opts['port'] + 1,
                               dns=opts['dns'], direct=opts['direct'], interface=interface)
    atomic_json(ROOT / 'pending.json', config)
    checks = [(tunnel_engine, ROOT / 'pending.json')]
    if core is not None:
        atomic_json(ROOT / 'pending-core.json', core)
        checks.append(('xray', ROOT / 'pending-core.json'))
    for engine, path in checks:
        completed = subprocess.run(command(engine, path, True), capture_output=True, timeout=20)
        if completed.returncode:
            raise VpnError('The profile configuration is invalid or unsupported')
    old_config, old_session = read_json(ROOT / 'config.json'), read_json(ROOT / 'session.json')
    old_core = read_json(ROOT / 'core.json')
    was_connected = status()['connected']
    os.replace(ROOT / 'pending.json', ROOT / 'config.json')
    if core is not None:
        os.replace(ROOT / 'pending-core.json', ROOT / 'core.json')
    atomic_json(ROOT / 'session.json', session)
    try:
        service('restart')
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            if ready(opts['port']):
                return
            time.sleep(.1)
        raise VpnError('The VPN tunnel did not start')
    except Exception:
        service('stop')
        if old_config is not None and old_session is not None:
            atomic_json(ROOT / 'config.json', old_config)
            atomic_json(ROOT / 'session.json', old_session)
            if old_core is not None:
                atomic_json(ROOT / 'core.json', old_core)
            if was_connected:
                service('start')
        raise


def receive(stream, size):
    result = b''
    while len(result) < size:
        part = stream.recv(size - len(result))
        if not part:
            raise VpnError('The VPN server did not respond to the connection test')
        result += part
    return result


def tcp_ping(profile):
    """Time to open a connection to the server, the number VPN apps show."""
    info = details(profile)
    if not info['server'] or not info['port']:
        return 0
    best = 0
    for _ in range(2):
        started = time.monotonic()
        try:
            socket.create_connection((info['server'], info['port']), timeout=3).close()
        except OSError:
            continue
        ms = max(1, round((time.monotonic() - started) * 1000))
        best = ms if not best else min(best, ms)
    return best


def latency(profile):
    """Check the server really works through the core, then report its ping."""
    full = real_latency(profile)
    tcp = tcp_ping(profile)
    # another VPN's tunnel answers connections itself within a millisecond
    return tcp if tcp > 3 else full


def other_tunnels():
    """Tunnels of other VPN apps (Happ, Hiddify…), which fight with this one."""
    found = []
    for path in Path('/sys/class/net').iterdir():
        name = path.name
        if name == 'hyprstack-vpn' or not (path / 'tun_flags').exists():
            continue
        try:
            if (path / 'operstate').read_text().strip() == 'down':
                continue
        except OSError:
            pass
        found.append(name)
    return sorted(found)


def physical_interface():
    """Wi-Fi or cable interface of the default route, skipping VPN tunnels."""
    try:
        for line in Path('/proc/net/route').read_text().splitlines()[1:]:
            fields = line.split()
            if len(fields) > 7 and fields[1] == '00000000' and fields[7] == '00000000' \
                    and not Path(f'/sys/class/net/{fields[0]}/tun_flags').exists():
                return fields[0]
    except OSError:
        pass
    return ''


def real_latency(profile):
    validate(profile)
    with tempfile.TemporaryDirectory(prefix='.test-', dir=ROOT) as temporary:
        with socket.socket() as reservation:
            reservation.bind(('127.0.0.1', 0))
            port = reservation.getsockname()[1]
        path = Path(temporary) / 'config.json'
        atomic_json(path, configuration(profile, port=port, http_port=0))
        with (Path(temporary) / 'core.log').open('w') as log:
            process = subprocess.Popen(command(profile['engine'], path), stdout=log, stderr=log, umask=0o077)
            try:
                deadline = time.monotonic() + 5
                while True:
                    try:
                        stream = socket.create_connection(('127.0.0.1', port), timeout=.2)
                        break
                    except OSError:
                        if process.poll() is not None or time.monotonic() > deadline:
                            raise VpnError('The VPN core could not start the connection test')
                        time.sleep(.05)
                started = time.monotonic()
                with stream:
                    stream.settimeout(10)
                    stream.sendall(b'\x05\x01\x00')
                    if receive(stream, 2) != b'\x05\x00':
                        raise VpnError('The VPN connection test failed')
                    host = b'www.gstatic.com'
                    stream.sendall(b'\x05\x01\x00\x03' + bytes([len(host)]) + host + struct.pack('>H', 443))
                    header = receive(stream, 4)
                    if header[1] != 0:
                        raise VpnError('The VPN server did not respond to the connection test')
                    receive(stream, {1: 4, 4: 16}.get(header[3], 0) or receive(stream, 1)[0])
                    receive(stream, 2)
                    with ssl.create_default_context().wrap_socket(stream, server_hostname=host.decode()) as secure:
                        secure.sendall(b'GET /generate_204 HTTP/1.1\r\nHost: www.gstatic.com\r\nConnection: close\r\n\r\n')
                        if b' 204 ' not in secure.recv(1024).split(b'\r\n', 1)[0]:
                            raise VpnError('The VPN connection test failed')
                return round((time.monotonic() - started) * 1000)
            finally:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def authorize(value):
    engines = sorted(e for e in required(value) if not can_tun(binary(e)))
    if not engines and dns_authorized():
        return
    for engine in engines:
        install(engine)
    sources = [binary(e) for e in engines]
    digests = [hashlib.sha256(p.read_bytes()).digest() for p in sources]
    args = [item for engine, source in zip(engines, sources) for item in (str(source), str(PRIVILEGED / engine))]
    with tempfile.TemporaryDirectory(prefix='.authorize-', dir=ROOT) as temporary:
        policy = Path(temporary) / 'dns.rules'
        policy.write_text(dns_policy())
        try:
            subprocess.run(['pkexec', '/bin/sh', '-c',
                            'set -eu\nvpn_gid="$1"\n/usr/bin/install -D -o root -g root -m 644 "$2" "$3"\n'
                            'shift 3\nwhile [ "$#" -gt 0 ]; do\n'
                            '/usr/bin/install -D -o root -g "$vpn_gid" -m 750 "$1" "$2"\n'
                            '/usr/bin/setcap cap_net_admin,cap_net_raw,cap_net_bind_service=ep "$2"\nshift 2\ndone',
                            'hyprstack-vpn-install', str(os.getgid()), str(policy), str(DNS_RULE), *args], check=True, timeout=180,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError as error:
            raise VpnError('VPN tunnel authorization failed or was cancelled') from error
    for engine, source, digest in zip(engines, sources, digests):
        target = PRIVILEGED / engine
        if hashlib.sha256(target.read_bytes()).digest() != digest or not can_tun(target):
            raise VpnError('The installed VPN core did not pass verification')
        if source == RUNTIME / engine and not source.is_symlink():
            link = RUNTIME / ('.' + engine + '-authorized')
            link.unlink(missing_ok=True)
            link.symlink_to(target)
            os.replace(link, source)
    atomic_json(ROOT / 'authorization.json', {'dnsPolicy': hashlib.sha256(dns_policy().encode()).hexdigest()})


def add_profiles(value, group, entries):
    names = set()
    old = {p['id']: p for p in value['profiles']}
    output = [p for p in value['profiles'] if p['group'] != group['id']]
    for item in entries:
        name, index = item['name'], 1
        while name in names:
            index += 1
            name = item['name'] + f' ({index})'
        names.add(name)
        if name in group.get('excluded', []):
            continue
        ident = hashlib.sha256((group['id'] + '\0' + name).encode()).hexdigest()[:16]
        output.append({**item, 'id': ident, 'name': name, 'group': group['id'], 'latency_ms': old.get(ident, {}).get('latency_ms', -1)})
    value['profiles'] = output
    if value['selectedProfile'] not in {p['id'] for p in output}:
        value['selectedProfile'] = output[0]['id'] if output else -1


def supervise(session):
    """Run Xray (to the server) and sing-box (the tunnel) together; if one stops, stop both."""
    processes = [subprocess.Popen(command('xray', ROOT / 'core.json'))]
    try:
        deadline = time.monotonic() + 10
        while True:
            try:
                socket.create_connection(('127.0.0.1', session['corePort']), timeout=.2).close()
                break
            except OSError:
                if processes[0].poll() is not None or time.monotonic() > deadline:
                    sys.exit(1)
                time.sleep(.05)
        processes.append(subprocess.Popen(command('sing-box', ROOT / 'config.json')))
        while all(p.poll() is None for p in processes):
            time.sleep(.5)
        sys.exit(1)
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
        for process in processes:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()


def dispatch(action, payload):
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(ROOT, 0o700)
    if action == 'status':
        return status()
    if action == 'overview':
        return overview()
    if action == 'serve':
        session = read_json(ROOT / 'session.json')
        if session is None:
            raise VpnError('Add or select a VPN profile first')
        atomic_json(ROOT / 'process.json', {**session, 'pid': os.getpid(), 'start': proc_start(os.getpid())})
        os.umask(0o077)
        if session.get('chain'):
            return supervise(session)
        os.execv(binary(session['engine']), command(session['engine'], ROOT / 'config.json'))
    descriptor = os.open(ROOT / 'mutation.lock', os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(descriptor, 'a+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise VpnError('Another VPN operation is in progress') from error
        value = model()
        if action == 'install':
            for engine in required(value):
                install(engine)
        elif action == 'authorize':
            authorize(value)
        elif action == 'connect':
            connect()
        elif action == 'disconnect':
            service('stop')
        else:
            connected = status()['connected']
            if action == 'import':
                text = unwrap(str(payload.get('text', '')))
                if not text or len(text.encode()) > MAX_IMPORT:
                    raise VpnError('Paste a profile link or subscription URL')
                subscription = bool(payload.get('subscription')) or urllib.parse.urlsplit(text).scheme in ('https', 'http')
                if subscription:
                    if urllib.parse.urlsplit(text).scheme not in ('https', 'http'):
                        raise VpnError('A subscription URL must begin with https:// or http://')
                    if any(g.get('url') == text for g in value['groups']):
                        raise VpnError('This subscription is already added')
                    entries = fetch_profiles(text)
                else:
                    entries = parse(text)
                entries = valid_entries(entries)
                group = {'id': secrets.token_hex(6), 'name': str(payload.get('name', '')).strip() or (subscription_title(text) if subscription else 'Imported'),
                         'subscription': subscription, 'excluded': []}
                if subscription:
                    group['url'] = text
                value['groups'].append(group)
                add_profiles(value, group, entries)
            elif action == 'update':
                for group in value['groups']:
                    if group['subscription'] and payload.get('id') in (None, '', group['id']):
                        entries = valid_entries(fetch_profiles(group['url']))
                        add_profiles(value, group, entries)
            elif action == 'select':
                value['selectedProfile'] = payload['id']
                selected(value)
            elif action == 'mode':
                if payload['mode'] not in ('tun', 'proxy'):
                    raise VpnError('Choose VPN mode or local proxy mode')
                value['mode'] = payload['mode']
            elif action == 'route':
                if payload['id'] not in ('all', 'bypass-ru'):
                    raise VpnError('Choose a routing profile')
                value['route'] = payload['id']
            elif action == 'options':
                current = options(value)
                if 'dns' in payload:
                    current['dns'] = payload['dns']
                if 'port' in payload:
                    current['port'] = int(payload['port'])
                if 'direct' in payload:
                    current['direct'] = [d.strip().lower().removeprefix('https://').removeprefix('http://').split('/')[0]
                                         for d in payload['direct'] if isinstance(d, str) and d.strip()]
                value.update(options(current))
            elif action == 'remove-group':
                group = next((g for g in value['groups'] if g['id'] == payload.get('id')), None)
                if group is None:
                    raise VpnError('The subscription no longer exists')
                if connected and any(p['id'] == value['selectedProfile'] and p['group'] == group['id'] for p in value['profiles']):
                    raise VpnError('Disconnect from this subscription before removing it')
                value['groups'].remove(group)
                value['profiles'] = [p for p in value['profiles'] if p['group'] != group['id']]
                if value['selectedProfile'] not in {p['id'] for p in value['profiles']}:
                    value['selectedProfile'] = value['profiles'][0]['id'] if value['profiles'] else -1
            elif action == 'test-all':
                wanted = [p for p in value['profiles'] if payload.get('group') in (None, '', p['group'])]

                def measure(profile):
                    try:
                        return latency(profile)
                    except Exception:  # an unreachable server only gets no ping
                        return 0
                with ThreadPoolExecutor(max_workers=8) as pool:
                    for profile, ms in zip(wanted, pool.map(measure, wanted)):
                        profile['latency_ms'] = ms
            elif action in ('delete', 'test'):
                profile = next((p for p in value['profiles'] if p['id'] == payload['id']), None)
                if profile is None:
                    raise VpnError('The selected profile no longer exists')
                if action == 'test':
                    profile['latency_ms'] = latency(profile)
                else:
                    if connected and profile['id'] == value['selectedProfile']:
                        raise VpnError('Disconnect this profile before deleting it')
                    group = next(g for g in value['groups'] if g['id'] == profile['group'])
                    group['excluded'].append(profile['name'])
                    value['profiles'].remove(profile)
                    if value['selectedProfile'] == profile['id']:
                        value['selectedProfile'] = value['profiles'][0]['id'] if value['profiles'] else -1
            else:
                raise VpnError('Unknown VPN action')
            if connected and action in ('select', 'mode', 'route', 'update', 'options'):
                connect(value)
            atomic_json(ROOT / 'profiles.json', value)
        return overview()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('serve', 'status', 'overview', 'install', 'authorize', 'connect', 'disconnect', 'import', 'update', 'select', 'mode', 'route', 'delete', 'test', 'test-all', 'remove-group', 'options'))
    args = parser.parse_args()
    try:
        raw = sys.stdin.read() if args.action in ('import', 'update', 'select', 'mode', 'route', 'delete', 'test', 'test-all', 'remove-group', 'options') and not sys.stdin.isatty() else ''
        payload = json.loads(raw) if raw.strip() else {}
        print(json.dumps(dispatch(args.action, payload), ensure_ascii=False))
        return 0
    except Exception as error:
        message = str(error) if isinstance(error, (VpnError, ProfileError)) else 'The VPN action did not complete'
        print(json.dumps({'connected': False, 'state': 'error', 'error': message, 'reason': message,
                          'installed': all(binary(e).is_file() for e in required(model()))}, ensure_ascii=False))
        return 1


if __name__ == '__main__':
    sys.exit(main())
