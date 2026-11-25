# Bridge hub collectors, Python 3.14, standard library only. Imported by bin/fm-board.py.
#
# Read-only data behind Bridge's "Fleet & models" and "Dashboards" tabs.
# Nothing here mutates a record, takes a lock, or starts a process per page view:
# GET /api/fleet and GET /api/dashboards only serialize the caches below.
#
# Fleet records (second mates, live workers, routing rules, council seats) are
# plain file reads of each configured home (state/<id>.meta, state/<id>.dormant,
# state/<id>.status, data/secondmates.md, config/crew-dispatch.json,
# config/council.json), refreshed by the daemon's ingest loop and at most every
# RECORDS_TTL seconds. Only whitelisted fields are copied; worktree and
# endpoint paths, pane identifiers, account keys, and error text from other
# tools never leave this module, and free text has e-mail addresses and
# absolute paths redacted.
#
# Quota comes from `quota-axi --json`, run by one background thread at most every
# QUOTA_TTL seconds; a failed run keeps the last good result and reports the
# error code. Dashboard liveness checks each configured link whose host is
# local (loopback, private or link-local IP, localhost, a single-label name, or
# *.local, *.lan, *.internal, *.home.arpa) with a no-redirect GET and a 2 s
# timeout, at most every LINK_TTL seconds; any HTTP response counts as up.
# Other hosts are listed as unchecked and never contacted.

import datetime
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

RECORDS_TTL = 5
QUOTA_TTL = 300
QUOTA_TIMEOUT = 60
LINK_TTL = 30
LINK_TIMEOUT = 2
MAX_LINKS = 100
LOCAL_SUFFIXES = ('.local', '.lan', '.internal', '.home.arpa')
EMAIL = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
ABS_PATH = re.compile(r'(?<![\w:/])(?:~|/[A-Za-z0-9_.@-]+)(?:/[^\s,;)"\']+)+')
SAFE_ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9_-]{0,119}\Z')
CODE = re.compile(r'[a-z0-9_.-]{1,60}\Z')
STATUS_LABELS = {
    'done': 'finished its last piece of work',
    'resolved': 'a decision was answered',
    'working': 'work under way',
    'note': 'left a note',
    'paused': 'waiting on something outside',
    'blocked': 'blocked, needs a hand',
    'needs-decision': 'waiting on a decision',
    'captain-held': 'waiting on the captain',
    'failed': 'something failed',
}
CRITICAL_PERCENT = 15
WARNING_PERCENT = 40


def clean(value, limit=200):
    value = ABS_PATH.sub('[path]', EMAIL.sub('[email]', str(value if value is not None else '')))
    value = ' '.join(value.split())
    return value if len(value) <= limit else value[:limit - 1] + '…'


def read_text(path):
    try:
        return Path(path).read_text(encoding='utf-8', errors='replace')
    except OSError:
        return ''


def read_json(path):
    try:
        value = json.loads(read_text(path))
    except ValueError:
        return {}
    return value if isinstance(value, dict) else {}


def parse_meta(path):
    meta = {}
    for line in read_text(path).splitlines():
        key, sep, value = line.partition('=')
        if sep:
            meta[key.strip()] = value.strip()
    return meta


def iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).isoformat(timespec='seconds')


def candidates(use):
    if isinstance(use, dict):
        use = [use]
    out = []
    for item in use if isinstance(use, list) else []:
        if isinstance(item, dict):
            out.append({key: clean(item.get(key), 80) for key in ('harness', 'model', 'effort') if item.get(key)})
    return out


def last_report(state_dir, task_id, now):
    path = state_dir / f'{task_id}.status'
    try:
        mtime = path.stat().st_mtime
        with path.open('rb') as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 16384))
            lines = [x for x in f.read().decode('utf-8', 'replace').splitlines() if x.strip()]
    except OSError:
        return None, None
    if not lines:
        return None, None
    head = re.sub(r'\s*\[.*$', '', lines[-1].split(':', 1)[0]).strip().lower()
    return STATUS_LABELS.get(head, 'recorded an update'), max(0, int(now - mtime))


def spawned_at(meta, path):
    match = re.match(r's(\d{9,11})(?:\.|$)', meta.get('spawn_gen', ''))
    if match:
        return int(match.group(1))
    try:
        return int(path.stat().st_mtime)
    except OSError:
        return None


def observed_state(observation):
    endpoint = observation.get('endpoint', {})
    current = observation.get('current_state', {})
    if endpoint.get('exists') is False or endpoint.get('agent_alive') == 'dead':
        return 'stopped'
    if endpoint.get('agent_alive') == 'alive':
        return 'live'
    if endpoint.get('exists') is True and current.get('source') == 'pane' and current.get('state') in ('working', 'idle', 'parked'):
        return 'live'
    return 'unknown'


def collect_records(home, homes, now=None, observations=None):
    now = time.time() if now is None else now
    home = Path(home)
    observations = observations or {}
    scopes = {}
    for line in read_text(home / 'data/secondmates.md').splitlines():
        match = re.match(r'^-\s+(\S+)\s+-\s+(.*)$', line.strip())
        if match and SAFE_ID.fullmatch(match.group(1)):
            scopes[match.group(1)] = clean(match.group(2).split(' (home:')[0].split('. ')[0].rstrip('.'), 240)
    mates, workers = [], []
    seen_mates = set()
    for hid, path in sorted(homes.items()):
        state = Path(path) / 'state'
        try:
            names = sorted(n for n in os.listdir(state) if n.endswith('.meta'))
        except OSError:
            continue
        for name in names[:500]:
            tid = name[:-5]
            if not SAFE_ID.fullmatch(tid):
                continue
            meta = parse_meta(state / name)
            observed = observed_state(observations.get(hid, {}).get(tid, {}))
            runtime = {key: clean(meta.get(key), 60) for key in ('harness', 'model', 'effort', 'backend') if meta.get(key)}
            if meta.get('kind') == 'secondmate':
                if Path(path) != home or tid in seen_mates:
                    continue
                seen_mates.add(tid)
                projects = [clean(os.path.basename(p.strip().rstrip('/')), 60) for p in meta.get('projects', '').split(',') if p.strip()]
                mates.append(dict(id=tid, scope=scopes.get(tid, ''), state='dormant' if (state / f'{tid}.dormant').exists() else observed,
                                  projects=projects[:20], **runtime))
                continue
            label, ago = last_report(state, tid, now)
            started = spawned_at(meta, state / name)
            workers.append(dict(id=tid, home=hid, state=observed, project=clean(os.path.basename(meta.get('project', '').rstrip('/')), 80),
                                kind=clean(meta.get('kind'), 20), mode=clean(meta.get('mode'), 40), yolo=clean(meta.get('yolo'), 10),
                                age_s=None if started is None else max(0, int(now - started)),
                                last_report=label, last_report_age_s=ago, **runtime))
    for sid, scope in scopes.items():
        if sid not in seen_mates and (home / 'state').is_dir():
            mates.append(dict(id=sid, scope=scope, state='dormant' if (home / f'state/{sid}.dormant').exists() else 'unknown', projects=[]))
    workers.sort(key=lambda w: (w['age_s'] is None, w['age_s'] or 0))
    dispatch = read_json(home / 'config/crew-dispatch.json')
    rules = []
    seat_use = {}
    for rule in dispatch.get('rules', []) if isinstance(dispatch.get('rules'), list) else []:
        if isinstance(rule, dict):
            if isinstance(rule.get('when'), str):
                seat_use[rule['when']] = candidates(rule.get('use'))
            rules.append(dict(when=clean(rule.get('when'), 400), why=clean(rule.get('why'), 400), use=candidates(rule.get('use'))))
    council = read_json(home / 'config/council.json')
    roster = [clean(x, 40) for x in council.get('default_roster', []) if isinstance(x, str)] if isinstance(council.get('default_roster'), list) else []
    advisory = council.get('advisory') if isinstance(council.get('advisory'), dict) else {}
    model = re.search(r'--model\s+([\w.:-]{1,80})', str(advisory.get('command_template', '')))
    caps = council.get('caps') if isinstance(council.get('caps'), dict) else {}
    seats = council.get('seats') if isinstance(council.get('seats'), dict) else {}
    return dict(
        second_mates=mates, workers=workers[:200],
        routing=dict(rules=rules, default=candidates(dispatch.get('default'))),
        council=dict(seats=[dict(seat=clean(seat, 40), standing=seat in roster, use=seat_use.get(rule_name, []) if isinstance(rule_name, str) else []) for seat, rule_name in seats.items()],
                     advisory_model=model.group(1) if model else None,
                     caps={clean(k, 40): v for k, v in caps.items() if type(v) is int}))


def safe_code(value):
    return value if isinstance(value, str) and CODE.fullmatch(value) else None


def shape_quota(raw):
    providers, attention = [], []
    for p in raw.get('providers', []) if isinstance(raw.get('providers'), list) else []:
        if not isinstance(p, dict):
            continue
        name = clean(p.get('provider'), 40)
        state = p.get('state') if isinstance(p.get('state'), dict) else {}
        status = clean(state.get('status') or 'unknown', 40)
        windows = []
        for w in p.get('windows', []) if isinstance(p.get('windows'), list) else []:
            if not isinstance(w, dict):
                continue
            pace = w.get('pace') if isinstance(w.get('pace'), dict) else {}
            windows.append(dict(id=clean(w.get('id'), 60), label=clean(w.get('label') or w.get('id'), 60), kind=clean(w.get('kind'), 20),
                                percent_remaining=w.get('percentRemaining') if type(w.get('percentRemaining')) in (int, float) else None,
                                resets_at=clean(w.get('resetsAt'), 40) or None, pace=clean(pace.get('status'), 20) or None))
        scopes = []
        semantics = p.get('quotaSemantics') if isinstance(p.get('quotaSemantics'), dict) else {}
        for e in semantics.get('effectiveAvailability', []) if isinstance(semantics.get('effectiveAvailability'), list) else []:
            if not isinstance(e, dict):
                continue
            runway = e.get('runway') if isinstance(e.get('runway'), dict) else {}
            selection = e.get('selection') if isinstance(e.get('selection'), dict) else {}
            priority = selection.get('spendPriority')
            scopes.append(dict(scope=clean(e.get('scope'), 80), status=clean(e.get('status'), 20),
                               percent_remaining=e.get('effectivePercentRemaining') if type(e.get('effectivePercentRemaining')) in (int, float) else None,
                               spend_priority=priority if type(priority) in (int, float) else None,
                               runway=clean(runway.get('status'), 40) or None,
                               projected_exhausted_at=clean(runway.get('projectedExhaustedAt'), 40) or None,
                               limiting=[clean(x, 60) for x in e.get('limitingWindowIds', []) if isinstance(x, str)][:6]))
        credits = p.get('credits') if isinstance(p.get('credits'), dict) else None
        entry = dict(provider=name, plan=clean(p.get('plan'), 40) or None, status=status, stale=state.get('stale') is True,
                     error=safe_code(state.get('error')), not_set_up=p.get('notSetUp') is True, windows=windows, scopes=scopes)
        if credits:
            entry['credits'] = dict(remaining=credits.get('remaining') if type(credits.get('remaining')) in (int, float) else None,
                                    unit=clean(credits.get('unit'), 20), unlimited=credits.get('unlimited') is True)
        providers.append(entry)
        if status in ('error', 'unavailable'):
            attention.append(dict(provider=name, level='warning', message=f'{name} quota could not be read'))
        elif status == 'fresh' and entry['stale']:
            attention.append(dict(provider=name, level='warning', message=f'{name} quota data is stale'))
        if status != 'fresh':
            continue
        for s in scopes:
            if s['runway'] == 'projected_exhaustion':
                when = f' at {s["projected_exhausted_at"]}' if s['projected_exhausted_at'] else ''
                attention.append(dict(provider=name, level='critical', message=f'{name} {s["scope"]} projected to run out{when}'))
        for w in windows:
            pct = w['percent_remaining']
            if pct is not None and pct <= WARNING_PERCENT:
                level = 'critical' if pct <= CRITICAL_PERCENT else 'warning'
                attention.append(dict(provider=name, level=level, message=f'{name} {w["label"]} has {pct:g}% left'))
    attention.sort(key=lambda a: a['level'] != 'critical')
    return dict(providers=providers, attention=attention)


def is_local_host(host):
    host = host.lower().rstrip('.')
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return host == 'localhost' or '.' not in host or host.endswith(LOCAL_SUFFIXES)
    return ip.is_loopback or ip.is_private or ip.is_link_local


def parse_links(value, invalid):
    if value is None:
        return []
    if not isinstance(value, list) or len(value) > MAX_LINKS or any(not isinstance(x, dict) for x in value):
        raise invalid(f'links must be an array of at most {MAX_LINKS} link objects')
    links = []
    for item in value:
        if set(item) - {'title', 'url', 'description', 'group'}:
            raise invalid('link keys are limited to title, url, description, and group')
        fields = {}
        for key, limit, required in (('title', 120, True), ('url', 2048, True), ('description', 300, False), ('group', 60, False)):
            v = item.get(key, '')
            if not isinstance(v, str) or len(v) > limit or (required and not v.strip()):
                raise invalid(f'link {key} must be a string of at most {limit} characters' + (' and is required' if required else ''))
            fields[key] = v.strip()
        parts = urllib.parse.urlsplit(fields['url'])
        try:
            parts.port
        except ValueError:
            raise invalid('link url has an invalid port') from None
        if parts.scheme not in ('http', 'https') or not parts.hostname or parts.username or parts.password or any(c.isspace() for c in fields['url']):
            raise invalid('link url must be absolute http or https without credentials')
        links.append(fields)
    return links


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class Hub:
    def __init__(self, home, homes, links, log=None, now=time.time):
        self.home = Path(home)
        self.homes = dict(homes)
        self.links = links
        self.log = log or (lambda message: None)
        self.now = now
        self.lock = threading.Lock()
        self.observations = {}
        self.records = None
        self.records_at = 0.0
        self.quota = None
        self.quota_at = 0.0
        self.quota_failed_at = 0.0
        self.quota_error = None
        self.quota_running = False
        self.link_status = {}
        self.link_at = 0.0
        self.link_running = False

    def update_observations(self, hid, snapshots, changed):
        with self.lock:
            if snapshots is not None:
                self.observations[hid] = snapshots
            else:
                for tid in changed:
                    self.observations.get(hid, {}).pop(tid, None)
            self.records_at = 0.0

    def refresh_records(self, force=False):
        if not force and self.records is not None and self.now() - self.records_at < RECORDS_TTL:
            return
        records = collect_records(self.home, self.homes, self.now(), self.observations)
        with self.lock:
            self.records, self.records_at = records, self.now()

    def find_quota_command(self):
        extra = os.pathsep.join(str(Path.home() / d) for d in ('.npm-global/bin', '.local/bin')) + os.pathsep + '/opt/homebrew/bin:/usr/local/bin'
        return shutil.which('quota-axi') or shutil.which('quota-axi', path=extra)

    def run_quota(self):
        try:
            command = self.find_quota_command()
            if not command:
                raise RuntimeError('quota_axi_missing')
            result = subprocess.run([command, '--json'], capture_output=True, text=True, timeout=QUOTA_TIMEOUT, check=False, stdin=subprocess.DEVNULL)
            try:
                raw = json.loads(result.stdout)
            except ValueError:
                raise RuntimeError('quota_axi_unreadable') from None
            if not isinstance(raw, dict):
                raise RuntimeError('quota_axi_unreadable')
            shaped = shape_quota(raw)
            with self.lock:
                self.quota, self.quota_at, self.quota_error = shaped, self.now(), None
        except subprocess.TimeoutExpired:
            self.fail_quota('quota_axi_timeout')
        except (RuntimeError, OSError) as e:
            self.fail_quota(safe_code(str(e)) or 'quota_axi_failed')
        finally:
            with self.lock:
                self.quota_running = False

    def fail_quota(self, code):
        with self.lock:
            self.quota_error = code
            # A failed run is retried after the normal interval, never in a tight loop.
            self.quota_failed_at = self.now()
        self.log(f'hub quota: {code}')

    def maybe_refresh_quota(self, force=False):
        with self.lock:
            due = self.now() - max(self.quota_at, self.quota_failed_at) >= QUOTA_TTL
            if self.quota_running or not (due or force):
                return False
            self.quota_running = True
        threading.Thread(target=self.run_quota, daemon=True).start()
        return True

    def tick(self):
        self.refresh_records()
        self.maybe_refresh_quota()

    def fleet(self):
        if self.records is None:
            self.refresh_records(force=True)
        self.maybe_refresh_quota()
        with self.lock:
            quota = dict(self.quota or dict(providers=[], attention=[]))
            return dict(generated_at=iso(self.now()), records=self.records, records_age_s=int(self.now() - self.records_at),
                        quota=dict(quota, fetched_at=iso(self.quota_at) if self.quota else None,
                                   age_s=int(self.now() - self.quota_at) if self.quota else None,
                                   error=self.quota_error, refreshing=self.quota_running))

    def probe(self, link):
        parts = urllib.parse.urlsplit(link['url'])
        if not is_local_host(parts.hostname):
            return 'unchecked'
        opener = urllib.request.build_opener(NoRedirect)
        try:
            with opener.open(urllib.request.Request(link['url'], method='GET'), timeout=LINK_TIMEOUT):
                return 'up'
        except urllib.error.HTTPError:
            return 'up'
        except (urllib.error.URLError, OSError, ValueError, socket.timeout):
            return 'down'

    def run_links(self):
        try:
            results = {}
            threads = []
            def check(link):
                results[link['url']] = self.probe(link)
            for link in self.links:
                t = threading.Thread(target=check, args=(link,), daemon=True)
                t.start()
                threads.append(t)
            for t in threads:
                t.join(LINK_TIMEOUT + 3)
            with self.lock:
                self.link_status, self.link_at = results, self.now()
        finally:
            with self.lock:
                self.link_running = False

    def maybe_refresh_links(self):
        with self.lock:
            if self.link_running or not self.links or self.now() - self.link_at < LINK_TTL:
                return
            self.link_running = True
        threading.Thread(target=self.run_links, daemon=True).start()

    def dashboards(self):
        self.maybe_refresh_links()
        with self.lock:
            status = dict(self.link_status)
            checked = self.link_at
        return dict(generated_at=iso(self.now()), checked_at=iso(checked) if checked else None,
                    links=[dict(link, status=status.get(link['url'], 'unchecked' if not is_local_host(urllib.parse.urlsplit(link['url']).hostname) else 'checking'))
                           for link in self.links])
