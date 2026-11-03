#!/usr/bin/env python3
"""Saved user workspaces. No shell interpretation of app argv; AI desktops excluded."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

STATE = Path(os.environ.get('CAELESTIA_WORKSPACE_PROFILES_STATE', str(Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'caelestia/workspace-profiles.json')))


def emit(**data):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def workspace(value):
    value = str(value).strip()
    if not re.fullmatch(r'[1-9][0-9]*|[A-Za-z][A-Za-z0-9_-]*', value) or value.lower().startswith(('ai-', 'special')):
        raise ValueError('Brug et positivt workspace-nummer eller et navn uden AI-/special-præfiks')
    return value


def ws_selector(value):
    return value if value.isdigit() else 'name:' + value


def validate(raw):
    p = dict(raw)
    p['id'] = str(p.get('id') or uuid.uuid4().hex)
    p['name'] = str(p.get('name', '')).strip()
    p['icon'] = str(p.get('icon') or 'workspaces')
    if not p['name']:
        raise ValueError('Profilen skal have et navn')
    p['focusWorkspace'] = workspace(p['focusWorkspace']) if p.get('focusWorkspace') else ''
    apps = []
    monitors = {}
    for raw_app in p.get('apps', []):
        a = dict(raw_app)
        a['program'] = str(a.get('program', '')).strip()
        if not a['program'] or '\0' in a['program']:
            raise ValueError('Alle apps skal have et program. Ret eller fjern ufuldstændige forslag.')
        if not isinstance(a.get('arguments', []), list) or not all(isinstance(x, str) and '\0' not in x for x in a.get('arguments', [])):
            raise ValueError('Argumenter skal være en JSON-liste med tekst')
        a['arguments'] = a.get('arguments', [])
        a['workspace'] = workspace(a.get('workspace', '1'))
        a['monitor'] = str(a.get('monitor') or '').strip()
        if a['monitor'] and (not re.fullmatch(r'[A-Za-z0-9_.:-]+', a['monitor']) or a['monitor'].startswith('AI-')):
            raise ValueError('AI-skærme kan ikke bruges til almindelige profiler')
        if a['monitor']:
            if a['workspace'] in monitors and monitors[a['workspace']] != a['monitor']:
                raise ValueError('Et workspace kan kun være på én skærm')
            monitors[a['workspace']] = a['monitor']
        a['resource'] = str(a.get('resource') or '')
        a['matchClass'] = str(a.get('matchClass') or '')
        a['matchTitle'] = str(a.get('matchTitle') or '')
        a['alwaysNew'] = bool(a.get('alwaysNew', False))
        apps.append(a)
    p['apps'] = apps
    return p


def load():
    if not STATE.exists():
        return {'version': 1, 'profiles': [dict(id='example-' + n.lower(), name=n, icon=i, focusWorkspace='', apps=[]) for n, i in [('Dev', 'code'), ('Gaming', 'sports_esports'), ('Study', 'school')]]}
    doc = json.loads(STATE.read_text())
    if doc.get('version') != 1 or not isinstance(doc.get('profiles'), list):
        raise ValueError('Ukendt profilformat; den eksisterende fil er bevaret')
    doc['profiles'] = [validate(p) for p in doc['profiles']]
    return doc


def save(doc):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    fd, path = tempfile.mkstemp(dir=STATE.parent, prefix='.workspace-profiles-')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(doc, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(path, STATE)
    finally:
        if os.path.exists(path):
            os.unlink(path)


class Hypr:
    def __init__(self, lua=False):
        self.lua = lua

    def ctl(self, *args):
        p = subprocess.run(['hyprctl', *args], capture_output=True, text=True, timeout=8)
        if p.returncode or (args[0] == 'dispatch' and p.stdout.strip() != 'ok'):
            raise RuntimeError(p.stderr.strip() or p.stdout.strip() or 'Hyprland svarede ikke')
        return p.stdout

    def query(self, what):
        return json.loads(self.ctl('-j', what))

    def dispatch(self, legacy, lua):
        return self.ctl('dispatch', lua if self.lua else legacy)

    def move(self, client, ws, monitor):
        # A workspace is attached to one output. Never relocate somebody else's
        # windows merely to satisfy this app's preferred output.
        others = [c for c in self.query('clients') if c['address'] != client['address'] and c.get('workspace', {}).get('name') == ws]
        monitor_ids = {m['name']: m['id'] for m in self.query('monitors')}
        shared_elsewhere = any(c.get('monitor') != monitor_ids.get(monitor) for c in others)
        selector = 'address:' + client['address']
        self.dispatch(f'movetoworkspacesilent {ws_selector(ws)},{selector}', 'hl.dsp.window.move({ window = %s, workspace = %s, follow = false })' % (json.dumps(selector), json.dumps(ws_selector(ws))))
        if shared_elsewhere:
            return f'Workspace {ws} har andre vinduer; dets eksisterende skærm er bevaret'
        self.dispatch(f'moveworkspacetomonitor {ws_selector(ws)} {monitor}', 'hl.dsp.workspace.move({ workspace = %s, monitor = %s })' % (json.dumps(ws_selector(ws)), json.dumps(monitor)))

    def focus(self, ws):
        self.dispatch('workspace ' + ws_selector(ws), 'hl.dsp.focus({ workspace = %s })' % json.dumps(ws_selector(ws)))

    def launch(self, app, monitor, ticket):
        argv = [app['program'], *app['arguments']]
        if app['resource']:
            argv.append(os.path.expanduser(app['resource']) if '://' not in app['resource'] else app['resource'])
        command = shlex.join([sys.executable, str(Path(__file__).resolve()), 'spawn', str(ticket), json.dumps(argv)])
        ws = ws_selector(app['workspace'])
        self.dispatch(f'exec [workspace {ws} silent; monitor {monitor}; no_initial_focus on; suppress_event activate activatefocus fullscreenoutput] {command}', 'hl.dsp.exec_cmd(%s, { workspace = %s, monitor = %s, no_initial_focus = true, suppress_event = "activate activatefocus fullscreenoutput" })' % (json.dumps(command), json.dumps(ws + ' silent'), json.dumps(monitor + ' silent')))


def normal(client, monitor_ids):
    name = client.get('workspace', {}).get('name', '')
    return client.get('mapped', True) and client.get('monitor') in monitor_ids and not name.lower().startswith(('ai-', 'special:'))


def matches(a, c):
    return bool(a['matchClass']) and a['matchClass'] == (c.get('initialClass') or c.get('class')) and (not a['matchTitle'] or a['matchTitle'] == c.get('title'))


def capture(hypr):
    monitors = {m['id']: m['name'] for m in hypr.query('monitors') if not m['name'].startswith('AI-')}
    apps = []
    for c in hypr.query('clients'):
        if not normal(c, monitors):
            continue
        try:
            argv = [x.decode() for x in (Path('/proc') / str(c['pid']) / 'cmdline').read_bytes().split(b'\0') if x]
        except (OSError, UnicodeError):
            argv = []
        apps.append(dict(program=argv[0] if argv else '', arguments=argv[1:], workspace=c['workspace']['name'], monitor=monitors[c['monitor']], resource='', matchClass=c.get('initialClass') or c.get('class', ''), matchTitle=c.get('title', ''), alwaysNew=False))
    return dict(id='', name='Aktuel vinduesfordeling', icon='workspaces', focusWorkspace='', apps=apps)


def write_ticket(ticket, data):
    temporary = ticket.with_name(ticket.name + '.pending')
    temporary.write_text(json.dumps(data))
    os.replace(temporary, ticket)


def process_identity(pid):
    try:
        fields = (Path('/proc') / str(pid) / 'stat').read_text().rsplit(')', 1)[1].split()
        return int(fields[1]), fields[19]  # parent PID, process start time
    except (OSError, ValueError, IndexError):
        return None


def owned(pid, root, start):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        info = process_identity(pid)
        if not info:
            return False
        if pid == root:
            return info[1] == start
        pid = info[0]
    return False


def activate(profile, hypr, timeout=60, report=emit):
    p = validate(profile)
    monitors = [m for m in hypr.query('monitors') if not m['name'].startswith('AI-')]
    if not monitors:
        raise RuntimeError('Ingen almindelig skærm tilgængelig')
    fallback = next((m for m in monitors if m.get('focused')), monitors[0])['name']
    ids = {m['id'] for m in monitors}
    names = {m['name'] for m in monitors}
    warnings, claimed, pending = [], set(), []
    completed = 0
    total = len(p['apps'])
    with tempfile.TemporaryDirectory(prefix='caelestia-workspaces-') as tmp:
        for index, a in enumerate(p['apps']):
            mon = a['monitor'] if a['monitor'] in names else fallback
            if a['monitor'] and a['monitor'] not in names:
                warnings.append(f"{a['monitor']} mangler; bruger {mon}")
            try:
                clients = [c for c in hypr.query('clients') if normal(c, ids)]
                candidates = [c for c in clients if c['address'] not in claimed and matches(a, c)]
                if not a['alwaysNew'] and len(candidates) == 1:
                    note = hypr.move(candidates[0], a['workspace'], mon)
                    if note:
                        warnings.append(note)
                    claimed.add(candidates[0]['address'])
                    completed += 1
                elif not a['alwaysNew'] and len(candidates) > 1:
                    warnings.append(f"{a['program']}: flere vinduesmatch; præcisér titel eller vælg åbn altid nyt")
                    completed += 1
                elif not shutil.which(os.path.expanduser(a['program'])):
                    warnings.append(f"{a['program']}: programmet mangler")
                    completed += 1
                else:
                    a['program'] = os.path.expanduser(a['program'])
                    ticket = Path(tmp) / str(index)
                    baseline = {c['address'] for c in hypr.query('clients')}
                    hypr.launch(a, mon, ticket)
                    pending.append((a, mon, ticket, baseline, time.monotonic() + timeout))
            except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
                warnings.append(f"{a['program']}: {e}")
                completed += 1
            report(event='progress', completed=completed, total=total, message=f'{completed}/{total} apps behandlet')
        while pending:
            clients = hypr.query('clients')
            for task in pending[:]:
                a, mon, ticket, baseline, deadline = task
                try:
                    identity = json.loads(ticket.read_text()) if ticket.exists() else None
                    candidates = [c for c in clients if normal(c, ids) and c['address'] not in baseline | claimed and identity and owned(c.get('pid', 0), identity['pid'], identity['start']) and (not a['matchClass'] or matches(dict(a, matchTitle=''), c))]
                    if identity and identity.get('error'):
                        raise RuntimeError(identity['error'])
                    if len(candidates) == 1:
                        # Re-query before moving so a closed/replaced window cannot be selected.
                        current = next((c for c in hypr.query('clients') if c['address'] == candidates[0]['address'] and c.get('pid') == candidates[0].get('pid')), None)
                        if current:
                            note = hypr.move(current, a['workspace'], mon)
                            if note:
                                warnings.append(note)
                            claimed.add(current['address'])
                            pending.remove(task)
                    elif time.monotonic() >= deadline:
                        raise RuntimeError('intet entydigt vindue efter ventetiden; ingen andre vinduer flyttet')
                    else:
                        continue
                except (RuntimeError, OSError, subprocess.TimeoutExpired) as e:
                    warnings.append(f"{a['program']}: {e}")
                    pending.remove(task)
                completed += 1
                report(event='progress', completed=completed, total=total, message=f'{completed}/{total} apps behandlet')
            if pending:
                time.sleep(.25)
    if p['focusWorkspace']:
        try:
            hypr.focus(p['focusWorkspace'])
        except (RuntimeError, subprocess.TimeoutExpired) as e:
            warnings.append(str(e))
    report(event='done', warnings=warnings, message='Arbejdsområde aktiveret' if not warnings else f'Aktiveret med {len(warnings)} bemærkninger', completed=completed, total=total)
    return warnings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['list', 'save', 'delete', 'capture', 'activate', 'spawn'])
    parser.add_argument('value', nargs='?', default='')
    parser.add_argument('payload', nargs='?', default='')
    parser.add_argument('--lua', action='store_true')
    args = parser.parse_args()
    if args.action == 'spawn':
        # This PID survives exec. Hyprland launch rules follow this process tree.
        ticket = Path(args.value)
        argv = json.loads(args.payload)
        data = dict(pid=os.getpid(), start=process_identity(os.getpid())[1])
        write_ticket(ticket, data)
        env = {k: v for k, v in os.environ.items() if not k.startswith('AI_')}
        try:
            os.execvpe(argv[0], argv, env)
        except OSError as e:
            data['error'] = str(e)
            write_ticket(ticket, data)
        return
    STATE.parent.mkdir(parents=True, exist_ok=True)
    with open(str(STATE) + '.lock', 'a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            emit(event='error', message='En profil er allerede ved at blive behandlet')
            return
        try:
            if args.action == 'capture':
                emit(event='capture', draft=capture(Hypr(args.lua)))
                return
            doc = load()
            if args.action == 'save':
                p = validate(json.loads(args.value))
                doc['profiles'] = [q for q in doc['profiles'] if q['id'] != p['id']] + [p]
                save(doc)
            elif args.action == 'delete':
                doc['profiles'] = [q for q in doc['profiles'] if q['id'] != args.value]
                save(doc)
            elif args.action == 'activate':
                p = next((p for p in doc['profiles'] if p['id'] == args.value or p['name'] == args.value), None)
                if not p:
                    raise ValueError('Profilen findes ikke')
                activate(p, Hypr(args.lua))
                return
            elif not STATE.exists():
                save(doc)
            emit(event='profiles', profiles=doc['profiles'])
        except (ValueError, OSError, RuntimeError, subprocess.TimeoutExpired) as e:
            emit(event='error', message=str(e))
            sys.exit(1)


if __name__ == '__main__':
    main()
