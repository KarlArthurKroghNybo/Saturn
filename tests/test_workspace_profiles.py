import importlib.util
import json
import fcntl
import os
import subprocess
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('profiles', Path(__file__).parents[1] / 'assets/workspace_profiles.py')
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


def app(**kw):
    return dict(program='test-app', arguments=[], workspace='3', monitor='', resource='', matchClass='Test', matchTitle='', alwaysNew=False, **kw)


def client(address='0x1', pid=100, **kw):
    return dict(address=address, pid=pid, mapped=True, monitor=0, workspace={'id': 1, 'name': '1'}, initialClass='Test', title='Test', **kw)


class FakeHypr:
    def __init__(self, clients=None):
        self.clients = clients or []
        self.moves = []
        self.launches = []
        self.focused = None
        self.slow = 0

    def query(self, what):
        if what == 'monitors':
            return [{'id': 0, 'name': 'DP-1', 'focused': True}, {'id': 1, 'name': 'AI-codex'}]
        if self.launches:
            self.slow += 1
            if self.slow > 3 and not any(c['address'] == '0x2' for c in self.clients):
                self.clients.append(client('0x2', 200))
        return list(self.clients)

    def launch(self, a, m, ticket):
        self.launches.append((a, m))
        ticket.write_text(json.dumps({'pid': 200, 'start': '123'}))
        self.clients.append(client('0x-unrelated', 300))

    def move(self, c, ws, m):
        self.moves.append((c['address'], ws, m))

    def focus(self, ws):
        self.focused = ws


class ProfilesTest(unittest.TestCase):
    def activate(self, h, apps, **kw):
        with patch.object(p.shutil, 'which', return_value='/bin/test-app'), patch.object(p, 'owned', side_effect=lambda pid, root, start: pid == root), patch.object(p.time, 'sleep'):
            return p.activate(dict(name='Dev', focusWorkspace='3', apps=apps), h, report=lambda **x: None, **kw)

    def test_atomic_persistence_and_examples(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(p, 'STATE', Path(tmp) / 'profiles.json'):
            doc = p.load()
            self.assertEqual([x['name'] for x in doc['profiles']], ['Dev', 'Gaming', 'Study'])
            doc['profiles'].append(p.validate(dict(name='My profile', apps=[app()])))
            p.save(doc)
            self.assertEqual(p.load(), doc)
            self.assertEqual(list(Path(tmp).glob('.workspace-profiles-*')), [])

    def test_reuse_unique_and_monitor_fallback(self):
        h = FakeHypr([client()])
        a = app(); a['monitor'] = 'DP-absent'
        warnings = self.activate(h, [a])
        self.assertEqual(h.moves, [('0x1', '3', 'DP-1')])
        self.assertFalse(h.launches)
        self.assertEqual(h.focused, '3')
        self.assertIn('mangler', warnings[0])

    def test_ambiguous_does_not_move_or_launch(self):
        h = FakeHypr([client(), client('0x2')])
        self.assertTrue(self.activate(h, [app()]))
        self.assertFalse(h.moves)
        self.assertFalse(h.launches)

    def test_slow_launch_ignores_other_windows(self):
        h = FakeHypr()
        self.assertEqual(self.activate(h, [app()]), [])
        self.assertEqual(h.moves, [('0x2', '3', 'DP-1')])

    def test_always_new(self):
        h = FakeHypr([client()])
        a = app(); a['alwaysNew'] = True
        self.activate(h, [a])
        self.assertEqual(h.moves, [('0x2', '3', 'DP-1')])
        self.assertEqual(len(h.launches), 1)

    def test_missing_app_continues_to_reuse(self):
        h = FakeHypr([client()])
        a = app(); a['matchClass'] = 'Missing'; a['program'] = 'missing'
        with patch.object(p.shutil, 'which', return_value=None):
            warnings = p.activate(dict(name='Test', apps=[a, app()]), h, report=lambda **x: None)
        self.assertEqual(len(warnings), 1)
        self.assertEqual(h.moves, [('0x1', '3', 'DP-1')])

    def test_timeout_does_not_move(self):
        h = FakeHypr()
        with patch.object(p.shutil, 'which', return_value='/bin/test'), patch.object(p, 'owned', return_value=False):
            warnings = p.activate(dict(name='Test', apps=[app()]), h, timeout=0, report=lambda **x: None)
        self.assertEqual(len(warnings), 1)
        self.assertFalse(h.moves)

    def test_ai_exclusion_and_validation(self):
        c = client(); c['monitor'] = 1
        self.assertFalse(p.normal(c, {0}))
        for ws in ['ai-codex-abc', 'special:test', '0', '-1', '3; exec evil']:
            with self.assertRaises(ValueError):
                p.workspace(ws)
        a = app(); a['monitor'] = 'AI-codex'
        with self.assertRaises(ValueError):
            p.validate(dict(name='Bad', apps=[a]))

    def test_named_normal_workspace(self):
        c = client(); c['workspace'] = {'id': -1338, 'name': 'dev'}
        self.assertTrue(p.normal(c, {0}))
        c['workspace']['name'] = 'ai-test'
        self.assertFalse(p.normal(c, {0}))

    def test_shared_workspace_keeps_unrelated_monitor(self):
        h = p.Hypr(lua=True)
        unrelated = client('0x3'); unrelated['workspace']['name'] = '3'
        with patch.object(h, 'query', side_effect=lambda what: [unrelated] if what == 'clients' else [{'id': 0, 'name': 'DP-1'}, {'id': 2, 'name': 'DP-2'}]), patch.object(h, 'dispatch') as dispatch:
            note = h.move(client(), '3', 'DP-2')
        self.assertIn('andre vinduer', note)
        self.assertEqual(dispatch.call_count, 1)
        self.assertNotIn('workspace.move', dispatch.call_args.args[1])

    def test_cli_create_edit_delete_and_invalid_save_preserves_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / 'profiles.json'
            env = dict(os.environ, CAELESTIA_WORKSPACE_PROFILES_STATE=str(state))
            def command(action, value=''):
                return subprocess.run([sys.executable, p.__file__, action, value], env=env, capture_output=True, text=True)
            profile = dict(id='custom', name='One', apps=[app()])
            self.assertEqual(command('save', json.dumps(profile)).returncode, 0)
            profile['name'] = 'Edited'
            self.assertEqual(command('save', json.dumps(profile)).returncode, 0)
            doc = json.loads(command('list').stdout)
            self.assertEqual([q['name'] for q in doc['profiles'] if q['id'] == 'custom'], ['Edited'])
            before = state.read_bytes()
            profile['apps'][0]['workspace'] = 'ai-forbidden'
            self.assertNotEqual(command('save', json.dumps(profile)).returncode, 0)
            self.assertEqual(state.read_bytes(), before)
            self.assertEqual(command('delete', 'custom').returncode, 0)
            self.assertFalse(any(q['id'] == 'custom' for q in json.loads(command('list').stdout)['profiles']))

    def test_duplicate_activation_lock(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / 'profiles.json'
            with open(str(state) + '.lock', 'a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                result = subprocess.run([sys.executable, p.__file__, 'activate', 'Dev'], env=dict(os.environ, CAELESTIA_WORKSPACE_PROFILES_STATE=str(state)), capture_output=True, text=True, check=True)
                self.assertEqual(json.loads(result.stdout)['event'], 'error')
                self.assertIn('allerede', result.stdout)

    def test_argv_is_shell_quoted_and_resource_single_argument(self):
        h = p.Hypr(lua=True)
        a = app(); a['arguments'] = ['$(touch /tmp/evil)', 'two words']; a['resource'] = 'https://example.org/a?x=1&y=2'
        with patch.object(h, 'dispatch') as dispatch:
            h.launch(a, 'DP-1', Path('/tmp/ticket'))
        expr = dispatch.call_args.args[1]
        self.assertIn('hl.dsp.exec_cmd', expr)
        self.assertIn('no_initial_focus = true', expr)

    def test_capture_ai_exclusion(self):
        h = FakeHypr([client()])
        other = client('0x2'); other['monitor'] = 1
        h.clients.append(other)
        with patch.object(Path, 'read_bytes', return_value=b'/usr/bin/test\0--flag\0'):
            draft = p.capture(h)
        self.assertEqual(len(draft['apps']), 1)
        self.assertEqual(draft['apps'][0]['arguments'], ['--flag'])

if __name__ == '__main__':
    unittest.main()
